# Architecture for 100 Participants - Day 2 Workshop

## TL;DR

**Deploy ONCE → Share with 100 users → Each user creates their own Fabric workspace**

**Total Cost:** $20-40 for 3-day workshop

---

## Deployment Model

```
┌─────────────────────────────────────────────────────────────┐
│  PepsiCo Azure Subscription (Deployed ONCE by Customer)     │
│                                                             │
│  Resource Group: rg-pepsi-workshop                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  SHARED INFRASTRUCTURE (100 users access these)      │  │
│  │                                                      │  │
│  │  • Azure OpenAI (1 endpoint)                        │  │
│  │  • Cosmos DB OR PostgreSQL (1 database)             │  │
│  │  • Azure ML Workspace (1 workspace)                 │  │
│  │  • Storage Account (1 account)                      │  │
│  │  • Key Vault (1 vault)                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  + RBAC: Entra Security Group "Workshop-Participants"      │
│    → 100 users granted read/execute permissions            │
└─────────────────────────────────────────────────────────────┘

          ↓ Each participant accesses shared resources ↓

┌─────────────────────────────────────────────────────────────┐
│  Participant 1 (john@pepsico.com)                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Fabric Workspace: WS_John_Day2 (FREE 60-day trial) │  │
│  │  • Lakehouse: LH_RetailData (LAB 01)                │  │
│  │  • Eventhouse: EH_Streaming (LAB 02)                │  │
│  │  • Notebooks, Pipelines, Dashboards                 │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Participant 2 (jane@pepsico.com)                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Fabric Workspace: WS_Jane_Day2 (FREE 60-day trial) │  │
│  │  • Lakehouse: LH_RetailData (LAB 01)                │  │
│  │  • Eventhouse: EH_Streaming (LAB 02)                │  │
│  │  • Notebooks, Pipelines, Dashboards                 │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

... (98 more participants, same pattern)
```

---

## Lab-by-Lab Architecture

### LAB 01: Fabric Lakehouse + Data Agent

**What each participant creates:**
- Personal Fabric Workspace (FREE trial)
- Lakehouse in their workspace
- Data Factory pipeline (ingests sample data)
- Spark notebooks (Bronze → Silver → Gold medallion)
- Power BI semantic model
- Fabric Data Agent

**Shared Azure resources used:**
- ❌ NONE (pure Fabric lab)
- OR ✓ Storage Account (optional - for hosting sample retail data files)

**Alternative:** Host sample data on GitHub → participants download → upload to Lakehouse

**Cost:** $0 (if using GitHub) OR $1-2 (if using Storage)

---

### LAB 02: Real-Time Intelligence

**What each participant creates:**
- Eventstream in their workspace
- Eventhouse (KQL database) in their workspace
- Real-Time Dashboard
- Activator alert

**Shared Azure resources used:**
- ❌ NONE (pure Fabric lab, uses built-in sample data source)

**Cost:** $0

---

### LAB 03: Vector Search

**What each participant does:**
1. Generate embeddings for sample documents (calls shared Azure OpenAI)
2. Load embeddings into database (shared Cosmos DB or PostgreSQL)
3. Run cosine similarity search
4. Expose as retrieval tool

**Shared Azure resources used:**
✓ **Azure OpenAI** (1 endpoint, all users call it)
  - RBAC: `Cognitive Services User` role
  - Each user gets same embeddings (deterministic)

✓ **Cosmos DB OR PostgreSQL** (1 database)
  - **Option A (Cosmos DB):** Each user has their own container
    ```
    Database: pepsi_rag
      Container: user_john_vectors
      Container: user_jane_vectors
      ... (100 containers)
    ```
  - **Option B (PostgreSQL):** Shared table with `user_id` column
    ```sql
    CREATE TABLE embeddings (
      id INT,
      user_id VARCHAR(100),  -- participant email
      document TEXT,
      embedding VECTOR(1536),
      PRIMARY KEY (id, user_id)
    );
    
    -- Each user queries only their data
    SELECT * FROM embeddings WHERE user_id = 'john@pepsico.com';
    ```

**Cost:** $5-15 total (Azure OpenAI tokens + Cosmos/Postgres serverless)

---

### LAB 04: Azure ML Train & Deploy

**What each participant does:**
1. Train a model on sample dataset (submits job to shared AML workspace)
2. Register model in model registry
3. Deploy to managed online endpoint
4. Score with sample data

**Shared Azure resources used:**
✓ **Azure ML Workspace** (1 workspace)
  - Compute cluster: 0-10 nodes (auto-scales)
  - Jobs queue automatically
  - Each participant's job is isolated

✓ **Storage Account** (1 account)
  - Each user's artifacts isolated by path:
    ```
    /azureml/
      /ExperimentRun/dcid.user_john_experiment_1/
      /ExperimentRun/dcid.user_jane_experiment_1/
    ```

**Data isolation strategy:**
- Participants name their experiments: `user_{email}_experiment`
- Models tagged with user email: `created_by=john@pepsico.com`
- Each user deploys to their own endpoint: `endpoint-john-model-v1`

**Cost:** $5-20 (compute only runs when jobs execute)

---

## Infrastructure Deployment (Customer)

### Step 1: Deploy Shared Infrastructure (15 minutes)

```powershell
# Clone repo
git clone https://github.com/SinglaSandeep/ai-workshop-infra.git
cd ai-workshop-infra
git checkout Pradipta_changes

# Configure
# Edit infra/main.parameters.json:
#   - Set adminObjectId to your Entra ID
#   - Set sqlAdministratorPassword

# Deploy
azd env new pepsi-workshop
azd env set AZURE_LOCATION eastus2
azd up
```

