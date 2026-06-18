# Workshop — Azure CLI commands

Manual `az` commands to stand up the **sandbox** workshop. Everything is
deployed into a **single region (`swedencentral`)** and an **existing resource
group that you select** — these commands never create a resource group except
in the explicit step below.

Run them from the repo root (`c:\dev\ai-workshop-infra`) in order.

## Prerequisites

```powershell
# Sign in and pick the subscription
az login
az account set --subscription "<your-subscription-name-or-id>"

# Variables reused by every command below
$RG = "rg-zava-sandbox"
$LOCATION = "swedencentral"

# Create the resource group (or skip this and reuse an existing one)
az group create --name $RG --location $LOCATION
```

---

## 1) Provisioning

Creates all shared resources directly with `az` — no bicep template and no
PowerShell script. The values below match `infra/main.parameters.json`
(region `swedencentral`, the `zava` Cosmos database, `gpt-4.1-mini` +
`text-embedding-3-small`, etc.). Adjust the names/SKUs as you like.

```powershell
# Resource names (pick globally-unique names for Foundry, Search, ACR, Cosmos)
$SUFFIX = "wrk01"
$FOUNDRY = "aif-$SUFFIX"
$PROJECT = "proj-$SUFFIX"
$SEARCH = "srch-$SUFFIX"
$ACR = "cr$SUFFIX"
$COSMOS = "cosmos-$SUFFIX"
$ACA_ENV = "cae-$SUFFIX"
$LAW = "law-$SUFFIX"
$APPI = "appi-$SUFFIX"

# One-time: make sure the CLI extensions used below are installed
az extension add --name application-insights --only-show-errors
az extension add --name containerapp --only-show-errors

# Register the resource providers (only needed the first time in a subscription)
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.Search
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.ContainerRegistry
```

### Observability — Log Analytics + Application Insights

```powershell
az monitor log-analytics workspace create `
  --resource-group $RG --workspace-name $LAW `
  --location $LOCATION --retention-time 30

$LAW_ID = az monitor log-analytics workspace show `
  --resource-group $RG --workspace-name $LAW --query id -o tsv

az monitor app-insights component create `
  --resource-group $RG --app $APPI `
  --location $LOCATION --kind web --application-type web `
  --workspace $LAW_ID
```

### Azure AI Search

```powershell
az search service create `
  --resource-group $RG --name $SEARCH `
  --location $LOCATION --sku basic `
  --replica-count 1 --partition-count 1
```

### Container Registry + Container Apps environment

```powershell
az acr create `
  --resource-group $RG --name $ACR `
  --location $LOCATION --sku Basic --admin-enabled true

az containerapp env create `
  --resource-group $RG --name $ACA_ENV `
  --location $LOCATION `
  --logs-destination none
```

### Azure AI Foundry — account + project + model deployments

```powershell
# Foundry (Cognitive Services AIServices) account
az cognitiveservices account create `
  --resource-group $RG --name $FOUNDRY `
  --location $LOCATION --kind AIServices --sku S0 `
  --custom-domain $FOUNDRY `
  --yes

# Foundry project (child of the account)
az cognitiveservices account project create `
  --resource-group $RG --name $FOUNDRY --project-name $PROJECT --location $LOCATION

# Chat model deployment
az cognitiveservices account deployment create `
  --resource-group $RG --name $FOUNDRY `
  --deployment-name gpt-4.1-mini `
  --model-name gpt-4.1-mini --model-version 2025-04-14 --model-format OpenAI `
  --sku-name GlobalStandard --sku-capacity 200

# Embedding model deployment (marketing knowledge base / Foundry IQ)
az cognitiveservices account deployment create `
  --resource-group $RG --name $FOUNDRY `
  --deployment-name text-embedding-3-small `
  --model-name text-embedding-3-small --model-version 1 --model-format OpenAI `
  --sku-name GlobalStandard --sku-capacity 350
```

### Azure Cosmos DB for NoSQL — `zava` database + containers

```powershell
# Account with the NoSQL vector-search capability
az cosmosdb create `
  --resource-group $RG --name $COSMOS `
  --locations regionName=$LOCATION failoverPriority=0 isZoneRedundant=False `
  --capabilities EnableNoSQLVectorSearch `
  --default-consistency-level Session

