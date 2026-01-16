// Extended example showing how to provide actual values for different environments
// This demonstrates a more complete pipeline integration

@description('The name of the environment')
param environmentName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Key Vault name')
param keyVaultName string

@description('App Configuration name')
param appConfigName string

// Environment-specific values would come from Azure DevOps Library or Key Vault references
@secure()
param databasePassword string

@secure()
param azureStorageAccountKey string

@secure()
param externalApiKey string

param databaseHost string
param databaseName string
param azureStorageAccountName string

// Load the generated metadata
var configMetadata = loadJsonContent('../expected-output.json')

// Helper function to get value for a specific key
// In real scenarios, this would be more sophisticated, reading from various sources
var configValues = {
  'Database:Host': databaseHost
  'Database:Port': '5432'
  'Database:DatabaseName': databaseName
  'Database:Username': 'dbadmin'
  'Database:TimeoutSeconds': '30'
  'Azure:StorageAccountName': azureStorageAccountName
  'Azure:ContainerName': 'uploads'
  'Azure:EnableApplicationInsights': 'true'
  'ExternalApi:BaseUrl': 'https://api.example.com'
  'ExternalApi:TimeoutSeconds': '60'
  'ExternalApi:MaxRetries': '3'
}

var secretValues = {
  'Database:Password': databasePassword
  'Database:SslCertificate': '' // Optional, can be empty
  'Azure:StorageAccountKey': azureStorageAccountKey
  'Azure:ApplicationInsightsKey': '' // Optional
  'ExternalApi:ApiKey': externalApiKey
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' existing = {
  name: appConfigName
}

// Provision secrets with actual values
resource secrets 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = [for entry in configMetadata.secretEntries: {
  parent: keyVault
  name: replace(entry.key, ':', '-')
  properties: {
    value: secretValues[entry.key]
    contentType: entry.description
  }
}]

// Provision config with actual values
resource configEntries 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = [for entry in configMetadata.configEntries: {
  parent: appConfig
  name: entry.key
  properties: {
    value: contains(configValues, entry.key) ? configValues[entry.key] : (contains(entry, 'defaultValue') ? entry.defaultValue : '')
    contentType: 'text/plain'
    tags: {
      environment: environmentName
      required: string(entry.required)
    }
  }
}]

// Also create Key Vault references in App Configuration for secrets
resource secretReferences 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = [for entry in configMetadata.secretEntries: {
  parent: appConfig
  name: entry.key
  properties: {
    value: '{"uri":"${keyVault.properties.vaultUri}secrets/${replace(entry.key, ':', '-')}"}'
    contentType: 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'
    tags: {
      environment: environmentName
      required: string(entry.required)
    }
  }
}]

output provisionedItemsCount int = length(configMetadata.configEntries) + length(configMetadata.secretEntries)
