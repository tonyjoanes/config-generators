# Config Generators

A C# source generator that automatically creates configuration metadata files for Infrastructure as Code (IaC) provisioning from strongly-typed configuration classes.

## Overview

This project solves the common problem of keeping application configuration in sync with infrastructure provisioning. Developers annotate their configuration classes with attributes, and the source generator automatically produces JSON files that describe all configuration entries and secrets needed by the application.

### The Problem

- Developers write code that requires configuration values
- DevOps teams must manually maintain lists of config keys for each environment
- Configuration drift occurs between code and infrastructure
- Manual coordination is error-prone and time-consuming

### The Solution

1. Developers use strongly-typed configuration classes with attributes
2. Source generator automatically creates metadata files at compile-time
3. DevOps teams use generated files in CI/CD pipelines to provision Azure App Configuration and Key Vault
4. Configuration is always in sync with code

## Features

- **Strongly-typed configuration**: Leverage C#'s type system and IOptions pattern
- **Automatic metadata generation**: No manual maintenance of config lists
- **Secret identification**: Mark sensitive values for Key Vault storage
- **Default values**: Specify defaults for non-required config
- **Documentation**: Add descriptions that flow through to infrastructure
- **Consolidated output**: Single JSON file for all application config needs

## Quick Start

### 1. Install the Packages

Add references to your project:

```xml
<ItemGroup>
  <PackageReference Include="ConfigGenerators.Attributes" Version="1.0.0" />
  <PackageReference Include="ConfigGenerators.Generator" Version="1.0.0"
                    OutputItemType="Analyzer"
                    ReferenceOutputAssembly="false" />
</ItemGroup>
```

### 2. Define Configuration Classes

```csharp
using ConfigGenerators.Attributes;

[GenerateConfig("Database", Description = "Database connection settings")]
public class DatabaseConfig
{
    [ConfigValue(Description = "Database server hostname", Required = true)]
    public string Host { get; set; } = string.Empty;

    [ConfigValue(DefaultValue = "5432", Description = "Database port")]
    public int Port { get; set; }

    [ConfigSecret(Description = "Database password", Required = true)]
    public string Password { get; set; } = string.Empty;
}
```

### 3. Build Your Project

When you compile, a `configuration-metadata.json` file is generated:

```json
{
  "configEntries": [
    {
      "key": "Database:Host",
      "type": "config",
      "valueType": "string",
      "description": "Database server hostname",
      "required": true
    },
    {
      "key": "Database:Port",
      "type": "config",
      "valueType": "int",
      "defaultValue": "5432",
      "description": "Database port",
      "required": false
    }
  ],
  "secretEntries": [
    {
      "key": "Database:Password",
      "type": "secret",
      "valueType": "string",
      "description": "Database password",
      "required": true
    }
  ]
}
```

### 4. Find Generated Files

Generated files are located in:
- `obj/Generated/ConfigGenerators.Generator/ConfigSourceGenerator/configuration-metadata.json`

Or configure your project to emit them to a specific location:

```xml
<PropertyGroup>
  <EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>
  <CompilerGeneratedFilesOutputPath>$(BaseIntermediateOutputPath)Generated</CompilerGeneratedFilesOutputPath>
</PropertyGroup>
```

## Attributes

### `[GenerateConfig]`

Applied to classes to mark them for configuration generation.

```csharp
[GenerateConfig(sectionName: "MySection", Description = "Optional description")]
public class MyConfig { }
```

**Parameters:**
- `sectionName` (optional): Configuration section name. Defaults to class name with "Config", "Options", or "Settings" removed.
- `Description` (optional): Description of the configuration section.

### `[ConfigValue]`

Applied to properties that should be stored in Azure App Configuration.

```csharp
[ConfigValue(
    DefaultValue = "default-value",
    Description = "What this config does",
    Required = true)]
public string MyProperty { get; set; }
```

**Parameters:**
- `DefaultValue` (optional): Default value if not provided
- `Description` (optional): Documentation for this config value
- `Required` (optional): Whether this value must be provided (default: false)

### `[ConfigSecret]`

Applied to properties that contain sensitive data and should be stored in Azure Key Vault.

```csharp
[ConfigSecret(
    Description = "Sensitive information",
    Required = true)]
public string MySecret { get; set; }
```

**Parameters:**
- `Description` (optional): Documentation for this secret
- `Required` (optional): Whether this secret must be provided (default: true)

## Generated Output Format

The generator creates a JSON file with the following structure:

```json
{
  "configEntries": [
    {
      "key": "Section:PropertyName",
      "type": "config",
      "valueType": "string|int|bool|etc",
      "defaultValue": "optional-default",
      "description": "optional-description",
      "sectionDescription": "optional-section-description",
      "required": true|false
    }
  ],
  "secretEntries": [
    {
      "key": "Section:PropertyName",
      "type": "secret",
      "valueType": "string|int|bool|etc",
      "description": "optional-description",
      "sectionDescription": "optional-section-description",
      "required": true|false
    }
  ]
}
```

## DevOps Integration

See the [examples/bicep](examples/bicep) folder for complete Bicep examples.

### Basic Workflow

1. **Build Phase**: Application is compiled, generating `configuration-metadata.json`
2. **Artifact Phase**: Include the JSON file in build artifacts
3. **Deployment Phase**: Read JSON and provision infrastructure

### Example Bicep Usage

```bicep
// Load the generated metadata
var configMetadata = loadJsonContent('../configuration-metadata.json')

// Create App Configuration entries
resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' existing = {
  name: appConfigName
}

// Create Key Vault secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Provision config entries
resource configValues 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = [for entry in configMetadata.configEntries: {
  parent: appConfig
  name: entry.key
  properties: {
    value: contains(entry, 'defaultValue') ? entry.defaultValue : ''
    contentType: 'text/plain'
  }
}]

// Provision secrets
resource secrets 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = [for entry in configMetadata.secretEntries: {
  parent: keyVault
  name: replace(entry.key, ':', '-')
  properties: {
    value: '' // Values provided separately per environment
  }
}]
```

### Azure DevOps Pipeline Example

```yaml
stages:
- stage: Build
  jobs:
  - job: BuildApp
    steps:
    - task: DotNetCoreCLI@2
      inputs:
        command: 'build'
        projects: '**/*.csproj'

    - task: CopyFiles@2
      displayName: 'Copy Config Metadata'
      inputs:
        SourceFolder: '$(Build.SourcesDirectory)'
        Contents: '**/configuration-metadata.json'
        TargetFolder: '$(Build.ArtifactStagingDirectory)/config'

    - publish: '$(Build.ArtifactStagingDirectory)'
      artifact: drop

- stage: DeployInfra
  jobs:
  - job: ProvisionConfig
    steps:
    - download: current
      artifact: drop

    - task: AzureCLI@2
      displayName: 'Deploy Configuration Infrastructure'
      inputs:
        azureSubscription: 'MySubscription'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az deployment group create \
            --resource-group my-rg \
            --template-file infrastructure/main.bicep \
            --parameters configMetadataPath=$(Pipeline.Workspace)/drop/config/configuration-metadata.json
```

## Project Structure

```
config-generators/
├── src/
│   ├── ConfigGenerators.Attributes/     # Attribute definitions
│   ├── ConfigGenerators.Generator/      # Source generator implementation
│   └── ConfigGenerators.Sample/         # Example usage
├── examples/
│   ├── expected-output.json             # Sample generated output
│   └── bicep/                           # Bicep examples (coming soon)
└── README.md
```

## Benefits

### For Developers
- Work with strongly-typed configuration classes
- No need to manually document config requirements
- Compile-time validation of config structure
- Standard IOptions pattern integration

### For DevOps
- Automated infrastructure provisioning
- No manual config list maintenance
- Reduced deployment errors
- Self-documenting configuration needs
- Environment-agnostic key definitions

### For Teams
- Single source of truth in code
- Configuration changes tracked in version control
- Reduced coordination overhead
- Faster onboarding for new environments

## Advanced Usage

### Multiple Configuration Classes

You can have multiple configuration classes, and they'll all be included in one consolidated output:

```csharp
[GenerateConfig("Database")]
public class DatabaseConfig { /* ... */ }

[GenerateConfig("Azure")]
public class AzureConfig { /* ... */ }

[GenerateConfig("ExternalApi")]
public class ApiConfig { /* ... */ }
```

All three will be merged into a single `configuration-metadata.json`.

### Nested Configuration

The generator handles hierarchical configuration through the section name:

```csharp
[GenerateConfig("Logging:Console")]
public class ConsoleLoggingConfig { /* ... */ }

[GenerateConfig("Logging:File")]
public class FileLoggingConfig { /* ... */ }
```

Generates keys like:
- `Logging:Console:MinLevel`
- `Logging:File:Path`

### Custom Key Names

By default, property names are used as-is. The section name becomes the prefix:

```csharp
[GenerateConfig("MySection")]
public class MyConfig
{
    [ConfigValue]
    public string MyProperty { get; set; }  // Key: "MySection:MyProperty"
}
```

## Roadmap

- [ ] Support for array/list properties
- [ ] Environment-specific value suggestions
- [ ] Integration with Azure CLI for direct provisioning
- [ ] YAML output format option
- [ ] Terraform output format
- [ ] Validation rule attributes

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see LICENSE file for details
