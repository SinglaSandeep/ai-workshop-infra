// ---------------------------------------------------------------------------
// Microsoft Purview account.
// Used for Day 2 governance demo (Purview + Fabric IQ walkthrough).
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Purview account name (3-63 chars, globally unique within the region).')
param purviewAccountName string

@description('Azure region. Purview is available in a curated set of regions; check docs if your primary region is not supported.')
param location string

@description('Object ID of the Entra principal that should be the Purview Data Curator/Reader at deploy time.')
param adminObjectId string

@description('Capacity units. 1 = 4 vCores. Stay at 1 for the workshop.')
param capacityUnits int = 1

@description('Tags to apply.')
param tags object

resource purview 'Microsoft.Purview/accounts@2024-04-01-preview' = {
  name: purviewAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Standard'
    capacity: capacityUnits
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    managedResourceGroupName: 'managed-${purviewAccountName}'
  }
}

// Grant the deploying admin "Purview Data Curator" via the catalog after deploy
// (data-plane role; cannot be assigned via ARM). Output the account name so the
// post-deploy script can do it.
output purviewAccountName string = purview.name
output purviewAtlasEndpoint string = purview.properties.endpoints.catalog
output purviewScanEndpoint string = purview.properties.endpoints.scan
output purviewPrincipalId string = purview.identity.principalId
output deployingAdminObjectId string = adminObjectId
