// ===========================================================================
// PepsiCo × Microsoft Workshop — Day 2 slim user-access (Pradipta).
// ---------------------------------------------------------------------------
// Grants workshop participants the ONE Azure RBAC role we can assign for
// Day 2: Cognitive Services User on Sandeep's existing Azure OpenAI account
// (used by Lab 03 to call text-embedding-3-small + chat).
//
// Fabric, Azure SQL, and Purview access are NOT Azure RBAC and are handled
// by ./scripts/grant-user-access-day2.ps1 (Fabric portal + Purview Studio +
// T-SQL CREATE USER). See that script for the full sequence.
// ===========================================================================

targetScope = 'resourceGroup'

@description('Workshop participants: people or Entra groups. Must already exist.')
param workshopUsers array

@description('Name of the existing Azure OpenAI account (Sandeep\'s Day 1 AOAI) in this resource group. Leave blank to skip the AOAI grant.')
param sandeepAzureOpenAIName string = ''

// ---------------------------------------------------------------------------
// Built-in role IDs
// ---------------------------------------------------------------------------
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

// ---------------------------------------------------------------------------
// Existing AOAI account (must be in this resource group)
// ---------------------------------------------------------------------------
resource sandeepAOAI 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = if (!empty(sandeepAzureOpenAIName)) {
  name: empty(sandeepAzureOpenAIName) ? 'placeholder' : sandeepAzureOpenAIName
}

// ---------------------------------------------------------------------------
// Cognitive Services User on Sandeep's AOAI for every workshop user
// ---------------------------------------------------------------------------
resource aoaiRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: if (!empty(sandeepAzureOpenAIName)) {
  name: guid(sandeepAOAI!.id, user.principalId, cognitiveServicesUserRoleId)
  scope: sandeepAOAI
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: user.principalId
    principalType: user.?principalType ?? 'User'
  }
}]

output assignedRoles object = {
  azureOpenAI: empty(sandeepAzureOpenAIName) ? 'skipped (no Sandeep AOAI provided)' : 'Cognitive Services User'
  fabric: 'manual — assign in Fabric admin portal'
  azureSQL: 'manual — T-SQL CREATE USER FROM EXTERNAL PROVIDER (run setup-sql-vector.sql)'
  purview: 'manual — Purview Studio → Collection role assignments → Data Reader'
}
output userCount int = length(workshopUsers)
