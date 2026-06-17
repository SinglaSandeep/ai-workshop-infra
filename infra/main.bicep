targetScope = 'resourceGroup'

@description('Central workshop configuration for all resources, regions, and SKUs.')
param workshopConfig object

// ---------------------------------------------------------------------------
// Naming — deterministic, globally unique
// ---------------------------------------------------------------------------
var unique = toLower(uniqueString(resourceGroup().id))
var compactWorkshop = toLower(replace(replace('${workshopConfig.workshopName}${workshopConfig.environmentName}', '-', ''), '_', ''))
var basePrefix = take(compactWorkshop, 12)

// ---------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------
module tagsModule './modules/tags.bicep' = {
  name: 'tagsModule'
  params: {
    workshopConfig: workshopConfig
  }
}

// ---------------------------------------------------------------------------
// Sandeep's core resources (AI Foundry, Cosmos DB, AI Search, Container Apps)
// ---------------------------------------------------------------------------
module core './modules/core-resources.bicep' = if (workshopConfig.features.enableAiFoundry || workshopConfig.features.enableAiSearch || workshopConfig.features.enableContainerApps || workshopConfig.features.enableCosmosDb) {
  name: 'coreResources'
  params: {
    workshopConfig: workshopConfig
    tags: tagsModule.outputs.tags
  }
}

// ---------------------------------------------------------------------------
// Pradipta's Data Platform resources (Azure OpenAI, SQL, AML, Storage, Fabric)
// ---------------------------------------------------------------------------

