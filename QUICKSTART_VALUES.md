# Quick Start: Managing Configuration Values

This guide shows you how to get actual values into your Azure infrastructure after the source generator has created the metadata.

## The Three-Step Process

```
1. CODE → METADATA     (source generator - automatic)
2. METADATA → STRUCTURE (Bicep/pipeline - automatic)
3. VALUES → STRUCTURE   (this guide - manual or automated)
```

Step 3 is what you're asking about - how do the actual values get in there?

## 🚀 Quick Start: Local Development

### 1. Generate the Metadata
```bash
dotnet build
# Generates: obj/Generated/.../configuration-metadata.json
```

### 2. Create a Parameter File
Create `parameters.dev.json`:
```json
{
  "values": {
    "Database:Host": "localhost",
    "Database:Port": "5432",
    "Azure:StorageAccountName": "devstoragelocal"
  }
}
```

### 3. Set Secret Environment Variables
```bash
# PowerShell
$env:Database-Password = "local-dev-password"
$env:Azure-StorageAccountKey = "your-storage-key"
$env:ExternalApi-ApiKey = "your-api-key"

# Bash
export Database-Password="local-dev-password"
export Azure-StorageAccountKey="your-storage-key"
export ExternalApi-ApiKey="your-api-key"
```

### 4. Run the Apply Script
```powershell
./scripts/Apply-ConfigValues.ps1 `
    -MetadataFile "./obj/Generated/.../configuration-metadata.json" `
    -AppConfigName "appconfig-myapp-dev" `
    -KeyVaultName "kv-myapp-dev" `
    -ParameterFile "./parameters.dev.json"
```

**Done!** ✅ Your App Configuration and Key Vault are now populated.

---

## 🏢 Production Setup: Azure DevOps Pipeline

### Step 1: Create Variable Groups

In Azure DevOps:
1. Go to **Pipelines → Library → Variable Groups**
2. Create `dev-secrets`:
   ```
   Database-Password = *** (click lock icon)
   Azure-StorageAccountKey = *** (click lock icon)
   ExternalApi-ApiKey = *** (click lock icon)
   ```
3. Create `prod-secrets` with production values

### Step 2: Create Parameter Files

Commit to source control:

**parameters/dev-values.yml:**
```yaml
variables:
  Database-Host: 'dev-db.postgres.database.azure.com'
  Database-Port: '5432'
  Database-DatabaseName: 'myapp_dev'
  Azure-StorageAccountName: 'stmyappdev001'
  ExternalApi-BaseUrl: 'https://api-dev.example.com'
```

**parameters/prod-values.yml:**
```yaml
variables:
  Database-Host: 'prod-db.postgres.database.azure.com'
  Database-Port: '5432'
  Database-DatabaseName: 'myapp_prod'
  Azure-StorageAccountName: 'stmyappprod001'
  ExternalApi-BaseUrl: 'https://api.example.com'
```

### Step 3: Update Your Pipeline

```yaml
trigger:
  branches:
    include:
    - main

stages:
- stage: DeployDev
  variables:
  - group: dev-secrets              # Secrets from variable group
  - template: parameters/dev-values.yml  # Non-secrets from file

  jobs:
  - job: Deploy
    steps:
    # Build and generate metadata
    - task: DotNetCoreCLI@2
      displayName: 'Build Application'
      inputs:
        command: 'build'

    # Extract generated metadata
    - task: CopyFiles@2
      displayName: 'Copy Metadata'
      inputs:
        SourceFolder: '$(Build.SourcesDirectory)'
        Contents: '**/obj/Generated/**/configuration-metadata.json'
        TargetFolder: '$(Build.ArtifactStagingDirectory)'
        flattenFolders: true

    # Provision infrastructure (creates structure from metadata)
    - task: AzureCLI@2
      displayName: 'Provision Infrastructure'
      inputs:
        azureSubscription: 'Azure-Subscription'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az deployment group create \
            --resource-group $(resourceGroupName) \
            --template-file infrastructure/main.bicep

    # Apply configuration values
    - task: PowerShell@2
      displayName: 'Apply Config Values'
      inputs:
        filePath: 'scripts/Apply-ConfigValues.ps1'
        arguments: >
          -MetadataFile '$(Build.ArtifactStagingDirectory)/configuration-metadata.json'
          -AppConfigName $(appConfigName)
          -KeyVaultName $(keyVaultName)

- stage: DeployProd
  dependsOn: DeployDev
  variables:
  - group: prod-secrets              # Production secrets
  - template: parameters/prod-values.yml  # Production values

  jobs:
  - deployment: DeployProduction
    environment: 'production'        # Requires manual approval
    strategy:
      runOnce:
        deploy:
          steps:
          # Same steps as dev
```

