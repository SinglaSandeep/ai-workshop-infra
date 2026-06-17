# Participant Setup Guide - PepsiCo Workshop Day 2

**Complete these steps BEFORE the workshop (30 minutes)**

---

## What You'll Create

| Component | Where | Cost | Purpose |
|-----------|-------|------|---------|
| **Fabric Workspace** | Fabric Portal | FREE (60-day trial) | Your personal workspace for Labs 01 & 02 |
| **Lakehouse** | Inside your Fabric workspace | FREE (trial capacity) | Lab 01 - Data ingestion & medallion architecture |
| **Eventhouse** | Inside your Fabric workspace | FREE (trial capacity) | Lab 02 - Real-Time Intelligence |

**Shared resources** (already deployed by instructor):
- ✅ Azure OpenAI
- ✅ Azure ML
- ✅ Storage Account
- ✅ Cosmos DB
- ✅ Key Vault

---

## Step 1: Verify Azure Portal Access (5 min)

### 1.1 Login to Azure Portal
1. Go to [https://portal.azure.com](https://portal.azure.com)
2. Login with your work email: `yourname@company.com`
3. Select your organization's tenant if prompted

### 1.2 Verify Access to Shared Resources
1. In the search bar, type `rg-pepsi-workshop` and press Enter
2. You should see the resource group with these resources:
   - Azure OpenAI account
   - Azure ML workspace
   - Storage account
   - Cosmos DB account
   - Key Vault

**✅ Success criteria:** You can see all 5 resources

**❌ Problem?** Email your instructor - you may need RBAC permissions added

---

## Step 2: Start Microsoft Fabric Trial (10 min)

### 2.1 Access Fabric Portal
1. Go to [https://app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Login with the **same email** you used for Azure Portal
3. You'll see the Fabric home page

### 2.2 Start Free Trial
1. Look for **"Start trial"** button in the top-right corner
2. Click it and select **"Microsoft Fabric (Free)"**
3. Accept the terms and conditions
4. Wait 30-60 seconds for trial activation

**What you get:**
- 60 days of FREE Fabric capacity
- Ability to create Lakehouses, Warehouses, Notebooks, Pipelines
- Real-Time Intelligence features (Eventstream, Eventhouse)
- Power BI Pro capabilities

### 2.3 Verify Trial is Active
1. Click your **profile icon** (top-right)
2. Select **"Trial status"**
3. Confirm: **"Microsoft Fabric trial - XX days remaining"**

**✅ Success criteria:** Trial shows "Active" with 60 days

**❌ Problem: "Trial not available"**
- Your organization may have disabled self-service trials
- Contact your **Microsoft 365 Global Admin**
- Or ask instructor about shared capacity option

---

## Step 3: Create Your Personal Workspace (10 min)

### 3.1 Create Workspace
1. In Fabric portal, click **"Workspaces"** in left navigation
2. Click **"+ New workspace"**
3. Fill in the form:

   | Field | Value | Example |
   |-------|-------|---------|
   | **Name** | `WS_<YourName>_Day2` | `WS_JohnDoe_Day2` |
   | **Description** | "PepsiCo Workshop Day 2 - Personal workspace" | (optional) |
   | **Advanced** | Leave defaults | |
   | **License mode** | Trial (auto-selected) | |

4. Click **"Apply"**

### 3.2 Verify Workspace Created
1. You should see your new workspace in the list
2. Click on it to open
3. You'll see an empty workspace with **"+ New"** button

**✅ Success criteria:** Workspace opens and shows "Get started" options

---

## Step 4: Create Your Lakehouse (5 min)

**This is for Lab 01 - we'll create it now to save time during the workshop**

### 4.1 Create Lakehouse
1. In your workspace, click **"+ New"**
2. Scroll down and select **"Lakehouse"**
3. Name it: `LH_RetailData`
4. Click **"Create"**
5. Wait 30-60 seconds for provisioning

### 4.2 Verify Lakehouse Created
1. You should see the Lakehouse explorer with:
   - **Tables** folder (empty)
   - **Files** folder (empty)
2. The interface shows **"Get data"** options

**✅ Success criteria:** Lakehouse opens with Tables and Files sections

---

## Step 5: Test Access to Shared Azure Resources (5 min)

### 5.1 Find Azure OpenAI Endpoint
1. Go back to [Azure Portal](https://portal.azure.com)
2. Navigate to resource group `rg-pepsi-workshop`
3. Click on the **Azure OpenAI** resource (name starts with `pepsiaiworks-`)
4. Click **"Keys and Endpoint"** in left menu
5. Copy the **Endpoint** URL (e.g., `https://xxxxx.openai.azure.com/`)

**✅ Success criteria:** You can view the endpoint (don't need to copy keys - using Entra auth)

### 5.2 Find Key Vault
1. In the same resource group, click **Key Vault** resource
2. Click **"Secrets"** in left menu
3. You should see a list (may be empty - instructor will populate during workshop)

**✅ Success criteria:** You can view the Key Vault secrets page (no "Access Denied" error)

---

## Checklist - Are You Ready?

- [ ] ✅ I can login to Azure Portal and see `rg-pepsi-workshop` resource group
- [ ] ✅ I can see all 5 shared resources (OpenAI, ML, Storage, Cosmos, KeyVault)
- [ ] ✅ My Fabric trial is active (60 days remaining)
- [ ] ✅ I created my personal workspace: `WS_<MyName>_Day2`
- [ ] ✅ I created my Lakehouse: `LH_RetailData`
- [ ] ✅ I can view Azure OpenAI endpoint
- [ ] ✅ I can view Key Vault secrets page

**All checked?** You're ready for Day 2! 🎉

---

## Troubleshooting

### "I can't see the resource group in Azure Portal"

**Cause:** RBAC permissions not assigned yet

**Fix:** 
1. Email your instructor with your full email address
2. They'll add you to the participant group
3. Wait 10 minutes and try again

---

### "Fabric trial says 'Not available'"

**Cause:** Organization policy blocks self-service trials

**Fix Option 1 - Request Access:**
1. Contact your Microsoft 365 admin
2. Ask them to enable: **Settings → Org settings → Services → Microsoft Fabric (Free)**

**Fix Option 2 - Use Shared Capacity:**
1. Email instructor
2. They can add you to a shared F2 capacity
3. You'll still have your personal workspace

---

### "I created the workspace but can't create a Lakehouse"

**Cause:** Trial capacity not active yet

**Fix:**
1. Wait 5 minutes (capacity provisioning can be slow)
2. Refresh the page
3. Try creating Lakehouse again
4. If still failing, check trial status: Profile → Trial status

---

### "Azure OpenAI endpoint shows 'Access Denied'"

**Cause:** RBAC role not assigned

**Fix:**
1. Confirm with instructor that user access script ran successfully
2. Check your role assignments:
   ```powershell
   az role assignment list --assignee your@email.com --resource-group rg-pepsi-workshop
   ```
3. Should see: **Cognitive Services User** role

---

## What to Bring to the Workshop

- [x] **Laptop** with web browser (Chrome/Edge recommended)
- [x] **Azure Portal access** confirmed (see Step 1)
- [x] **Fabric workspace** created (see Step 3)
- [x] **Lakehouse** created (see Step 4)
- [x] **Notepad** or text editor for copy-pasting connection strings
- [ ] Optional: **Power BI Desktop** installed (for Lab 01 semantic model - can install during workshop)

---

## During the Workshop - What You'll Do

### Lab 01 - Fabric Lakehouse + Data Agent
- ✅ Use your `LH_RetailData` Lakehouse
- 📥 Ingest sample retail data with Data Factory pipeline
- 🔄 Build Bronze → Silver → Gold medallion architecture
- 📊 Create Power BI semantic model
- 🤖 Build Fabric Data Agent with natural language queries

### Lab 02 - Real-Time Intelligence
- 📡 Create Eventstream from sample data source
- 💾 Land events in Eventhouse (KQL database)
- 🔍 Query with Kusto Query Language (KQL)
- 📈 Build Real-Time Dashboard
- ⚠️ Configure Activator alert

### Lab 03 - Vector Search
- 🔢 Generate embeddings with Azure OpenAI (shared endpoint)
- 💾 Load into Cosmos DB vector index
- 🔍 Run cosine similarity search
- 🔗 Expose as retrieval tool for agents

### Lab 04 - Azure ML Train & Deploy
- 🧪 Train a model on sample dataset
- 📝 Register model in Azure ML (shared workspace)
- 🚀 Deploy to managed online endpoint
- 🔧 Wrap endpoint as agent tool

---

## Support Contacts

| Issue | Contact |
|-------|---------|
| Azure Portal access issues | Instructor |
| Fabric trial activation | Microsoft 365 admin or Instructor |
| Workshop content questions | Instructor |
| Technical Azure issues | Azure Support Portal |

---

## FAQ

**Q: Will my Fabric trial expire during the workshop?**  
A: No - you get 60 days. The workshop is only 1-3 days.

**Q: Can I use the same workspace for all labs?**  
A: Yes! Create everything in your `WS_<YourName>_Day2` workspace.

**Q: Do I need to pay for anything?**  
A: No - the Fabric trial is FREE. The Azure resources are shared and paid by the organization.

**Q: What happens to my data after the trial ends?**  
A: Your workspace becomes read-only. You can export data before expiry or purchase a Fabric capacity.

**Q: Can I delete my workspace if I make a mistake?**  
A: Yes - just create a new one. No limit on workspace creation.

**Q: Do I need Power BI Desktop installed?**  
A: Optional for Lab 01. You can build semantic models in the browser, but Desktop gives more features.

---

**Last Updated:** June 2026  
**Workshop:** PepsiCo AI Workshop - Day 2  
**Estimated Setup Time:** 30 minutes
