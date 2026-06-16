targetScope = 'resourceGroup'

// ===========================================================================
// Part C — Resource (service-to-service) access.
//
// Grants the workshop's own services the permissions they need to call each
// other at runtime, using managed identities (no keys). Every grant is
// switchable and its role level is configurable in resource-access.parameters.json.
// ===========================================================================

@description('Config controlling each service-to-service grant and its role level. See resource-access.parameters.json.')
param resourceGrants object

@description('Name of the Azure AI Search service (from deployment outputs).')
param searchServiceName string = ''

@description('Name of the Azure Container Registry (from deployment outputs).')
param containerRegistryName string = ''

@description('Name of the Cosmos DB account (from deployment outputs).')
param cosmosAccountName string = ''

@description('Primary Foundry PROJECT managed-identity principal id (from deployment outputs).')
param foundryPrimaryProjectPrincipalId string = ''

@description('Secondary Foundry PROJECT managed-identity principal id (optional).')
param foundrySecondaryProjectPrincipalId string = ''

@description('Primary Foundry ACCOUNT managed-identity principal id (from deployment outputs).')
param foundryPrimaryAccountPrincipalId string = ''

@description('Secondary Foundry ACCOUNT managed-identity principal id (optional).')
param foundrySecondaryAccountPrincipalId string = ''

@description('Container Apps workload (user-assigned) managed-identity principal id (from deployment outputs).')
param containerAppsWorkloadPrincipalId string = ''

// ---------------------------------------------------------------------------
// Existing resources (created by Part A).
// ---------------------------------------------------------------------------
resource search 'Microsoft.Search/searchServices@2025-05-01' existing = if (!empty(searchServiceName)) {
  name: searchServiceName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (!empty(containerRegistryName)) {
  name: containerRegistryName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = if (!empty(cosmosAccountName)) {
  name: cosmosAccountName
}

// Collapse the optional secondary principals out so the loops only act on the
// identities that actually exist.
var foundryProjectPrincipalIds = filter([
  foundryPrimaryProjectPrincipalId
  foundrySecondaryProjectPrincipalId
], p => !empty(p))

var foundryAccountPrincipalIds = filter([
  foundryPrimaryAccountPrincipalId
  foundrySecondaryAccountPrincipalId
], p => !empty(p))

// ---------------------------------------------------------------------------
// (1) Foundry PROJECT identity -> AI Search.
//     Lets the Foundry IQ knowledge base index the data into AI Search and the
//     hosted marketing agent query it (over MCP).
// ---------------------------------------------------------------------------
resource foundryToSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in foundryProjectPrincipalIds: if (resourceGrants.foundryProjectToSearch.enabled && !empty(searchServiceName)) {
  name: guid(search.id, principalId, resourceGrants.foundryProjectToSearch.roleDefinitionId)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', resourceGrants.foundryProjectToSearch.roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}]

// ---------------------------------------------------------------------------
// (2) Foundry ACCOUNT identity -> Container Registry.
//     Lets hosted agents pull their container images.
// ---------------------------------------------------------------------------
resource foundryToAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in foundryAccountPrincipalIds: if (resourceGrants.foundryAccountToAcr.enabled && !empty(containerRegistryName)) {
  name: guid(registry.id, principalId, resourceGrants.foundryAccountToAcr.roleDefinitionId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', resourceGrants.foundryAccountToAcr.roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}]

// ---------------------------------------------------------------------------
// (3) Container Apps workload identity -> Container Registry.
//     Lets the MCP servers and chat app pull their images.
// ---------------------------------------------------------------------------
resource workloadToAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (resourceGrants.containerAppsToAcr.enabled && !empty(containerRegistryName) && !empty(containerAppsWorkloadPrincipalId)) {
  name: guid(registry.id, containerAppsWorkloadPrincipalId, resourceGrants.containerAppsToAcr.roleDefinitionId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', resourceGrants.containerAppsToAcr.roleDefinitionId)
    principalId: containerAppsWorkloadPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// (4) Container Apps workload identity -> Cosmos DB (data plane).
//     Lets the MCP servers read/write the workshop data. Uses a Cosmos SQL
//     role assignment (default: built-in Data Contributor).
// ---------------------------------------------------------------------------
resource workloadToCosmos 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = if (resourceGrants.containerAppsToCosmos.enabled && !empty(cosmosAccountName) && !empty(containerAppsWorkloadPrincipalId)) {
  parent: cosmos
  name: guid(cosmos.id, containerAppsWorkloadPrincipalId, resourceGrants.containerAppsToCosmos.cosmosSqlRoleDefinitionId)
  properties: {
    principalId: containerAppsWorkloadPrincipalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${resourceGrants.containerAppsToCosmos.cosmosSqlRoleDefinitionId}'
    scope: cosmos.id
  }
}

output summary object = {
  foundryProjectToSearch: resourceGrants.foundryProjectToSearch.enabled ? '${resourceGrants.foundryProjectToSearch.roleName} x ${length(foundryProjectPrincipalIds)}' : 'disabled'
  foundryAccountToAcr: resourceGrants.foundryAccountToAcr.enabled ? '${resourceGrants.foundryAccountToAcr.roleName} x ${length(foundryAccountPrincipalIds)}' : 'disabled'
  containerAppsToAcr: (resourceGrants.containerAppsToAcr.enabled && !empty(containerAppsWorkloadPrincipalId)) ? resourceGrants.containerAppsToAcr.roleName : 'disabled'
  containerAppsToCosmos: (resourceGrants.containerAppsToCosmos.enabled && !empty(containerAppsWorkloadPrincipalId)) ? resourceGrants.containerAppsToCosmos.roleName : 'disabled'
}
