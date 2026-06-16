// ---------------------------------------------------------------------------
// One Azure AI Foundry stack: account + project + model deployments.
// Invoked once per region by core-resources.bicep so the workshop can run a
// primary stack plus a secondary stack (different region) for quota overflow.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Foundry (Cognitive Services AIServices) account name. Globally unique.')
param accountName string

@description('Foundry project name (child of the account).')
param projectName string

@description('Azure region for this Foundry stack.')
param location string

@description('Account SKU, e.g. S0.')
param sku string

@description('Model deployments to create on this account.')
param deployments array

@description('Tags to apply.')
param tags object

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: accountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: sku
  }
  kind: 'AIServices'
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    // Entra-only: API keys are rejected.
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
  name: projectName
  parent: aiFoundry
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
  tags: tags
}

// Model deployments must be created one at a time per account: the Cognitive
// Services control plane serializes operations on the parent account, so
// parallel creation fails with RequestConflict. @batchSize(1) deploys them
// sequentially.
@batchSize(1)
resource aiDeployments 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = [for deployment in deployments: {
  name: deployment.name
  parent: aiFoundry
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

output accountName string = aiFoundry.name
output accountPrincipalId string = aiFoundry.identity.principalId
output accountEndpoint string = aiFoundry.properties.endpoint
output projectName string = aiProject.name
output projectId string = aiProject.id
output projectPrincipalId string = aiProject.identity.principalId
output projectEndpoint string = 'https://${accountName}.services.ai.azure.com/api/projects/${projectName}'
