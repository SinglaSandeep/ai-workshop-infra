# Day 2 — Customer Call Cheat Sheet

> **One-page handoff** for getting Day 2 (Data) deployed in the customer's
> Azure subscription. For the full guide see [`DAY2-DEPLOY-GUIDE.md`](DAY2-DEPLOY-GUIDE.md).

## What we are deploying (3 resources)

| Resource | Purpose | Approx cost (pay-go) |
|---|---|---|
| **Fabric Capacity** (F-SKU) | Lakehouse, notebooks, Power BI, Data Agent (Lab 01 + 02) | F2 ≈ $0.36/hr · F32 ≈ $5.76/hr · F64 ≈ $11.52/hr · **pause off-hours** |
| **Azure SQL Database** (serverless GP_S_Gen5_2, Entra-only) | `VECTOR(1536)` cosine search (Lab 03) | ≈ $0.52/vCore-hr; auto-pauses after 60 min idle |
| **Microsoft Purview** account | Catalog, lineage, classifications (governance demo) | ≈ $0.411/hr capacity unit |

Sandeep's Day 1 stack (Foundry, AOAI, Cosmos, AI Search, Container Apps) is **reused** — we don't redeploy it.

---

## Prereqs the CUSTOMER must have ready before the call

| # | Item | How they get it |
|---|---|---|
| 1 | **Owner / Contributor** on an Azure subscription | Their Azure team |
| 2 | **Resource group** — same one Sandeep used for Day 1 | `az group list -o table` |
| 3 | **Region** — must support Fabric, SQL VECTOR, Purview | `eastus2`, `swedencentral`, or `westus3` |
| 4 | **Fabric tenant signed up** | Tenant admin signs up at <https://fabric.microsoft.com> for Fabric Free (one-time tenant action). Without this, F-SKU provisioning fails. |
| 5 | **Fabric admin UPN** (e.g. `pat@contoso.com`) | The person who will own the Fabric capacity. **UPN string, NOT Object ID** — many tenants reject the Object ID form. |
| 6 | **SQL Entra admin** UPN + Object ID | Same person as #5 is fine. SQL is Entra-only — no SQL password. |
| 7 | **Workshop attendees CSV** — 60 rows of `UPN, ObjectId, DisplayName` | Their identity team. ObjectIds must exist in the **same Entra tenant**. |
| 8 | **Sandeep's AOAI account name** | From Sandeep's `.azure/.env` from Day 1 |
| 9 | Local tools on operator laptop | `az` CLI 2.65+, `Az` PowerShell, `sqlcmd`, PowerShell 7+ |

---

## The 3-command deployment

Run all on the operator laptop (not the customer laptop) — `az login` to the customer subscription first.

```powershell
git clone https://github.com/SinglaSandeep/ai-workshop-infra.git
cd ai-workshop-infra
git checkout Pradipta_Day2_v2
```

### 1. Provision the 3 resources

```powershell
./scripts/deploy-day2.ps1 `
    -ResourceGroupName    rg-pepsi-shared `
    -Location             eastus2 `
    -SqlLocation          centralus `
    -FabricAdminObjectId  'fabricadmin@contoso.com' `
    -SqlAadAdminLogin     'sqladmin@contoso.com' `
    -SqlAadAdminObjectId  '<their-objectId>' `
    -FabricSku            F2
```

> **Common gotchas:**
> - **`RegionDoesNotAllowProvisioning`** on SQL → use `-SqlLocation centralus` (or another region)
> - **"All provided principals must be existing"** on Fabric → you passed an Object ID for `-FabricAdminObjectId`; pass **UPN** instead
> - **Purview "tenant-level account already exists"** → only one Enterprise Purview per tenant. If they already have one, add `-SkipPurview` and reuse theirs
> - **Fabric provisioning fails with capacity-not-allowed** → tenant hasn't signed up for Fabric. See prereq #4.

Outputs go to `.azure/main-day2-outputs.json` and `.azure/workshop-day2.env`. **Capture the Fabric capacity name from these — you need it next.**

### 2. Bulk-create one Fabric workspace per attendee (60 of them)

```powershell
./scripts/provision-fabric-workspaces.ps1 `
    -AttendeesCsv    Allfiles/attendees.csv `
    -CapacityName    <FabricCapacityName-from-step-1>
