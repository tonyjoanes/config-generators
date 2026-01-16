using ConfigGenerators.Attributes;

namespace ConfigGenerators.Sample
{
    [GenerateConfig("Azure", Description = "Azure service configuration")]
    public class AzureConfig
    {
        [ConfigValue(
            Description = "Azure storage account name",
            Required = true)]
        public string StorageAccountName { get; set; } = string.Empty;

        [ConfigSecret(
            Description = "Azure storage account key")]
        public string StorageAccountKey { get; set; } = string.Empty;

        [ConfigValue(
            Description = "Azure blob container name",
            DefaultValue = "uploads")]
        public string ContainerName { get; set; } = string.Empty;

        [ConfigValue(
            Description = "Enable Azure Application Insights",
            DefaultValue = "true")]
        public bool EnableApplicationInsights { get; set; }

        [ConfigSecret(
            Description = "Application Insights instrumentation key",
            Required = false)]
        public string? ApplicationInsightsKey { get; set; }
    }
}
