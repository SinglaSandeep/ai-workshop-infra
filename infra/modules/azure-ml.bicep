// ---------------------------------------------------------------------------
// Azure Machine Learning workspace + compute cluster.
// Used by Lab 04 (train, deploy, wrap as agent tool).
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('AML workspace name.')
param workspaceName string

@description('Azure region.')
param location string

@description('Resource ID of the Storage Account for AML.')
param storageAccountId string

@description('Resource ID of the Key Vault for AML.')
param keyVaultId string

@description('Resource ID of Application Insights (optional).')
param appInsightsId string = ''

@description('Compute cluster name.')
param computeClusterName string = 'cpu-cluster'

@description('Compute VM size.')
param computeVmSize string = 'Standard_DS3_v2'

@description('Min nodes for compute cluster.')
param computeMinNodes int = 0

@description('Max nodes for compute cluster.')
param computeMaxNodes int = 2

@description('Tags to apply.')
param tags object

resource workspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: workspaceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    friendlyName: workspaceName
    keyVault: keyVaultId
    storageAccount: storageAccountId
    applicationInsights: !empty(appInsightsId) ? appInsightsId : null
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

resource compute 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  name: computeClusterName
  parent: workspace
  location: location
  properties: {
    computeType: 'AmlCompute'
    properties: {
      vmSize: computeVmSize
      scaleSettings: {
        minNodeCount: computeMinNodes
        maxNodeCount: computeMaxNodes
        nodeIdleTimeBeforeScaleDown: 'PT120S'
      }
      vmPriority: 'Dedicated'
    }
  }
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id
output principalId string = workspace.identity.principalId
