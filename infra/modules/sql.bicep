// ---------------------------------------------------------------------------
// Azure SQL Server + Database (Entra-only auth, VECTOR-capable).
// Used for Day 2 LAB 03 — vector search with the SQL VECTOR data type.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('SQL logical server name (must be globally unique, lowercase).')
param sqlServerName string

@description('SQL database name.')
param sqlDatabaseName string = 'vectordb'

@description('Azure region. Must be a region where the SQL VECTOR data type is available (e.g. eastus2, westus3, swedencentral).')
param location string

@description('UPN of the Microsoft Entra admin for the SQL server.')
param aadAdminLogin string

@description('Object ID of the Microsoft Entra admin for the SQL server.')
param aadAdminObjectId string

@description('SKU name for the database. Default GP serverless to keep cost low.')
param skuName string = 'GP_S_Gen5_2'

@description('Tier for the database SKU.')
param skuTier string = 'GeneralPurpose'

@description('Tags to apply.')
param tags object

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    // Entra-only auth — no SQL admin password.
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: aadAdminLogin
      sid: aadAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    autoPauseDelay: 60
    minCapacity: json('0.5')
    zoneRedundant: false
  }
}

// Allow Azure services (and resources inside the customer's Azure tenant) through.
// Customers can tighten this to specific IPs after deploy.
resource fwAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
