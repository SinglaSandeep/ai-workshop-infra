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
var workloadIdentityName = take('${basePrefix}-${unique}-app-id', 128)

// Foundry runs in one OR two regions. The first region is PRIMARY (feeds the
// workshop .env); the second is a secondary full stack for model-quota
// overflow / fallback. All other resources stay in primaryLocation.
var foundryRegions = workshopConfig.aiFoundry.locations

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
    // Entra-only: reject instrumentation-key / connection-string-key ingestion.
    DisableLocalAuth: true
  }
  tags: tags
}

// ---------------------------------------------------------------------------
// Azure AI Search (Foundry IQ knowledge base backing store)
// Entra-only. Admin/query API keys are disabled; the data-load operator and the
// Foundry project identity authenticate with AAD role assignments instead.
// ---------------------------------------------------------------------------
resource search 'Microsoft.Search/searchServices@2025-05-01' = if (workshopConfig.features.enableAiSearch) {
  name: searchName
  location: workshopConfig.primaryLocation
  sku: {
    name: workshopConfig.aiSearch.sku
  }
  properties: {
    disableLocalAuth: true
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

// Shared user-assigned identity for the Container Apps workload (MCP servers +
// chat app). It is created now so its access to Cosmos / ACR can be granted in
// Part C; the workshop apps attach this identity when they are deployed.
resource workloadIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (workshopConfig.features.enableContainerApps) {
  name: workloadIdentityName
  location: workshopConfig.primaryLocation
  tags: tags
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = if (workshopConfig.features.enableContainerApps) {
  name: registryName
  location: workshopConfig.primaryLocation
  sku: {
    name: workshopConfig.containerRegistry.sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Entra-only: the admin username/password is never enabled. Image pull/push
    // uses AAD (AcrPull / AcrPush) or the registry's managed identity.
    adminUserEnabled: false
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
// Azure AI Foundry — one stack per region in workshopConfig.aiFoundry.locations.
// Region 0 is primary (workshop .env); region 1 (if present) is the secondary
// quota-overflow stack. Each stack = account + project + the same deployments.
// ---------------------------------------------------------------------------
module foundry './foundry.bicep' = [for (region, i) in foundryRegions: if (workshopConfig.features.enableAiFoundry) {
  name: 'foundry-${i}'
  params: {
    accountName: take('aif-${basePrefix}${toLower(uniqueString(resourceGroup().id, region))}', 24)
    projectName: take('proj-${basePrefix}${toLower(uniqueString(resourceGroup().id, region))}', 24)
    location: region
    sku: workshopConfig.aiFoundry.sku
    deployments: workshopConfig.aiFoundry.deployments
    tags: tags
  }
}]

// Service-to-service RBAC (Foundry -> Search, Foundry -> ACR) is granted
// separately in Part C (infra/resource-access.bicep) so the level of access is
// configurable and reviewable on its own.

// ---------------------------------------------------------------------------
// Azure Cosmos DB for NoSQL — `zava` database + workshop containers.
// Containers are pre-created so the data-load step only has to upsert items,
// and so participants can be granted item-level (read/write) access without
// the ability to create, delete, or scale containers.
// ---------------------------------------------------------------------------
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = if (workshopConfig.features.enableCosmosDb) {
  name: cosmosName
  location: workshopConfig.primaryLocation
  identity: {
    type: 'SystemAssigned'
  }
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
    disableLocalAuth: true
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
  aiFoundry: workshopConfig.features.enableAiFoundry ? foundry[0]!.outputs.accountName : ''
  aiProject: workshopConfig.features.enableAiFoundry ? foundry[0]!.outputs.projectName : ''
  aiFoundrySecondary: (workshopConfig.features.enableAiFoundry && length(foundryRegions) > 1) ? foundry[1]!.outputs.accountName : ''
  aiProjectSecondary: (workshopConfig.features.enableAiFoundry && length(foundryRegions) > 1) ? foundry[1]!.outputs.projectName : ''
  aiSearch: workshopConfig.features.enableAiSearch ? search.name : ''
  appInsights: workshopConfig.features.enableContainerApps ? appInsights.name : ''
  containerAppsEnvironment: workshopConfig.features.enableContainerApps ? managedEnv.name : ''
  containerRegistry: workshopConfig.features.enableContainerApps ? registry.name : ''
  cosmosDb: workshopConfig.features.enableCosmosDb ? cosmos.name : ''
  logAnalytics: workshopConfig.features.enableContainerApps ? logAnalytics.name : ''
  workloadIdentity: workshopConfig.features.enableContainerApps ? workloadIdentity.name : ''
}

output endpoints object = {
  aiFoundryEndpoint: workshopConfig.features.enableAiFoundry ? foundry[0]!.outputs.accountEndpoint : ''
  aiProjectEndpoint: workshopConfig.features.enableAiFoundry ? foundry[0]!.outputs.projectEndpoint : ''
  aiProjectResourceId: workshopConfig.features.enableAiFoundry ? foundry[0]!.outputs.projectId : ''
  aiProjectEndpointSecondary: (workshopConfig.features.enableAiFoundry && length(foundryRegions) > 1) ? foundry[1]!.outputs.projectEndpoint : ''
  aiProjectResourceIdSecondary: (workshopConfig.features.enableAiFoundry && length(foundryRegions) > 1) ? foundry[1]!.outputs.projectId : ''
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
  workloadIdentityClientId: workshopConfig.features.enableContainerApps ? workloadIdentity.properties.clientId : ''
  workloadIdentityResourceId: workshopConfig.features.enableContainerApps ? workloadIdentity.id : ''
}

output managedIdentityPrincipals object = {
  aiFoundryPrincipalId: workshopConfig.features.enableAiFoundry ? foundry[0]!.outputs.accountPrincipalId : ''
  aiProjectPrincipalId: workshopConfig.features.enableAiFoundry ? foundry[0]!.outputs.projectPrincipalId : ''
  aiFoundrySecondaryPrincipalId: (workshopConfig.features.enableAiFoundry && length(foundryRegions) > 1) ? foundry[1]!.outputs.accountPrincipalId : ''
  aiProjectSecondaryPrincipalId: (workshopConfig.features.enableAiFoundry && length(foundryRegions) > 1) ? foundry[1]!.outputs.projectPrincipalId : ''
  containerRegistryPrincipalId: workshopConfig.features.enableContainerApps ? registry.identity.principalId : ''
  cosmosPrincipalId: workshopConfig.features.enableCosmosDb ? cosmos.identity.principalId : ''
  workloadIdentityPrincipalId: workshopConfig.features.enableContainerApps ? workloadIdentity.properties.principalId : ''
}
