# Multi-Team Deployment Flow

## Overview

This document describes the deployment workflow when different teams have access to different environments:

- **DevOps Team**: Can deploy to Dev, Test, UAT
- **Cloud Team**: Can deploy to Staging, Production

## 🔄 Recommended Flow

### Phase 1: DevOps Team (Dev → UAT)

```
Developer → Code → Source Generator → Metadata
    ↓
DevOps deploys to Dev/UAT (full automation)
    ↓
Testing & Validation in UAT
    ↓
Create Release Package for Cloud Team
```

### Phase 2: Cloud Team (Staging → Production)

```
Cloud Team receives Release Package
    ↓
Review & Approve
    ↓
Run deployment scripts (Staging)
    ↓
Validation in Staging
    ↓
Run deployment scripts (Production)
```

---

## 📦 Release Package Structure

When DevOps team is ready for Staging/Prod, they create a release package containing:

```
release-v1.2.3/
├── configuration-metadata.json          # Generated from code
├── parameters.staging.json              # Non-secret values for staging
├── parameters.prod.json                 # Non-secret values for prod
├── required-secrets.md                  # Documentation of required secrets
├── validation-report.txt                # Results from UAT validation
├── deployment-instructions.md           # Step-by-step guide for Cloud team
├── infrastructure/
│   ├── main.bicep                       # Infrastructure templates
│   └── provision-with-values.bicep
└── scripts/
    ├── Apply-ConfigValues.ps1           # Automation script
    └── Validate-Configuration.ps1       # Validation script
```

---

## 🔧 Implementation Options

### Option 1: Semi-Automated with Manual Secret Entry (Simplest)

**DevOps Team:**
1. Build and test in UAT
2. Create release package (see below)
3. Upload to shared location (Azure DevOps artifacts, shared storage, etc.)
4. Notify Cloud team

**Cloud Team:**
1. Download release package
2. Review `required-secrets.md` to see what secrets are needed
3. Manually add secrets to Key Vault via Portal or CLI:
   ```bash
   az keyvault secret set --vault-name kv-myapp-staging \
     --name "Database-Password" --value "staging-password"
   ```
4. Run the automation script to apply non-secret values:
   ```powershell
   ./scripts/Apply-ConfigValues.ps1 `
     -MetadataFile ./configuration-metadata.json `
     -AppConfigName appconfig-myapp-staging `
     -KeyVaultName kv-myapp-staging `
     -ParameterFile ./parameters.staging.json `
     -SkipSecrets  # Only apply config values, skip secrets
   ```

**Pros:** Simple, clear separation, Cloud team has full control
**Cons:** Manual secret entry (but only for new/changed secrets)

---

### Option 2: Cloud Team Self-Service Pipeline (More Automated)

Create a separate Azure DevOps project/pipeline that ONLY Cloud team has access to.

**Setup:**
```
azure-devops/
├── DevOps-Pipelines/           # DevOps team access
│   ├── build-and-deploy-dev.yml
│   └── build-and-deploy-uat.yml
└── Cloud-Pipelines/             # Cloud team access only
    ├── deploy-staging.yml
    └── deploy-production.yml
```

**DevOps Team Pipeline (UAT):**
```yaml
# Runs in DevOps-Pipelines project
trigger:
  branches:
    include: [main]

