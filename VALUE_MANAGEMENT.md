# Getting Config Values Into Your Infrastructure

## Overview

The source generator creates the **structure** (keys, types, required flags), but you still need to provide **values** for each environment. Here are the recommended approaches.

## Approach 1: Azure DevOps Variable Groups (Recommended)

### Setup

1. **Create Variable Groups per Environment**
   - Navigate to Pipelines → Library → Variable Groups
   - Create groups: `dev-config`, `staging-config`, `prod-config`

2. **Add Values Matching Generated Keys**
   ```
   Group: dev-config
   ├─ Database-Host = "dev-db.postgres.azure.com"
   ├─ Database-Port = "5432"
   ├─ Database-DatabaseName = "myapp_dev"
   ├─ Database-Username = "devuser"
   └─ Database-Password = "***" (mark as secret)

   Group: prod-config
   ├─ Database-Host = "prod-db.postgres.azure.com"
   ├─ Database-Port = "5432"
   ├─ Database-DatabaseName = "myapp_prod"
   ├─ Database-Username = "produser"
   └─ Database-Password = "***" (mark as secret)
   ```

3. **Update Pipeline to Use Variable Groups**

```yaml
trigger:
  branches:
    include:
    - main

stages:
- stage: DeployDev
  variables:
  - group: dev-config  # Links to variable group

  jobs:
  - job: Deploy
    steps:
    - task: DotNetCoreCLI@2
      displayName: 'Build Application'
      inputs:
        command: 'build'
        projects: '**/*.csproj'

    - task: CopyFiles@2
      displayName: 'Copy Config Metadata'
      inputs:
        SourceFolder: '$(Build.SourcesDirectory)'
        Contents: '**/obj/Generated/**/configuration-metadata.json'
        TargetFolder: '$(Build.ArtifactStagingDirectory)/config'
        flattenFolders: true

    # Step 1: Provision infrastructure (creates empty keys/secrets)
    - task: AzureCLI@2
      displayName: 'Provision Infrastructure'
      inputs:
        azureSubscription: 'Azure-Subscription'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az deployment group create \
            --resource-group $(resourceGroupName) \
            --template-file infrastructure/main.bicep \
            --parameters \
              environmentName=dev \
              keyVaultName=$(keyVaultName) \
              appConfigName=$(appConfigName)

    # Step 2: Populate values from variable group
    - task: PowerShell@2
      displayName: 'Populate Configuration Values'
      inputs:
        targetType: 'inline'
        script: |
          # Read the generated metadata
          $metadata = Get-Content '$(Build.ArtifactStagingDirectory)/config/configuration-metadata.json' | ConvertFrom-Json

          # Set App Configuration values
          foreach ($entry in $metadata.configEntries) {
            $key = $entry.key
            $varName = $key.Replace(':', '-')
            $value = [Environment]::GetEnvironmentVariable($varName)

            if ($value) {
              Write-Host "Setting config: $key"
              az appconfig kv set `
                --name $(appConfigName) `
                --key $key `
                --value $value `
                --yes
            } elseif ($entry.defaultValue) {
              Write-Host "Setting config with default: $key = $($entry.defaultValue)"
              az appconfig kv set `
                --name $(appConfigName) `
                --key $key `
                --value $entry.defaultValue `
                --yes
            } elseif ($entry.required) {
              Write-Error "Required config missing: $key"
              exit 1
            }
          }

          # Set Key Vault secrets
          foreach ($entry in $metadata.secretEntries) {
            $key = $entry.key
            $secretName = $key.Replace(':', '-')
            $varName = $secretName
            $value = [Environment]::GetEnvironmentVariable($varName)

            if ($value) {
              Write-Host "Setting secret: $secretName"
              az keyvault secret set `
                --vault-name $(keyVaultName) `
                --name $secretName `
                --value $value
            } elseif ($entry.required) {
              Write-Error "Required secret missing: $secretName"
              exit 1
            }
          }

