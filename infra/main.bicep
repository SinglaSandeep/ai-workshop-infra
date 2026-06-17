targetScope = 'resourceGroup'

@description('Central workshop configuration for all resources, regions, and SKUs.')
param workshopConfig object

module tagsModule './modules/tags.bicep' = {
  name: 'tagsModule'
  params: {
    workshopConfig: workshopConfig
  }
}

// ===========================================================================
// DAY 1 RESOURCES (Sandeep's AI Foundry stack)
// ===========================================================================
module core './modules/core-resources.bicep' = if (workshopConfig.features.enableAiFoundry || workshopConfig.features.enableAiSearch || workshopConfig.features.enableContainerApps || workshopConfig.features.enableCosmosDb) {
  name: 'coreResources'
  params: {
    workshopConfig: workshopConfig
    tags: tagsModule.outputs.tags
  }
}

// ===========================================================================
// DAY 2 DATA PLATFORM RESOURCES (Pradipta's additions)
// ===========================================================================
var enableDataPlatform = contains(workshopConfig.features, 'enableDataPlatform') ? workshopConfig.features.enableDataPlatform : false
var unique = toLower(uniqueString(resourceGroup().id))
var compactWorkshop = toLower(replace(replace('${workshopConfig.workshopName}${workshopConfig.environmentName}', '-', ''), '_', ''))
var basePrefix = take(compactWorkshop, 12)

