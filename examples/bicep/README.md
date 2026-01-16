# Bicep Examples for Config Generators

This folder contains example Bicep templates showing how DevOps teams can use the generated `configuration-metadata.json` file to provision Azure infrastructure.

## Files

- **main.bicep**: Basic example that creates placeholders for all config entries and secrets
- **main.parameters.dev.json**: Sample parameter file for the dev environment
- **provision-with-values.bicep**: Advanced example showing how to provide actual values

## Usage

### Option 1: Basic Deployment (Placeholders)

This creates all the infrastructure with placeholder values:

```bash
az deployment group create \
  --resource-group my-rg \
  --template-file main.bicep \
  --parameters @main.parameters.dev.json
```

After deployment, you'd manually update the values or use Azure DevOps variable groups.

### Option 2: Full Deployment (With Values)

This provisions everything with actual values from your pipeline:

```bash
az deployment group create \
  --resource-group my-rg \
  --template-file provision-with-values.bicep \
  --parameters \
    environmentName=dev \
    keyVaultName=kv-myapp-dev-001 \
    appConfigName=appconfig-myapp-dev-001 \
    databasePassword="$DB_PASSWORD" \
    azureStorageAccountKey="$STORAGE_KEY" \
    externalApiKey="$API_KEY" \
    databaseHost="mydb.postgres.database.azure.com" \
    databaseName="myappdb" \
    azureStorageAccountName="mystorageaccount"
```

## Azure DevOps Integration

### Pipeline Example

```yaml
trigger:
  branches:
    include:
    - main

variables:
  - group: 'dev-secrets' # Variable group containing secrets

stages:
- stage: Build
  jobs:
  - job: BuildAndExtractConfig
    steps:
    - task: DotNetCoreCLI@2
      displayName: 'Build Application'
      inputs:
        command: 'build'
        projects: '**/*.csproj'
        configuration: 'Release'

    - task: CopyFiles@2
      displayName: 'Copy Configuration Metadata'
      inputs:
        SourceFolder: '$(Build.SourcesDirectory)'
        Contents: '**/obj/Generated/**/configuration-metadata.json'
        TargetFolder: '$(Build.ArtifactStagingDirectory)/config'
        flattenFolders: true

    - task: PublishBuildArtifacts@1
      displayName: 'Publish Artifacts'
      inputs:
        PathtoPublish: '$(Build.ArtifactStagingDirectory)'
        ArtifactName: 'drop'

- stage: DeployDev
  dependsOn: Build
  condition: succeeded()
  jobs:
  - deployment: DeployInfrastructure
    environment: 'development'
    strategy:
      runOnce:
        deploy:
          steps:
          - download: current
            artifact: drop

          - task: AzureCLI@2
            displayName: 'Deploy Infrastructure'
            inputs:
              azureSubscription: 'Azure-Subscription-Connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az deployment group create \
                  --resource-group $(resourceGroupName) \
                  --template-file $(Pipeline.Workspace)/drop/config/main.bicep \
                  --parameters \
                    environmentName=dev \
                    keyVaultName=$(keyVaultName) \
                    appConfigName=$(appConfigName) \
                    configMetadataPath=$(Pipeline.Workspace)/drop/config/configuration-metadata.json

          - task: AzureCLI@2
            displayName: 'Update Secret Values'
            inputs:
              azureSubscription: 'Azure-Subscription-Connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                # Update actual secret values from variable group
                az keyvault secret set \
                  --vault-name $(keyVaultName) \
                  --name "Database-Password" \
                  --value "$(DatabasePassword)"

                az keyvault secret set \
                  --vault-name $(keyVaultName) \
                  --name "Azure-StorageAccountKey" \
                  --value "$(AzureStorageAccountKey)"

                az keyvault secret set \
                  --vault-name $(keyVaultName) \
                  --name "ExternalApi-ApiKey" \
                  --value "$(ExternalApiKey)"
```

## GitHub Actions Integration

```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Setup .NET
      uses: actions/setup-dotnet@v3
      with:
        dotnet-version: '8.0.x'

    - name: Build
      run: dotnet build --configuration Release

    - name: Extract Config Metadata
      run: |
        mkdir -p ./artifacts
        find . -name "configuration-metadata.json" -path "*/obj/Generated/*" \
          -exec cp {} ./artifacts/ \;

    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}

    - name: Deploy Infrastructure
      uses: azure/arm-deploy@v1
      with:
        resourceGroupName: my-rg
        template: ./examples/bicep/main.bicep
        parameters: >
          environmentName=dev
          keyVaultName=kv-myapp-dev-001
          appConfigName=appconfig-myapp-dev-001
          configMetadataPath=./artifacts/configuration-metadata.json

    - name: Update Secrets
      run: |
        az keyvault secret set --vault-name kv-myapp-dev-001 \
          --name "Database-Password" --value "${{ secrets.DB_PASSWORD }}"
        az keyvault secret set --vault-name kv-myapp-dev-001 \
          --name "ExternalApi-ApiKey" --value "${{ secrets.API_KEY }}"
```

## Key Concepts

### 1. Loading Generated Metadata

Bicep can load JSON files using `loadJsonContent()`:

```bicep
var configMetadata = loadJsonContent('../configuration-metadata.json')
```

### 2. Iterating Over Entries

Use array iteration to create resources for each config entry:

```bicep
resource configValues 'Microsoft.AppConfiguration/.../keyValues@2023-03-01' = [for entry in configMetadata.configEntries: {
  // ... resource definition
}]
```

### 3. Handling Default Values

Check if a default value exists before using it:

```bicep
value: contains(entry, 'defaultValue') ? entry.defaultValue : ''
```

### 4. Key Vault Secret Naming

Key Vault doesn't allow colons in secret names, so replace them:

```bicep
name: replace(entry.key, ':', '-')
// "Database:Password" becomes "Database-Password"
```

### 5. Key Vault References in App Configuration

You can create references from App Configuration to Key Vault:

```bicep
value: '{"uri":"${keyVault.properties.vaultUri}secrets/${secretName}"}'
contentType: 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'
```

This allows your application to read secrets through App Configuration while they're securely stored in Key Vault.

## Best Practices

1. **Version Control**: Commit the generated `configuration-metadata.json` to source control
2. **Artifact Publishing**: Include the JSON file in your build artifacts
3. **Secret Management**: Never hardcode secrets in Bicep - use pipeline variables or parameter files
4. **Environment Separation**: Use separate parameter files for each environment
5. **Validation**: Add validation steps to ensure all required config values are provided
6. **Tagging**: Use tags to track metadata about config entries (environment, required, etc.)
7. **RBAC**: Use Azure RBAC to control access to Key Vault and App Configuration

## Troubleshooting

### Issue: Can't find configuration-metadata.json

The file is generated at build time. Check:
- Build succeeded
- Source generator is properly referenced in .csproj
- Look in `obj/Generated/ConfigGenerators.Generator/ConfigSourceGenerator/`

### Issue: Key Vault secret name invalid

Key Vault names must be alphanumeric or hyphens. Use `replace(entry.key, ':', '-')` to convert keys.

### Issue: App Configuration quota exceeded

The free tier of App Configuration has limits. Consider:
- Using standard tier for production
- Grouping related config into objects
- Using Key Vault references instead of duplicating secrets

## Additional Resources

- [Azure App Configuration Documentation](https://docs.microsoft.com/azure/azure-app-configuration/)
- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
