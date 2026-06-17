// ─────────────────────────────────────────────────────────────────────────────
// Azure Database for PostgreSQL (Flexible Server) with pgvector extension
// Lab 03 — Vector search with cosine similarity
// ─────────────────────────────────────────────────────────────────────────────

@description('Globally unique name prefix for the PostgreSQL server')
param serverName string

@description('Azure region')
param location string = resourceGroup().location

@description('PostgreSQL administrator username')
param administratorLogin string

@description('PostgreSQL administrator password')
@secure()
param administratorPassword string

@description('Database name for workshop vector data')
param databaseName string

@description('PostgreSQL version')
param postgresVersion string = '16'

@description('SKU name (Standard_D2ds_v4 recommended for dev/test)')
param skuName string = 'Standard_D2ds_v4'

@description('Storage size in GB')
param storageSizeGB int = 32

@description('Resource tags')
param tags object = {}

// ─────────────────────────────────────────────────────────────────────────────
// PostgreSQL Flexible Server
// ─────────────────────────────────────────────────────────────────────────────

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: 'GeneralPurpose'
  }
  properties: {
    version: postgresVersion
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
      tenantId: subscription().tenantId
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Firewall rule: Allow Azure services
// ─────────────────────────────────────────────────────────────────────────────

resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuration: Enable pgvector extension
// ─────────────────────────────────────────────────────────────────────────────

resource pgvectorConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-03-01-preview' = {
  parent: postgresServer
  name: 'azure.extensions'
  properties: {
    value: 'VECTOR'
    source: 'user-override'
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Database
// ─────────────────────────────────────────────────────────────────────────────

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-03-01-preview' = {
  parent: postgresServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outputs
// ─────────────────────────────────────────────────────────────────────────────

output postgresServerId string = postgresServer.id
output postgresServerName string = postgresServer.name
output postgresDatabaseName string = database.name
output postgresConnectionString string = 'postgresql://${administratorLogin}@${serverName}:***@${serverName}.postgres.database.azure.com:5432/${databaseName}?sslmode=require'
output postgresEndpoint string = '${serverName}.postgres.database.azure.com'
