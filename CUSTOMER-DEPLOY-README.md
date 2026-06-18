# PepsiCo Day 2 (Data) Workshop — Customer Self-Deploy Guide

> **Purpose.** Step-by-step guide for the PepsiCo operator to deploy the Day 2
> (Data) workshop infrastructure into the existing Day 1 resource group,
> **without disturbing any Day 1 resource Sandeep deployed**.
>
> This file is tailored to PepsiCo's confirmed environment (Sweden Central,
> `pep-sandbox-01-sub`, RG `pep-azr-aisp-msft-training-lab-sbx-eus-01-rg`).

---

## 1. What gets created (3 new Azure resources)

| # | Resource type | Generated name (example) | SKU / config | Purpose |
|---|---|---|---|---|
| 1 | `Microsoft.Fabric/capacities` | `fabpepsiws<hash>` | **F2** Fabric capacity (Sweden Central) | Lakehouse + notebooks (Lab 01), RTI (Lab 02) |
| 2 | `Microsoft.Sql/servers` + `databases` | `sql-pepsiws-<hash>` / `vectordb` | **GP_S_Gen5_2** serverless, Entra-only auth, auto-pause 60 min, `VECTOR(1536)` capable | Vector search (Lab 03) |
| 3 | `Microsoft.Purview/accounts` | `pv-pepsiws-<hash>` | **Standard** SKU, System-Assigned identity | Catalog, lineage, classifications (Governance demo) |

Plus 2 dependent sub-resources auto-created with #2:
- A SQL **firewall rule** `AllowAllAzureServices` (the `0.0.0.0` rule = "Allow Azure services and resources" — standard Azure pattern; **not** an internet allow rule).
- The SQL **database** `vectordb` (child of the SQL server).

### What is reused, not redeployed
Day 1 already deployed all of these — the script does **not** touch them:

| Day 1 resource | Used in Day 2 |
|---|---|
| `aif-workshop2026` (AI Foundry / AOAI hub) — contains `gpt-4.1-mini` + `text-embedding-3-small` | Lab 03 embeddings + chat |
| `cosmos-workshop2026` (Cosmos DB, NoSQL + vector) | Lab 03 read-along comparison |
| `srch-workshop2026`, `crworkshop2026`, `cae-workshop2026`, `id-zava-workload`, 17 AI Foundry projects | Day 1 only |

### What gets created OUTSIDE the RG
| Item | Where | Why |
|---|---|---|
| Per-attendee **Fabric workspaces** (~60) | Microsoft Fabric tenant (not Azure) | Each attendee gets a dedicated workspace bound to the capacity. Done by step 5 of this guide. |
| Managed RG `managed-pv-pepsiws-<hash>` | Same subscription, separate RG | Purview auto-creates and manages this — do not modify. |

---

## 2. Cost estimate (Pay-As-You-Go)

| Resource | Idle (24 h) | Workshop day (8 h active) |
|---|---|---|
| Fabric **F2** | $0.36/h × 24 = **$8.64** | Scale up to **F64** for workshop = $11.52/h × 8 = **$92** |
| SQL `GP_S_Gen5_2` | Auto-pauses after 60 min idle → near zero | 2 vCore × $0.52 × 8 = **$8.32** |
| Purview Standard | 1 capacity unit × $0.411/h × 24 = **$9.86** | Same |
| **Total (idle day)** | **≈ $19/day** | **≈ $110/workshop day** |

**Cost lever:** Fabric SKU. Run at F2 during testing & setup, scale to F64 the morning of the workshop, scale back to F2 (or pause) the same evening. See §7.

---

## 3. Pre-requisites checklist

### A. Identity / permissions
- [ ] Operator account has **Contributor** (or Owner) on `pep-sandbox-01-sub` subscription.
- [ ] Operator account has **User Access Administrator** on the RG (needed because the deploy assigns the SQL Entra admin role).
- [ ] Operator can sign in to `https://portal.azure.com` with this account.

### B. Fabric tenant (one-time, by Pepsico Fabric/Power BI tenant admin) ⚠️
- [ ] Pepsico tenant has signed up for Microsoft Fabric at <https://fabric.microsoft.com>.
- [ ] **Fabric admin portal → Tenant settings**: "Service principals can use Fabric APIs" enabled (or equivalent group permission), and **"Users can create Fabric items"** enabled for the workshop attendee group.
- [ ] Without this, the F-SKU capacity deploy fails with `CapacityNotAllowed`.

