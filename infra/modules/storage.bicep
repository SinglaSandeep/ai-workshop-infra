// ---------------------------------------------------------------------------
// Azure Storage Account (ADLS Gen2) for AML artifacts and Lakehouse raw data.
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
    isHnsEnabled: true // ADLS Gen2
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

output storageAccountName string = storage.name
output storageAccountId string = storage.id
output primaryBlobEndpoint string = storage.properties.primaryEndpoints.blob
output primaryDfsEndpoint string = storage.properties.primaryEndpoints.dfs
