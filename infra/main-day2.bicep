// ===========================================================================
// PepsiCo × Microsoft Workshop — Day 2 (Data) slim infrastructure.
// ---------------------------------------------------------------------------
// Day 1 (Sandeep — Agentic AI) is deployed separately (Foundry, Cosmos, AI
// Search, Container Apps, ACR, AOAI). This template adds ONLY the Day 2
// resources Pradipta's labs need, into the SAME resource group:
//
//   * Microsoft Fabric capacity (Lab 01 Lakehouse + Lab 02 RTI)
//   * Azure SQL Server + Database with VECTOR support (Lab 03 Vector Search)
//   * Microsoft Purview account (Governance demo)
//
// Run with:
//   az deployment group create \
//     --resource-group <sandeep-rg> \
//     --template-file infra/main-day2.bicep \
//     --parameters infra/main-day2.parameters.json
//
// Or via the convenience script: ./scripts/deploy-day2.ps1
// ===========================================================================

targetScope = 'resourceGroup'

@description('Workshop name prefix for resource names. Lowercase, 3-12 chars.')
@minLength(3)
@maxLength(12)
param workshopName string = 'pepsiws'

@description('Environment suffix (e.g. prod, sandbox).')
param environmentName string = 'day2'

@description('Azure region for the Day 2 resources. Must support: Fabric, Azure SQL VECTOR, and Purview. eastus2, swedencentral, westus3 are good defaults.')
param location string = resourceGroup().location

@description('Optional override for the Azure SQL region. Defaults to the main location. Use this if your primary region is temporarily not accepting new SQL servers.')
param sqlLocation string = location

@description('Enable Microsoft Fabric capacity provisioning (Lab 01 + 02). Set to false if a shared Fabric capacity already exists in the tenant.')
param enableFabricCapacity bool = true

@description('Fabric capacity SKU. F2 is workshop-minimum; F4 recommended for 5+ concurrent teams.')
@allowed([ 'F2', 'F4', 'F8', 'F16', 'F32', 'F64' ])
param fabricSkuName string = 'F2'

@description('Object ID of the Entra user/group to be Fabric capacity admin.')
param fabricAdminObjectId string

@description('Enable Azure SQL Server + DB provisioning (Lab 03 Vector Search).')
param enableSqlVector bool = true

@description('UPN of the Entra admin for Azure SQL (Entra-only auth).')
param sqlAadAdminLogin string

@description('Object ID of the Entra admin for Azure SQL.')
param sqlAadAdminObjectId string

@description('Azure SQL database name.')
param sqlDatabaseName string = 'vectordb'

@description('Enable Microsoft Purview account provisioning (governance demo).')
param enablePurview bool = true

@description('Object ID of the deploying admin for Purview data-plane role assignment guidance.')
param purviewAdminObjectId string = sqlAadAdminObjectId

@description('Tags applied to every resource.')
param tags object = {
  Project: 'PepsiCo MSFT Workshop'
  Day: 'Day 2 - Data'
  Owner: 'Pradipta'
  ManagedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Naming
// ---------------------------------------------------------------------------
var unique = toLower(uniqueString(resourceGroup().id, environmentName))
var basePrefix = take(toLower(replace(replace(workshopName, '-', ''), '_', '')), 12)

var fabricCapacityName = take('fab${basePrefix}${unique}', 24)
var sqlServerName = take('sql-${basePrefix}-${unique}', 50)
var purviewAccountName = take('pv-${basePrefix}-${unique}', 50)

// ---------------------------------------------------------------------------
// Microsoft Fabric capacity (Lab 01 Lakehouse + Lab 02 RTI)
// ---------------------------------------------------------------------------
module fabric './modules/fabric-capacity.bicep' = if (enableFabricCapacity) {
  name: 'fabricCapacity'
  params: {
    capacityName: fabricCapacityName
    location: location
    skuName: fabricSkuName
    adminObjectId: fabricAdminObjectId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Azure SQL with VECTOR (Lab 03 Vector Search)
// ---------------------------------------------------------------------------
module sql './modules/sql.bicep' = if (enableSqlVector) {
  name: 'sqlVector'
  params: {
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    location: sqlLocation
    aadAdminLogin: sqlAadAdminLogin
    aadAdminObjectId: sqlAadAdminObjectId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Microsoft Purview (governance demo)
// ---------------------------------------------------------------------------
module purview './modules/purview.bicep' = if (enablePurview) {
  name: 'purview'
  params: {
    purviewAccountName: purviewAccountName
    location: location
    adminObjectId: purviewAdminObjectId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs (consumed by ./scripts/deploy-day2.ps1 to write a customer .env)
// ---------------------------------------------------------------------------
output fabricCapacityName string = enableFabricCapacity ? fabric!.outputs.capacityName : ''
output sqlServerFqdn string = enableSqlVector ? sql!.outputs.sqlServerFqdn : ''
output sqlDatabaseName string = enableSqlVector ? sql!.outputs.sqlDatabaseName : ''
output purviewAccountName string = enablePurview ? purview!.outputs.purviewAccountName : ''
output purviewAtlasEndpoint string = enablePurview ? purview!.outputs.purviewAtlasEndpoint : ''
output resourceGroupName string = resourceGroup().name
output region string = location
