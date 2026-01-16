using System.Collections.Generic;
using System.Linq;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Text;
using ConfigGenerators.Generator.Models;

namespace ConfigGenerators.Generator
{
    [Generator]
    public class ConfigSourceGenerator : IIncrementalGenerator
    {
        private const string GenerateConfigAttributeName = "ConfigGenerators.Attributes.GenerateConfigAttribute";
        private const string ConfigValueAttributeName = "ConfigGenerators.Attributes.ConfigValueAttribute";
        private const string ConfigSecretAttributeName = "ConfigGenerators.Attributes.ConfigSecretAttribute";

        public void Initialize(IncrementalGeneratorInitializationContext context)
        {
            // Find all classes with the GenerateConfig attribute
            var classDeclarations = context.SyntaxProvider
                .CreateSyntaxProvider(
                    predicate: static (s, _) => IsSyntaxTargetForGeneration(s),
                    transform: static (ctx, _) => GetSemanticTargetForGeneration(ctx))
                .Where(static m => m is not null);

            // Combine all classes and generate a single output file
            var compilationAndClasses = context.CompilationProvider.Combine(classDeclarations.Collect());

            context.RegisterSourceOutput(compilationAndClasses,
                static (spc, source) => Execute(source.Left, source.Right!, spc));
        }

        private static bool IsSyntaxTargetForGeneration(SyntaxNode node)
        {
            return node is ClassDeclarationSyntax classDeclaration &&
                   classDeclaration.AttributeLists.Count > 0;
        }

        private static ClassDeclarationSyntax? GetSemanticTargetForGeneration(GeneratorSyntaxContext context)
        {
            var classDeclaration = (ClassDeclarationSyntax)context.Node;

            foreach (var attributeList in classDeclaration.AttributeLists)
            {
                foreach (var attribute in attributeList.Attributes)
                {
                    var symbol = context.SemanticModel.GetSymbolInfo(attribute).Symbol;
                    if (symbol is not IMethodSymbol attributeSymbol)
                        continue;

                    var attributeContainingTypeSymbol = attributeSymbol.ContainingType;
                    var fullName = attributeContainingTypeSymbol.ToDisplayString();

                    if (fullName == GenerateConfigAttributeName)
                    {
                        return classDeclaration;
                    }
                }
            }

            return null;
        }

        private static void Execute(Compilation compilation, IEnumerable<ClassDeclarationSyntax> classes, SourceProductionContext context)
        {
            if (!classes.Any())
                return;

            var metadata = new ConfigurationMetadata();

            foreach (var classDeclaration in classes)
            {
                var semanticModel = compilation.GetSemanticModel(classDeclaration.SyntaxTree);
                var classSymbol = semanticModel.GetDeclaredSymbol(classDeclaration);

                if (classSymbol is null)
                    continue;

                ProcessClass(classSymbol, metadata);
            }

            // Generate the JSON output
            var json = GenerateJson(metadata);
            context.AddSource("configuration-metadata.json", SourceText.From(json, Encoding.UTF8));
        }

        private static void ProcessClass(INamedTypeSymbol classSymbol, ConfigurationMetadata metadata)
        {
            // Get the section name from the attribute or use class name
            var generateConfigAttr = classSymbol.GetAttributes()
                .FirstOrDefault(a => a.AttributeClass?.ToDisplayString() == GenerateConfigAttributeName);

            var sectionName = generateConfigAttr?.ConstructorArguments.FirstOrDefault().Value as string
                              ?? classSymbol.Name.Replace("Config", "").Replace("Options", "").Replace("Settings", "");

            var sectionDescription = generateConfigAttr?.NamedArguments
                .FirstOrDefault(kvp => kvp.Key == "Description").Value.Value as string;

            // Process all properties
            foreach (var member in classSymbol.GetMembers().OfType<IPropertySymbol>())
            {
                ProcessProperty(member, sectionName, sectionDescription, metadata);
            }
        }

