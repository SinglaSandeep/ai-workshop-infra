targetScope = 'resourceGroup'

@description('Central workshop configuration object.')
param workshopConfig object

@description('Standardized tags to apply to all resources.')
param tags object

// ---------------------------------------------------------------------------
// Naming
// A short, deterministic token keeps every resource name globally unique while
// still being readable. `workshopName` and `environmentName` come from the
// central config so customers control the prefix.
// ---------------------------------------------------------------------------
var unique = toLower(uniqueString(resourceGroup().id))
var compactWorkshop = toLower(replace(replace('${workshopConfig.workshopName}${workshopConfig.environmentName}', '-', ''), '_', ''))
var basePrefix = take(compactWorkshop, 12)

var searchName = take('${basePrefix}${unique}srch', 24)
var registryName = take('${basePrefix}${unique}cr', 50)
var managedEnvName = take('${basePrefix}-${unique}-cae', 32)
var appInsightsName = take('${basePrefix}-${unique}-appi', 64)
var logAnalyticsName = take('${basePrefix}-${unique}-law', 63)
var cosmosName = take('${basePrefix}-${unique}-cosmos', 44)

// ---------------------------------------------------------------------------
// Observability: Log Analytics + Application Insights
// ---------------------------------------------------------------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (workshopConfig.features.enableContainerApps) {
  name: logAnalyticsName
  location: workshopConfig.primaryLocation
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: workshopConfig.containerApps.logRetentionInDays
  }
  tags: tags
}

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = if (workshopConfig.features.enableContainerApps) {
  name: appInsightsName
  location: workshopConfig.primaryLocation
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
  tags: tags
}

// ---------------------------------------------------------------------------
// Azure AI Search (Foundry IQ knowledge base backing store)
// Uses key-based auth (default). The data-load operator and the Foundry IQ
// pipeline authenticate with the service keys / connection settings.
// ---------------------------------------------------------------------------
resource search 'Microsoft.Search/searchServices@2025-05-01' = if (workshopConfig.features.enableAiSearch) {
  name: searchName
  location: workshopConfig.primaryLocation
  sku: {
    name: workshopConfig.aiSearch.sku
  }
  properties: {
    partitionCount: workshopConfig.aiSearch.partitionCount
    publicNetworkAccess: 'enabled'
    replicaCount: workshopConfig.aiSearch.replicaCount
    semanticSearch: workshopConfig.aiSearch.semanticSearch
  }
  tags: tags
}

