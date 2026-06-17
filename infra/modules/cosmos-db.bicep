// ─────────────────────────────────────────────────────────────────────────────
// Azure Cosmos DB with NoSQL Vector Search
// LAB 03 - Vector search alternative to Azure SQL
// ─────────────────────────────────────────────────────────────────────────────

@description('Cosmos DB account name')
param accountName string

@description('Azure region')
param location string = resourceGroup().location

@description('Enable vector search capability')
param enableVectorSearch bool = true

@description('Resource tags')
param tags object = {}

// ─────────────────────────────────────────────────────────────────────────────
// Cosmos DB Account
// ─────────────────────────────────────────────────────────────────────────────

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: enableVectorSearch ? [
      {
        name: 'EnableNoSQLVectorSearch'
      }
    ] : []
    disableLocalAuth: false  // Allow key-based access for workshop simplicity
    publicNetworkAccess: 'Enabled'
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outputs
// ─────────────────────────────────────────────────────────────────────────────

output accountName string = cosmosAccount.name
output accountId string = cosmosAccount.id
output endpoint string = cosmosAccount.properties.documentEndpoint
output primaryKey string = cosmosAccount.listKeys().primaryMasterKey
