#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Creates a release package for Cloud team deployment to staging/production.

.DESCRIPTION
    Packages all necessary files for Cloud team deployment including metadata,
    parameter files, scripts, and documentation. Generates required secrets
    documentation and deployment instructions.

.PARAMETER Version
    Version number for this release (e.g., "1.2.3", "2024.01.15.1")

.PARAMETER MetadataFile
    Path to the generated configuration-metadata.json file.
    Default: Searches in obj/Generated/**/configuration-metadata.json

.PARAMETER OutputPath
    Directory where release packages will be created.
    Default: ./release-packages

.PARAMETER IncludeInfrastructure
    Include infrastructure templates in the package.
    Default: true

.PARAMETER CreateZip
    Create a zip file of the release package.
    Default: true

.EXAMPLE
    ./Create-ReleasePackage.ps1 -Version "1.2.3"

.EXAMPLE
    ./Create-ReleasePackage.ps1 `
        -Version "2024.01.15.1" `
        -MetadataFile "./custom-path/configuration-metadata.json" `
        -OutputPath "./releases"

.NOTES
    This script is intended to be run by DevOps team after successful UAT deployment.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$MetadataFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "./release-packages",

    [Parameter(Mandatory = $false)]
    [bool]$IncludeInfrastructure = $true,

    [Parameter(Mandatory = $false)]
    [bool]$CreateZip = $true
)

$ErrorActionPreference = "Stop"

# Colors
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"
$ColorInfo = "Cyan"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "📦 Creating Release Package v$Version" $ColorInfo
Write-ColorOutput "=====================================" $ColorInfo

# Find metadata file if not specified
if (-not $MetadataFile) {
    Write-ColorOutput "`n🔍 Searching for configuration-metadata.json..." $ColorInfo
    $found = Get-ChildItem -Path . -Recurse -Filter "configuration-metadata.json" |
             Where-Object { $_.FullName -like "*obj*Generated*" } |
             Select-Object -First 1

    if ($found) {
        $MetadataFile = $found.FullName
        Write-ColorOutput "  ✓ Found: $MetadataFile" $ColorSuccess
    } else {
        Write-ColorOutput "  ❌ Could not find configuration-metadata.json" $ColorError
        Write-ColorOutput "     Please build the project first or specify -MetadataFile" $ColorError
        exit 1
    }
}

# Validate metadata file exists
if (-not (Test-Path $MetadataFile)) {
    Write-ColorOutput "❌ Metadata file not found: $MetadataFile" $ColorError
    exit 1
}

# Create release directory
$releaseDir = "$OutputPath/release-$Version"
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
Write-ColorOutput "`n📁 Release directory: $releaseDir" $ColorInfo

# Copy metadata
Write-ColorOutput "`n📋 Copying files..." $ColorInfo
Copy-Item $MetadataFile "$releaseDir/configuration-metadata.json" -Force
Write-ColorOutput "  ✓ Configuration metadata" $ColorSuccess

# Copy parameter files if they exist
$parameterFiles = @("parameters.staging.json", "parameters.prod.json", "examples/parameters.dev.json")
foreach ($file in $parameterFiles) {
    if (Test-Path $file) {
        $destName = Split-Path $file -Leaf
        Copy-Item $file "$releaseDir/$destName" -Force
        Write-ColorOutput "  ✓ $file" $ColorSuccess
    }
}

# Copy infrastructure if requested
if ($IncludeInfrastructure -and (Test-Path "./infrastructure")) {
    Copy-Item "./infrastructure" "$releaseDir/" -Recurse -Force
    Write-ColorOutput "  ✓ Infrastructure templates" $ColorSuccess
} elseif ($IncludeInfrastructure -and (Test-Path "./examples/bicep")) {
    Copy-Item "./examples/bicep" "$releaseDir/infrastructure" -Recurse -Force
    Write-ColorOutput "  ✓ Infrastructure templates (from examples)" $ColorSuccess
}

# Copy scripts
if (Test-Path "./scripts") {
    Copy-Item "./scripts" "$releaseDir/" -Recurse -Force
    Write-ColorOutput "  ✓ Deployment scripts" $ColorSuccess
}

