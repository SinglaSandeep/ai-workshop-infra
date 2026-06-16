# PepsiCo Workshop — Data Platform Infrastructure

This branch (`Pradipta_changes`) extends the shared workshop infrastructure
with the **Data Platform** resources needed for Pradipta's Day 1/Day 2 labs:

| Service | Lab | Why |
| ------- | --- | --- |
| Azure OpenAI (`text-embedding-3-small` + `gpt-4o-mini`) | Lab 03, Data Agent | Embeddings for vector search; chat for Fabric Data Agent |
| Azure SQL Database (with `VECTOR` type) | Lab 03 | Native vector table for cosine similarity retrieval |
| Azure Machine Learning (workspace + compute cluster) | Lab 04 | Train, register, deploy a model; expose as agent tool |
| Azure Storage Account (ADLS Gen2) | Lab 04, Lab 01 | AML artifact store; raw landing for Lakehouse |
| Azure Key Vault | All labs | Secure storage of endpoints and keys for participants |
| Microsoft Fabric capacity (F2) | Labs 01, 02, Demo 01 | Lakehouse, RTI, Data Agent, governance |
| Application Insights + Log Analytics | Lab 04 | AML workspace telemetry |

---

## What gets created (Data Platform additions)

In addition to Sandeep's agentic AI resources (AI Foundry, Cosmos DB, AI Search,
Container Apps), this branch provisions:

```
Azure OpenAI account
  └── text-embedding-3-small deployment (60K TPM)
  └── gpt-4o-mini deployment (60K TPM)
Azure SQL server (Entra-only auth)
  └── db_pepsi_rag database (GP serverless, VECTOR type)
Azure Machine Learning workspace
  └── cpu-cluster (Standard_DS3_v2, 0-2 nodes)
Azure Storage Account (ADLS Gen2)
Azure Key Vault (RBAC-enabled)
Application Insights + Log Analytics
Microsoft Fabric capacity (F2) — optional, off by default
```

---

## Quick start

### Prerequisites

Same as the base repo (Azure CLI, azd, Python 3.11+, Git).
Additionally: **ODBC Driver 18 for SQL Server** (for Lab 03 data load).

### Step 1 — Configure

Edit `infra/main.parameters.json`:

1. Replace `<REPLACE-WITH-YOUR-ENTRA-OBJECT-ID>` with your Entra user object ID.
2. Replace `<REPLACE-WITH-YOUR-UPN>` with your UPN (e.g., `alias@contoso.com`).
3. Adjust regions if needed (default: `eastus2`).
4. Set `enableFabric: true` if you want Bicep to provision Fabric capacity.

```powershell
azd env new pepsi-sandbox
azd env set AZURE_LOCATION eastus2
```

### Step 2 — Deploy infrastructure (Part A)

```powershell
./scripts/deploy.ps1
```

### Step 3 — Load data platform data (Part B-Data)

```powershell
./scripts/load-data-platform.ps1 -WorkshopPath C:\dev\pepsico-msft-workshop
```

This creates the vector table in Azure SQL, embeds the product corpus,
and seeds Key Vault with connection info.

### Step 4 — Load agentic AI data (Part B — Sandeep's)

```powershell
./scripts/load-data.ps1 -WorkshopPath C:\dev\ai-agents-workshop
```

### Step 5 — Grant service-to-service access (Part C)

```powershell
./scripts/grant-resource-access.ps1
```

### Step 6 — Grant participant access (Part D)

```powershell
./scripts/grant-user-access.ps1
```

Participants receive:
- **Azure OpenAI**: Cognitive Services User (call models, not deploy)
- **Azure ML**: AzureML Data Scientist (train, deploy endpoints)
- **Azure SQL**: Entra authentication (db_datareader via SQL script)
- **Cosmos DB**: Read/write items (custom role)
- **AI Foundry**: Foundry User (run/create agents)
- **AI Search**: Search Index Data Reader

---

## Teardown

```powershell
./scripts/destroy.ps1
```

---

## Project structure (additions highlighted)

```
infra/
  main.bicep                        entry point (updated: orchestrates all modules)
  main.parameters.json              central config (updated: dataPlatform section)
  modules/
    core-resources.bicep            Sandeep's resources (unchanged)
    foundry.bicep                   one Foundry stack (unchanged)
    tags.bicep                      standard tags (unchanged)
    azure-openai.bicep              ★ NEW: Azure OpenAI account + deployments
    azure-sql.bicep                 ★ NEW: Azure SQL server + database (VECTOR)
    azure-ml.bicep                  ★ NEW: AML workspace + compute cluster
    storage.bicep                   ★ NEW: ADLS Gen2 storage account
    keyvault.bicep                  ★ NEW: Key Vault (RBAC-enabled)
    fabric-capacity.bicep           ★ NEW: Microsoft Fabric capacity (optional)
    observability.bicep             ★ NEW: App Insights + Log Analytics
  resource-access.bicep             service-to-service access (unchanged)
  resource-access.parameters.json   grant config (unchanged)
  user-access.bicep                 participant access (updated: OpenAI + AML grants)
  user-access.parameters.json       user list (unchanged)
scripts/
  deploy.ps1                        Part A (unchanged)
  load-data.ps1                     Part B - Sandeep's data (unchanged)
  load-data-platform.ps1            ★ NEW: Part B-Data - vector load + KV seed
  grant-resource-access.ps1         Part C (unchanged)
  grant-user-access.ps1             Part D (updated: passes openAi + aml params)
  revoke-resource-access.ps1        remove service access (unchanged)
  revoke-user-access.ps1            remove participant access (unchanged)
  destroy.ps1                       teardown (unchanged)
```

---

## Feature flags

| Flag | Default | Controls |
| ---- | ------- | -------- |
| `enableAiFoundry` | `true` | Sandeep's AI Foundry + model deployments |
| `enableAiSearch` | `true` | Azure AI Search |
| `enableContainerApps` | `true` | Container Apps + Registry + observability |
| `enableCosmosDb` | `true` | Cosmos DB NoSQL |
| `enableDataPlatform` | `true` | ★ Azure OpenAI, SQL, AML, Storage, Key Vault |
| `enableFabric` | `false` | ★ Microsoft Fabric capacity (provision manually if preferred) |

Set any flag to `false` to skip that resource group entirely.

---

## Troubleshooting

| Symptom | Fix |
| ------- | --- |
| `VECTOR type not supported` in Azure SQL | Database region doesn't support VECTOR yet. Change `dataPlatform.sqlLocation` to `eastus2` or `westus2`. |
| AML deployment takes >15 min | Normal for first container image pull. Use the shared fallback endpoint. |
| Azure OpenAI quota error | Lower `capacity` in `openAiDeployments` or switch region. |
| Fabric capacity not available | Set `enableFabric: false` and provision manually via Fabric admin portal. |
| `embed_and_load.py` fails with 403 | Wait for RBAC propagation (60s) or re-run `load-data-platform.ps1`. |