// Observability (shared across AML and data platform)
module observability './modules/observability.bicep' = if (workshopConfig.features.enableDataPlatform) {
  name: 'observability'
  params: {
    appInsightsName: take('${basePrefix}-${unique}-appi-data', 64)
    logAnalyticsName: take('${basePrefix}-${unique}-law-data', 63)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// Storage Account (ADLS Gen2)
module storage './modules/storage.bicep' = if (workshopConfig.features.enableDataPlatform) {
  name: 'storage'
  params: {
    storageAccountName: take('${basePrefix}${unique}st', 24)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// Storage Account for AML (WITHOUT HNS - AML requirement)
module storageAml './modules/storage-aml.bicep' = if (workshopConfig.features.enableDataPlatform) {
  name: 'storageAml'
  params: {
    storageAccountName: take('${basePrefix}${unique}aml', 24)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// Key Vault
module keyVault './modules/keyvault.bicep' = if (workshopConfig.features.enableDataPlatform) {
  name: 'keyVault'
  params: {
    keyVaultName: take('${basePrefix}-${unique}-kv', 24)
    location: workshopConfig.primaryLocation
    tenantId: tenant().tenantId
    adminObjectId: workshopConfig.dataPlatform.adminObjectId
    tags: tagsModule.outputs.tags
  }
}

// Azure OpenAI (embeddings + chat for Lab 03 and Data Agent)
module openai './modules/azure-openai.bicep' = if (workshopConfig.features.enableDataPlatform) {
  name: 'azureOpenAI'
  params: {
    accountName: take('${basePrefix}-${unique}-aoai', 64)
    location: workshopConfig.dataPlatform.openAiLocation
    deployments: workshopConfig.dataPlatform.openAiDeployments
    tags: tagsModule.outputs.tags
  }
}

// Azure SQL Database with VECTOR support (Lab 03)
module sql './modules/azure-sql.bicep' = if (workshopConfig.features.enableDataPlatform) {
  name: 'azureSql'
  params: {
    serverName: take('${basePrefix}-${unique}-sql', 63)
    databaseName: workshopConfig.dataPlatform.sqlDatabaseName
    location: workshopConfig.dataPlatform.sqlLocation
    aadAdminLogin: workshopConfig.dataPlatform.aadAdminLogin
    aadAdminObjectId: workshopConfig.dataPlatform.adminObjectId
    tenantId: tenant().tenantId
    tags: tagsModule.outputs.tags
  }
}

// Azure Machine Learning workspace + compute (Lab 04)
module aml './modules/azure-ml.bicep' = if (workshopConfig.features.enableDataPlatform) {
  name: 'azureMl'
  params: {
    workspaceName: take('${basePrefix}-${unique}-aml', 32)
    location: workshopConfig.primaryLocation
    storageAccountId: storageAml.outputs.storageAccountId
    keyVaultId: keyVault.outputs.keyVaultId
    appInsightsId: observability.outputs.appInsightsId
    computeClusterName: workshopConfig.dataPlatform.amlComputeName
    computeVmSize: workshopConfig.dataPlatform.amlComputeVmSize
    computeMinNodes: workshopConfig.dataPlatform.amlComputeMinNodes
    computeMaxNodes: workshopConfig.dataPlatform.amlComputeMaxNodes
    tags: tagsModule.outputs.tags
  }
}

// Microsoft Fabric capacity (Labs 01, 02, Governance demo)
module fabric './modules/fabric-capacity.bicep' = if (workshopConfig.features.enableFabric) {
  name: 'fabricCapacity'
  params: {
    capacityName: take('${basePrefix}-${unique}-fabric', 63)
    location: workshopConfig.primaryLocation
    skuName: workshopConfig.dataPlatform.fabricSkuName
    adminObjectId: workshopConfig.dataPlatform.adminObjectId
    tags: tagsModule.outputs.tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output resourceNames object = {
  // Sandeep's resources
  aiFoundry: (workshopConfig.features.enableAiFoundry) ? core.outputs.resourceNames.aiFoundry : ''
  aiProject: (workshopConfig.features.enableAiFoundry) ? core.outputs.resourceNames.aiProject : ''
  aiFoundrySecondary: (workshopConfig.features.enableAiFoundry) ? core.outputs.resourceNames.aiFoundrySecondary : ''
  aiProjectSecondary: (workshopConfig.features.enableAiFoundry) ? core.outputs.resourceNames.aiProjectSecondary : ''
  aiSearch: (workshopConfig.features.enableAiSearch) ? core.outputs.resourceNames.aiSearch : ''
  appInsights: (workshopConfig.features.enableContainerApps) ? core.outputs.resourceNames.appInsights : ''
  containerAppsEnvironment: (workshopConfig.features.enableContainerApps) ? core.outputs.resourceNames.containerAppsEnvironment : ''
  containerRegistry: (workshopConfig.features.enableContainerApps) ? core.outputs.resourceNames.containerRegistry : ''
  cosmosDb: (workshopConfig.features.enableCosmosDb) ? core.outputs.resourceNames.cosmosDb : ''
  logAnalytics: (workshopConfig.features.enableContainerApps) ? core.outputs.resourceNames.logAnalytics : ''
  workloadIdentity: (workshopConfig.features.enableContainerApps) ? core.outputs.resourceNames.workloadIdentity : ''
  // Pradipta's resources
  storageAccount: workshopConfig.features.enableDataPlatform ? storage.outputs.storageAccountName : ''
  keyVault: workshopConfig.features.enableDataPlatform ? keyVault.outputs.keyVaultName : ''
  openAi: workshopConfig.features.enableDataPlatform ? openai.outputs.accountName : ''
  sqlServer: workshopConfig.features.enableDataPlatform ? sql.outputs.sqlServerName : ''
  sqlDatabase: workshopConfig.features.enableDataPlatform ? sql.outputs.databaseName : ''
  amlWorkspace: workshopConfig.features.enableDataPlatform ? aml.outputs.workspaceName : ''
  fabricCapacity: workshopConfig.features.enableFabric ? fabric.outputs.capacityName : ''
  dataAppInsights: workshopConfig.features.enableDataPlatform ? observability.outputs.appInsightsName : ''
}

output endpoints object = {
  // Sandeep's endpoints
  aiFoundryEndpoint: (workshopConfig.features.enableAiFoundry) ? core.outputs.endpoints.aiFoundryEndpoint : ''
  aiProjectEndpoint: (workshopConfig.features.enableAiFoundry) ? core.outputs.endpoints.aiProjectEndpoint : ''
  aiProjectResourceId: (workshopConfig.features.enableAiFoundry) ? core.outputs.endpoints.aiProjectResourceId : ''
  aiProjectEndpointSecondary: (workshopConfig.features.enableAiFoundry) ? core.outputs.endpoints.aiProjectEndpointSecondary : ''
  aiProjectResourceIdSecondary: (workshopConfig.features.enableAiFoundry) ? core.outputs.endpoints.aiProjectResourceIdSecondary : ''
  appInsightsConnectionString: (workshopConfig.features.enableContainerApps) ? core.outputs.endpoints.appInsightsConnectionString : ''
  cosmosEndpoint: (workshopConfig.features.enableCosmosDb) ? core.outputs.endpoints.cosmosEndpoint : ''
  searchEndpoint: (workshopConfig.features.enableAiSearch) ? core.outputs.endpoints.searchEndpoint : ''
  // Pradipta's endpoints
  openAiEndpoint: workshopConfig.features.enableDataPlatform ? openai.outputs.endpoint : ''
  sqlServerFqdn: workshopConfig.features.enableDataPlatform ? sql.outputs.sqlServerFqdn : ''
  storageEndpoint: workshopConfig.features.enableDataPlatform ? storage.outputs.primaryDfsEndpoint : ''
  keyVaultUri: workshopConfig.features.enableDataPlatform ? keyVault.outputs.keyVaultUri : ''
}

output workshopSettings object = {
  // Sandeep's settings
  modelDeployment: workshopConfig.aiFoundry.chatDeploymentName
  embeddingDeployment: workshopConfig.aiFoundry.embeddingDeploymentName
  cosmosDatabase: workshopConfig.cosmosDb.databaseName
  cosmosSalesContainer: workshopConfig.cosmosDb.salesContainerName
  cosmosInventoryContainer: workshopConfig.cosmosDb.inventoryContainerName
  cosmosMarketingContainer: workshopConfig.cosmosDb.marketingContainerName
  acaEnvironment: (workshopConfig.features.enableContainerApps) ? core.outputs.workshopSettings.acaEnvironment : ''
  acrName: (workshopConfig.features.enableContainerApps) ? core.outputs.workshopSettings.acrName : ''
  workloadIdentityClientId: (workshopConfig.features.enableContainerApps) ? core.outputs.workshopSettings.workloadIdentityClientId : ''
  workloadIdentityResourceId: (workshopConfig.features.enableContainerApps) ? core.outputs.workshopSettings.workloadIdentityResourceId : ''
  // Pradipta's settings
  openAiEmbedDeployment: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.openAiEmbedDeploymentName : ''
  openAiChatDeployment: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.openAiChatDeploymentName : ''
  sqlDatabaseName: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.sqlDatabaseName : ''
  amlComputeName: workshopConfig.features.enableDataPlatform ? workshopConfig.dataPlatform.amlComputeName : ''
}

output managedIdentityPrincipals object = {
  // Sandeep's identities
  aiFoundryPrincipalId: (workshopConfig.features.enableAiFoundry) ? core.outputs.managedIdentityPrincipals.aiFoundryPrincipalId : ''
  aiProjectPrincipalId: (workshopConfig.features.enableAiFoundry) ? core.outputs.managedIdentityPrincipals.aiProjectPrincipalId : ''
  aiFoundrySecondaryPrincipalId: (workshopConfig.features.enableAiFoundry) ? core.outputs.managedIdentityPrincipals.aiFoundrySecondaryPrincipalId : ''
  aiProjectSecondaryPrincipalId: (workshopConfig.features.enableAiFoundry) ? core.outputs.managedIdentityPrincipals.aiProjectSecondaryPrincipalId : ''
  containerRegistryPrincipalId: (workshopConfig.features.enableContainerApps) ? core.outputs.managedIdentityPrincipals.containerRegistryPrincipalId : ''
  cosmosPrincipalId: (workshopConfig.features.enableCosmosDb) ? core.outputs.managedIdentityPrincipals.cosmosPrincipalId : ''
  workloadIdentityPrincipalId: (workshopConfig.features.enableContainerApps) ? core.outputs.managedIdentityPrincipals.workloadIdentityPrincipalId : ''
  // Pradipta's identities
  openAiPrincipalId: workshopConfig.features.enableDataPlatform ? openai.outputs.principalId : ''
  amlPrincipalId: workshopConfig.features.enableDataPlatform ? aml.outputs.principalId : ''
}