# PepsiCo Workshop Day 2 - Quick Deployment Reference

**Deploy shared Azure infrastructure for 100+ workshop participants in 15 minutes.**

---

## Prerequisites ✅

```powershell
# Install tools
winget install Microsoft.AzureCLI
winget install Microsoft.Azd

# Login
az login
az account set --subscription "Your-Subscription"
```

---

## 1️⃣ Clone & Configure (5 min)

```powershell
git clone https://github.com/SinglaSandeep/ai-workshop-infra.git
cd ai-workshop-infra
git checkout Pradipta_changes
```

**Edit:** `infra/main.parameters.json`

```json
{
  "dataPlatform": {
    "adminObjectId": "YOUR-OBJECT-ID",          // ⚠️ CHANGE THIS
    "aadAdminLogin": "you@company.com",         // ⚠️ CHANGE THIS
    "sqlAdministratorPassword": "STRONG-PWD"    // ⚠️ CHANGE THIS
  },
  "features": {
    "enableDataPlatform": true,                 // ✅ Day 2 components
    "enableAiFoundry": false                    // ❌ Not needed for Day 2
  }
}
```

**Get your Object ID:**
```powershell
az ad signed-in-user show --query id -o tsv
```

---

## 2️⃣ Deploy (10 min)

```powershell
azd env new pepsi-workshop
azd env set AZURE_LOCATION eastus2
azd up
```

**Resources created:**
- ✅ Azure OpenAI (text-embedding-3-small + gpt-4o-mini)
- ✅ Azure ML Workspace + Compute
- ✅ Storage Account (ADLS Gen2)
- ✅ Cosmos DB (vector search)
- ✅ Key Vault
- ✅ Application Insights

---

## 3️⃣ Grant Participant Access (5 min)

### Option A: Entra Security Group (Recommended)
```powershell
# Create group
az ad group create --display-name "Workshop-Participants" --mail-nickname "workshop"

# Get group ID
az ad group show --group "Workshop-Participants" --query id -o tsv
# Output: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee

# Add to user-access.parameters.json
```

**Edit:** `infra/user-access.parameters.json`
```json
{
  "workshopUsers": {
    "value": [
      {
        "objectId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",  // Group ID
        "principalType": "Group",
        "displayName": "Workshop-Participants"
      }
    ]
  }
}
```

```powershell
# Grant RBAC
.\scripts\grant-user-access.ps1
```

### Option B: Individual Users
```json
{
  "workshopUsers": {
    "value": [
      {"objectId": "user1-guid", "principalType": "User"},
      {"objectId": "user2-guid", "principalType": "User"}
    ]
  }
}
```

---

## 4️⃣ Verify Deployment

```powershell
# List all resources
az resource list --resource-group rg-pepsi-workshop --output table

# Test OpenAI
az cognitiveservices account show -g rg-pepsi-workshop -n <aoai-name>

# Test AML
az ml workspace show -g rg-pepsi-workshop -n <aml-name>
```

---

## 📧 Send to Participants (1 week before workshop)

**Subject:** PepsiCo AI Workshop - Setup Instructions

**Email body:**

> Hi Team,
> 
> Please complete these 3 steps before the workshop:
> 
> 1. **Verify Azure access:**  
>    Login to [Azure Portal](https://portal.azure.com) and confirm you can see `rg-pepsi-workshop`
> 
> 2. **Start Fabric trial:**  
>    Go to [https://app.fabric.microsoft.com](https://app.fabric.microsoft.com) → Click "Start Trial"
> 
> 3. **Create your workspace:**  
>    In Fabric → Workspaces → New workspace → Name: `WS_YourName_Day2`
> 
> See you at the workshop!

---

## 💰 Cost Estimate

| Component | Monthly Cost |
|-----------|--------------|
| Azure OpenAI | $50-150 |
| Azure ML | $20-80 |
| Storage | $10-20 |
| Cosmos DB | $25-50 |
| Other | $10-15 |
| **TOTAL** | **$115-315/month** |

**For 3-day workshop:** ~$12-32 total

---

## 🧹 Cleanup After Workshop

```powershell
azd down --purge
```

---

## 🆘 Troubleshooting

| Error | Fix |
|-------|-----|
| "Insufficient quota for gpt-4o-mini" | Change `openAiLocation` to "westus" in parameters.json |
| "Provisioning disabled for SQL" | ✅ Already handled - using Cosmos DB instead |
| Participant can't see resources | Re-run `grant-user-access.ps1`, wait 10 min |

---

## 📞 Support

**Deployment issues:** pradiptadash@microsoft.com  
**GitHub:** [SinglaSandeep/ai-workshop-infra](https://github.com/SinglaSandeep/ai-workshop-infra/issues)  
**Docs:** See `DEPLOYMENT-GUIDE.md` for detailed instructions

---

**Version:** Pradipta_changes (June 2026)  
**Deployment Time:** ~15-20 minutes  
**Supports:** 100+ concurrent users