---

## 💡 How Values Flow

### Configuration Entries (Non-Secrets)
```
parameters.dev.json
    ↓
Pipeline variable
    ↓
Apply-ConfigValues.ps1
    ↓
Azure App Configuration
```

### Secret Entries
```
Azure DevOps Variable Group (masked)
    ↓
Environment variable in pipeline
    ↓
Apply-ConfigValues.ps1
    ↓
Azure Key Vault
```

### In Your Application
```
Azure App Configuration
    ↓ (references Key Vault)
Azure Key Vault
    ↓
.NET Configuration
    ↓
IOptions<DatabaseConfig>
    ↓
Your Code
```

---

## 🔍 Common Scenarios

### Scenario 1: Adding a New Config Value

1. **Developer adds to code:**
   ```csharp
   [ConfigValue(Description = "New feature flag")]
   public bool EnableNewFeature { get; set; }
   ```

2. **Build generates updated metadata:**
   - New entry: `"key": "Section:EnableNewFeature"`

3. **DevOps adds to parameter files:**
   ```json
   "Section:EnableNewFeature": "false"  // dev
   "Section:EnableNewFeature": "true"   // prod
   ```

4. **Next deployment automatically provisions it** ✅

### Scenario 2: Adding a New Secret

1. **Developer adds to code:**
   ```csharp
   [ConfigSecret(Description = "Third-party service token")]
   public string ServiceToken { get; set; }
   ```

2. **Build generates updated metadata:**
   - New entry: `"key": "Section:ServiceToken", "type": "secret"`

3. **DevOps adds to variable groups:**
   - `dev-secrets`: Add variable `Section-ServiceToken` (lock it)
   - `prod-secrets`: Add variable `Section-ServiceToken` (lock it)

4. **Next deployment automatically provisions it** ✅

### Scenario 3: Removing Old Config

1. **Developer removes from code:**
   ```csharp
   // [ConfigValue] public string OldSetting { get; set; }  // Deleted
   ```

2. **Build generates updated metadata:**
   - Entry removed from JSON

3. **DevOps removes from parameter files/variable groups** (optional cleanup)

4. **Config key remains in Azure but is unused**
   - Can be manually cleaned up later
   - Or add automated cleanup script

---

## ✅ Validation

### Before Deployment
```powershell
# Validate all required values are available
./scripts/Apply-ConfigValues.ps1 `
    -MetadataFile "./configuration-metadata.json" `
    -AppConfigName "appconfig-myapp-dev" `
    -KeyVaultName "kv-myapp-dev" `
    -ValidateOnly
```

### After Deployment
```powershell
# Check what's in App Configuration
az appconfig kv list --name appconfig-myapp-dev

# Check what's in Key Vault
az keyvault secret list --vault-name kv-myapp-dev
```

### In Your Application
Add startup validation:
```csharp
// Program.cs
builder.Services.AddOptions<DatabaseConfig>()
    .Bind(builder.Configuration.GetSection("Database"))
    .ValidateDataAnnotations()
    .ValidateOnStart();  // Fail fast if config is invalid
```

---

## 🎯 Best Practices

### ✅ Do
- **Parameter files for non-secrets** - Version controlled, visible in PRs
- **Variable groups for secrets** - Encrypted, access controlled
- **Validate before deploying** - Catch missing values early
- **Use defaults wisely** - For values that rarely change
- **Document required secrets** - In your parameter files

### ❌ Don't
- **Commit secrets** - Never put secrets in parameter files
- **Hardcode values** - Use the generated metadata
- **Skip validation** - Always validate required values
- **Mix environments** - Use separate variable groups per environment

---

## 🆘 Troubleshooting

### "Required configuration missing: Database:Password"
**Fix:** Set environment variable or add to variable group:
```powershell
$env:Database-Password = "your-password"
```

### "Failed to set config: Authorization failed"
**Fix:** Ensure your service principal has permissions:
```bash
# App Configuration
az role assignment create \
  --role "App Configuration Data Owner" \
  --assignee <service-principal-id> \
  --scope <app-config-resource-id>

# Key Vault
az keyvault set-policy \
  --name kv-myapp-dev \
  --object-id <service-principal-id> \
  --secret-permissions get list set
```

### "Configuration metadata not found"
**Fix:** Ensure build completed successfully:
```bash
dotnet build
find . -name "configuration-metadata.json"
```

---

## 📚 See Also

- [VALUE_MANAGEMENT.md](VALUE_MANAGEMENT.md) - Detailed approaches
- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md) - Using attributes in code
- [examples/bicep/README.md](examples/bicep/README.md) - Infrastructure provisioning
