// ═══════════════════════════════════════════════════════════════════════════
// PepsiCo Workshop - Day 2 Infrastructure
// Data Platform: Fabric, Vector Search, Azure ML
// ═══════════════════════════════════════════════════════════════════════════

targetScope = 'subscription'

@description('Workshop configuration from main.parameters.json')
param workshopConfig object

// ═══════════════════════════════════════════════════════════════════════════
// Resource Group
// ═══════════════════════════════════════════════════════════════════════════

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${workshopConfig.workshopName}-${workshopConfig.environmentName}'
  location: workshopConfig.primaryLocation
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared Modules
// ═══════════════════════════════════════════════════════════════════════════

module tagsModule './modules/tags.bicep' = {
  scope: rg
  name: 'tags'
  params: {
    tags: workshopConfig.tags
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Day 2 Data Platform Components
// ═══════════════════════════════════════════════════════════════════════════

// Azure OpenAI (LAB 03: Vector embeddings, Data Agent chat)
module openai './modules/azure-openai.bicep' = if (workshopConfig.features.enableDataPlatform) {
  scope: rg
  name: 'azureOpenAI'
  params: {
    name: take('${workshopConfig.workshopName}-${uniqueString(rg.id)}-aoai', 64)
    location: workshopConfig.dataPlatform.openAiLocation
    deployments: workshopConfig.dataPlatform.openAiDeployments
    tags: tagsModule.outputs.tags
  }
}

// Cosmos DB with Vector Search (LAB 03: Alternative to SQL for vector search)
module cosmos './modules/cosmos-db.bicep' = if (workshopConfig.features.enableCosmosDb) {
  scope: rg
  name: 'cosmosDb'
  params: {
    accountName: take('${workshopConfig.workshopName}-${uniqueString(rg.id)}-cosmos', 44)
    location: workshopConfig.primaryLocation
    enableVectorSearch: true
    tags: tagsModule.outputs.tags
  }
}

// PostgreSQL with pgvector (LAB 03: Vector search alternative)
module postgres './modules/azure-postgres.bicep' = if (workshopConfig.features.enableDataPlatform) {
  scope: rg
  name: 'azurePostgres'
  params: {
    serverName: take('${workshopConfig.workshopName}-${uniqueString(rg.id)}-pg', 63)
    databaseName: workshopConfig.dataPlatform.sqlDatabaseName
    location: workshopConfig.primaryLocation
    administratorLogin: workshopConfig.dataPlatform.sqlAdministratorLogin
    administratorPassword: workshopConfig.dataPlatform.sqlAdministratorPassword
    tags: tagsModule.outputs.tags
  }
}

// Storage Account - ADLS Gen2 (LAB 01: Lakehouse, LAB 04: AML artifacts)
module storage './modules/storage.bicep' = if (workshopConfig.features.enableDataPlatform) {
  scope: rg
  name: 'storage'
  params: {
    name: take(replace('${workshopConfig.workshopName}${uniqueString(rg.id)}', '-', ''), 24)
    location: workshopConfig.primaryLocation
    isHnsEnabled: true  // ADLS Gen2 for Lakehouse
    tags: tagsModule.outputs.tags
  }
}

// Storage Account - Standard (LAB 04: AML workspace requirement)
module storageAml './modules/storage-aml.bicep' = if (workshopConfig.features.enableDataPlatform) {
  scope: rg
  name: 'storageAml'
  params: {
    name: take(replace('${workshopConfig.workshopName}${uniqueString(rg.id)}aml', '-', ''), 24)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// Azure ML Workspace (LAB 04: Train, register, deploy models)
module aml './modules/azure-ml.bicep' = if (workshopConfig.features.enableDataPlatform) {
  scope: rg
  name: 'azureML'
  params: {
    workspaceName: take('${workshopConfig.workshopName}-${uniqueString(rg.id)}-aml', 63)
    location: workshopConfig.primaryLocation
    storageAccountId: storageAml.outputs.storageAccountId
    keyVaultId: keyvault.outputs.keyVaultId
    appInsightsId: observability.outputs.appInsightsId
    computeName: workshopConfig.dataPlatform.amlComputeName
    computeVmSize: workshopConfig.dataPlatform.amlComputeVmSize
    computeMinNodes: workshopConfig.dataPlatform.amlComputeMinNodes
    computeMaxNodes: workshopConfig.dataPlatform.amlComputeMaxNodes
    tags: tagsModule.outputs.tags
  }
}

// Key Vault (All labs: Secure connection strings)
module keyvault './modules/keyvault.bicep' = {
  scope: rg
  name: 'keyVault'
  params: {
    name: take('${workshopConfig.workshopName}-${uniqueString(rg.id)}', 24)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// Observability (LAB 04: AML monitoring)
module observability './modules/observability.bicep' = if (workshopConfig.features.enableDataPlatform) {
  scope: rg
  name: 'observability'
  params: {
    logAnalyticsName: take('${workshopConfig.workshopName}-${uniqueString(rg.id)}-law-data', 63)
    appInsightsName: take('${workshopConfig.workshopName}-${uniqueString(rg.id)}-appi-data', 63)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Outputs
// ═══════════════════════════════════════════════════════════════════════════

output resourceGroupName string = rg.name
output location string = rg.location

output resources object = {
  openAiEndpoint: workshopConfig.features.enableDataPlatform ? openai.outputs.endpoint : ''
  openAiName: workshopConfig.features.enableDataPlatform ? openai.outputs.name : ''
  
  postgresEndpoint: workshopConfig.features.enableDataPlatform ? postgres.outputs.postgresEndpoint : ''
  postgresDatabase: workshopConfig.features.enableDataPlatform ? postgres.outputs.postgresDatabaseName : ''
  
  cosmosEndpoint: workshopConfig.features.enableCosmosDb ? cosmos.outputs.endpoint : ''
  cosmosName: workshopConfig.features.enableCosmosDb ? cosmos.outputs.accountName : ''
  
  storageName: workshopConfig.features.enableDataPlatform ? storage.outputs.storageAccountName : ''
  storageEndpoint: workshopConfig.features.enableDataPlatform ? storage.outputs.primaryEndpoint : ''
  
  amlWorkspaceName: workshopConfig.features.enableDataPlatform ? aml.outputs.workspaceName : ''
  amlComputeName: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.amlComputeName : ''
  
  keyVaultName: keyvault.outputs.keyVaultName
  keyVaultUri: keyvault.outputs.keyVaultUri
}

output workshopSettings object = {
  openAiEmbedDeployment: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.openAiEmbedDeploymentName : ''
  openAiChatDeployment: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.openAiChatDeploymentName : ''
  postgresDatabase: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.sqlDatabaseName : ''
  amlComputeName: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.amlComputeName : ''
}

output managedIdentityPrincipals object = {
  openAiPrincipalId: workshopConfig.features.enableDataPlatform ? openai.outputs.principalId : ''
  amlPrincipalId: workshopConfig.features.enableDataPlatform ? aml.outputs.principalId : ''
}
