# PepsiCo AI Workshop - Day 2 Infrastructure Deployment Guide

This guide walks you through deploying the **shared Azure infrastructure** needed for Day 2 labs. Participants will use these shared resources to complete hands-on exercises in Fabric, Real-Time Intelligence, Vector Search, and Azure ML.

---

## 📋 What Gets Deployed

### Pradipta's Data Platform Components (Day 2)

| Azure Service | Purpose | Workshop Labs |
|--------------|---------|---------------|
| **Azure OpenAI** | Text embeddings + chat completions | Lab 03 (Vector Search), Data Agent |
| ↳ _text-embedding-3-small_ | Generate embeddings for vector search | Lab 03 |
| ↳ _gpt-4o-mini_ | Chat completions for Data Agent | Lab 01, Demos |
| **Azure ML Workspace** | Train, register, and deploy ML models | Lab 04 (Model Training & Deployment) |
| **Storage Account (ADLS Gen2)** | Data lake for Lakehouse + AML artifacts | Lab 01 (Lakehouse), Lab 04 |
| **Cosmos DB NoSQL** | Vector search database (fallback for Lab 03) | Lab 03 (Vector Search) |
| **Key Vault** | Secure storage of connection strings | All labs |
| **Application Insights** | Monitoring & telemetry | Lab 04 |

### Architecture: Shared Resources + RBAC

```
┌────────────────────────────────────────────────────┐
│  Azure Subscription (Customer)                     │
│                                                    │
│  Resource Group: rg-pepsi-workshop                 │
│  ┌──────────────────────────────────────────────┐ │
│  │  ✓ 1x Azure OpenAI (shared by all)          │ │
│  │  ✓ 1x Azure ML Workspace (shared compute)   │ │
│  │  ✓ 1x Storage Account (ADLS Gen2)           │ │
│  │  ✓ 1x Cosmos DB (vector search)             │ │
│  │  ✓ 1x Key Vault (connection strings)        │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  + RBAC Permissions granted to:                   │
│    → Workshop participants (Entra users/groups)   │
└────────────────────────────────────────────────────┘

Each Participant Provisions (in Fabric Portal):
  ✓ Personal Fabric Workspace (FREE 60-day trial)
  ✓ Lakehouse, Pipelines, Notebooks (isolated)
```

**Cost Estimate:** ~$150-300/month for shared infrastructure serving 100+ users

---

## 🛠️ Prerequisites

Before deploying, ensure you have:

### 1. Azure Subscription
- **Owner** or **Contributor** role on the subscription
- **No restrictive policies** blocking:
  - Azure OpenAI provisioning
  - Storage account creation
  - Machine Learning workspace creation
- **Quota available** for:
  - Azure OpenAI model deployments (recommend eastus2 or westus)

### 2. Local Development Tools
Install these on your deployment machine (Windows, Mac, or Linux):

