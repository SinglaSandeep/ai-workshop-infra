// ---------------------------------------------------------------------------
// Azure OpenAI account + model deployments for the data workshop.
// Used by Lab 03 (embeddings) and the Fabric Data Agent (chat completions).
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Globally unique name for the Azure OpenAI account.')
param accountName string

@description('Azure region.')
param location string

@description('Model deployments to create.')
param deployments array

@description('Tags to apply.')
param tags object

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: accountName
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  tags: tags
}

@batchSize(1)
resource modelDeployments 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for deployment in deployments: {
  name: deployment.name
  parent: openai
  sku: {
    name: deployment.skuName
    capacity: deployment.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: deployment.model
      version: deployment.version
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}]

output accountName string = openai.name
output endpoint string = openai.properties.endpoint
output principalId string = openai.identity.principalId
