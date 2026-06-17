// ---------------------------------------------------------------------------
// Azure SQL Database with VECTOR type support.
// Used by Lab 03 (vector search on product descriptions).
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('SQL server name (globally unique).')
param serverName string

@description('Database name.')
param databaseName string

@description('Azure region.')
param location string

@description('UPN of the Entra admin for the SQL server.')
param aadAdminLogin string

@description('Object ID of the Entra admin.')
param aadAdminObjectId string

@description('Tenant ID for the Entra admin.')
param tenantId string

@description('Tags to apply.')
param tags object

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: aadAdminLogin
      sid: aadAdminObjectId
      tenantId: tenantId
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    version: '12.0'
  }
  tags: tags
}

// Allow Azure services to access (needed for AML, Fabric, notebooks)
resource firewallAllowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  name: 'AllowAzureServices'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  name: databaseName
  parent: sqlServer
  location: location
  sku: {
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
    autoPauseDelay: 60
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368 // 32 GB
    minCapacity: json('0.5')
    zoneRedundant: false
  }
  tags: tags
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = database.name