```

Output: `.azure/workspace-assignments.csv` — one URL per attendee. **Email each attendee their `WorkspaceUrl`**. Idempotent (re-runnable).

### 3. Grant attendees access to AOAI + run SQL setup

```powershell
./scripts/grant-user-access-day2.ps1 `
    -ResourceGroupName        rg-pepsi-shared `
    -WorkshopGroupObjectId    <attendees-entra-group-objectId> `
    -WorkshopGroupDisplayName 'pepsi-workshop-day2-attendees' `
    -SandeepAzureOpenAIName   <Sandeep-AOAI-name> `
    -RunSqlSetup
```

This does:
- Azure RBAC `Cognitive Services User` on Sandeep's AOAI (automatic)
- Prints manual portal steps for **Fabric capacity admin** + **Purview Studio role** (Bicep can't do these)
- Creates SQL user, `documents VECTOR(1536)` table, and the cosine search TVF

---

## Capacity sizing decision (F-SKU)

| Concurrent attendees actively running notebooks | Recommended SKU | Hourly |
|---|---|---|
| 1–2 (testing only) | **F2** | $0.36 |
| 10–15 | **F8** | $1.44 |
| 30 | **F32** | $5.76 |
| 60 (full workshop) | **F64** | $11.52 |

**Standard practice:** deploy at **F2** for setup/testing, scale up to **F64** the morning of the workshop, scale back down (or pause) the same evening.

```powershell
./scripts/deploy-day2.ps1 ... -FabricSku F64 -SkipSql -SkipPurview
```

---

## Manual portal steps (the script prints them)

These cannot be automated via Bicep:

1. **Fabric capacity admin** — Fabric portal → Admin → Capacity settings → add the workshop attendees Entra group as **Capacity Admin** (so they can assign workspaces to the capacity).
2. **Purview Studio** — `https://web.purview.azure.com` → pick the account → Data map → Collections → root collection → Role assignments → add the workshop group as **Data Reader** + **Data Curator**.

---

## Teardown

```powershell
./scripts/deprovision-fabric-workspaces.ps1   # delete all 60 workspaces
./scripts/destroy-day2.ps1 -ResourceGroupName rg-pepsi-shared
```

`destroy-day2.ps1` deletes only our 3 resources — it does **NOT** delete the resource group (Sandeep's Day 1 resources live there too).

---

## What MSFT must support during the customer's run

If they hit issues, you'll most often see one of:

| Symptom | Cause | Fix |
|---|---|---|
| `RegionDoesNotAllowProvisioning` | Region capacity throttle | Pass `-SqlLocation <other-region>` |
| Fabric deploy 400 / "principal not found" | Object ID instead of UPN | Use UPN string in `-FabricAdminObjectId` |
| `InvalidResourceLocation` on SQL retry | Server name reserved at old region | Bump `-EnvironmentName` for fresh `uniqueString` |
| `PrincipalAlreadyHasWorkspaceRolePermissions` | Re-run; principal already Admin | Ignore — script treats it as success |
| Attendee can't see their workspace | Different tenant or no Fabric license | Ensure attendee is in the same tenant + has Fabric Free license assigned |
| SQL `setup-sql-vector.sql` fails on `CREATE USER FROM EXTERNAL PROVIDER` | Operator running it is not the SQL Entra admin | Run as the principal in `-SqlAadAdminLogin` |

---

## Talking points for the call

1. "We deploy 3 resources — Fabric, Azure SQL, Purview — into the **same RG** as Sandeep's Day 1. Sandeep's stack is reused for Lab 03 embeddings."
2. "Cost lever is Fabric capacity. We start at F2 (~$9/day). Day-of we scale to F64 (~$280/day). Pause off-hours."
3. "60 attendees, 60 workspaces — fully automated. Each attendee gets a direct URL and is Admin only on **their own** workspace; no tenant-level powers."
4. "Three identity touchpoints we need from your side: a Fabric admin UPN, a SQL Entra admin, and an Entra group of attendees with Object IDs."
5. "Workshop runs entirely on Entra — no SQL passwords, no AOAI keys. Everything is `DefaultAzureCredential`."

---

## What the customer hands the attendees

For each attendee:
- The `WorkspaceUrl` from `workspace-assignments.csv`
- The lab markdown link (workshop site / repo)
- A one-line note: *"Sign in with your Pepsi Entra account at the URL above. Your workspace is named `ws-pepsi-day2-<your-id>`. Your Lakehouse, notebook, semantic model, and Data Agent must all use the same `<your-id>` suffix."*
