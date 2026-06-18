# AI Workshop — Infrastructure

This project provisions everything the **workshop** needs in Azure,
then loads its data and grants participants the right access. The same
infrastructure is reused for the Data and Data Science workshops.

Provisioning is run manually with the Azure Developer CLI (`azd`) and the
PowerShell scripts in [scripts/](scripts). The steps below cover installing the
tools and running each of the four parts.

---

## What gets created

The workshop uses exactly these shared services (nothing else):

| Service | Why the workshop needs it |
| ------- | ------------------------- |
| Azure AI Foundry account + project | Hosts the agents and model deployments. |
| Model deployments (`gpt-4.1-mini`, `text-embedding-3-small`) | Chat model + embeddings for the marketing knowledge base (Foundry IQ). |
| Azure Cosmos DB for NoSQL | Sales, inventory, and marketing data the agents query. |
| Azure AI Search | Backs the marketing Foundry IQ knowledge base. |
| Azure Container Apps environment + Container Registry | Host the MCP servers and chat app later in the workshop. |
| Log Analytics + Application Insights | Observability for the deployed apps. |

> **Region.** Everything is deployed in a single region, `swedencentral`
> (configurable via `primaryLocation` and `aiFoundry.location` in
> [infra/main.parameters.json](infra/main.parameters.json)). This is a sandbox
> workshop, so there is no secondary / quota-overflow region.

> **Key-based authentication.** Services keep their default key / connection
> string auth and talk to each other with keys (no managed identities). Access
> for people and apps is granted with Azure RBAC at the **resource group**
> scope by the Part C and Part D scripts.

---

## The four parts

Provisioning is split into four independent steps so each can be reviewed,
re-run, or handed to a different team:

```
A. Infrastructure    ->  ./scripts/deploy.ps1
B. Data load         ->  ./scripts/load-data.ps1 -WorkshopPath <repo>
C. Resource access   ->  ./scripts/grant-resource-access.ps1
D. User access       ->  ./scripts/grant-user-access.ps1
```

| Part | Script | Outcome |
| ---- | ------ | ------- |
| **A. Infrastructure** | `deploy.ps1` | All Azure resources exist and are empty. |
| **B. Data load** | `load-data.ps1` | Cosmos containers are seeded, the marketing knowledge base is built, and a ready-to-use `.env` is written into the workshop repo. |
| **C. Resource access** | `grant-resource-access.ps1` | The workshop's service principals / apps get access to the resource group (see below). |
| **D. User access** | `grant-user-access.ps1` | Participants get exactly the permissions below. |

### Resource access (Part C — service principals / apps)

Services authenticate to each other with keys / connection settings, so no
per-resource role assignments are needed. This step simply grants any service
principals / apps listed in
[infra/resource-access.parameters.json](infra/resource-access.parameters.json)
access at the **resource group** scope:

| Principal | Default access | Why |
| --------- | -------------- | --- |
| Service principals / apps (`servicePrincipals`) | Contributor on the resource group | Manage / use every resource in the workshop RG (and read the keys they need). |

> Leave the `servicePrincipals` array empty to grant nothing in Part C.

### Participant permissions (Part D)

Every participant (user or Entra group) gets built-in **Contributor** at the
**resource group** scope, so they can manage and use every resource in the
workshop RG. With key-based auth enabled, Contributor also lets them read the
resource keys / connection settings they need (including Cosmos).

The access level is configurable in
[infra/user-access.parameters.json](infra/user-access.parameters.json).

### Multiple isolated projects (optional)

For isolation you can create **several Foundry projects** inside the same
Foundry account and give one Entra **group** access to all of them. Every
project shares the account's model deployments, so all projects expose the
**same models** with no duplication.

1. List the projects to create in
   **[infra/foundry-projects.txt](infra/foundry-projects.txt)** — one project
   name per line (this controls **how many** projects are created; it is not a
   list of users):

   ```
   project-01
   project-02
   ```

2. After Part A, run it with the Entra group that should access every project:

   ```powershell
   ./scripts/deploy-user-projects.ps1
   ```

The script creates one project per name
(via [infra/user-projects.bicep](infra/user-projects.bicep)), grants the group
**Azure AI User** on **every** project, then rewrites the projects file with
each project's Foundry endpoint:

```
# project | foundryEndpoint
project-01 | https://<account>.services.ai.azure.com/api/projects/project-01
project-02 | https://<account>.services.ai.azure.com/api/projects/project-02
```

Hand out the `foundryEndpoint` for whichever project each user should use.

---

## Step 0 — Install the tools (one time)

You need three tools. Open **PowerShell** and install any that are missing.

1. **Azure CLI** (`az`)

   ```powershell
   winget install --exact --id Microsoft.AzureCLI
   ```