### C. Identity values you need to have ready
| # | Value | Today's confirmed value | How to find it |
|---|---|---|---|
| 1 | Subscription ID | `11a82ecc-d5ba-473d-abe2-4b86557c9d55` | `az account show --query id -o tsv` |
| 2 | Resource group | `pep-azr-aisp-msft-training-lab-sbx-eus-01-rg` | Same RG as Day 1 |
| 3 | Region | `swedencentral` | Matches Day 1 colocation |
| 4 | Fabric / SQL admin **UPN** | `Pradipta.Dash.Contractor@pepsico.com` | Operator's UPN |
| 5 | Fabric / SQL admin **Object ID** | `6f07fb7a-cfc2-4bfe-853c-a1b5a87df124` | Portal → Entra ID → Users → search → copy Object ID |
| 6 | Workshop attendees **Entra group** (Object ID + display name) | _TBD — supplied by Pepsico identity team_ | Group must contain all ~60 attendees |
| 7 | Workshop attendees **CSV** (UPN, ObjectId, DisplayName) | _TBD — supplied by Pepsico identity team_ | One row per attendee. Template in `Allfiles/attendees-sample.csv` |
| 8 | AI Foundry account name (reused from Day 1) | `aif-workshop2026` | `az cognitiveservices account list -g <rg> -o table` |

### D. Operator laptop tooling
- [ ] PowerShell 7+ (`pwsh --version`)
- [ ] Azure CLI 2.65+ (`az --version`)
- [ ] `sqlcmd` (Microsoft SQL command-line, install via `winget install Microsoft.Sqlcmd` or it ships with SSMS)
- [ ] `Az.Resources` PowerShell module (`Install-Module Az -Scope CurrentUser`)
- [ ] `git`

---

## 4. Validate BEFORE you deploy (no Azure resource is created)

We use Azure's three validation layers in order. **None of these create or modify any resource.** If any of them fail, fix and re-run before step 5.

### 4.1 — Bicep syntax check (local, no Azure call)
```powershell
cd data-workshop-infra
az bicep build --file infra/main-day2.bicep --stdout > $null
# Exit 0 = syntax OK
```

### 4.2 — ARM server-side validation
```powershell
az deployment group validate `
    --resource-group  pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --template-file   infra/main-day2.bicep `
    --parameters `
        workshopName=pepsiws `
        environmentName=day2 `
        location=swedencentral `
        sqlLocation=swedencentral `
        fabricSkuName=F2 `
        fabricAdminObjectId='Pradipta.Dash.Contractor@pepsico.com' `
        sqlAadAdminLogin='Pradipta.Dash.Contractor@pepsico.com' `
        sqlAadAdminObjectId='6f07fb7a-cfc2-4bfe-853c-a1b5a87df124' `
        sqlDatabaseName=vectordb `
    --query "{status:properties.provisioningState, count:length(properties.validatedResources)}" -o json
```
Expected output:
```json
{ "status": "Succeeded", "count": 8 }
```

### 4.3 — What-if (full preview of exactly what will change) ✅ RECOMMENDED
```powershell
az deployment group what-if `
    --resource-group  pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --template-file   infra/main-day2.bicep `
    --parameters `
        workshopName=pepsiws `
        environmentName=day2 `
        location=swedencentral `
        sqlLocation=swedencentral `
        fabricSkuName=F2 `
        fabricAdminObjectId='Pradipta.Dash.Contractor@pepsico.com' `
        sqlAadAdminLogin='Pradipta.Dash.Contractor@pepsico.com' `
        sqlAadAdminObjectId='6f07fb7a-cfc2-4bfe-853c-a1b5a87df124' `
        sqlDatabaseName=vectordb
```

**You must see EXACTLY this footer:**
```
Resource changes: 5 to create, 22 to ignore.
```
- `5 to create` → the 3 new resources + SQL DB + SQL firewall rule
- `22 to ignore` → Day 1 resources Bicep doesn't touch (AI Foundry + 17 projects, Cosmos, AI Search, ACR, Container Apps env, managed identity)
- **Any other count, any "modify", "delete", or "deploy" symbols → STOP and investigate. Do not proceed.**

The detailed diff lists each resource with `+ Create` / `* Ignore` / `~ Modify` / `- Delete` markers. The only marker you should see is `+ Create` (5 of them) and `* Ignore` (22 of them).

### 4.4 — Sanity check: existing resources are untouched
```powershell
az resource list -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --query "[].name" -o tsv | Measure-Object -Line
# Should report 22 before the deploy, 27 after.
```

---

## 5. Deploy

Two ways: PowerShell wrapper (recommended) or raw `az` command.

### 5.1 — Wrapper script (preferred)
```powershell
cd data-workshop-infra

