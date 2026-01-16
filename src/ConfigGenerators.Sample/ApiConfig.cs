using ConfigGenerators.Attributes;

namespace ConfigGenerators.Sample
{
    [GenerateConfig("ExternalApi")]
    public class ApiConfig
    {
        [ConfigValue(
            Description = "External API base URL",
            Required = true)]
        public string BaseUrl { get; set; } = string.Empty;

        [ConfigSecret(
            Description = "API authentication key")]
        public string ApiKey { get; set; } = string.Empty;

        [ConfigValue(
            DefaultValue = "60",
            Description = "Request timeout in seconds")]
        public int TimeoutSeconds { get; set; }

        [ConfigValue(
            DefaultValue = "3",
            Description = "Number of retry attempts")]
        public int MaxRetries { get; set; }
    }
}
