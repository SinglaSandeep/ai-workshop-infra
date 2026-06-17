# Quick Deployment Checklist

Use this checklist to ensure a smooth deployment for the PepsiCo AI Workshop Day 2.

---

## ☑️ Pre-Deployment (1 week before)

- [ ] **Azure subscription ready**
  - [ ] Owner/Contributor access confirmed
  - [ ] No restrictive policies blocking OpenAI/ML/Storage
  - [ ] Budget alerts configured ($500/month recommended)

- [ ] **Tools installed**
  - [ ] Azure CLI: `az --version`
  - [ ] Azure Developer CLI: `azd version`
  - [ ] Git: `git --version`
  - [ ] PowerShell (Windows) or Bash (Mac/Linux)

- [ ] **Participant list ready**
  - [ ] CSV with participant emails
  - [ ] Entra Security Group created (optional but recommended)
  - [ ] Object IDs collected

---

## ☑️ Deployment Day

### Step 1: Clone & Configure
- [ ] Clone repo: `git clone https://github.com/SinglaSandeep/ai-workshop-infra.git`
- [ ] Checkout branch: `git checkout Pradipta_changes`
- [ ] Edit `infra/main.parameters.json`:
  - [ ] Set `adminObjectId` to your Entra Object ID
  - [ ] Set `aadAdminLogin` to your email
  - [ ] Change `sqlAdministratorPassword` to strong password
  - [ ] Verify `primaryLocation` (recommend `eastus2`)
  - [ ] Confirm `enableDataPlatform: true`
  - [ ] Confirm `enableAiFoundry: false` (for Day 2 only)

### Step 2: Deploy Infrastructure
- [ ] Login: `az login`
- [ ] Set subscription: `az account set --subscription "Your-Sub"`
- [ ] Initialize: `azd env new pepsi-workshop-prod`
- [ ] Set location: `azd env set AZURE_LOCATION eastus2`
- [ ] Deploy: `azd up` (wait ~10-15 minutes)
- [ ] Verify: `az resource list --resource-group rg-pepsi-workshop-prod`

### Step 3: Grant Participant Access
- [ ] Edit `infra/user-access.parameters.json` with participant Object IDs
- [ ] Run: `.\scripts\grant-user-access.ps1`
- [ ] Verify: `az role assignment list --resource-group rg-pepsi-workshop-prod`

---

## ☑️ Verify Deployment

- [ ] **Azure OpenAI**
  ```powershell
  az cognitiveservices account show -g rg-pepsi-workshop-prod -n <name> --query properties.endpoint
  ```
  Expected: `https://<name>.openai.azure.com/`

- [ ] **Azure ML**
  ```powershell
  az ml workspace show -g rg-pepsi-workshop-prod -n <name>
  ```
  Expected: `provisioningState: Succeeded`

- [ ] **Storage Account**
  ```powershell
  az storage account show -g rg-pepsi-workshop-prod -n <name> --query isHnsEnabled
  ```
  Expected: `true` (ADLS Gen2 enabled)

- [ ] **Cosmos DB**
  ```powershell
  az cosmosdb show -g rg-pepsi-workshop-prod -n <name> --query capabilities[].name
  ```
  Expected: `["EnableNoSQLVectorSearch"]`

- [ ] **Key Vault**
  ```powershell
  az keyvault show -g rg-pepsi-workshop-prod -n <name> --query properties.vaultUri
  ```
  Expected: `https://<name>.vault.azure.net/`

---

## ☑️ Pre-Workshop Email (Send 1 week before)

- [ ] **Email sent to all participants** with:
  - [ ] Azure Portal access instructions
  - [ ] Fabric trial activation link
  - [ ] Workspace creation steps
  - [ ] Contact info for support

**Email template:** See `DEPLOYMENT-GUIDE.md` → "Pre-Workshop: Participant Setup Instructions"

---

## ☑️ Workshop Day

- [ ] **Morning setup (30 min before start)**
  - [ ] Test OpenAI endpoint with sample API call
  - [ ] Verify AML compute cluster can start
  - [ ] Check Key Vault access from participant account
  - [ ] Have Azure Portal open on shared screen

- [ ] **During workshop**
  - [ ] Monitor Azure costs in real-time
  - [ ] Watch for quota errors (OpenAI token limits)
  - [ ] Help participants with Fabric workspace creation

---

## ☑️ Post-Workshop Cleanup

- [ ] **Export any important data** (if needed)
- [ ] **Delete resources:**
  ```powershell
  azd down --purge
  ```
- [ ] **Verify deletion:**
  ```powershell
  az group exists --name rg-pepsi-workshop-prod
  ```
  Expected: `false`

- [ ] **Cost reconciliation**
  - [ ] Review final Azure bill
  - [ ] Compare with budget estimates

---

## 🚨 Emergency Contacts

| Issue | Contact |
|-------|---------|
| Deployment failures | Pradipta Dash: pradiptadash@microsoft.com |
| Azure subscription/billing | Your Azure account manager |
| Participant access issues | IT help desk / Entra ID admin |
| OpenAI quota limits | Azure Support (create ticket via Portal) |

---

## 📊 Success Metrics

- [ ] **Infrastructure deployed:** All 6 components (OpenAI, ML, Storage, Cosmos, KV, AppInsights)
- [ ] **Participants have access:** All users can view resources in Portal
- [ ] **Fabric workspaces created:** Each participant has personal workspace
- [ ] **Zero downtime:** No service interruptions during workshop
- [ ] **Cost within budget:** Total spend < $500 for workshop duration

---

## 📝 Notes / Lessons Learned

_Use this space to document any issues encountered and how you resolved them:_

```
Date: ________________

Issue 1: 


Resolution: 


Issue 2: 


Resolution: 


```

---

**Deployment Version:** Pradipta_changes branch (June 2026)  
**Estimated Total Time:** 2-3 hours (including participant access setup)