./scripts/deploy-day2.ps1 `
    -ResourceGroupName    pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    -Location             swedencentral `
    -SqlLocation          swedencentral `
    -FabricAdminObjectId  'Pradipta.Dash.Contractor@pepsico.com' `
    -SqlAadAdminLogin     'Pradipta.Dash.Contractor@pepsico.com' `
    -SqlAadAdminObjectId  '6f07fb7a-cfc2-4bfe-853c-a1b5a87df124' `
    -WorkshopName         pepsiws `
    -EnvironmentName      day2 `
    -FabricSku            F2
```

Optional flags:
| Flag | Effect |
|---|---|
| `-SkipFabric`  | Skip Fabric capacity (use if tenant prereq not done yet — deploy SQL + Purview only) |
| `-SkipSql`     | Skip SQL (e.g. SQL VECTOR throttled in region) |
| `-SkipPurview` | Skip Purview (e.g. tenant already has a Purview account elsewhere) |

### 5.2 — Raw `az` (advanced)
```powershell
az deployment group create `
    --resource-group  pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --template-file   infra/main-day2.bicep `
    --name            "pepsi-day2-$(Get-Date -Format yyyyMMddHHmmss)" `
    --parameters `
        workshopName=pepsiws environmentName=day2 `
        location=swedencentral sqlLocation=swedencentral fabricSkuName=F2 `
        fabricAdminObjectId='Pradipta.Dash.Contractor@pepsico.com' `
        sqlAadAdminLogin='Pradipta.Dash.Contractor@pepsico.com' `
        sqlAadAdminObjectId='6f07fb7a-cfc2-4bfe-853c-a1b5a87df124' `
        sqlDatabaseName=vectordb
```

**Expected duration:** 5–10 minutes (Fabric ≈ 2 min, SQL ≈ 4 min, Purview ≈ 6 min).

**Outputs are written to:**
- `.azure/main-day2-outputs.json` — raw ARM outputs
- `.azure/workshop-day2.env` — `KEY=value` for distributing to attendees

---

## 6. Verify after deploy

```powershell
# 1. Three new resources present
az resource list -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --query "[?starts_with(name,'fab') || starts_with(name,'sql-') || starts_with(name,'pv-')].{name:name,type:type,loc:location,state:provisioningState}" -o table

# 2. Fabric capacity is Active
az resource show --resource-type Microsoft.Fabric/capacities `
    -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    -n <fabric-capacity-name-from-outputs> --query "properties.state" -o tsv
# Expected: Active

# 3. SQL server reachable
az sql server show -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    -n <sql-server-name-from-outputs> --query "{fqdn:fullyQualifiedDomainName,state:state}" -o table
# Expected: state=Ready

# 4. Purview Atlas endpoint up
az purview account show -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    -n <purview-name-from-outputs> --query "{name:name,state:provisioningState,atlas:endpoints.catalog}" -o table
# Expected: state=Succeeded
```

---

## 7. Capacity sizing (workshop day)

| Concurrent attendees running notebooks | SKU | $/h |
|---|---|---|
| 1–2 (testing) | **F2** | $0.36 |
| ~10–15 | F8 | $1.44 |
| ~30 | F32 | $5.76 |
| **60 (full workshop)** | **F64** | $11.52 |

**Scale-up command (run the morning of the workshop):**
```powershell
az resource update --resource-type Microsoft.Fabric/capacities `
    -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    -n <fabric-capacity-name> --set sku.name=F64
```
Scale-down at end of day: replace `F64` with `F2`. Or pause:
```powershell
az resource invoke-action --resource-type Microsoft.Fabric/capacities `
    -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    -n <fabric-capacity-name> --action suspend
```

---

## 8. Post-deploy steps (still required for the workshop)

These are **separate scripts**, each with its own preview / dry-run option.

### 8.1 — Bulk-create Fabric workspaces (one per attendee)
```powershell
./scripts/provision-fabric-workspaces.ps1 `
    -AttendeesCsv  Allfiles/attendees.csv `
    -CapacityName  <fabric-capacity-name-from-outputs>