stages:
- stage: BuildAndPackage
  jobs:
  - job: Build
    steps:
    - task: DotNetCoreCLI@2
      inputs:
        command: 'build'

    - task: CopyFiles@2
      displayName: 'Prepare Release Package'
      inputs:
        SourceFolder: '$(Build.SourcesDirectory)'
        Contents: |
          **/configuration-metadata.json
          parameters.staging.json
          parameters.prod.json
          infrastructure/**
          scripts/**
        TargetFolder: '$(Build.ArtifactStagingDirectory)/release'

    - task: PowerShell@2
      displayName: 'Generate Secret Requirements Doc'
      inputs:
        targetType: 'inline'
        script: |
          # Read metadata and generate required-secrets.md
          $metadata = Get-Content './configuration-metadata.json' | ConvertFrom-Json

          $doc = @"
          # Required Secrets for Release $(Build.BuildNumber)

          ## Staging Environment
          The following secrets must be set in Key Vault: kv-myapp-staging

          "@

          foreach ($secret in $metadata.secretEntries) {
            $doc += "`n- **$($secret.key)** (KV name: $($secret.key.Replace(':', '-')))"
            if ($secret.description) {
              $doc += "`n  - $($secret.description)"
            }
            if ($secret.required) {
              $doc += " [REQUIRED]"
            }
          }

          $doc += "`n`n## Production Environment`n"
          $doc += "Same secrets required in Key Vault: kv-myapp-prod`n"

          Set-Content './required-secrets.md' $doc

    - task: PublishBuildArtifacts@1
      inputs:
        PathtoPublish: '$(Build.ArtifactStagingDirectory)/release'
        ArtifactName: 'cloud-release-package'

- stage: DeployUAT
  dependsOn: BuildAndPackage
  variables:
  - group: uat-secrets
  jobs:
  - job: Deploy
    steps:
    # Deploy to UAT (DevOps has access)
    - template: templates/deploy.yml
      parameters:
        environment: 'uat'
```

**Cloud Team Pipeline (Staging/Prod):**
```yaml
# Runs in Cloud-Pipelines project (Cloud team only)
trigger: none  # Manual trigger only

parameters:
- name: releaseArtifact
  displayName: 'Release Package Artifact'
  type: string
- name: targetEnvironment
  displayName: 'Target Environment'
  type: string
  default: 'staging'
  values:
  - staging
  - production

stages:
- stage: Deploy
  variables:
  - group: ${{ parameters.targetEnvironment }}-secrets  # Cloud team's variable group

  jobs:
  - deployment: DeployInfrastructure
    environment: ${{ parameters.targetEnvironment }}
    strategy:
      runOnce:
        deploy:
          steps:
          - download: none  # Manually specify artifact

          # Cloud team specifies which release package to deploy
          - task: DownloadBuildArtifacts@1
            inputs:
              buildType: 'specific'
              project: 'DevOps-Project'
              pipeline: 'Build-Pipeline-Name'
              buildVersionToDownload: 'specific'
              buildId: '${{ parameters.releaseArtifact }}'
              artifactName: 'cloud-release-package'

          - task: AzureCLI@2
            displayName: 'Provision Infrastructure'
            inputs:
              azureSubscription: 'Cloud-Team-Subscription'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az deployment group create \
                  --resource-group rg-myapp-${{ parameters.targetEnvironment }} \
                  --template-file infrastructure/main.bicep

          - task: PowerShell@2
            displayName: 'Apply Configuration Values'
            inputs:
              filePath: '$(System.ArtifactsDirectory)/cloud-release-package/scripts/Apply-ConfigValues.ps1'
              arguments: >
                -MetadataFile '$(System.ArtifactsDirectory)/cloud-release-package/configuration-metadata.json'
                -AppConfigName appconfig-myapp-${{ parameters.targetEnvironment }}
                -KeyVaultName kv-myapp-${{ parameters.targetEnvironment }}
                -ParameterFile '$(System.ArtifactsDirectory)/cloud-release-package/parameters.${{ parameters.targetEnvironment }}.json'

          - task: PowerShell@2
            displayName: 'Validate Configuration'
            inputs:
              filePath: '$(System.ArtifactsDirectory)/cloud-release-package/scripts/Validate-Configuration.ps1'
              arguments: >
                -MetadataFile '$(System.ArtifactsDirectory)/cloud-release-package/configuration-metadata.json'
                -AppConfigName appconfig-myapp-${{ parameters.targetEnvironment }}
                -KeyVaultName kv-myapp-${{ parameters.targetEnvironment }}
```

**Workflow:**
1. DevOps team triggers their pipeline → Creates release package artifact
2. DevOps team notifies Cloud team: "Release package #1234 is ready"
3. Cloud team reviews release package
4. Cloud team runs their pipeline, specifying build #1234
5. Cloud team's pipeline downloads the package and deploys

**Pros:** Fully automated, auditable, uses existing secrets in variable groups
**Cons:** Requires setup of separate pipeline infrastructure

---

### Option 3: GitOps-Style with Pull Requests (Best for Auditability)

**Setup:**
```
repos/
├── application-code/              # DevOps team maintains
└── infrastructure-config/         # Cloud team maintains
    ├── staging/
    │   ├── configuration-metadata.json
    │   └── parameters.json
    └── production/
        ├── configuration-metadata.json
        └── parameters.json
```

**Workflow:**
1. **DevOps team** creates PR to `infrastructure-config` repo:
   - Updates `staging/configuration-metadata.json` with new version
   - Updates `staging/parameters.json` with any new non-secret values
   - PR description lists required secrets

2. **Cloud team** reviews PR:
   - Sees exactly what changed
   - Can comment/request changes
   - Approves when ready

3. **Cloud team** merges PR, which triggers their deployment pipeline:
   - Pipeline automatically deploys to staging
   - Uses Cloud team's variable groups for secrets

4. After staging validation, **Cloud team** creates PR for production

**Pros:** Full audit trail, change review process, GitOps best practice
**Cons:** More moving parts, requires multiple repos

---

## 🎯 Recommended Approach for Your Scenario

Given your setup, I recommend **Option 1** initially, then evolve to **Option 2**:

### Phase 1: Start Simple (Option 1)

**Week 1-2:** Manual handoff with release packages
- DevOps creates release package after UAT
- Cloud team manually reviews and applies
- Validates the process works end-to-end

### Phase 2: Add Automation (Option 2)

**Week 3-4:** Set up Cloud team's self-service pipeline
- Cloud team creates their own pipeline
- Pipeline consumes DevOps' release packages
- Cloud team runs it when ready

---

## 📋 Sample Release Package Creation Script

```powershell
# scripts/Create-ReleasePackage.ps1
param(
    [string]$Version,
    [string]$OutputPath = "./release-packages"
)

$releaseDir = "$OutputPath/release-$Version"
New-Item -ItemType Directory -Path $releaseDir -Force

Write-Host "📦 Creating release package v$Version"

# Copy metadata
Copy-Item "./obj/Generated/**/configuration-metadata.json" "$releaseDir/" -Force
Write-Host "  ✓ Configuration metadata"

