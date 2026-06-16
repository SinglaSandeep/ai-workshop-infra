targetScope = 'resourceGroup'

@description('Workshop users (people or Entra groups) that receive participant access. Principal IDs must already exist in Entra ID.')
param workshopUsers array

@description('Configurable access levels for participants (roles + Cosmos data actions). See user-access.parameters.json.')
param userAccess object

@description('Name of the AI Foundry account in this resource group (from deployment outputs).')
param aiFoundryName string = ''

@description('Name of the AI Foundry project in this resource group (from deployment outputs).')
param aiProjectName string = ''

@description('Name of the SECONDARY AI Foundry account (optional; empty when Foundry runs in one region).')
param aiFoundrySecondaryName string = ''

@description('Name of the SECONDARY AI Foundry project (optional; empty when Foundry runs in one region).')
param aiProjectSecondaryName string = ''

@description('Name of the Azure AI Search service in this resource group (from deployment outputs).')
param searchServiceName string = ''

@description('Name of the Cosmos DB account in this resource group (from deployment outputs).')
param cosmosAccountName string = ''

// --- Pradipta's Data Platform resources ---
@description('Name of the Azure OpenAI account (from deployment outputs).')
param openAiAccountName string = ''

@description('Name of the Azure ML workspace (from deployment outputs).')
param amlWorkspaceName string = ''

// ---------------------------------------------------------------------------
// Existing resources (created by the infra deployment).
// ---------------------------------------------------------------------------
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' existing = if (!empty(aiFoundryName)) {
  name: aiFoundryName
}

resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' existing = if (!empty(aiFoundryName) && !empty(aiProjectName)) {
  name: aiProjectName
  parent: aiFoundry
}

resource aiFoundrySecondary 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' existing = if (!empty(aiFoundrySecondaryName)) {
  name: aiFoundrySecondaryName
}

resource aiProjectSecondary 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' existing = if (!empty(aiFoundrySecondaryName) && !empty(aiProjectSecondaryName)) {
  name: aiProjectSecondaryName
  parent: aiFoundrySecondary
}

resource search 'Microsoft.Search/searchServices@2025-05-01' existing = if (!empty(searchServiceName)) {
  name: searchServiceName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = if (!empty(cosmosAccountName)) {
  name: cosmosAccountName
}

// ---------------------------------------------------------------------------
// Built-in role definitions (configurable in user-access.parameters.json).
//  - foundry: data-plane role for running/creating agents (default Foundry
//    User, formerly Azure AI User). No control-plane rights, so users cannot
//    create/delete deployments.
//  - search:  read-only query access (default Search Index Data Reader).
// ---------------------------------------------------------------------------
var azureAiUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', userAccess.foundry.roleDefinitionId)
var searchIndexDataReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', userAccess.search.roleDefinitionId)

// ---------------------------------------------------------------------------
// Custom Cosmos DB data-plane role. Default = read + write ITEMS only, which
// excludes container create / delete / replace (scale). The exact dataActions
// are configurable in user-access.parameters.json.
// ---------------------------------------------------------------------------
resource cosmosReadWriteItemsRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2024-11-15' = if (!empty(cosmosAccountName)) {
  parent: cosmos
  name: guid(cosmos.id, 'workshop-data-read-write-items')
  properties: {
    roleName: userAccess.cosmos.roleName
    type: 'CustomRole'
    assignableScopes: [
      cosmos.id
    ]
    permissions: [
      {
        dataActions: userAccess.cosmos.dataActions
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Assignments — one per workshop user/group.
// ---------------------------------------------------------------------------

// (b) Foundry: run + create agents, but no deployment management.
resource userFoundryAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(aiProjectName)) {
  name: guid(aiProject.id, user.objectId, 'workshop-user-azure-ai-user')
  scope: aiProject
  properties: {
    roleDefinitionId: azureAiUserRoleId
    principalId: user.objectId
    principalType: user.principalType
  }
}]

// (b) Foundry secondary region: same grant so users can fall back to it.
resource userFoundrySecondaryAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(aiProjectSecondaryName)) {
  name: guid(aiProjectSecondary.id, user.objectId, 'workshop-user-azure-ai-user-secondary')
  scope: aiProjectSecondary
  properties: {
    roleDefinitionId: azureAiUserRoleId
    principalId: user.objectId
    principalType: user.principalType
  }
}]

// (c) Search: read only.
resource userSearchAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(searchServiceName)) {
  name: guid(search.id, user.objectId, 'workshop-user-search-reader')
  scope: search
  properties: {
    roleDefinitionId: searchIndexDataReaderRoleId
    principalId: user.objectId
    principalType: user.principalType
  }
}]

// (a) Cosmos: read + write items, no create/delete/scale.
resource userCosmosAssignments 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = [for user in workshopUsers: if (!empty(cosmosAccountName)) {
  parent: cosmos
  name: guid(cosmos.id, user.objectId, 'workshop-user-cosmos-read-write-items')
  properties: {
    principalId: user.objectId
    roleDefinitionId: cosmosReadWriteItemsRole.id
    scope: cosmos.id
  }
}]

// ---------------------------------------------------------------------------
// Pradipta's Data Platform — participant grants
// ---------------------------------------------------------------------------

// (d) Azure OpenAI: Cognitive Services User (call embeddings + chat, no deploy).
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (!empty(openAiAccountName)) {
  name: openAiAccountName
}

var cogServicesUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')

resource userOpenAiAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(openAiAccountName)) {
  name: guid(openAiAccount.id, user.objectId, 'workshop-user-cog-services-user')
  scope: openAiAccount
  properties: {
    roleDefinitionId: cogServicesUserRoleId
    principalId: user.objectId
    principalType: user.principalType
  }
}]

// (e) Azure ML: AzureML Data Scientist (run experiments, deploy endpoints).
resource amlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' existing = if (!empty(amlWorkspaceName)) {
  name: amlWorkspaceName
}

var amlDataScientistRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f6c7c914-8db3-469d-8ca1-694a8f32e121')

resource userAmlAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(amlWorkspaceName)) {
  name: guid(amlWorkspace.id, user.objectId, 'workshop-user-aml-data-scientist')
  scope: amlWorkspace
  properties: {
    roleDefinitionId: amlDataScientistRoleId
    principalId: user.objectId
    principalType: user.principalType
  }
}]

output summary object = {
  usersGranted: length(workshopUsers)
  cosmosRoleName: empty(cosmosAccountName) ? '' : userAccess.cosmos.roleName
  openAiAccess: !empty(openAiAccountName) ? 'Cognitive Services User' : 'disabled'
  amlAccess: !empty(amlWorkspaceName) ? 'AzureML Data Scientist' : 'disabled'
}