| Tool | Purpose | Install Command |
|------|---------|-----------------|
| **Azure CLI** | Interact with Azure resources | [Download](https://aka.ms/azure-cli) |
| **Azure Developer CLI (azd)** | Infrastructure deployment | [Download](https://aka.ms/azd) |
| **Git** | Clone repository | [Download](https://git-scm.com/) |
| **PowerShell** (Windows) or **Bash** (Mac/Linux) | Run deployment scripts | Pre-installed |

**Verify installations:**
```powershell
# Check Azure CLI
az --version

# Check Azure Developer CLI
azd version

# Check Git
git --version
```

### 3. Entra ID Setup
- List of **workshop participant email addresses** (or an Entra Security Group)
- Obtain **Object IDs** for users/groups:
  ```powershell
  # Get user Object ID
  az ad user show --id participant@company.com --query id -o tsv
  
  # Get group Object ID
  az ad group show --group "Workshop-Participants" --query id -o tsv
  ```

---

## 🚀 Deployment Steps

### Step 1: Clone the Repository

```powershell
# Clone Sandeep's workshop infrastructure repo (Pradipta_changes branch)
git clone https://github.com/SinglaSandeep/ai-workshop-infra.git
cd ai-workshop-infra

# Switch to Pradipta's branch with data platform additions
git checkout Pradipta_changes
```

---

### Step 2: Configure Deployment Parameters

Edit `infra/main.parameters.json` to customize the deployment:

```powershell
# Open in your editor (VS Code, Notepad, etc.)
code infra/main.parameters.json
```

**Key settings to change:**

#### 2.1 Workshop Name & Location
```json
{
  "workshopName": "pepsi-ai-workshop",          // Change if needed
  "environmentName": "prod",                     // "dev", "test", or "prod"
  "primaryLocation": "eastus2",                  // Change if needed (eastus2, westus, etc.)
}
```

#### 2.2 Enable/Disable Components
```json
"features": {
  "enableAiFoundry": false,          // Sandeep's component (Day 1) - set false for Day 2 only
  "enableAiSearch": false,           // Sandeep's component - set false
  "enableContainerApps": false,      // Sandeep's component - set false
  "enableCosmosDb": true,            // ✅ Keep true (needed for Lab 03 vector search)
  "enableDataPlatform": true,        // ✅ Keep true (Pradipta's Day 2 components)
  "enableFabric": false              // Manual provisioning recommended
}
```

#### 2.3 Admin User (for initial deployment)
```json
"dataPlatform": {
  "adminObjectId": "<YOUR-ENTRA-OBJECT-ID>",     // ⚠️ REPLACE with your Object ID
  "aadAdminLogin": "admin@yourcompany.com"       // ⚠️ REPLACE with your email
}
```

**Find your Object ID:**
```powershell
az ad signed-in-user show --query id -o tsv
```

#### 2.4 Database Credentials (for Cosmos DB)
```json
"sqlAdministratorLogin": "pgadmin",              // Change if desired
"sqlAdministratorPassword": "P@ssw0rd123!"       // ⚠️ CHANGE to strong password
```

#### 2.5 Azure OpenAI Configuration
```json
"openAiLocation": "eastus2",                     // Region with OpenAI quota
"openAiEmbedDeploymentName": "text-embedding-3-small",
"openAiChatDeploymentName": "gpt-4o-mini",
"openAiDeployments": [
  {
    "name": "text-embedding-3-small",
    "model": "text-embedding-3-small",
    "version": "1",
    "skuName": "Standard",
    "capacity": 60                                // TPM quota (increase if needed)
  },
  {
    "name": "gpt-4o-mini",
    "model": "gpt-4o-mini",
    "version": "2024-07-18",
    "skuName": "Standard",
    "capacity": 60
  }
]
```

#### 2.6 Azure ML Configuration
```json
"amlComputeName": "cpu-cluster",
"amlComputeVmSize": "Standard_DS3_v2",           // Change VM size if needed
"amlComputeMinNodes": 0,                         // Auto-scale from 0 (cost-efficient)
"amlComputeMaxNodes": 2                          // Max nodes for parallel jobs
```

---

### Step 3: Login to Azure

```powershell
# Login to Azure
az login

# Set subscription (if you have multiple)
az account set --subscription "Your-Subscription-Name-or-ID"

# Verify correct subscription
az account show --query "{Name:name, ID:id, TenantId:tenantId}" -o table
```

---

### Step 4: Deploy Infrastructure

```powershell
# Initialize Azure Developer CLI environment
azd env new pepsi-workshop-prod

# Set deployment region (must match main.parameters.json primaryLocation)
azd env set AZURE_LOCATION eastus2

# Deploy all resources (takes ~10-15 minutes)
azd up
```

**What happens during deployment:**
1. Creates resource group `rg-pepsi-workshop-prod`
2. Deploys Azure OpenAI with model deployments
3. Deploys Azure ML workspace + compute cluster
4. Deploys Storage Account (ADLS Gen2)
5. Deploys Cosmos DB with vector search enabled
6. Deploys Key Vault
7. Deploys Application Insights + Log Analytics

**Expected output:**
```
SUCCESS: Your application was provisioned in Azure in 12 minutes 34 seconds.
You can view the resources created under the resource group rg-pepsi-workshop-prod in Azure Portal:
https://portal.azure.com/#@.../resource/subscriptions/.../resourceGroups/rg-pepsi-workshop-prod
```

---

### Step 5: Grant Access to Workshop Participants

#### Option A: Grant Access to Entra Security Group (Recommended for 100+ users)

**5.1 Create Entra Security Group**
```powershell
# Create group
az ad group create --display-name "PepsiCo-Workshop-Day2" --mail-nickname "pepsi-workshop"

# Get group Object ID
$groupId = az ad group show --group "PepsiCo-Workshop-Day2" --query id -o tsv
Write-Host "Group ID: $groupId"
```

**5.2 Add Participants to Group**
```powershell
# Add users one-by-one
az ad group member add --group "PepsiCo-Workshop-Day2" --member-id <user-object-id>

# Or bulk import from CSV (create participants.csv with email column)
Import-Csv participants.csv | ForEach-Object {
    $userId = az ad user show --id $_.email --query id -o tsv
    az ad group member add --group "PepsiCo-Workshop-Day2" --member-id $userId
}
```

**5.3 Configure Group Access**

Edit `infra/user-access.parameters.json`:
```json
{
  "workshopUsers": {
    "value": [
      {
        "objectId": "<GROUP-OBJECT-ID>",        // ⚠️ Paste group ID from Step 5.1
        "principalType": "Group",
        "displayName": "PepsiCo-Workshop-Day2"
      }
    ]
  }
}
```

**5.4 Grant RBAC Permissions**
```powershell
# Run access grant script
.\scripts\grant-user-access.ps1
```

#### Option B: Grant Access to Individual Users

Edit `infra/user-access.parameters.json`:
```json
{
  "workshopUsers": {
    "value": [
      {
        "objectId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "principalType": "User",
        "displayName": "user1@company.com"
      },
      {
        "objectId": "ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj",
        "principalType": "User",
        "displayName": "user2@company.com"
      }
      // ... add all participants
    ]
  }
}
```

Then run:
```powershell
.\scripts\grant-user-access.ps1
```

**Permissions granted to each participant:**
- ✅ **Cognitive Services User** → Call Azure OpenAI embeddings/chat
- ✅ **AzureML Data Scientist** → Submit training jobs, deploy models
- ✅ **Storage Blob Data Contributor** → Read/write to data lake
- ✅ **Key Vault Secrets User** → Read connection strings
- ✅ **Cosmos DB Data Contributor** → Query vector database

---

### Step 6: Verify Deployment

```powershell
# Check all deployed resources
az resource list --resource-group rg-pepsi-workshop-prod --output table

# Test Azure OpenAI endpoint
$aoaiEndpoint = az cognitiveservices account show `
  --resource-group rg-pepsi-workshop-prod `
  --name <openai-account-name> `
  --query properties.endpoint -o tsv
Write-Host "Azure OpenAI Endpoint: $aoaiEndpoint"

# Check AML workspace
az ml workspace show `
  --resource-group rg-pepsi-workshop-prod `
  --name <aml-workspace-name>

# List Key Vault secrets (should be empty initially)
az keyvault secret list --vault-name <keyvault-name> --query "[].name"
```

---

## 📧 Pre-Workshop: Participant Setup Instructions

**Send this to all workshop participants 1 week before the workshop:**

---

**Subject:** PepsiCo AI Workshop Day 2 - Pre-Workshop Setup

Dear Participant,

To prepare for **Day 2** of the PepsiCo AI Workshop, please complete these steps:

### 1. Verify Azure Portal Access
- Login to [Azure Portal](https://portal.azure.com)
- Confirm you can see the `rg-pepsi-workshop-prod` resource group
- If you don't see it, reply to this email

### 2. Start Your FREE Fabric Trial (60 days)
1. Go to [https://app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Click **Start Trial** (top-right corner)
3. Follow the prompts to activate your **60-day Fabric trial**
4. This gives you a personal workspace for Labs 01 & 02

### 3. Create Your Fabric Workspace
1. In Fabric portal, click **Workspaces** → **+ New workspace**
2. Name it: `WS_<YourName>_Day2` (e.g., `WS_JohnDoe_Day2`)
3. Leave other settings as default
4. Click **Apply**

### 4. Verify Access to Shared Resources
Open [Azure Portal](https://portal.azure.com) and navigate to `rg-pepsi-workshop-prod`. You should see:
- ✅ Azure OpenAI account
- ✅ Azure ML workspace
- ✅ Storage account
- ✅ Key Vault

If you encounter any issues, contact the workshop organizer.

**See you on Day 2!**

---

---

## 💰 Cost Breakdown

Monthly cost for **shared infrastructure** (serving 100 participants):

| Service | Pricing Tier | Estimated Cost/Month |
|---------|--------------|---------------------|
| Azure OpenAI | Pay-per-token (gpt-4o-mini + embeddings) | $50 - $150 |
| Azure ML | Compute only when running (0-2 nodes, auto-scale) | $20 - $80 |
| Storage (ADLS Gen2) | Hot tier, ~100 GB | $10 - $20 |
| Cosmos DB | Serverless (pay-per-RU) | $25 - $50 |
| Key Vault | Standard tier | $5 |
| Application Insights | 5 GB/month free tier | $0 - $10 |
| **TOTAL** | | **$110 - $310/month** |

**Fabric Costs:**
- **Participant trials:** FREE for 60 days
- **Production (optional):** F2 capacity = ~$262/month (shared across all participants)

**Cost Optimization Tips:**
1. **Auto-scale AML compute from 0 nodes** (only pay when jobs run)
2. **Use serverless Cosmos DB** (no provisioned throughput charges when idle)
3. **Set budget alerts** in Azure Portal
4. **Delete after workshop** if no longer needed:
   ```powershell
   azd down --purge
   ```

---

## 🔧 Troubleshooting

### Issue: Azure OpenAI quota errors during deployment

**Error:**
```
Insufficient quota for model "gpt-4o-mini" in eastus2
```

**Solution:**
1. Change region in `infra/main.parameters.json`:
   ```json
   "openAiLocation": "westus"
   ```
2. Re-run `azd up`

Or request quota increase:
```powershell
# Open quota increase request
https://aka.ms/oai/quotaincrease
```

---

### Issue: Subscription policy blocks SQL/PostgreSQL provisioning

**Error:**
```
Provisioning is restricted in this region
```

**Solution:**
This infrastructure uses **Cosmos DB** as fallback (already deployed). Lab 03 scripts are adapted for Cosmos DB vector search. No action needed.

---

### Issue: Participant cannot see resources in Azure Portal

**Cause:** RBAC permissions not applied or Entra sync delay

**Solution:**
```powershell
# Re-run access grant script
cd scripts
.\grant-user-access.ps1

# Check role assignments
az role assignment list --assignee <user-object-id> --resource-group rg-pepsi-workshop-prod
```

Wait 5-10 minutes for Entra role assignments to propagate.

---

### Issue: Fabric trial not available

**Cause:** Organization tenant policy blocks self-service trials

**Solution:**
Contact your **Microsoft 365 Global Admin** to enable Fabric trials:
1. Go to [Microsoft 365 Admin Center](https://admin.microsoft.com)
2. Navigate to **Settings** → **Org settings** → **Services**
3. Enable **Microsoft Fabric (Free)** for users

---

## 🧹 Post-Workshop Cleanup

After the workshop, delete all resources to avoid ongoing charges:

```powershell
# Delete everything (including soft-deleted resources)
azd down --purge

# Or manually delete resource group
az group delete --name rg-pepsi-workshop-prod --yes --no-wait
```

**Note:** This will delete:
- All Azure resources (OpenAI, ML, Storage, Cosmos DB, Key Vault)
- All data (Lakehouse tables, ML models, vector embeddings)

**Participant Fabric workspaces** are NOT deleted (users must delete manually if desired).

---

## 📚 Additional Resources

- **Azure Developer CLI Docs:** [https://aka.ms/azd](https://aka.ms/azd)
- **Azure OpenAI Service:** [https://learn.microsoft.com/azure/ai-services/openai/](https://learn.microsoft.com/azure/ai-services/openai/)
- **Microsoft Fabric Documentation:** [https://learn.microsoft.com/fabric/](https://learn.microsoft.com/fabric/)
- **Azure Machine Learning:** [https://learn.microsoft.com/azure/machine-learning/](https://learn.microsoft.com/azure/machine-learning/)

---

## 🆘 Support

For deployment issues, contact:
- **Workshop Organizer:** Pradipta Dash (pradiptadash@microsoft.com)
- **GitHub Issues:** [SinglaSandeep/ai-workshop-infra/issues](https://github.com/SinglaSandeep/ai-workshop-infra/issues)

---

**Last Updated:** June 2026  
**Branch:** `Pradipta_changes`  
**Deployment Model:** Shared Resources + RBAC
