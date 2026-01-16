// Main infrastructure deployment that uses generated configuration metadata

@description('The name of the environment (dev, staging, prod)')
param environmentName string

@description('The location for all resources')
param location string = resourceGroup().location

@description('The name of the Key Vault')
param keyVaultName string

@description('The name of the App Configuration store')
param appConfigName string

@description('Path to the generated configuration metadata JSON file')
param configMetadataPath string = '../expected-output.json'

// Load the generated metadata from the build output
var configMetadata = loadJsonContent(configMetadataPath)

// Create or reference Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// Create or reference App Configuration
resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' = {
  name: appConfigName
  location: location
  sku: {
    name: 'standard'
  }
  properties: {
    encryption: {}
    disableLocalAuth: false
  }
}

// Provision all secrets in Key Vault
// Note: Actual secret values should come from parameter files or Azure DevOps variables
resource secrets 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = [for entry in configMetadata.secretEntries: {
  parent: keyVault
  name: replace(entry.key, ':', '-') // Key Vault doesn't allow colons in names
  properties: {
    value: '' // Placeholder - actual values provided via pipeline variables
    contentType: entry.description
  }
}]

// Provision all config entries in App Configuration
// For entries with defaults, use the default value; otherwise use empty string as placeholder
resource configValues 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = [for entry in configMetadata.configEntries: {
  parent: appConfig
  name: entry.key
  properties: {
    value: contains(entry, 'defaultValue') ? entry.defaultValue : ''
    contentType: 'application/json'
    tags: {
      required: string(entry.required)
      description: contains(entry, 'description') ? entry.description : ''
      environment: environmentName
    }
  }
}]

// Output the Key Vault and App Configuration details
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output appConfigId string = appConfig.id
output appConfigEndpoint string = appConfig.properties.endpoint

// Output summary of what was created
output summary object = {
  configEntriesCount: length(configMetadata.configEntries)
  secretEntriesCount: length(configMetadata.secretEntries)
  totalItemsProvisioned: length(configMetadata.configEntries) + length(configMetadata.secretEntries)
}