# Database
az cosmosdb sql database create `
  --resource-group $RG --account-name $COSMOS --name zava

# Containers (partition key /id, 400 RU/s each)
foreach ($c in @("sales","inventory","marketing_campaigns")) {
  az cosmosdb sql container create `
    --resource-group $RG --account-name $COSMOS --database-name zava `
    --name $c --partition-key-path "/id" --throughput 400
}
```

### Read back the values you need for the later sections

```powershell
$AI_PROJECT_ENDPOINT = "https://$FOUNDRY.services.ai.azure.com/api/projects/$PROJECT"
$SEARCH_ENDPOINT = "https://$SEARCH.search.windows.net"
$COSMOS_ENDPOINT = az cosmosdb show -g $RG -n $COSMOS --query documentEndpoint -o tsv
$APPI_CONNECTION = az monitor app-insights component show -g $RG --app $APPI --query connectionString -o tsv
```

> Names for Foundry, Search, ACR and Cosmos must be globally unique — change
> `$SUFFIX` if a create call reports the name is taken.

### Load the workshop data into Cosmos DB

The containers created above are empty. Seed them with the workshop's
deterministic Python seeders (idempotent — re-running upserts the same
documents). The seeders authenticate with the **Cosmos account key**
(key-based), so no data-plane role assignment is needed.

```powershell
# Clone the workshop app repo and install its Python package
git clone https://github.com/SinglaSandeep/ai-agents-workshop.git C:\dev\ai-agents-workshop
cd C:\dev\ai-agents-workshop
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .

# Read the Cosmos endpoint + primary key (key-based auth)
$COSMOS_ENDPOINT = az cosmosdb show -g $RG -n $COSMOS --query documentEndpoint -o tsv
$COSMOS_KEY = az cosmosdb keys list -g $RG -n $COSMOS --query primaryMasterKey -o tsv

# Write the minimal .env the seeders read (pydantic-settings)
@"
COSMOS_ENDPOINT=$COSMOS_ENDPOINT
COSMOS_KEY=$COSMOS_KEY
COSMOS_DATABASE=zava
COSMOS_SALES_CONTAINER=sales
COSMOS_INVENTORY_CONTAINER=inventory
COSMOS_MARKETING_CONTAINER=marketing_campaigns
"@ | Set-Content -Path .env -Encoding utf8

# Seed each container (creates it if missing, then upserts the rows)
python -m src.mcp_servers.sales.seed.seed_cosmos
python -m src.mcp_servers.inventory.seed.seed_cosmos
python -m src.mcp_servers.marketing.seed.seed_cosmos
```

Verify the documents landed (counts the rows in each container via the
data-plane, using the same `COSMOS_KEY` from above):

```powershell
# Expose the Cosmos values to the Python child process
$env:COSMOS_ENDPOINT = $COSMOS_ENDPOINT
$env:COSMOS_KEY      = $COSMOS_KEY

foreach ($c in @("sales","inventory","marketing_campaigns")) {
  $count = python -c "import os; from azure.cosmos import CosmosClient; c = CosmosClient(os.environ['COSMOS_ENDPOINT'], os.environ['COSMOS_KEY']); print(list(c.get_database_client('zava').get_container_client('$c').query_items('SELECT VALUE COUNT(1) FROM c', enable_cross_partition_query=True))[0])"
  Write-Host "Container '$c': $count documents"
}
```

> Run the `python -m ...` commands from the **activated** virtual environment
> (`.\.venv\Scripts\Activate.ps1`) so the workshop package resolves.

---

## 2) Provisioning of Foundry projects

**Optional.** Create several isolated Foundry **projects** inside the **same**
Foundry account, all sharing the account's model deployments. One Entra **group**
is granted **Azure AI User** on every project.

The project names are read from [`foundry-projects.txt`](foundry-projects.txt) —
one name per line (blank lines and `#` comments are ignored). Add as many as you
need (20, 50, …) and re-run the loop below.

```powershell
# The Foundry account created in section 1 (or set it manually)
$FOUNDRY = az cognitiveservices account list -g $RG --query "[?kind=='AIServices'].name | [0]" -o tsv

# Read the project names from foundry-projects.txt (one per line, '#' = comment)
$projects = Get-Content foundry-projects.txt |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and -not $_.StartsWith('#') }

# Create one project per name (run once per project)
foreach ($p in $projects) {
  az cognitiveservices account project create `
    --resource-group $RG `
    --name $FOUNDRY `
    --project-name $p `
    --location $LOCATION
}
```