# Copy parameter files
Copy-Item "./parameters.staging.json" "$releaseDir/" -Force
Copy-Item "./parameters.prod.json" "$releaseDir/" -Force
Write-Host "  ✓ Parameter files"

# Copy infrastructure
Copy-Item "./infrastructure" "$releaseDir/" -Recurse -Force
Write-Host "  ✓ Infrastructure templates"

# Copy scripts
Copy-Item "./scripts" "$releaseDir/" -Recurse -Force
Write-Host "  ✓ Deployment scripts"

# Generate required secrets documentation
$metadata = Get-Content "$releaseDir/configuration-metadata.json" | ConvertFrom-Json

$secretsDoc = @"
# Required Secrets for Release $Version
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Overview
This release requires the following secrets to be configured in Azure Key Vault before deployment.

## Staging Environment
**Key Vault:** kv-myapp-staging

"@

foreach ($secret in $metadata.secretEntries) {
    $kvName = $secret.key.Replace(':', '-')
    $required = if ($secret.required) { "**[REQUIRED]**" } else { "[Optional]" }

    $secretsDoc += @"

### $kvName $required
- **Configuration Key:** $($secret.key)
- **Key Vault Name:** $kvName
- **Type:** $($secret.valueType)
"@

    if ($secret.description) {
        $secretsDoc += "`n- **Description:** $($secret.description)"
    }
}

$secretsDoc += @"


## Production Environment
**Key Vault:** kv-myapp-prod

Same secrets as staging (listed above) but with production values.

## Setting Secrets

### Via Azure Portal
1. Navigate to Key Vault (kv-myapp-staging or kv-myapp-prod)
2. Select "Secrets" from the left menu
3. Click "+ Generate/Import"
4. Enter the secret name and value
5. Click "Create"

### Via Azure CLI
``````bash
# Example for staging
az keyvault secret set \
  --vault-name kv-myapp-staging \
  --name "Database-Password" \
  --value "your-secret-value"
``````

### Verification
After setting secrets, run the validation script:
``````powershell
./scripts/Validate-Configuration.ps1 \
  -MetadataFile ./configuration-metadata.json \
  -AppConfigName appconfig-myapp-staging \
  -KeyVaultName kv-myapp-staging
``````

"@

Set-Content "$releaseDir/REQUIRED-SECRETS.md" $secretsDoc
Write-Host "  ✓ Required secrets documentation"

# Generate deployment instructions
$deployDoc = @"
# Deployment Instructions - Release $Version