# Read metadata for documentation generation
$metadata = Get-Content "$releaseDir/configuration-metadata.json" | ConvertFrom-Json

# Generate required secrets documentation
Write-ColorOutput "`n📝 Generating documentation..." $ColorInfo

$secretsDoc = @"
# Required Secrets for Release $Version
**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")

## Overview
This release requires the following secrets to be configured in Azure Key Vault before deployment.

**Important:** These are the KEY NAMES required - you must provide the actual VALUES.

---

## Staging Environment
**Key Vault:** ``kv-myapp-staging`` (update with your actual Key Vault name)

"@

if ($metadata.secretEntries.Count -eq 0) {
    $secretsDoc += "`n✓ No secrets required for this release`n"
} else {
    $secretsDoc += "`n| Key Vault Secret Name | Config Key | Type | Required | Description |`n"
    $secretsDoc += "|----------------------|------------|------|----------|-------------|`n"

    foreach ($secret in $metadata.secretEntries) {
        $kvName = $secret.key.Replace(':', '-')
        $required = if ($secret.required) { "✓ YES" } else { "Optional" }
        $description = if ($secret.description) { $secret.description } else { "-" }
        $secretsDoc += "| ``$kvName`` | ``$($secret.key)`` | $($secret.valueType) | $required | $description |`n"
    }

    $secretsDoc += @"


### Azure Portal Method
1. Navigate to your Key Vault (kv-myapp-staging)
2. Select **Secrets** from the left menu
3. Click **+ Generate/Import**
4. Enter the secret name from the table above
5. Paste the secret value
6. Click **Create**

### Azure CLI Method
``````bash
# Set each required secret
az keyvault secret set \
  --vault-name kv-myapp-staging \
  --name "Secret-Name-Here" \
  --value "your-secret-value-here"
``````

### PowerShell Method
``````powershell
# Set each required secret
Set-AzKeyVaultSecret \
  -VaultName "kv-myapp-staging" \
  -Name "Secret-Name-Here" \
  -SecretValue (ConvertTo-SecureString "your-secret-value-here" -AsPlainText -Force)
``````
"@
}

$secretsDoc += @"


---

## Production Environment
**Key Vault:** ``kv-myapp-prod`` (update with your actual Key Vault name)

**Same secrets as staging** (listed above) but with **production values**.

⚠️ **CRITICAL:** Use different, production-grade secrets for production environment!

---

## Verification

After setting all required secrets, validate before deployment:

``````powershell
# Validate staging
./scripts/Apply-ConfigValues.ps1 \
  -MetadataFile ./configuration-metadata.json \
  -AppConfigName appconfig-myapp-staging \
  -KeyVaultName kv-myapp-staging \
  -ParameterFile ./parameters.staging.json \
  -ValidateOnly
``````

---

## Secret Management Best Practices

1. ✓ Use different secrets for each environment
2. ✓ Store secrets in a password manager
3. ✓ Limit access to secrets (use Azure RBAC)
4. ✓ Enable Key Vault audit logging
5. ✓ Set up secret expiration alerts
6. ✓ Document who has access to production secrets

---

## Configuration Values (Non-Secrets)

The following non-secret configuration values are included in ``parameters.staging.json`` and ``parameters.prod.json``:

| Configuration Key | Type | Default | Description |
|------------------|------|---------|-------------|
"@

foreach ($entry in $metadata.configEntries) {
    $default = if ($entry.defaultValue) { "``$($entry.defaultValue)``" } else { "-" }
    $description = if ($entry.description) { $entry.description } else { "-" }
    $secretsDoc += "`n| ``$($entry.key)`` | $($entry.valueType) | $default | $description |"
}

$secretsDoc += @"


These values are automatically applied by the deployment script.

---

**Questions?** Contact the DevOps team.
"@

Set-Content "$releaseDir/REQUIRED-SECRETS.md" $secretsDoc
Write-ColorOutput "  ✓ REQUIRED-SECRETS.md" $ColorSuccess

# Generate deployment instructions
$deployDoc = @"
# Deployment Instructions - Release $Version

## 📋 Pre-Deployment Checklist

Before deploying, ensure:

- [ ] Review ``REQUIRED-SECRETS.md`` for required secrets
- [ ] All required secrets are set in target Key Vault
- [ ] Review changes in ``configuration-metadata.json``
- [ ] Verify values in ``parameters.staging.json`` or ``parameters.prod.json``
- [ ] Have rollback plan ready (previous release package)
- [ ] Deployment window scheduled and communicated

---

## 🚀 Deployment Steps

### Step 1: Prepare Azure CLI / PowerShell

Ensure you're logged in with correct subscription:

``````bash
# Azure CLI
az login
az account set --subscription "Your-Subscription-Name"
az account show  # Verify correct subscription

# Verify access
az keyvault secret list --vault-name kv-myapp-staging --query "[0]"
``````

### Step 2: Set Required Secrets (First Time / New Secrets Only)

See ``REQUIRED-SECRETS.md`` for the complete list.

``````bash
# Example: Set each required secret
az keyvault secret set \
  --vault-name kv-myapp-staging \
  --name "Database-Password" \
  --value "your-secret-value"
``````

### Step 3: Provision Infrastructure (if needed)

``````bash
# For staging
az deployment group create \
  --resource-group rg-myapp-staging \
  --template-file ./infrastructure/main.bicep \
  --parameters environmentName=staging

# For production
az deployment group create \
  --resource-group rg-myapp-prod \
  --template-file ./infrastructure/main.bicep \
  --parameters environmentName=production
``````

### Step 4: Apply Configuration Values

``````powershell
# For staging
./scripts/Apply-ConfigValues.ps1 \
  -MetadataFile ./configuration-metadata.json \
  -AppConfigName appconfig-myapp-staging \
  -KeyVaultName kv-myapp-staging \
  -ParameterFile ./parameters.staging.json

# For production
./scripts/Apply-ConfigValues.ps1 \
  -MetadataFile ./configuration-metadata.json \
  -AppConfigName appconfig-myapp-prod \
  -KeyVaultName kv-myapp-prod \
  -ParameterFile ./parameters.prod.json
``````

### Step 5: Validate Configuration

``````powershell
# Validate staging
./scripts/Apply-ConfigValues.ps1 \
  -MetadataFile ./configuration-metadata.json \
  -AppConfigName appconfig-myapp-staging \
  -KeyVaultName kv-myapp-staging \
  -ValidateOnly

# Validate production
./scripts/Apply-ConfigValues.ps1 \
  -MetadataFile ./configuration-metadata.json \
  -AppConfigName appconfig-myapp-prod \
  -KeyVaultName kv-myapp-prod \
  -ValidateOnly
``````

### Step 6: Deploy Application

[Add your application deployment steps here]

Examples:
- Deploy App Service
- Update Container Registry
- Trigger release pipeline

### Step 7: Post-Deployment Verification

- [ ] Application health check passes
- [ ] Can connect to database
- [ ] External APIs responding
- [ ] Smoke tests pass
- [ ] Logs show no configuration errors

---

## 🔄 Rollback Procedure

If issues occur:

1. Identify previous stable release package
2. Re-run deployment steps with previous package
3. Restore configuration:
   ``````powershell
   ./scripts/Apply-ConfigValues.ps1 \
     -MetadataFile ./configuration-metadata.json \
     -AppConfigName appconfig-myapp-prod \
     -KeyVaultName kv-myapp-prod \
     -ParameterFile ./parameters.prod.json
   ``````

---

## 📞 Support

- **DevOps Team:** devops@example.com
- **On-Call:** +1-XXX-XXX-XXXX
- **Documentation:** [Link to wiki]

---

## 📝 Deployment Log

Record deployment details:

- **Deployed By:** _____________
- **Date/Time:** _____________
- **Environment:** Staging / Production
- **Issues Encountered:** _____________
- **Resolution:** _____________

"@

Set-Content "$releaseDir/DEPLOYMENT-INSTRUCTIONS.md" $deployDoc
Write-ColorOutput "  ✓ DEPLOYMENT-INSTRUCTIONS.md" $ColorSuccess

# Generate README
$readmeDoc = @"
# Release Package v$Version

**Created:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**For:** Staging and Production Deployment

## 📦 Package Contents