// ---------------------------------------------------------------------------
// Container Registry + Container Apps environment
// Used later in the workshop to host the MCP servers and the chat app.
// ---------------------------------------------------------------------------

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = if (workshopConfig.features.enableContainerApps) {
  name: registryName
  location: workshopConfig.primaryLocation
  sku: {
    name: workshopConfig.containerRegistry.sku
  }
  properties: {
    // Key-based auth: the admin username/password is enabled so the workshop
    // apps can pull/push images without a managed identity.
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

resource managedEnv 'Microsoft.App/managedEnvironments@2024-03-01' = if (workshopConfig.features.enableContainerApps) {
  name: managedEnvName
  location: workshopConfig.primaryLocation
  properties: {
    // Keyless logging: route app logs to Azure Monitor instead of using the
    // Log Analytics shared key. Avoids any listKeys()/shared-key dependency.
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
    workloadProfiles: workshopConfig.containerApps.workloadProfiles
  }
  tags: tags
}

// Route Container Apps console/system logs to Log Analytics with a diagnostic
// setting. This uses the workspace resource id (AAD-backed) — no shared key.
resource managedEnvDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (workshopConfig.features.enableContainerApps) {
  name: 'send-to-log-analytics'
  scope: managedEnv
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Azure AI Foundry — single stack (account + project + model deployments) in
// primaryLocation.
// ---------------------------------------------------------------------------
module foundry './foundry.bicep' = if (workshopConfig.features.enableAiFoundry) {
  name: 'foundry'
  params: {
    accountName: take('aif-${basePrefix}${unique}', 24)
    projectName: take('proj-${basePrefix}${unique}', 24)
    location: workshopConfig.aiFoundry.location
    sku: workshopConfig.aiFoundry.sku
    deployments: workshopConfig.aiFoundry.deployments
    tags: tags
  }
}

// Service-to-service auth uses keys / connection settings (no managed
// identities). Participant and service-principal RBAC is granted separately in
// Part C / Part D so it is configurable and reviewable on its own.

// ---------------------------------------------------------------------------
// Azure Cosmos DB for NoSQL — `zava` database + workshop containers.
// Containers are pre-created so the data-load step only has to upsert items,
// and so participants can be granted item-level (read/write) access without
// the ability to create, delete, or scale containers.
// ---------------------------------------------------------------------------
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = if (workshopConfig.features.enableCosmosDb) {
  name: cosmosName
  location: workshopConfig.primaryLocation
  kind: 'GlobalDocumentDB'
  properties: {
    capabilities: [
      {
        name: 'EnableNoSQLVectorSearch'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        failoverPriority: 0
        isZoneRedundant: false
        locationName: workshopConfig.primaryLocation
      }
    ]
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

resource cosmosSqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = if (workshopConfig.features.enableCosmosDb) {
  name: workshopConfig.cosmosDb.databaseName
  parent: cosmos
  properties: {
    resource: {
      id: workshopConfig.cosmosDb.databaseName
    }
  }
}

resource cosmosContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = [for container in workshopConfig.cosmosDb.containers: if (workshopConfig.features.enableCosmosDb) {
  name: container.name
  parent: cosmosSqlDb
  properties: {
    options: {
      throughput: container.throughput
    }
    resource: {
      id: container.name
      partitionKey: {
        kind: 'Hash'
        paths: [
          container.partitionKey
        ]
      }
    }
  }
}]

// ---------------------------------------------------------------------------
// Outputs — consumed by scripts/deploy.ps1 and scripts/load-data.ps1 to build
// the workshop `.env`, and by scripts/grant-access.ps1 for RBAC.
// ---------------------------------------------------------------------------
output resourceNames object = {
  aiFoundry: workshopConfig.features.enableAiFoundry ? foundry!.outputs.accountName : ''
  aiProject: workshopConfig.features.enableAiFoundry ? foundry!.outputs.projectName : ''
  aiSearch: workshopConfig.features.enableAiSearch ? search.name : ''
  appInsights: workshopConfig.features.enableContainerApps ? appInsights.name : ''
  containerAppsEnvironment: workshopConfig.features.enableContainerApps ? managedEnv.name : ''
  containerRegistry: workshopConfig.features.enableContainerApps ? registry.name : ''
  cosmosDb: workshopConfig.features.enableCosmosDb ? cosmos.name : ''
  logAnalytics: workshopConfig.features.enableContainerApps ? logAnalytics.name : ''
}

output endpoints object = {
  aiFoundryEndpoint: workshopConfig.features.enableAiFoundry ? foundry!.outputs.accountEndpoint : ''
  aiProjectEndpoint: workshopConfig.features.enableAiFoundry ? foundry!.outputs.projectEndpoint : ''
  aiProjectResourceId: workshopConfig.features.enableAiFoundry ? foundry!.outputs.projectId : ''
  appInsightsConnectionString: workshopConfig.features.enableContainerApps ? appInsights.properties.ConnectionString : ''
  cosmosEndpoint: workshopConfig.features.enableCosmosDb ? cosmos.properties.documentEndpoint : ''
  searchEndpoint: workshopConfig.features.enableAiSearch ? 'https://${search.name}.search.windows.net' : ''
}

output workshopSettings object = {
  modelDeployment: workshopConfig.aiFoundry.chatDeploymentName
  embeddingDeployment: workshopConfig.aiFoundry.embeddingDeploymentName
  cosmosDatabase: workshopConfig.cosmosDb.databaseName
  cosmosSalesContainer: workshopConfig.cosmosDb.salesContainerName
  cosmosInventoryContainer: workshopConfig.cosmosDb.inventoryContainerName
  cosmosMarketingContainer: workshopConfig.cosmosDb.marketingContainerName
  acaEnvironment: workshopConfig.features.enableContainerApps ? managedEnvName : ''
  acrName: workshopConfig.features.enableContainerApps ? registryName : ''
}