2. **Python 3.11+** (only needed for Part B, the data load)

   ```powershell
   winget install --exact --id Python.Python.3.12
   ```

3. **Git** (to clone the workshop repo)

   ```powershell
   winget install --exact --id Git.Git
   ```

Close and reopen PowerShell after installing, then verify:

```powershell
az version
python --version
git --version
```

### Sign in

```powershell
az login
az account set --subscription "<your-subscription-name-or-id>"
```

> **What permissions do *you* (the operator) need?**
> To run all three parts you need **Owner** (or **Contributor** + **User Access
> Administrator**) on the target subscription or resource group, plus quota for
> the Azure AI models in your chosen region.

> **Tokens expire.** Your `az` sign-in token lapses after a period of
> inactivity. If a script stops with `ERROR: Login expired` or `AADSTS700082`,
> sign in again with `az login` (add `--tenant <your-tenant-id>` if prompted),
> then re-run the script.

---

## Step 1 — Configure (change anything you like)

Everything is configurable in **[infra/main.parameters.json](infra/main.parameters.json)**.
Open it and adjust as needed — the most common changes:

| Setting | What it controls |
| ------- | ---------------- |
| `workshopName`, `environmentName` | Prefix used in every resource name. |
| `primaryLocation` | Region for every resource (default `swedencentral`). |
| `aiFoundry.location` | Region for Foundry + models (default `swedencentral`). |
| `aiFoundry.deployments` | The models and capacities to deploy. |
| `aiFoundry.chatDeploymentName` / `embeddingDeploymentName` | Which deployments become the chat and embedding models in `.env`. |
| `aiSearch`, `containerRegistry`, `containerApps` | SKUs and sizes. |
| `cosmosDb` | Database name, container names, and throughput. |

You do **not** need to pick resource names — they are generated automatically
from `workshopName` + `environmentName` and are globally unique.

**Select the resource group.** You always deploy into an **existing** resource
group that you choose — the scripts never create one. Create one (or reuse an
existing group) and pass its name to `deploy.ps1` in the next step:

```powershell
az group create --name rg-zava-sandbox --location swedencentral
```

---

## Step 2 — Part A: provision the infrastructure

```powershell
./scripts/deploy.ps1 -ResourceGroup rg-zava-sandbox
```

This deploys `infra/main.bicep` into the **existing** resource group you pass
(it never creates one), then saves the deployment outputs to
`.azure/main-outputs.json` and records the selected subscription / resource
group / location in `.azure/deploy-config.json` (used by the next steps). When
it finishes, all resources exist but contain no data.

> **Multiple isolated Foundry projects (optional).** Part A creates a single
> shared Foundry project. If you instead want **several isolated projects** in
> the same Foundry account — all sharing the same account-level models — list
> the project names (one per line) in
> [infra/foundry-projects.txt](infra/foundry-projects.txt) and, after this step,
> run:
>
> ```powershell
> ./scripts/deploy-user-projects.ps1 -GroupObjectId <entra-group-object-id>
> ```
>
> This creates one project per name and grants the Entra **group** Azure AI User
> on **every** project, then writes each project's endpoint back into the file.
> See [Multiple isolated projects (optional)](#multiple-isolated-projects-optional)
> for details.

---

## Step 3 — Part B: load the data

First clone the workshop repo and install its Python dependencies:

```powershell
git clone https://github.com/SinglaSandeep/ai-agents-workshop.git C:\dev\ai-agents-workshop
cd C:\dev\ai-agents-workshop
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .
cd ..\ai-workshop-infra
```

Then run the data load (point it at that clone):

```powershell
./scripts/load-data.ps1 -WorkshopPath C:\dev\ai-agents-workshop
```

This will:

1. Grant **you** (the operator) the temporary data-plane roles needed to seed
   Cosmos and build the Search index.
2. Write a ready-to-use `.env` into the workshop repo.
3. Seed the `sales`, `inventory`, and `marketing_campaigns` Cosmos containers.
4. Build the `zava-marketing-kb` Foundry IQ knowledge base.

> Run it from the **activated** Python virtual environment so the `python -m ...`
> seed commands resolve. Use `-SkipSeed` or `-SkipKnowledgeBase` to run only
> part of the load.

---

## Step 4 — Part C: grant resource (service-to-service) access

This lets the workshop's own services call each other (Foundry → Search,
Foundry → Container Registry) using managed identities. Adjust the levels in
[infra/resource-access.parameters.json](infra/resource-access.parameters.json)
if you need to, then run:

```powershell
./scripts/grant-resource-access.ps1
```

---

## Step 5 — Part D: grant participant access

Edit **[infra/user-access.parameters.json](infra/user-access.parameters.json)**
and replace the placeholder with your real Entra users or groups (the access
levels are configurable in the same file):