```
Idempotent — safe to re-run. Outputs `.azure/workspace-assignments.csv` with one URL per attendee.

### 8.2 — Grant attendees access (AOAI RBAC + SQL setup)
```powershell
./scripts/grant-user-access-day2.ps1 `
    -ResourceGroupName        pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    -WorkshopGroupObjectId    <attendees-group-objectId> `
    -WorkshopGroupDisplayName <attendees-group-name> `
    -SandeepAzureOpenAIName   aif-workshop2026 `
    -RunSqlSetup
```
This script:
1. Grants `Cognitive Services User` on `aif-workshop2026` to the attendee group (so they can call embeddings + chat from Lab 03).
2. Prints manual portal instructions for Fabric Capacity Admin + Purview Studio role grants (these cannot be done via ARM/Bicep).
3. Runs `Allfiles/lab03/setup-sql-vector.sql` — creates a SQL user for the attendee group, the `dbo.documents` table with `VECTOR(1536)`, and the cosine-similarity TVF.

> Requires `sqlcmd` and the operator must be the SQL Entra admin set above.

---

## 9. Common failures and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| `CapacityNotAllowed` on Fabric | Pepsico Fabric tenant not signed up | Tenant admin signs up at <https://fabric.microsoft.com>, then re-run |
| `All provided principals must be existing` on Fabric | Object ID format rejected in this tenant | Use **UPN string** for `-FabricAdminObjectId` (already done in this guide) |
| `RegionDoesNotAllowProvisioning` on SQL | swedencentral SQL quota throttled | Add `-SqlLocation centralus` (or other region) and re-run |
| `Tenant-level account already exists` on Purview | Pepsico already has an Enterprise Purview elsewhere | Add `-SkipPurview` and reuse the existing one (you'll still grant the attendee group `Data Reader` + `Data Curator` on it via Purview Studio) |
| SQL `CREATE USER … FROM EXTERNAL PROVIDER` fails | Operator isn't the SQL Entra admin | Run `grant-user-access-day2.ps1` as the principal in `-SqlAadAdminLogin` |
| Attendee can't see their workspace | Different Entra tenant or no Fabric license | Attendee must be in the Pepsico tenant + have Fabric Free license assigned |

---

## 10. Teardown (only when workshop is over)

```powershell
# 1. Delete 60 Fabric workspaces
./scripts/deprovision-fabric-workspaces.ps1

# 2. Delete the 3 Day 2 Azure resources (does NOT delete the RG — Day 1 stays)
./scripts/destroy-day2.ps1 `
    -ResourceGroupName pep-azr-aisp-msft-training-lab-sbx-eus-01-rg
```

If you prefer to nuke them by hand:
```powershell
az resource delete -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --resource-type Microsoft.Fabric/capacities --name <fabric-capacity-name>
az sql db delete -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --server <sql-server> --name vectordb --yes
az sql server delete -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --name <sql-server> --yes
az purview account delete -g pep-azr-aisp-msft-training-lab-sbx-eus-01-rg `
    --name <purview-account> --yes
```

The managed RG `managed-pv-pepsiws-<hash>` is auto-deleted when Purview is deleted.

---

## 11. Quick-reference: validated values (Pepsico, 2026-06-18)

| Setting | Value |
|---|---|
| Tenant | Pepsico (`42cc3295-cd0e-449c-b98e-5ce5b560c1d3`) |
| Subscription | `pep-sandbox-01-sub` (`11a82ecc-d5ba-473d-abe2-4b86557c9d55`) |
| Resource group | `pep-azr-aisp-msft-training-lab-sbx-eus-01-rg` |
| Region (Day 1 + Day 2) | `swedencentral` |
| Operator UPN | `Pradipta.Dash.Contractor@pepsico.com` |
| Operator Object ID | `6f07fb7a-cfc2-4bfe-853c-a1b5a87df124` |
| AOAI account (reused) | `aif-workshop2026` (kind=AIServices, contains `gpt-4.1-mini` + `text-embedding-3-small`) |
| Existing Fabric capacities in sub | **0** (clean — no conflicts) |
| Existing Purview accounts in sub | **0** (clean — no conflicts) |
| Validation status (`what-if`) | ✅ **5 to create, 22 to ignore** — no modify/delete on Day 1 resources |

---

For repo layout and module-by-module description, see [`README.md`](README.md).