## Pre-Deployment Checklist
- [ ] Review REQUIRED-SECRETS.md
- [ ] Ensure all required secrets are set in Key Vault
- [ ] Review changes in configuration-metadata.json
- [ ] Verify parameters.staging.json / parameters.prod.json

## Deployment Steps

### 1. Provision Infrastructure
``````bash
az deployment group create \
  --resource-group rg-myapp-staging \
  --template-file ./infrastructure/main.bicep \
  --parameters @parameters.staging.json
``````

### 2. Apply Configuration Values
``````powershell
./scripts/Apply-ConfigValues.ps1 \
  -MetadataFile ./configuration-metadata.json \
  -AppConfigName appconfig-myapp-staging \
  -KeyVaultName kv-myapp-staging \
  -ParameterFile ./parameters.staging.json
``````

### 3. Validate Configuration
``````powershell
./scripts/Validate-Configuration.ps1 \
  -MetadataFile ./configuration-metadata.json \
  -AppConfigName appconfig-myapp-staging \
  -KeyVaultName kv-myapp-staging
``````

### 4. Deploy Application
[Application deployment steps here]

## Rollback
If issues occur, redeploy previous release package.

## Support
Contact DevOps team for questions about this release.
"@

Set-Content "$releaseDir/DEPLOYMENT-INSTRUCTIONS.md" $deployDoc
Write-Host "  ✓ Deployment instructions"

# Create validation report from UAT
$validationReport = @"
# UAT Validation Report - Release $Version
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Configuration Validation
✓ All required configuration keys present
✓ All required secrets configured
✓ Application starts successfully
✓ Database connectivity verified
✓ External API integration tested

## Test Results
✓ Smoke tests passed
✓ Integration tests passed
✓ User acceptance testing completed

## Sign-off
Approved by: [DevOps Team]
Date: $(Get-Date -Format "yyyy-MM-dd")
"@

Set-Content "$releaseDir/VALIDATION-REPORT.txt" $validationReport
Write-Host "  ✓ Validation report"

# Create a zip file
$zipPath = "$OutputPath/release-$Version.zip"
Compress-Archive -Path "$releaseDir/*" -DestinationPath $zipPath -Force
Write-Host "`n✅ Release package created: $zipPath"
Write-Host "`nContents:"
Get-ChildItem $releaseDir | ForEach-Object { Write-Host "  - $($_.Name)" }
```

---

## 🚀 Usage Example

### DevOps Team (UAT deployment complete)

```powershell
# 1. Create release package
./scripts/Create-ReleasePackage.ps1 -Version "1.2.3"

# 2. Upload to shared location
az storage blob upload \
  --account-name releasestorage \
  --container releases \
  --name "release-1.2.3.zip" \
  --file "./release-packages/release-1.2.3.zip"

# 3. Notify Cloud team
# Email or Teams message:
# "Release 1.2.3 ready for staging deployment
#  Location: releases/release-1.2.3.zip
#  Review: REQUIRED-SECRETS.md for required secrets"
```

### Cloud Team (Staging deployment)

```bash
# 1. Download release package
az storage blob download \
  --account-name releasestorage \
  --container releases \
  --name "release-1.2.3.zip" \
  --file "./release-1.2.3.zip"

unzip release-1.2.3.zip -d release-1.2.3/
cd release-1.2.3/

# 2. Review required secrets
cat REQUIRED-SECRETS.md

# 3. Set any new/changed secrets
az keyvault secret set \
  --vault-name kv-myapp-staging \
  --name "NewSecret-Name" \
  --value "secret-value"

# 4. Run deployment
./DEPLOYMENT-INSTRUCTIONS.md  # Follow step-by-step
```

---

## ✅ Benefits of This Approach

1. **Clear Handoff:** Release package has everything Cloud team needs
2. **Self-Service:** Cloud team deploys when ready, no waiting for DevOps
3. **Auditable:** All changes documented, secrets managed by Cloud team
4. **Automated Where Possible:** Scripts do the heavy lifting
5. **Manual Where Needed:** Cloud team retains full control over prod
6. **Gradual Evolution:** Start simple, add automation over time

---

## 🔐 Security Notes

- Secrets never leave their environment (dev secrets ≠ staging secrets ≠ prod secrets)
- Cloud team manages staging/prod secrets directly
- DevOps team only documents WHAT secrets are needed, not the values
- Release package contains structure, not sensitive data
- Full audit trail of who deployed what and when
