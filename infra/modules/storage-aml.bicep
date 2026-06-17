// ---------------------------------------------------------------------------
// Azure Storage Account for AML workspace (WITHOUT HNS - AML requirement).
// Separate from the ADLS Gen2 storage which HAS HNS enabled.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Storage account name (3-24 lowercase alphanumeric).')
param storageAccountName string

@description('Azure region.')
param location string

@description('Tags to apply.')
param tags object

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    isHnsEnabled: false // AML workspace requires HNS disabled
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

output storageAccountName string = storage.name
output storageAccountId string = storage.id
output primaryBlobEndpoint string = storage.properties.primaryEndpoints.blob