Grant an Entra group **Azure AI User** (`53ca6127-db72-4b80-b1b0-d745d6d5456d`)
at the **resource group** scope (data-plane: run + create agents, no deployment
management). RBAC inherits downward, so this one assignment covers **every**
Foundry account and project in the resource group — **including projects you add
later** — so you never have to re-run a per-project loop.

```powershell
$GROUP_OBJECT_ID = "<entra-group-object-id>"
$AI_USER_ROLE    = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
$RG_SCOPE        = az group show --name $RG --query id -o tsv

az role assignment create `
  --assignee-object-id $GROUP_OBJECT_ID `
  --assignee-principal-type Group `
  --role $AI_USER_ROLE `
  --scope $RG_SCOPE
```

> Use the RG-scoped grant when the resource group is dedicated to this workshop.
> The role only allows Foundry **data-plane** actions (run/create agents), not
> model-deployment management, so the wider scope stays low-risk.

<details>
<summary>Alternative — grant per project (tighter scope)</summary>

Scope the grant to individual projects instead of the whole RG when the group
should only reach specific projects. You must re-run this after adding projects:

```powershell
$GROUP_OBJECT_ID = "<entra-group-object-id>"
$AI_USER_ROLE = "53ca6127-db72-4b80-b1b0-d745d6d5456d"

# Same project list as above, read from the config file
$projects = Get-Content foundry-projects.txt |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and -not $_.StartsWith('#') }

foreach ($p in $projects) {
  $scope = az cognitiveservices account project show `
    --resource-group $RG --name $FOUNDRY --project-name $p --query id -o tsv

  az role assignment create `
    --assignee-object-id $GROUP_OBJECT_ID `
    --assignee-principal-type Group `
    --role $AI_USER_ROLE `
    --scope $scope
}
```

</details>

Each project's endpoint is:
`https://<foundry-account>.services.ai.azure.com/api/projects/<project-name>`

---

## 3) Access Granting

Everyone gets built-in **Contributor** (`b24988ac-6180-42a0-9c14-49b21d8d3a83`)
at the **resource group** scope. With key-based auth, Contributor also lets them
read the resource keys / connection strings they need (including Cosmos).

```powershell
$CONTRIBUTOR = "b24988ac-6180-42a0-9c14-49b21d8d3a83"
$RG_SCOPE = az group show --name $RG --query id -o tsv
```

### Participants (users / groups)

```powershell
# A workshop group (look up its id: az ad group show --group "<name>" --query id -o tsv)
az role assignment create `
  --assignee-object-id "<entra-group-object-id>" `
  --assignee-principal-type Group `
  --role $CONTRIBUTOR `
  --scope $RG_SCOPE

# An individual user (look up: az ad user show --id alias@contoso.com --query id -o tsv)
az role assignment create `
  --assignee-object-id "<entra-user-object-id>" `
  --assignee-principal-type User `
  --role $CONTRIBUTOR `
  --scope $RG_SCOPE
```

### Service principals / apps

```powershell
# Look up an app's SP object id: az ad sp show --id <appId> --query id -o tsv
az role assignment create `
  --assignee-object-id "<service-principal-object-id>" `
  --assignee-principal-type ServicePrincipal `
  --role $CONTRIBUTOR `
  --scope $RG_SCOPE
```

### Reusable user-assigned managed identity

Create one user-assigned managed identity now so it is available later (for
example, to attach to a Container App or other workload). Adding its principal
to the **same workshop group** means it inherits every role the group already
has (`Contributor` on the RG, `Azure AI User` on the RG, …) — no per-identity
role assignments to manage.

```powershell
$UAMI_NAME = "id-zava-workload"

# Create the identity (idempotent — re-running returns the existing one)
az identity create --resource-group $RG --name $UAMI_NAME --location $LOCATION

# Capture the values you will need later
$UAMI_RESOURCE_ID = az identity show -g $RG -n $UAMI_NAME --query id -o tsv
$UAMI_CLIENT_ID   = az identity show -g $RG -n $UAMI_NAME --query clientId -o tsv
$UAMI_PRINCIPAL_ID = az identity show -g $RG -n $UAMI_NAME --query principalId -o tsv

# Add the identity's service principal to the workshop group so it inherits
# the group's role assignments (group membership uses the principal/object id)
az ad group member add `
  --group $GROUP_OBJECT_ID `
  --member-id $UAMI_PRINCIPAL_ID
```

