# Pull Request: C# Source Generator for Configuration Metadata Extraction

## Summary

Implements a complete C# source generator solution that automatically creates configuration metadata files for Infrastructure as Code (IaC) provisioning from strongly-typed configuration classes.

### Problem Solved
- Eliminates manual coordination between developers and DevOps for configuration management
- Prevents configuration drift between code and infrastructure
- Removes error-prone magic string configuration access (`configuration["Key"]`)
- Automates Azure App Configuration and Key Vault provisioning

## What's Included

### Core Implementation
- ✅ **ConfigGenerators.Attributes** - Developer-facing attributes (`[GenerateConfig]`, `[ConfigValue]`, `[ConfigSecret]`)
- ✅ **ConfigGenerators.Generator** - Roslyn-based source generator using incremental generation
- ✅ **ConfigGenerators.Sample** - Real-world examples (Database, Azure, External API configs)

### Generated Output
- Consolidated JSON file with all config entries and secrets
- Includes: keys, types, default values, descriptions, required flags
- Separate sections for App Configuration vs Key Vault entries

### Documentation
- 📖 **README.md** - Overview, quick start, features, and benefits
- 📖 **DEVELOPER_GUIDE.md** - Comprehensive usage guide with patterns and best practices
- 📖 **examples/bicep/README.md** - Complete DevOps integration guide

### Infrastructure Integration
- 🏗️ Bicep templates for Azure App Configuration and Key Vault provisioning
- 🔄 Azure DevOps and GitHub Actions pipeline examples
- 📋 Parameter files for environment-specific deployments

## Key Benefits

### For Developers
- Strongly-typed configuration with IntelliSense
- Compile-time validation (no more runtime config errors)
- Works seamlessly with IOptions pattern
- Easy refactoring with full IDE support

### For DevOps
- Automated infrastructure provisioning from generated metadata
- No manual config key maintenance
- Self-documenting infrastructure requirements
- Reduced deployment errors and incidents

### For Teams
- Single source of truth (code defines config needs)
- Configuration requirements tracked in version control
- Faster environment setup and onboarding
- Eliminates drift between code and infrastructure

## Example Usage

### Developer writes:
```csharp
[GenerateConfig("Database", Description = "Database connection settings")]
public class DatabaseConfig
{
    [ConfigValue(Required = true, Description = "Database server hostname")]
    public string Host { get; set; }

    [ConfigValue(DefaultValue = "5432")]
    public int Port { get; set; }

    [ConfigSecret(Required = true, Description = "Database password")]
    public string Password { get; set; }
}
```

### Generator produces:
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

### DevOps provisions with Bicep:
```bicep
var configMetadata = loadJsonContent('configuration-metadata.json')

resource configValues 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = [
  for entry in configMetadata.configEntries: {
    // Automatically provision all config entries
  }
]
```

## Technical Implementation

- **Incremental Source Generator** - Uses Roslyn's `IIncrementalGenerator` for optimal build performance
- **Compile-Time Generation** - Zero runtime overhead, all metadata extracted during compilation
- **Consolidated Output** - Single JSON file per project/assembly for all configuration needs
- **Type-Aware** - Understands C# types and outputs friendly names (string, int, bool, etc.)

## Testing Notes

The solution is ready to build and test with .NET SDK. To verify:

```bash
dotnet build ConfigGenerators.sln
dotnet run --project src/ConfigGenerators.Sample
```

The generated `configuration-metadata.json` can be found in:
```
src/ConfigGenerators.Sample/obj/Generated/ConfigGenerators.Generator/ConfigSourceGenerator/
```

## Files Changed

- 22 files changed, 2224 insertions(+)
- New projects: Attributes, Generator, Sample
- Comprehensive documentation and examples
- Ready-to-use Bicep templates

## Next Steps After Merge

1. Package as NuGet packages for distribution
2. Add CI/CD pipeline for automated releases
3. Consider additional features:
   - Array/list property support
   - Environment-specific value suggestions
   - Terraform output format
   - Direct Azure CLI integration

---

**Branch:** `claude/config-source-generator-uoZcQ`
**Repository:** `tonyjoanes/config-generators`

This implementation provides a production-ready foundation for eliminating configuration drift and automating infrastructure provisioning based on application code requirements.
