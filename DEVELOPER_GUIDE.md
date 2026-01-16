# Developer Guide

This guide explains how to use Config Generators in your .NET applications.

## Table of Contents

- [Getting Started](#getting-started)
- [Basic Usage](#basic-usage)
- [Attribute Reference](#attribute-reference)
- [Common Patterns](#common-patterns)
- [Integration with IOptions](#integration-with-ioptions)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Getting Started

### Installation

Add the NuGet packages to your project:

```bash
dotnet add package ConfigGenerators.Attributes
dotnet add package ConfigGenerators.Generator
```

Or edit your `.csproj` directly:

```xml
<ItemGroup>
  <PackageReference Include="ConfigGenerators.Attributes" Version="1.0.0" />
  <PackageReference Include="ConfigGenerators.Generator" Version="1.0.0"
                    OutputItemType="Analyzer"
                    ReferenceOutputAssembly="false" />
</ItemGroup>
```

### Enable Generated File Visibility (Optional)

To see the generated JSON file during development:

```xml
<PropertyGroup>
  <EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>
  <CompilerGeneratedFilesOutputPath>$(BaseIntermediateOutputPath)Generated</CompilerGeneratedFilesOutputPath>
</PropertyGroup>
```

## Basic Usage

### 1. Create a Configuration Class

```csharp
using ConfigGenerators.Attributes;

namespace MyApp.Configuration
{
    [GenerateConfig("Database")]
    public class DatabaseConfig
    {
        [ConfigValue(Required = true)]
        public string Host { get; set; } = string.Empty;

        [ConfigValue(DefaultValue = "5432")]
        public int Port { get; set; }

        [ConfigSecret(Required = true)]
        public string Password { get; set; } = string.Empty;
    }
}
```

### 2. Register with IOptions

In your `Program.cs` or `Startup.cs`:

```csharp
// Read from appsettings.json and environment variables
builder.Services.Configure<DatabaseConfig>(
    builder.Configuration.GetSection("Database"));

// Or with Azure App Configuration + Key Vault
builder.Configuration.AddAzureAppConfiguration(options =>
{
    options.Connect(connectionString)
           .ConfigureKeyVault(kv => kv.SetCredential(new DefaultAzureCredential()));
});

builder.Services.Configure<DatabaseConfig>(
    builder.Configuration.GetSection("Database"));
```

### 3. Use in Your Code

```csharp
public class DatabaseService
{
    private readonly DatabaseConfig _config;

    public DatabaseService(IOptions<DatabaseConfig> config)
    {
        _config = config.Value;
    }

    public void Connect()
    {
        var connectionString = $"Host={_config.Host};Port={_config.Port};Password={_config.Password}";
        // ... connect to database
    }
}
```

### 4. Build and Extract Generated File

```bash
dotnet build
```

Find the generated file at:
```
obj/Generated/ConfigGenerators.Generator/ConfigSourceGenerator/configuration-metadata.json
```

## Attribute Reference

### `[GenerateConfig]`

Marks a class for configuration generation.

```csharp
[GenerateConfig("SectionName", Description = "What this config section is for")]
public class MyConfig { }
```

**When to use:**
- On any class that holds application configuration
- Typically on classes used with IOptions pattern

**Tips:**
- If you don't specify a section name, it derives from the class name
- `DatabaseConfig` → `"Database"`
- `MyApiOptions` → `"MyApi"`
- `AppSettings` → `"App"`

### `[ConfigValue]`

Marks a property as a standard configuration value (Azure App Configuration).

```csharp
[ConfigValue(
    DefaultValue = "default-value",
    Description = "Clear description of what this configures",
    Required = true)]
public string MyProperty { get; set; }
```

**When to use:**
- Non-sensitive configuration values
- Values that may differ per environment but aren't secret
- Examples: URLs, timeouts, feature flags, limits

**Tips:**
- Use `Required = true` for values that have no sensible default
- Provide defaults when there's a standard value that works in most cases
- Add descriptions to help DevOps teams understand what each value does

### `[ConfigSecret]`

Marks a property as a secret (Azure Key Vault).

```csharp
[ConfigSecret(
    Description = "Clear description of what this secret is",
    Required = true)]
public string MySecret { get; set; }
```

**When to use:**
- Passwords, connection strings with embedded credentials
- API keys, tokens
- Certificates, private keys
- Any sensitive data that should be encrypted at rest

**Tips:**
- Secrets default to `Required = true` (unlike ConfigValue)
- Set `Required = false` only for truly optional secrets
- Never include actual secret values in code or comments

## Common Patterns

### Multiple Configuration Sections

Organize related config into separate classes:

```csharp
[GenerateConfig("Database")]
public class DatabaseConfig
{
    [ConfigValue(Required = true)]
    public string Host { get; set; } = string.Empty;

    [ConfigSecret]
    public string Password { get; set; } = string.Empty;
}

[GenerateConfig("Redis")]
public class RedisConfig
{
    [ConfigValue(Required = true)]
    public string Host { get; set; } = string.Empty;

    [ConfigSecret]
    public string Password { get; set; } = string.Empty;
}

[GenerateConfig("Email")]
public class EmailConfig
{
    [ConfigValue]
    public string SmtpServer { get; set; } = string.Empty;

    [ConfigSecret]
    public string ApiKey { get; set; } = string.Empty;
}
```

### Hierarchical Configuration

Use section names to create hierarchy:

```csharp
[GenerateConfig("Logging:Application")]
public class ApplicationLoggingConfig
{
    [ConfigValue(DefaultValue = "Information")]
    public string MinLevel { get; set; } = string.Empty;
}

[GenerateConfig("Logging:External")]
public class ExternalLoggingConfig
{
    [ConfigValue]
    public string EndpointUrl { get; set; } = string.Empty;

    [ConfigSecret]
    public string ApiKey { get; set; } = string.Empty;
}
```

Generates:
- `Logging:Application:MinLevel`
- `Logging:External:EndpointUrl`
- `Logging:External:ApiKey`

### Feature Flags

```csharp
[GenerateConfig("Features")]
public class FeatureFlags
{
    [ConfigValue(DefaultValue = "false", Description = "Enable new dashboard UI")]
    public bool EnableNewDashboard { get; set; }

    [ConfigValue(DefaultValue = "false", Description = "Enable experimental API endpoints")]
    public bool EnableBetaApi { get; set; }

    [ConfigValue(DefaultValue = "100", Description = "Maximum concurrent uploads")]
    public int MaxConcurrentUploads { get; set; }
}
```

### Connection Strings

```csharp
[GenerateConfig("ConnectionStrings")]
public class ConnectionStrings
{
    [ConfigSecret(Description = "Primary database connection string")]
    public string Database { get; set; } = string.Empty;

    [ConfigSecret(Description = "Azure Service Bus connection string")]
    public string ServiceBus { get; set; } = string.Empty;

    [ConfigSecret(Description = "Azure Storage connection string")]
    public string Storage { get; set; } = string.Empty;
}
```

### External Service Configuration

```csharp
[GenerateConfig("PaymentGateway", Description = "Third-party payment service configuration")]
public class PaymentGatewayConfig
{
    [ConfigValue(Required = true, Description = "Payment gateway API base URL")]
    public string BaseUrl { get; set; } = string.Empty;

    [ConfigValue(Required = true, Description = "Merchant ID")]
    public string MerchantId { get; set; } = string.Empty;

    [ConfigSecret(Description = "API secret key")]
    public string SecretKey { get; set; } = string.Empty;

    [ConfigValue(DefaultValue = "30", Description = "Timeout in seconds")]
    public int TimeoutSeconds { get; set; }

    [ConfigValue(DefaultValue = "true", Description = "Use sandbox environment")]
    public bool UseSandbox { get; set; }
}
```

## Integration with IOptions

### Basic Setup

```csharp
// Program.cs (.NET 6+)
var builder = WebApplication.CreateBuilder(args);

// Register all your config classes
builder.Services.Configure<DatabaseConfig>(
    builder.Configuration.GetSection("Database"));
builder.Services.Configure<RedisConfig>(
    builder.Configuration.GetSection("Redis"));
builder.Services.Configure<EmailConfig>(
    builder.Configuration.GetSection("Email"));
```

### With Validation

Add validation to ensure required values are present:

```csharp
builder.Services.Configure<DatabaseConfig>(
    builder.Configuration.GetSection("Database"));

builder.Services.AddOptions<DatabaseConfig>()
    .Validate(config =>
    {
        return !string.IsNullOrEmpty(config.Host);
    }, "Database host is required")
    .ValidateOnStart(); // Fail fast if config is invalid
```

### With Azure App Configuration

```csharp
builder.Configuration.AddAzureAppConfiguration(options =>
{
    options
        .Connect(Environment.GetEnvironmentVariable("AppConfigConnectionString"))
        .Select(KeyFilter.Any)
        .ConfigureKeyVault(kv =>
        {
            kv.SetCredential(new DefaultAzureCredential());
        });
});

builder.Services.Configure<DatabaseConfig>(
    builder.Configuration.GetSection("Database"));
```

### Injecting Configuration

```csharp
// Option 1: IOptions (read once, cached)
public class MyService
{
    public MyService(IOptions<DatabaseConfig> config)
    {
        var dbConfig = config.Value;
    }
}

// Option 2: IOptionsSnapshot (per-request, supports reloading)
public class MyController : ControllerBase
{
    public MyController(IOptionsSnapshot<DatabaseConfig> config)
    {
        var dbConfig = config.Value;
    }
}

// Option 3: IOptionsMonitor (dynamic reloading)
public class MyBackgroundService
{
    private DatabaseConfig _config;

    public MyBackgroundService(IOptionsMonitor<DatabaseConfig> config)
    {
        _config = config.CurrentValue;

        // React to changes
        config.OnChange(newConfig =>
        {
            _config = newConfig;
            // Reconnect, reload, etc.
        });
    }
}
```

## Best Practices

### ✅ Do

1. **Use meaningful section names**
   ```csharp
   [GenerateConfig("Database")] // Good
   [GenerateConfig("Db")]       // Less clear
   ```

2. **Add descriptions to non-obvious config**
   ```csharp
   [ConfigValue(Description = "Maximum retry attempts before giving up")]
   public int MaxRetries { get; set; }
   ```

3. **Mark secrets appropriately**
   ```csharp
   [ConfigSecret] // Passwords, keys, tokens
   public string ApiKey { get; set; }
   ```

4. **Provide sensible defaults**
   ```csharp
   [ConfigValue(DefaultValue = "30")]
   public int TimeoutSeconds { get; set; }
   ```

5. **Use Required for critical values**
   ```csharp
   [ConfigValue(Required = true)]
   public string ApiEndpoint { get; set; }
   ```

### ❌ Don't

1. **Don't put sensitive values in ConfigValue**
   ```csharp
   // BAD - password should be a secret
   [ConfigValue]
   public string Password { get; set; }
   ```

2. **Don't use vague property names**
   ```csharp
   // BAD
   [ConfigValue]
   public string Url { get; set; }

   // GOOD
   [ConfigValue]
   public string ApiBaseUrl { get; set; }
   ```

3. **Don't skip descriptions for complex config**
   ```csharp
   // BAD - what does this threshold control?
   [ConfigValue]
   public int Threshold { get; set; }

   // GOOD
   [ConfigValue(Description = "Memory usage threshold (MB) before triggering garbage collection")]
   public int MemoryThresholdMb { get; set; }
   ```

4. **Don't create one giant config class**
   ```csharp
   // BAD - too many responsibilities
   [GenerateConfig("App")]
   public class AppConfig
   {
       public string DatabaseHost { get; set; }
       public string RedisHost { get; set; }
       public string EmailSmtp { get; set; }
       // ... 50 more properties
   }
   ```

## Troubleshooting

### Generated file not found

**Problem**: Can't find `configuration-metadata.json` after building.

**Solutions**:
1. Ensure the build succeeded: `dotnet build`
2. Check the generator is properly referenced:
   ```xml
   <ProjectReference Include="..\ConfigGenerators.Generator\ConfigGenerators.Generator.csproj"
                     OutputItemType="Analyzer"
                     ReferenceOutputAssembly="false" />
   ```
3. Look in the correct location: `obj/Generated/ConfigGenerators.Generator/ConfigSourceGenerator/`
4. Enable emit in your .csproj:
   ```xml
   <EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>
   ```

### Attributes not recognized

**Problem**: `GenerateConfigAttribute` not found.

**Solutions**:
1. Verify ConfigGenerators.Attributes is referenced
2. Check the namespace: `using ConfigGenerators.Attributes;`
3. Rebuild the solution

### Properties not appearing in output

**Problem**: Some properties are missing from generated JSON.

**Causes**:
- Property doesn't have `[ConfigValue]` or `[ConfigSecret]` attribute
- Property is not public
- Class doesn't have `[GenerateConfig]` attribute

### Build performance

**Problem**: Build is slower after adding the generator.

**Notes**:
- Source generators run during compilation
- Performance impact is typically minimal
- The generator uses incremental generation to minimize overhead

### IDE not showing generated files

**Problem**: Can't see generated files in Visual Studio/Rider.

**Solution**:
1. Enable emit (see above)
2. Rebuild
3. In Visual Studio: Show All Files in Solution Explorer
4. In Rider: Check "Show Generated Files" in project view

## Advanced Topics

### Custom Output Location

To output the JSON file to a specific location for easier access:

```xml
<Target Name="CopyConfigMetadata" AfterTargets="Build">
  <ItemGroup>
    <GeneratedConfig Include="$(BaseIntermediateOutputPath)Generated/**/configuration-metadata.json" />
  </ItemGroup>
  <Copy SourceFiles="@(GeneratedConfig)" DestinationFolder="$(OutputPath)" />
</Target>
```

### Multiple Projects

If you have multiple projects in a solution:
1. Each project generates its own metadata file
2. You can merge them in your build pipeline
3. Or reference the generator only in your main entry project

### CI/CD Integration

```yaml
# Azure Pipelines example
- task: DotNetCoreCLI@2
  inputs:
    command: 'build'

- task: CopyFiles@2
  inputs:
    SourceFolder: '$(Build.SourcesDirectory)'
    Contents: '**/configuration-metadata.json'
    TargetFolder: '$(Build.ArtifactStagingDirectory)'
    flattenFolders: true
```

## Getting Help

- Check the [README](README.md) for overview and quick start
- Review [Bicep examples](examples/bicep/README.md) for DevOps integration
- Open an issue on GitHub for bugs or feature requests

---

**Next Steps**: See the [Bicep Examples](examples/bicep/README.md) to learn how your DevOps team can use the generated files.