**What gets deployed:**
- 1x Azure OpenAI account
- 1x Cosmos DB account (with vector search)
- 1x Azure ML workspace + compute cluster
- 1x Storage account (ADLS Gen2)
- 1x Key Vault

**Total deployment time:** ~15 minutes

---

### Step 2: Grant Access to 100 Participants (5 minutes)

**Option A: Entra Security Group (Recommended)**

```powershell
# Create group
az ad group create --display-name "Workshop-Day2-Participants" --mail-nickname "workshop-day2"

# Add all 100 users to group (bulk import from CSV)
Import-Csv participants.csv | ForEach-Object {
    $userId = az ad user show --id $_.email --query id -o tsv
    az ad group member add --group "Workshop-Day2-Participants" --member-id $userId
}

# Get group ID
$groupId = az ad group show --group "Workshop-Day2-Participants" --query id -o tsv

# Grant RBAC permissions
# Edit infra/user-access.parameters.json - add group ID
.\scripts\grant-user-access.ps1
```

**Permissions granted:**
- `Cognitive Services User` → Call Azure OpenAI
- `AzureML Data Scientist` → Submit ML jobs
- `Cosmos DB Data Contributor` → Read/write Cosmos DB
- `Storage Blob Data Contributor` → Read/write Storage
- `Key Vault Secrets User` → Read connection strings

---

### Step 3: Participant Onboarding (30 minutes self-service)

Send email to all 100 participants (template in `PARTICIPANT-SETUP-GUIDE.md`):

1. **Verify Azure access:** Login to portal, confirm you see `rg-pepsi-workshop`
2. **Start Fabric trial:** Go to app.fabric.microsoft.com → Start Trial
3. **Create workspace:** `WS_<YourName>_Day2`
4. **Create Lakehouse:** `LH_RetailData`

---

## Cost Breakdown

| Component | Pricing Model | 3-Day Workshop Cost |
|-----------|---------------|---------------------|
| **Azure OpenAI** | Pay-per-token | $5-10 |
| **Cosmos DB** | Serverless (pay-per-RU) | $5-10 |
| **Azure ML** | Compute only when jobs run | $5-20 |
| **Storage** | Hot tier, ~10 GB | $1-2 |
| **Key Vault** | Standard tier | <$1 |
| **Fabric (100 users)** | 60-day trial | $0 |
| **TOTAL** | | **$20-40** |

**Post-workshop cleanup:**
```powershell
azd down --purge  # Deletes everything
```

---

## Data Isolation Strategies

### Strategy 1: Container-per-User (Cosmos DB)
**Pros:**
- Complete isolation
- Easy to delete user's data
- No accidental data mixing

**Cons:**
- 100 containers (management overhead)
- Higher RU usage (each container has separate index)

### Strategy 2: Shared Table with user_id Column (PostgreSQL/Cosmos)
**Pros:**
- Simple schema
- Lower resource usage
- Easy to query across all users (instructor view)

**Cons:**
- Requires app-level filtering (`WHERE user_id = ...`)
- Risk of data leakage if filter forgotten

### Strategy 3: User-scoped Access Keys (Recommended for Workshop)
**Approach:**
- Each user gets a unique API key (stored in Key Vault secret)
- API key maps to user's container/data scope
- Middleware enforces isolation

**Implementation:**
```python
# Lab script template
import os
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# Get user's unique connection string
user_email = "john@pepsico.com"
kv_client = SecretClient("https://pepsi-workshop-kv.vault.azure.net", DefaultAzureCredential())
cosmos_conn = kv_client.get_secret(f"cosmos-{user_email.split('@')[0]}").value

# User can only access their own data
```

---

## Alternative: Read-Only Shared Data (Simplest)

For LAB 03 (Vector Search), use **read-only shared dataset**:

1. Instructor pre-loads sample embeddings into 1 container
2. All 100 users query the SAME dataset
3. No write permissions needed
4. Zero data isolation concerns

**Trade-off:**
- Users can't practice "loading" embeddings (only querying)
- Simpler setup, zero cost

---

## Recommendations

### For 100 Participants:
1. ✅ **Use Entra Security Group** for RBAC (one-time setup)
2. ✅ **Cosmos DB with read-only shared data** for LAB 03 (simplest)
3. ✅ **Azure ML with user-tagged experiments** for LAB 04 (automatic isolation)
4. ✅ **Fabric trials** for LAB 01 & 02 (zero Azure cost)
5. ✅ **Sample data on GitHub** instead of Storage (saves $2)

### Total Deployment Time:
- Customer setup: 20 minutes
- Participant self-service: 30 minutes
- **Ready to start workshop**

### Total Cost:
- **$15-30 for 3-day workshop**
- **$0/month** after cleanup

---

## FAQ

**Q: What if 100 users overwhelm the OpenAI endpoint?**
A: Set `capacity: 240` (240K TPM) in parameters. Azure OpenAI has built-in rate limiting and queuing.

**Q: What if Azure ML compute cluster is too slow for 100 users?**
A: Set `amlComputeMaxNodes: 20` for more parallelism. Jobs queue automatically - participants may wait 5-10 minutes during peak times.

**Q: What if participants forget to delete their Fabric workspace?**
A: Fabric trials expire after 60 days and become read-only. No ongoing cost to PepsiCo.

**Q: Can we use this for multiple workshop sessions?**
A: Yes! Keep the Azure resources deployed. Just create a new Entra group for each cohort.

**Q: What if we need 200 participants?**
A: Same architecture! Just increase Azure OpenAI capacity and AML compute nodes. Cost scales linearly (~$40-60 for 200 users).

---

**Last Updated:** June 2026  
**Architecture:** Shared Resources + RBAC + Participant Self-Service