- stage: DeployProd
  dependsOn: DeployDev
  condition: succeeded()
  variables:
  - group: prod-config  # Different variable group for prod

  jobs:
  - deployment: DeployProduction
    environment: 'production'  # Requires approval
    strategy:
      runOnce:
        deploy:
          steps:
          # Same steps as dev, but uses prod-config variable group
          # ... (repeat steps above)
```

### Benefits
- ✅ Centralized value management in Azure DevOps
- ✅ Role-based access control
- ✅ Secret masking in logs
- ✅ Easy to update without code changes
- ✅ Audit trail of who changed what

---

## Approach 2: Parameter Files per Environment

Store values in JSON files checked into source control (for non-secrets).

### Setup

```
infrastructure/
├── parameters.dev.json
├── parameters.staging.json
└── parameters.prod.json
```

**parameters.dev.json:**
```json
{
  "values": {
    "Database:Host": "dev-db.postgres.azure.com",
    "Database:Port": "5432",
    "Database:DatabaseName": "myapp_dev",
    "Database:Username": "devuser",
    "Azure:StorageAccountName": "devstorageaccount",
    "ExternalApi:BaseUrl": "https://api-dev.example.com"
  }
}
```

**Secrets still come from pipeline variables** (never commit secrets!):
```yaml
- task: PowerShell@2
  displayName: 'Apply Configuration'
  env:
    DATABASE_PASSWORD: $(DatabasePassword)
    AZURE_STORAGE_KEY: $(AzureStorageKey)
    EXTERNAL_API_KEY: $(ExternalApiKey)
  inputs:
    targetType: 'inline'
    script: |
      # Load parameter file
      $params = Get-Content 'infrastructure/parameters.dev.json' | ConvertFrom-Json

      # Apply non-secret values from parameter file
      foreach ($key in $params.values.PSObject.Properties.Name) {
        $value = $params.values.$key
        az appconfig kv set --name $(appConfigName) --key $key --value $value --yes
      }

      # Apply secrets from environment variables
      az keyvault secret set --vault-name $(keyVaultName) --name "Database-Password" --value $env:DATABASE_PASSWORD
      az keyvault secret set --vault-name $(keyVaultName) --name "Azure-StorageAccountKey" --value $env:AZURE_STORAGE_KEY
      az keyvault secret set --vault-name $(keyVaultName) --name "ExternalApi-ApiKey" --value $env:EXTERNAL_API_KEY
```

### Benefits
- ✅ Non-secret values version controlled
- ✅ Easy to see differences between environments
- ✅ Secrets still protected in pipeline variables
- ✅ Simple to review in PRs

---

## Approach 3: Azure Key Vault as Source of Truth

Store ALL configuration in Key Vault, reference from App Config.

### Setup

1. **Manually populate Key Vault once** (or via pipeline)
```bash
# One-time setup per environment
az keyvault secret set --vault-name kv-myapp-dev --name "Database-Host" --value "dev-db.postgres.azure.com"
az keyvault secret set --vault-name kv-myapp-dev --name "Database-Password" --value "supersecret"
```

2. **App Configuration references Key Vault**
```bicep
// In your Bicep template
resource configValues 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = [for entry in configMetadata.configEntries: {
  parent: appConfig
  name: entry.key
  properties: {
    // Create a Key Vault reference instead of storing value
    value: '{"uri":"${keyVault.properties.vaultUri}secrets/${replace(entry.key, ':', '-')}"}'
    contentType: 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'
  }
}]
```

3. **App reads from App Config** (which fetches from Key Vault)
```csharp
builder.Configuration.AddAzureAppConfiguration(options =>
{
    options.Connect(connectionString)
           .ConfigureKeyVault(kv => kv.SetCredential(new DefaultAzureCredential()));
});
```

### Benefits
- ✅ Everything in one secure place
- ✅ Fine-grained access control
- ✅ Automatic rotation support
- ✅ Centralized secret management

---

## Approach 4: Terraform/Bicep with tfvars

Use infrastructure-as-code variable files.

**dev.tfvars:**
```hcl
database_host = "dev-db.postgres.azure.com"
database_port = 5432
database_name = "myapp_dev"
```

**main.tf:**
```hcl
variable "database_host" {}
variable "database_password" { sensitive = true }

