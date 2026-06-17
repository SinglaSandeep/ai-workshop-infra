// ---------------------------------------------------------------------------
// Microsoft Fabric capacity (F SKU).
// Used for Labs 01 (Lakehouse), 02 (RTI), and Governance demo.
// NOTE: Fabric capacities are often provisioned via the Fabric admin portal.
// This module is provided for full automation; skip if capacity exists.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Fabric capacity name.')
param capacityName string

@description('Azure region.')
param location string

@description('Fabric capacity SKU (F2, F4, F8, etc.).')
param skuName string = 'F2'

@description('Object ID of the capacity admin (Entra user). NOTE: Microsoft.Fabric/capacities accepts either an Entra Object ID or a UPN (email-style) string here. Some tenants accept only one or the other — try UPN if Object ID returns "All provided principals must be existing".')
param adminObjectId string

@description('Tags to apply.')
param tags object

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  sku: {
    name: skuName
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: [
        adminObjectId
      ]
    }
  }
  tags: tags
}

output capacityName string = fabricCapacity.name
output capacityId string = fabricCapacity.id
output state string = fabricCapacity.properties.state
