// ---------------------------------------------------------------------------
// Azure Key Vault for storing workshop secrets (AOAI keys, SQL connection info,
// AML endpoint credentials).
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Key Vault name (3-24 alphanumeric + hyphens).')
param keyVaultName string

@description('Azure region.')
param location string

@description('Tenant ID.')
param tenantId string

@description('Object ID of the operator/admin who can manage secrets.')
param adminObjectId string

@description('Tags to apply.')
param tags object

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

// Grant the admin Key Vault Secrets Officer so they can set secrets
resource adminSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, adminObjectId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: adminObjectId
    principalType: 'User'
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
