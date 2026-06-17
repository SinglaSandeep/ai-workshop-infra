targetScope = 'resourceGroup'

@description('Workshop users (people or Entra groups) that receive participant access. Principal IDs must already exist in Entra ID.')
param workshopUsers array

@description('Configurable access levels for participants. See user-access-day2.parameters.json.')
param userAccess object

@description('Name of the Azure OpenAI account (from deployment outputs).')
param azureOpenAIName string = ''

@description('Name of the Azure ML workspace (from deployment outputs).')
param azureMLWorkspaceName string = ''

@description('Name of the storage account for Lakehouse data (from deployment outputs).')
param storageAccountName string = ''

@description('Name of the PostgreSQL server (from deployment outputs).')
param postgresServerName string = ''

@description('Name of the Key Vault (from deployment outputs).')
param keyVaultName string = ''

// ---------------------------------------------------------------------------
// Existing Day 2 resources (created by the infra deployment).
// ---------------------------------------------------------------------------
resource azureOpenAI 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = if (!empty(azureOpenAIName)) {
  name: azureOpenAIName
}

resource azureML 'Microsoft.MachineLearningServices/workspaces@2024-04-01' existing = if (!empty(azureMLWorkspaceName)) {
  name: azureMLWorkspaceName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(storageAccountName)) {
  name: storageAccountName
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' existing = if (!empty(postgresServerName)) {
  name: postgresServerName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

// ---------------------------------------------------------------------------
// Azure RBAC built-in role IDs (globally consistent across all subscriptions).
// ---------------------------------------------------------------------------
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var azureMLDataScientistRoleId = 'f6c7c914-8db3-469d-8ca1-694a8f32e121'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// ---------------------------------------------------------------------------
// Azure OpenAI - Cognitive Services User
// Grants: inference (chat completions, embeddings), no model deployment.
// ---------------------------------------------------------------------------
resource openAIRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(azureOpenAIName) && userAccess.enableAzureOpenAI) {
  name: guid(azureOpenAI.id, user.principalId, cognitiveServicesUserRoleId)
  scope: azureOpenAI
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: user.principalId
    principalType: contains(user, 'principalType') ? user.principalType : 'User'
  }
}]

// ---------------------------------------------------------------------------
// Azure ML - AzureML Data Scientist
// Grants: run experiments, submit jobs, read datasets, no workspace config changes.
// ---------------------------------------------------------------------------
resource amlRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(azureMLWorkspaceName) && userAccess.enableAzureML) {
  name: guid(azureML.id, user.principalId, azureMLDataScientistRoleId)
  scope: azureML
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureMLDataScientistRoleId)
    principalId: user.principalId
    principalType: contains(user, 'principalType') ? user.principalType : 'User'
  }
}]

// ---------------------------------------------------------------------------
// Storage Account (ADLS Gen2) - Storage Blob Data Contributor
// Grants: read, write, delete blobs/containers. For Lakehouse data uploads.
// ---------------------------------------------------------------------------
resource storageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(storageAccountName) && userAccess.enableStorage) {
  name: guid(storage.id, user.principalId, storageBlobDataContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: user.principalId
    principalType: contains(user, 'principalType') ? user.principalType : 'User'
  }
}]

// ---------------------------------------------------------------------------
// Key Vault - Key Vault Secrets User
// Grants: read secrets (connection strings, API keys). No write/delete.
// ---------------------------------------------------------------------------
resource keyVaultRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(keyVaultName) && userAccess.enableKeyVault) {
  name: guid(keyVault.id, user.principalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: user.principalId
    principalType: contains(user, 'principalType') ? user.principalType : 'User'
  }
}]

// ---------------------------------------------------------------------------
// PostgreSQL - Custom role for database access
// Note: RBAC for PostgreSQL data plane requires Azure AD authentication to be
// configured on the server. Participants will get "reader" role on the server
// resource, then must be granted database permissions via SQL GRANT commands.
// ---------------------------------------------------------------------------
var postgresReaderRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader role

resource postgresRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(postgresServerName) && userAccess.enablePostgreSQL) {
  name: guid(postgres.id, user.principalId, postgresReaderRoleId)
  scope: postgres
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', postgresReaderRoleId)
    principalId: user.principalId
    principalType: contains(user, 'principalType') ? user.principalType : 'User'
  }
}]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output assignedRoles object = {
  azureOpenAI: userAccess.enableAzureOpenAI ? 'Cognitive Services User' : 'disabled'
  azureML: userAccess.enableAzureML ? 'AzureML Data Scientist' : 'disabled'
  storage: userAccess.enableStorage ? 'Storage Blob Data Contributor' : 'disabled'
  keyVault: userAccess.enableKeyVault ? 'Key Vault Secrets User' : 'disabled'
  postgres: userAccess.enablePostgreSQL ? 'Reader (data plane via SQL GRANT)' : 'disabled'
}

output userCount int = length(workshopUsers)