resource "azurerm_app_configuration_key" "database_host" {
  configuration_store_id = azurerm_app_configuration.main.id
  key                    = "Database:Host"
  value                  = var.database_host
}

resource "azurerm_key_vault_secret" "database_password" {
  name         = "Database-Password"
  value        = var.database_password
  key_vault_id = azurerm_key_vault.main.id
}
```

---

## Approach 5: Manual Portal Entry (Not Recommended for Production)

For development/testing only:

1. Build generates `configuration-metadata.json`
2. DevOps manually enters values in Azure Portal:
   - App Configuration → Configuration explorer → Add key/value
   - Key Vault → Secrets → Add secret

**Use for:**
- Local development
- Quick prototyping
- One-off testing environments

**Don't use for:**
- Production
- Environments that need to be recreated
- Teams with multiple people deploying

---

## Recommended Hybrid Approach

Combine methods for best results:

```yaml
# Pipeline structure
stages:
- stage: Build
  # Generate configuration-metadata.json

- stage: DeployDev
  variables:
  - group: dev-secrets  # Secrets only
  - template: parameters/dev-values.yml  # Non-secrets from file

  steps:
  # 1. Provision infrastructure from generated metadata (creates structure)
  - template: templates/provision-infrastructure.yml

  # 2. Apply non-secret values from parameter file
  - template: templates/apply-config-values.yml

  # 3. Apply secrets from variable group
  - template: templates/apply-secrets.yml
```

This gives you:
- ✅ Non-secrets version controlled (visible in PRs)
- ✅ Secrets secured in variable groups
- ✅ Generated metadata ensures structure matches code
- ✅ Automated deployment with manual approval gates for prod

---

## Validation Script

Add this to validate all required config is present:

```powershell
# validate-config.ps1
param(
    [string]$MetadataFile,
    [string]$AppConfigName,
    [string]$KeyVaultName
)

$metadata = Get-Content $MetadataFile | ConvertFrom-Json
$errors = @()

# Check required config entries
foreach ($entry in $metadata.configEntries | Where-Object { $_.required }) {
    $key = $entry.key
    $value = az appconfig kv show --name $AppConfigName --key $key --query value -o tsv 2>$null

    if (-not $value) {
        $errors += "Missing required config: $key"
    }
}

# Check required secrets
foreach ($entry in $metadata.secretEntries | Where-Object { $_.required }) {
    $secretName = $entry.key.Replace(':', '-')
    $exists = az keyvault secret show --vault-name $KeyVaultName --name $secretName 2>$null

    if (-not $exists) {
        $errors += "Missing required secret: $secretName"
    }
}

if ($errors.Count -gt 0) {
    Write-Error "Configuration validation failed:"
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "✅ All required configuration is present"
```

Use in pipeline:
```yaml
- task: PowerShell@2
  displayName: 'Validate Configuration'
  inputs:
    filePath: 'scripts/validate-config.ps1'
    arguments: >
      -MetadataFile '$(Build.ArtifactStagingDirectory)/config/configuration-metadata.json'
      -AppConfigName $(appConfigName)
      -KeyVaultName $(keyVaultName)
```

---

## Summary Table

| Approach | Secrets | Non-Secrets | Best For | Complexity |
|----------|---------|-------------|----------|------------|
| **Variable Groups** | ✅ Great | ✅ Good | Teams, automation | Low |
| **Parameter Files** | ❌ No | ✅ Great | Version control | Low |
| **Key Vault Only** | ✅ Great | ⚠️ OK | High security needs | Medium |
| **Terraform/Bicep** | ✅ Good | ✅ Great | Full IaC | High |
| **Manual Portal** | ⚠️ OK | ⚠️ OK | Dev/testing only | Very Low |

**Recommended:** Variable Groups (secrets) + Parameter Files (non-secrets)
