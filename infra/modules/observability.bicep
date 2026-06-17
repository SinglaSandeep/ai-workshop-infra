// ---------------------------------------------------------------------------
// Application Insights + Log Analytics for AML and general telemetry.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Application Insights name.')
param appInsightsName string

@description('Log Analytics workspace name.')
param logAnalyticsName string

@description('Azure region.')
param location string

@description('Log retention in days.')
param retentionInDays int = 30

@description('Tags to apply.')
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
  tags: tags
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
  tags: tags
}

output appInsightsName string = appInsights.name
output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsName string = logAnalytics.name
output logAnalyticsId string = logAnalytics.id