```jsonc
{
  "objectId": "<entra-user-or-group-object-id>",
  "principalType": "Group",          // or "User"
  "displayName": "workshop-participants"
}
```

Find an object id:

```powershell
# a group
az ad group show --group "workshop-participants" --query id -o tsv
# a single user
az ad user show --id alias@contoso.com --query id -o tsv
```

Then apply the grants:

```powershell
./scripts/grant-user-access.ps1
```

---

## Teardown

When the workshop is over:

```powershell
./scripts/destroy.ps1 -ResourceGroup rg-zava-sandbox
```

This deletes every **resource inside** the resource group (and purges any
soft-deleted Foundry accounts) but **keeps the resource group itself** — you
selected it, so it stays. To also revoke the role assignments first, run
`./scripts/revoke-user-access.ps1` and `./scripts/revoke-resource-access.ps1`
before this step.

---

## Project structure

```
azure.yaml                          azd project definition
infra/
  main.bicep                        entry point (Part A)
  main.parameters.json              central, fully configurable workshop settings
  modules/
    core-resources.bicep            shared resources
    foundry.bicep                   one Foundry stack (account + project + models)
    tags.bicep                      standard resource tags
  resource-access.bicep             service-to-service access (Part C)
  resource-access.parameters.json   which service grants + levels
  user-access.bicep                 participant access (Part D)
  user-access.parameters.json       the users/groups to grant + access levels
  user-projects.bicep               optional: multiple isolated Foundry projects + group access
  foundry-projects.txt              optional: project names to create (how many projects)
scripts/
  deploy.ps1                        Part A - provision
  load-data.ps1                     Part B - seed data + build KB + write .env
  grant-resource-access.ps1         Part C - grant service-to-service access
  revoke-resource-access.ps1        remove service-to-service access
  grant-user-access.ps1             Part D - grant participant access
  revoke-user-access.ps1            remove participant access
  deploy-user-projects.ps1          optional - multiple isolated Foundry projects + group access
  destroy.ps1                       teardown
```

---

## Troubleshooting

| Symptom | Fix |
| ------- | --- |
| `azd up` fails with `ERROR: Login expired` / `AADSTS700082` | The sign-in token lapsed. Run `azd auth login --tenant-id <your-tenant-id>` (and `az login` if needed), then re-run the script. |
| `azd up` fails on a model deployment with a quota error | Lower `capacity` in `aiFoundry.deployments`, or change `aiFoundry.location` / `primaryLocation` to a region with quota. |
| Seed commands fail with a 403 from Cosmos | Wait a minute for the operator role grant to propagate, then re-run `load-data.ps1` (it is idempotent). |
| `python -m src...` not found | Activate the workshop venv and `pip install -e .` inside the workshop repo. |
| KB build fails with `ModuleNotFoundError: No module named 'azure.search'` | The workshop's `pip install -e .` doesn't pull in the Search SDK. Install it into the workshop venv: `pip install "azure-search-documents==11.7.0b2"`, then re-run `load-data.ps1 -SkipSeed`. |
| Participants get 401 from Search/Foundry right after Part D | Azure RBAC can take a few minutes to propagate. |

---

## How it works (design notes)

### Participant permission model

Every participant (user or Entra group) is granted built-in **Contributor** at
the **resource group** scope by `user-access.bicep` (Part D). That lets them
manage and use every resource in the workshop RG. Because services keep their
default key / connection-string auth, Contributor also lets participants read
the keys they need (including Cosmos). The role is configurable in
`user-access.parameters.json`.

### Resource (service / app) access (Part C)

Services authenticate to each other with keys / connection settings, so there
are no per-resource role assignments. Part C simply grants any service
principals / apps listed in `resource-access.parameters.json` **Contributor**
on the resource group, deployed by `resource-access.bicep` and configurable on
its own. Leave the `servicePrincipals` array empty to grant nothing.

### Auth posture — key-based authentication

This is a sandbox workshop, so services keep their **default key / connection
string** authentication and talk to each other with keys (no managed
identities). Access for people and apps is granted with Azure RBAC at the
resource group scope by the Part C / Part D scripts. The data-load operator
still receives temporary data-plane roles in `load-data.ps1` so it can seed
Cosmos and build the Search index.

### Why the four-part split

| Part | Mechanism | Reason |
| ---- | --------- | ------ |
| A. Infra | `deploy.ps1` / `main.bicep` | Repeatable, declarative provisioning into your resource group. |
| B. Data | `load-data.ps1` + workshop Python | Seeding is a data-plane operation that needs the workshop code; kept out of Bicep. |
| C. Resource access | `resource-access.bicep` / `grant-resource-access.ps1` | Service-principal / app grants, reviewable and configurable on their own. |
| D. User access | `user-access.bicep` / `grant-user-access.ps1` | Participant access, reviewed and changed without touching infrastructure. |