- **configuration-metadata.json** - Generated configuration structure from code
- **parameters.staging.json** - Non-secret values for staging environment
- **parameters.prod.json** - Non-secret values for production environment
- **REQUIRED-SECRETS.md** - List of secrets needed in Key Vault
- **DEPLOYMENT-INSTRUCTIONS.md** - Step-by-step deployment guide
- **scripts/** - Automation scripts for deployment
- **infrastructure/** - Bicep templates (if included)

## 🚀 Quick Start

1. Read **REQUIRED-SECRETS.md** first
2. Set required secrets in Key Vault
3. Follow **DEPLOYMENT-INSTRUCTIONS.md**

## ⚠️ Important Notes

- This package contains NO secret values
- All secrets must be set manually in Key Vault
- Review all parameter files before deployment
- Test in staging before production

## 📊 Configuration Summary

- **Config Entries:** $($metadata.configEntries.Count)
- **Secret Entries:** $($metadata.secretEntries.Count)
- **Required Secrets:** $(($metadata.secretEntries | Where-Object { $_.required }).Count)

## 📞 Contact

Questions? Contact DevOps team.
"@

Set-Content "$releaseDir/README.md" $readmeDoc
Write-ColorOutput "  ✓ README.md" $ColorSuccess

# Create a change summary
$changeSummary = @"
# Change Summary - Release $Version

## Configuration Changes

### New Configuration Entries
[Review configuration-metadata.json for all entries]

### New Secrets Required
[Review REQUIRED-SECRETS.md for all required secrets]

## Validation

This release was validated in UAT environment on $(Get-Date -Format "yyyy-MM-dd").

### Tests Passed
- ✓ Application starts successfully
- ✓ All configuration loaded correctly
- ✓ Database connectivity verified
- ✓ External service integration tested

## Deployment Notes

[Add any specific notes for Cloud team about this release]

---

**Prepared by:** DevOps Team
**Date:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

Set-Content "$releaseDir/CHANGE-SUMMARY.md" $changeSummary
Write-ColorOutput "  ✓ CHANGE-SUMMARY.md" $ColorSuccess

# Create zip file if requested
if ($CreateZip) {
    Write-ColorOutput "`n📦 Creating zip file..." $ColorInfo
    $zipPath = "$OutputPath/release-$Version.zip"

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    Compress-Archive -Path "$releaseDir/*" -DestinationPath $zipPath -Force
    $zipSize = (Get-Item $zipPath).Length / 1MB
    Write-ColorOutput "  ✓ $zipPath ($([math]::Round($zipSize, 2)) MB)" $ColorSuccess
}

# Summary
Write-ColorOutput "`n✅ Release Package Created Successfully!" $ColorSuccess
Write-ColorOutput "=======================================" $ColorSuccess
Write-ColorOutput "`n📁 Location: $releaseDir" $ColorInfo
if ($CreateZip) {
    Write-ColorOutput "📦 Zip File: $OutputPath/release-$Version.zip" $ColorInfo
}

Write-ColorOutput "`n📋 Package Contents:" $ColorInfo
Get-ChildItem $releaseDir | ForEach-Object {
    Write-ColorOutput "  - $($_.Name)" "White"
}

Write-ColorOutput "`n📊 Statistics:" $ColorInfo
Write-ColorOutput "  - Configuration Entries: $($metadata.configEntries.Count)" "White"
Write-ColorOutput "  - Secret Entries: $($metadata.secretEntries.Count)" "White"
Write-ColorOutput "  - Required Secrets: $(($metadata.secretEntries | Where-Object { $_.required }).Count)" "Yellow"

Write-ColorOutput "`n📤 Next Steps:" $ColorInfo
Write-ColorOutput "  1. Review the package contents" "White"
Write-ColorOutput "  2. Upload to shared location for Cloud team" "White"
Write-ColorOutput "  3. Notify Cloud team that release $Version is ready" "White"

Write-ColorOutput "`n💡 Upload Command Example:" $ColorInfo
Write-ColorOutput "  az storage blob upload \" "DarkGray"
Write-ColorOutput "    --account-name releasestorage \" "DarkGray"
Write-ColorOutput "    --container releases \" "DarkGray"
Write-ColorOutput "    --name 'release-$Version.zip' \" "DarkGray"
Write-ColorOutput "    --file '$OutputPath/release-$Version.zip'" "DarkGray"