        private static void ProcessProperty(IPropertySymbol property, string sectionName, string? sectionDescription, ConfigurationMetadata metadata)
        {
            var configValueAttr = property.GetAttributes()
                .FirstOrDefault(a => a.AttributeClass?.ToDisplayString() == ConfigValueAttributeName);

            var configSecretAttr = property.GetAttributes()
                .FirstOrDefault(a => a.AttributeClass?.ToDisplayString() == ConfigSecretAttributeName);

            if (configValueAttr is null && configSecretAttr is null)
                return;

            var key = $"{sectionName}:{property.Name}";
            var valueType = GetFriendlyTypeName(property.Type);

            if (configSecretAttr is not null)
            {
                var description = configSecretAttr.NamedArguments
                    .FirstOrDefault(kvp => kvp.Key == "Description").Value.Value as string;
                var required = configSecretAttr.NamedArguments
                    .FirstOrDefault(kvp => kvp.Key == "Required").Value.Value as bool? ?? true;

                metadata.SecretEntries.Add(new SecretEntry
                {
                    Key = key,
                    ValueType = valueType,
                    Description = description,
                    Required = required,
                    SectionDescription = sectionDescription
                });
            }
            else if (configValueAttr is not null)
            {
                var defaultValue = configValueAttr.NamedArguments
                    .FirstOrDefault(kvp => kvp.Key == "DefaultValue").Value.Value as string;
                var description = configValueAttr.NamedArguments
                    .FirstOrDefault(kvp => kvp.Key == "Description").Value.Value as string;
                var required = configValueAttr.NamedArguments
                    .FirstOrDefault(kvp => kvp.Key == "Required").Value.Value as bool? ?? false;

                metadata.ConfigEntries.Add(new ConfigEntry
                {
                    Key = key,
                    ValueType = valueType,
                    DefaultValue = defaultValue,
                    Description = description,
                    Required = required,
                    SectionDescription = sectionDescription
                });
            }
        }

        private static string GetFriendlyTypeName(ITypeSymbol type)
        {
            return type.SpecialType switch
            {
                SpecialType.System_String => "string",
                SpecialType.System_Int32 => "int",
                SpecialType.System_Int64 => "long",
                SpecialType.System_Boolean => "bool",
                SpecialType.System_Double => "double",
                SpecialType.System_Decimal => "decimal",
                _ => type.Name
            };
        }

        private static string GenerateJson(ConfigurationMetadata metadata)
        {
            var sb = new StringBuilder();
            sb.AppendLine("{");
            sb.AppendLine("  \"configEntries\": [");

            for (int i = 0; i < metadata.ConfigEntries.Count; i++)
            {
                var entry = metadata.ConfigEntries[i];
                sb.AppendLine("    {");
                sb.AppendLine($"      \"key\": \"{entry.Key}\",");
                sb.AppendLine($"      \"type\": \"{entry.Type}\",");
                sb.AppendLine($"      \"valueType\": \"{entry.ValueType}\",");

                if (!string.IsNullOrEmpty(entry.DefaultValue))
                    sb.AppendLine($"      \"defaultValue\": \"{entry.DefaultValue}\",");

                if (!string.IsNullOrEmpty(entry.Description))
                    sb.AppendLine($"      \"description\": \"{EscapeJson(entry.Description)}\",");

                if (!string.IsNullOrEmpty(entry.SectionDescription))
                    sb.AppendLine($"      \"sectionDescription\": \"{EscapeJson(entry.SectionDescription)}\",");

                sb.AppendLine($"      \"required\": {entry.Required.ToString().ToLower()}");
                sb.Append("    }");

                if (i < metadata.ConfigEntries.Count - 1)
                    sb.AppendLine(",");
                else
                    sb.AppendLine();
            }

            sb.AppendLine("  ],");
            sb.AppendLine("  \"secretEntries\": [");

            for (int i = 0; i < metadata.SecretEntries.Count; i++)
            {
                var entry = metadata.SecretEntries[i];
                sb.AppendLine("    {");
                sb.AppendLine($"      \"key\": \"{entry.Key}\",");
                sb.AppendLine($"      \"type\": \"{entry.Type}\",");
                sb.AppendLine($"      \"valueType\": \"{entry.ValueType}\",");

                if (!string.IsNullOrEmpty(entry.Description))
                    sb.AppendLine($"      \"description\": \"{EscapeJson(entry.Description)}\",");

                if (!string.IsNullOrEmpty(entry.SectionDescription))
                    sb.AppendLine($"      \"sectionDescription\": \"{EscapeJson(entry.SectionDescription)}\",");

                sb.AppendLine($"      \"required\": {entry.Required.ToString().ToLower()}");
                sb.Append("    }");

                if (i < metadata.SecretEntries.Count - 1)
                    sb.AppendLine(",");
                else
                    sb.AppendLine();
            }

            sb.AppendLine("  ]");
            sb.AppendLine("}");

            return sb.ToString();
        }

        private static string EscapeJson(string value)
        {
            return value
                .Replace("\\", "\\\\")
                .Replace("\"", "\\\"")
                .Replace("\n", "\\n")
                .Replace("\r", "\\r")
                .Replace("\t", "\\t");
        }
    }
}
