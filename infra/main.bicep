targetScope = 'resourceGroup'

@description('Central workshop configuration for all resources, regions, and SKUs.')
param workshopConfig object

module tagsModule './modules/tags.bicep' = {
  name: 'tagsModule'
  params: {
    workshopConfig: workshopConfig
  }
}

module core './modules/core-resources.bicep' = {
  name: 'coreResources'
  params: {
    workshopConfig: workshopConfig
    tags: tagsModule.outputs.tags
  }
}

output resourceNames object = core.outputs.resourceNames
output endpoints object = core.outputs.endpoints
output workshopSettings object = core.outputs.workshopSettings
output managedIdentityPrincipals object = core.outputs.managedIdentityPrincipals