// Observability (shared across AML and data platform)
module observability './modules/observability.bicep' = if (enableDataPlatform) {
  name: 'observability'
  params: {
    appInsightsName: take('${basePrefix}-${unique}-appi-data', 64)
    logAnalyticsName: take('${basePrefix}-${unique}-law-data', 63)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// Key Vault (for secrets management)
module keyVault './modules/keyvault.bicep' = if (enableDataPlatform) {
  name: 'keyVault'
  params: {
    keyVaultName: take('${basePrefix}-${unique}-kv', 24)
    location: workshopConfig.primaryLocation
    tenantId: workshopConfig.dataPlatform.tenantId
    adminObjectId: workshopConfig.dataPlatform.adminObjectId
    tags: tagsModule.outputs.tags
  }
}

// Azure OpenAI (for LAB 03 - Vector Search)
module openai './modules/azure-openai.bicep' = if (enableDataPlatform && contains(workshopConfig.dataPlatform, 'enableAzureOpenAI') ? workshopConfig.dataPlatform.enableAzureOpenAI : false) {
  name: 'azureOpenAI'
  params: {
    accountName: take('${basePrefix}-${unique}-aoai', 64)
    location: contains(workshopConfig.dataPlatform, 'azureOpenAILocation') ? workshopConfig.dataPlatform.azureOpenAILocation : workshopConfig.primaryLocation
    deployments: contains(workshopConfig.dataPlatform, 'azureOpenAIDeployments') ? workshopConfig.dataPlatform.azureOpenAIDeployments : []
    tags: tagsModule.outputs.tags
  }
}

// Storage Account with HNS for Lakehouse (LAB 01)
module storage './modules/storage.bicep' = if (enableDataPlatform) {
  name: 'storage'
  params: {
    storageAccountName: take('${basePrefix}${unique}lake', 24)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// Separate storage for Azure ML (cannot use HNS)
module storageAML './modules/storage-aml.bicep' = if (enableDataPlatform && contains(workshopConfig.dataPlatform, 'enableAzureML') ? workshopConfig.dataPlatform.enableAzureML : false) {
  name: 'storageAML'
  params: {
    storageAccountName: take('${basePrefix}${unique}aml', 24)
    location: workshopConfig.primaryLocation
    tags: tagsModule.outputs.tags
  }
}

// Azure Machine Learning (LAB 04)
module azureML './modules/azure-ml.bicep' = if (enableDataPlatform && contains(workshopConfig.dataPlatform, 'enableAzureML') ? workshopConfig.dataPlatform.enableAzureML : false) {
  name: 'azureML'
  params: {
    workspaceName: take('${basePrefix}-${unique}-mlw', 64)
    location: workshopConfig.primaryLocation
    storageAccountId: storageAML.outputs.storageAccountId
    keyVaultId: keyVault.outputs.keyVaultId
    appInsightsId: observability.outputs.appInsightsId
    computeClusterName: contains(workshopConfig.dataPlatform, 'amlComputeClusterName') ? workshopConfig.dataPlatform.amlComputeClusterName : 'cpu-cluster'
    computeVmSize: contains(workshopConfig.dataPlatform, 'amlComputeVmSize') ? workshopConfig.dataPlatform.amlComputeVmSize : 'Standard_DS3_v2'
    computeMinNodes: contains(workshopConfig.dataPlatform, 'amlComputeMinNodes') ? workshopConfig.dataPlatform.amlComputeMinNodes : 0
    computeMaxNodes: contains(workshopConfig.dataPlatform, 'amlComputeMaxNodes') ? workshopConfig.dataPlatform.amlComputeMaxNodes : 4
    tags: tagsModule.outputs.tags
  }
}

// PostgreSQL with pgvector (LAB 03 - Vector Search alternative)
module postgres './modules/azure-postgres.bicep' = if (enableDataPlatform && contains(workshopConfig.dataPlatform, 'enablePostgreSQL') ? workshopConfig.dataPlatform.enablePostgreSQL : false) {
  name: 'azurePostgreSQL'
  params: {
    serverName: take('${basePrefix}-${unique}-pg', 63)
    location: contains(workshopConfig.dataPlatform, 'postgreSQLLocation') ? workshopConfig.dataPlatform.postgreSQLLocation : workshopConfig.primaryLocation
    administratorLogin: contains(workshopConfig.dataPlatform, 'postgreSQLAdminLogin') ? workshopConfig.dataPlatform.postgreSQLAdminLogin : 'workshopadmin'
    administratorPassword: contains(workshopConfig.dataPlatform, 'postgreSQLAdminPassword') ? workshopConfig.dataPlatform.postgreSQLAdminPassword : ''
    databaseName: contains(workshopConfig.dataPlatform, 'postgreSQLDatabaseName') ? workshopConfig.dataPlatform.postgreSQLDatabaseName : 'vectordb'
    tags: tagsModule.outputs.tags
  }
}

// ===========================================================================
// OUTPUTS
// ===========================================================================
output resourceNames object = union(
  workshopConfig.features.enableAiFoundry || workshopConfig.features.enableAiSearch || workshopConfig.features.enableContainerApps || workshopConfig.features.enableCosmosDb ? core.outputs.resourceNames : {},
  enableDataPlatform ? {
    azureOpenAI: openai.outputs.accountName
    keyVault: keyVault.outputs.keyVaultName
    storage: storage.outputs.storageAccountName
    storageAML: storageAML.outputs.storageAccountName
    azureML: azureML.outputs.workspaceName
    postgres: postgres.outputs.postgresServerName
  } : {}
)

output endpoints object = union(
  workshopConfig.features.enableAiFoundry || workshopConfig.features.enableAiSearch || workshopConfig.features.enableContainerApps || workshopConfig.features.enableCosmosDb ? core.outputs.endpoints : {},
  enableDataPlatform ? {
    azureOpenAIEndpoint: openai.outputs.endpoint
    keyVaultUri: keyVault.outputs.keyVaultUri
    azureMLEndpoint: azureML.outputs.workspaceId
    postgresEndpoint: postgres.outputs.postgresEndpoint
  } : {}
)

output workshopSettings object = union(
  workshopConfig.features.enableAiFoundry || workshopConfig.features.enableAiSearch || workshopConfig.features.enableContainerApps || workshopConfig.features.enableCosmosDb ? core.outputs.workshopSettings : {},
  enableDataPlatform ? {
    dataLakeContainerName: 'lakehouse'
    postgresDatabase: contains(workshopConfig.dataPlatform, 'postgreSQLDatabaseName') ? workshopConfig.dataPlatform.postgreSQLDatabaseName : 'vectordb'
  } : {}
)

output managedIdentityPrincipals object = union(
  workshopConfig.features.enableAiFoundry || workshopConfig.features.enableAiSearch || workshopConfig.features.enableContainerApps || workshopConfig.features.enableCosmosDb ? core.outputs.managedIdentityPrincipals : {},
  {} // Day 2 components don't have managed identities yet
)