> Group-membership changes for a managed identity can take a few minutes (and a
> fresh token) to take effect. Confirm membership with:
> `az ad group member check --group $GROUP_OBJECT_ID --member-id $UAMI_PRINCIPAL_ID --query value -o tsv`

To attach this identity to a Container App later:
`az containerapp identity assign --name <app> --resource-group $RG --user-assigned $UAMI_RESOURCE_ID`
and set `AZURE_CLIENT_ID=$UAMI_CLIENT_ID` so `DefaultAzureCredential` selects it.

### Chat app managed identity → Foundry

The chat app deploy (`ai-agents-workshop/scripts/deploy-chat-app.ps1`) attaches
the **user-assigned identity** created above (`id-zava-workload`) to the
Container App and uses it to call the Foundry Agent Service (Foundry only
accepts Microsoft Entra ID, not API keys).

Because that identity is already a **member of the workshop group** — which has
`Azure AI User` on the resource group — it inherits Foundry access
automatically. **No extra role assignment is required**, and the deploy script
creates none.

Point the deploy at the identity by setting these in the workshop `.env`
(or let the script look it up by name, `id-zava-workload`):

```powershell
# From the "Reusable user-assigned managed identity" step above
"APP_IDENTITY_RESOURCE_ID=$UAMI_RESOURCE_ID" | Add-Content (Join-Path $WORKSHOP_PATH '.env')
"APP_IDENTITY_CLIENT_ID=$UAMI_CLIENT_ID"     | Add-Content (Join-Path $WORKSHOP_PATH '.env')
```

ACR image pull uses the registry's **admin credentials** (key-based), so the
chat app identity does **not** need `AcrPull`. Cosmos access likewise uses the
account key (`COSMOS_KEY`), so no Cosmos data-plane role is required.

> If you instead deploy with a fresh **system-assigned** identity (no group
> membership), an admin must grant that identity `Azure AI Developer` +
> `Cognitive Services User` on the Foundry account after the first deploy, since
> participants only have `Contributor` (which cannot create role assignments).

### Revoke (optional)

```powershell
az role assignment delete `
  --assignee-object-id "<object-id>" `
  --role $CONTRIBUTOR `
  --scope $RG_SCOPE
```

---

## 4) Deploy the application (MCP servers + chat app)

Ships the workshop code to Azure Container Apps: three **MCP servers** (sales,
inventory, marketing) and the **chat app**. All commands run from the workshop
repo with its virtual environment active and the `.env` populated by the data
load in section 1.

```powershell
$WORKSHOP = "C:\dev\ai-agents-workshop"
cd $WORKSHOP
.\.venv\Scripts\Activate.ps1
```

Make sure the `.env` has the resource values the deploy scripts read (the data
load wrote the `COSMOS_*` values; add the rest from sections 1–3):

```powershell
$ENV_FILE = Join-Path $WORKSHOP '.env'
@(
  "AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)"
  "AZURE_RESOURCE_GROUP=$RG"
  "ACR_NAME=$ACR"
  "ACA_ENVIRONMENT=$ACA_ENV"
  "AZURE_AI_PROJECT_ENDPOINT=$AI_PROJECT_ENDPOINT"
  "AZURE_AI_MODEL_DEPLOYMENT=gpt-4.1-mini"
  "COSMOS_KEY=$COSMOS_KEY"
  "APP_IDENTITY_RESOURCE_ID=$UAMI_RESOURCE_ID"
  "APP_IDENTITY_CLIENT_ID=$UAMI_CLIENT_ID"
) | Add-Content $ENV_FILE
```

> `COSMOS_KEY`, `$UAMI_RESOURCE_ID`, and `$UAMI_CLIENT_ID` come from the
> Cosmos data-load and the user-assigned identity steps above. The MCP servers
> use key-based auth (ACR admin creds + `COSMOS_KEY`); the chat app runs as the
> user-assigned identity (Foundry access via group membership).

### A. Deploy the three MCP servers

Each script builds `src/mcp_servers/<service>/Dockerfile` into ACR and creates a
public Container App (key-based ACR + Cosmos auth):

```powershell
./scripts/deploy-sales-mcp.ps1
./scripts/deploy-inventory-mcp.ps1
./scripts/deploy-marketing-mcp.ps1
```

Each run prints the server's public URL, for example
`https://zava-sales-mcp.<env-id>.<region>.azurecontainerapps.io/mcp`. Save all
three into the workshop `.env`:

```powershell
SALES_MCP_URL=https://zava-sales-mcp.<env-id>.<region>.azurecontainerapps.io/mcp
INVENTORY_MCP_URL=https://zava-inventory-mcp.<env-id>.<region>.azurecontainerapps.io/mcp
MARKETING_MCP_URL=https://zava-marketing-mcp.<env-id>.<region>.azurecontainerapps.io/mcp
```

### B. Point the Foundry agents at the deployed MCP servers

Re-run the agent-creation scripts so each Foundry agent's MCP connection targets
the public URL you just saved (instead of a local `localhost` endpoint):

```powershell
python -m src.foundry_agents.create_sales_agent
python -m src.foundry_agents.create_inventory_agent
python -m src.foundry_agents.create_marketing_agent
```

### C. Deploy the chat app

Builds the repo-root `Dockerfile` into ACR and creates the `zava-chat-app`
Container App, attached to the `id-zava-workload` user-assigned identity. You
are prompted securely for a Basic-auth password:

```powershell
./scripts/deploy-chat-app.ps1
```

The script prints the app URL. Open it, sign in with the Basic-auth credentials
(`demo-admin` + your password), and ask a cross-domain Zava question to confirm
the full orchestration runs in the cloud.

> Re-run any deploy script after a code change — they are idempotent (create on
> the first run, update afterward).

---

## Teardown (optional)

Delete the resources **inside** the resource group but keep the group itself.

### Teardown by resource type

Remove resources **type by type**, in a dependency-safe order (workloads first,
then the platforms they run on, then shared/observability resources). Each step
deletes only the resource types this document creates, so you can run a single
type in isolation or the whole sequence. Every step is idempotent — a type with
no matching resources is simply skipped.

```powershell
# Helper: delete all resources of a given type in the resource group
function Remove-ByType($type) {
  $ids = az resource list --resource-group $RG --resource-type $type --query "[].id" -o tsv
  if ($ids) {
    Write-Host "Deleting $type ..." -ForegroundColor Cyan
    az resource delete --ids $ids
  } else {
    Write-Host "No $type resources found — skipping." -ForegroundColor DarkGray
  }
}

# Order matters: delete dependent workloads before the platforms they depend on.
$orderedTypes = @(
  "Microsoft.App/containerApps",                       # chat app + 3 MCP servers
  "Microsoft.App/managedEnvironments",                 # Container Apps environment
  "Microsoft.CognitiveServices/accounts",              # Azure AI Foundry account + projects
  "Microsoft.DocumentDB/databaseAccounts",             # Cosmos DB
  "Microsoft.Search/searchServices",                   # Azure AI Search
  "Microsoft.ContainerRegistry/registries",            # Container Registry
  "Microsoft.ManagedIdentity/userAssignedIdentities",  # id-zava-workload
  "Microsoft.Insights/components",                      # Application Insights
  "Microsoft.OperationalInsights/workspaces"           # Log Analytics workspace
)

foreach ($type in $orderedTypes) { Remove-ByType $type }
```

> To remove just one category, call the helper directly, e.g.
> `Remove-ByType "Microsoft.App/containerApps"` to delete only the Container
> Apps, or `Remove-ByType "Microsoft.DocumentDB/databaseAccounts"` for Cosmos.

### Purge soft-deleted Foundry accounts

Deleting a `Microsoft.CognitiveServices/accounts` resource only soft-deletes it.
Purge it so the name is free for a redeploy:

```powershell
az cognitiveservices account list-deleted `
  --query "[?contains(id, '/resourceGroups/$RG/')].{name:name,location:location}" -o tsv |
  ForEach-Object {
    $parts = $_ -split "`t"
    az cognitiveservices account purge --name $parts[0] --resource-group $RG --location $parts[1]
  }
```

### Delete everything at once (any type)

Prefer the type-ordered teardown above. If you just want a clean sweep
regardless of type, delete every remaining resource in the group:

```powershell
# Delete every resource in the group (re-run if some remain due to dependencies)
$ids = az resource list --resource-group $RG --query "[].id" -o tsv
if ($ids) { az resource delete --ids $ids }
```
