# Day 2 (Data) — Customer Deployment Guide

> **Scope.** This guide is for the **Day 2 / Data** workshop track only (Pradipta).
> Day 1 (Sandeep — Agentic AI: Foundry, Cosmos, AI Search, Container Apps,
> ACR, AOAI) is deployed separately via [`scripts/deploy.ps1`](scripts/deploy.ps1).
> Day 2 deploys **into the same resource group** Sandeep used.

## What gets created

| Resource | Why | Used by |
| --- | --- | --- |
| **Microsoft Fabric capacity** (F2+) | Fabric workspace runtime | Lab 01 (Lakehouse + Data Agent), Lab 02 (RTI), Governance demo |
| **Azure SQL Server + Database** (Entra-only, `VECTOR(1536)` capable) | Vector search demo | Lab 03 (Vector Search) |
| **Microsoft Purview** account | Catalog, lineage, classifications | Governance demo |

Sandeep's existing services are reused:
- **Azure OpenAI** (text-embedding-3-small + a chat model) — embeddings + chat for Lab 03
- **Cosmos DB** (already in Day 1 stack) — read-along comparison in Lab 03

## What you will need before running

| # | Item | How to get it |
|---|---|---|
| 1 | **Existing resource group** (from Sandeep's Day 1 deploy) | `az group list -o table` |
| 2 | **Azure region** | Must support Fabric + SQL VECTOR + Purview. Recommended: `eastus2`, `swedencentral`, `westus3`. |
| 3 | **Fabric admin Object ID** | Entra Object ID of the user/group that should own the Fabric capacity. `az ad signed-in-user show --query id -o tsv` for yourself, or `az ad group show --group <name> --query id -o tsv`. |
| 4 | **SQL Entra admin UPN + Object ID** | The principal that becomes the SQL server admin (Entra-only auth, no SQL password). Often the same user/group as #3. |
| 5 | **Workshop participants Entra group** (Object ID + display name) | The group that gets workshop access. Created in Entra ID. |
| 6 | **Sandeep's AOAI account name** | From Sandeep's Day 1 deploy outputs. Empty = skip AOAI grant. |

## Step 1 — Provision Day 2 resources

```powershell
cd data-workshop-infra

./scripts/deploy-day2.ps1 `
    -ResourceGroupName  rg-pepsi-shared `
    -Location           eastus2 `
    -FabricAdminObjectId  4c517221-2844-4edd-84e1-8a3f5f4bb55f `
    -SqlAadAdminLogin     admin@contoso.com `
    -SqlAadAdminObjectId  4c517221-2844-4edd-84e1-8a3f5f4bb55f
```

Optional flags:

| Flag | Purpose |
|---|---|
| `-FabricSku F4` | Bigger capacity (default `F2`). |
| `-SkipFabric` | Customer already has a Fabric capacity. |
| `-SkipSql` | Don't deploy Azure SQL. |
| `-SkipPurview` | Don't deploy Purview. |

**Outputs.** After success the script writes:
- `.azure/main-day2-outputs.json` — full deployment outputs
- `.azure/workshop-day2.env` — endpoints in `KEY=value` form for the workshop notebooks

## Step 2 — Grant participant access

```powershell
./scripts/grant-user-access-day2.ps1 `
    -ResourceGroupName        rg-pepsi-shared `
    -WorkshopGroupObjectId    11111111-2222-3333-4444-555555555555 `
    -WorkshopGroupDisplayName 'pepsi-workshop-day2-attendees' `
    -SandeepAzureOpenAIName   aoai-pepsi-shared `
    -RunSqlSetup
```

This script does three things:

1. **Azure RBAC (automatic)** — grants `Cognitive Services User` on Sandeep's AOAI account so participants can call embeddings + chat from Lab 03.
2. **Manual portal grants (printed instructions)** — Fabric capacity admin + Purview Studio collection role assignments. These cannot be made by ARM/Bicep.
3. **SQL setup (`-RunSqlSetup`)** — runs [`Allfiles/lab03/setup-sql-vector.sql`](Allfiles/lab03/setup-sql-vector.sql) which:
   - `CREATE USER [<workshop group>] FROM EXTERNAL PROVIDER`
   - Adds them to `db_datareader` and `db_datawriter`
   - Creates `dbo.documents` table with a `VECTOR(1536)` column
   - Creates `dbo.search_documents(@query, @top)` cosine-similarity TVF

Requires `sqlcmd` on the operator machine and the operator must be the SQL Entra admin set in step 1.

## Step 3 — Bulk-provision one Fabric workspace per attendee

For ~60 attendees, every person gets their own isolated workspace bound to
the shared Fabric capacity. There is no Bicep/ARM resource for Fabric
workspaces — this is done via the Fabric REST API.

```powershell
./scripts/provision-fabric-workspaces.ps1 `
    -AttendeesCsv  Allfiles/attendees.csv `
    -CapacityName  <fabric-capacity-name-from-step-1>
```

Input CSV columns: `UPN, ObjectId, DisplayName` (see `Allfiles/attendees-sample.csv`).

Output: `.azure/workspace-assignments.csv` with one row per attendee:
`UPN, WorkspaceName, WorkspaceId, WorkspaceUrl, Status`.

Hand each attendee their `WorkspaceUrl` and they will land in their own
workspace pre-bound to the Fabric capacity, as **Admin** so they can create
the Lab 01 Lakehouse, run notebooks, build the semantic model, and create
their Fabric Data Agent.

> **Capacity sizing.** F2 supports only ~1 concurrent Spark session. For 60
> attendees running Lab 01 + Lab 02 in parallel, you need **F32 minimum**
> (~16 concurrent Spark sessions) or **F64 comfortable** (~32). Re-run
> `deploy-day2.ps1 -FabricSku F64` the morning of the workshop, then drop
> back to `F2` (or pause) the evening after.

## Step 4 — Point participants at the resources

Distribute these to attendees (already in `.azure/workshop-day2.env`):

| Setting | Source |
|---|---|
| `FABRIC_CAPACITY_NAME` | Used to bind a Fabric workspace to the capacity. |
| `SQL_SERVER_FQDN` / `SQL_DATABASE_NAME` | Lab 03 connection string. |
| `PURVIEW_ACCOUNT_NAME` / `PURVIEW_ATLAS_ENDPOINT` | Governance demo. |
| `AZURE_OPENAI_ENDPOINT` (Sandeep) | Lab 03 embeddings. Take from Sandeep's `.env`. |
| `AZURE_OPENAI_EMBEDDING_DEPLOYMENT` | `text-embedding-3-small` (or whatever Sandeep deployed). |

Attendees authenticate to all of these via `DefaultAzureCredential` — there are no keys to distribute.

## Teardown

```powershell
az deployment group create --resource-group <rg> --template-file infra/main-day2.bicep `
    --parameters enableFabricCapacity=false enableSqlVector=false enablePurview=false `
        fabricAdminObjectId=00000000-0000-0000-0000-000000000000 `
        sqlAadAdminLogin=admin sqlAadAdminObjectId=00000000-0000-0000-0000-000000000000
```

Or simpler — delete the three resources directly:

```powershell
az resource delete --resource-group <rg> --name <fabricCapacityName> --resource-type Microsoft.Fabric/capacities
az sql db delete --resource-group <rg> --server <sqlServer> --name vectordb --yes
az sql server delete --resource-group <rg> --name <sqlServer> --yes
az purview account delete --resource-group <rg> --name <purviewAccountName> --yes
```

## Files in this slim Day 2 set

| File | Purpose |
|---|---|
| `infra/main-day2.bicep` | Day 2 infra entry point (Fabric + SQL + Purview) |
| `infra/main-day2.parameters.json` | Customer-edited parameters |
| `infra/modules/fabric-capacity.bicep` | Fabric F SKU capacity |
| `infra/modules/sql.bicep` | Azure SQL Server + DB (Entra-only) |
| `infra/modules/purview.bicep` | Purview account (system-assigned identity) |
| `infra/user-access-day2-slim.bicep` | RBAC on Sandeep's AOAI for participants |
| `infra/user-access-day2-slim.parameters.json` | Customer-edited participant list |
| `scripts/deploy-day2.ps1` | One-shot deploy wrapper |
| `scripts/grant-user-access-day2.ps1` | Participant access wrapper |
| `Allfiles/lab03/setup-sql-vector.sql` | Lab 03 SQL setup (run by `grant-user-access-day2.ps1 -RunSqlSetup`) |

Anything else in this repo (azd flow, fat dataPlatform stack, AML, Storage HNS, Key Vault, PostgreSQL, foundry-projects, etc.) belongs to **Day 1 (Sandeep)** or is **legacy/unused for Day 2** and is safe to ignore.
