# PepsiCo × Microsoft Workshop — Day 2 (Data) Infrastructure

This branch holds **only the Day 2 / Data workshop infrastructure** (Pradipta's track).
Day 1 (Sandeep — Agentic AI) is on `main`.

## Quick start

See **[DAY2-DEPLOY-GUIDE.md](DAY2-DEPLOY-GUIDE.md)** for the full customer-facing guide.

```powershell
./scripts/deploy-day2.ps1 `
    -ResourceGroupName <sandeep-rg> `
    -Location           eastus2 `
    -FabricAdminObjectId  <upn-or-objectid> `
    -SqlAadAdminLogin     <admin@tenant.onmicrosoft.com> `
    -SqlAadAdminObjectId  <admin-object-id>
```

## What gets deployed

| Resource | Purpose | Used by |
|---|---|---|
| Microsoft Fabric capacity (F2+) | Fabric runtime | Lab 01 (Lakehouse + Data Agent), Lab 02 (RTI), governance demo |
| Azure SQL Server + DB (Entra-only, `VECTOR(1536)`) | Vector search | Lab 03 (Vector Search) |
| Microsoft Purview account | Catalog, lineage, sensitivity labels | Governance demo |

Reuses from Sandeep's Day 1: Azure OpenAI (embeddings + chat), Cosmos DB.

## Files

```
infra/
  main-day2.bicep                   Entry point (RG-scoped)
  main-day2.parameters.json         Customer-edited parameters
  modules/
    fabric-capacity.bicep           Microsoft.Fabric/capacities
    sql.bicep                       Azure SQL server + db, Entra-only auth
    purview.bicep                   Microsoft.Purview/accounts
  user-access-day2-slim.bicep       RBAC on Sandeep's existing AOAI
  user-access-day2-slim.parameters.json
scripts/
  deploy-day2.ps1                     Provision
  grant-user-access-day2.ps1          Participant access (AOAI RBAC + portal instructions + SQL setup)
  provision-fabric-workspaces.ps1     Bulk-create one Fabric workspace per attendee, bind to capacity
  deprovision-fabric-workspaces.ps1   Bulk-delete the workspaces created above
  destroy-day2.ps1                    Teardown (does NOT delete the RG)
Allfiles/
  attendees-sample.csv                Template for the bulk workspace script
  lab03/
    setup-sql-vector.sql              CREATE USER + demo VECTOR table for Lab 03
DAY2-DEPLOY-GUIDE.md                Customer-facing guide
```
