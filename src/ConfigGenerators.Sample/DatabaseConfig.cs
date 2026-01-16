using ConfigGenerators.Attributes;

namespace ConfigGenerators.Sample
{
    [GenerateConfig("Database", Description = "Database connection settings")]
    public class DatabaseConfig
    {
        [ConfigValue(
            Description = "The database server hostname",
            Required = true)]
        public string Host { get; set; } = string.Empty;

        [ConfigValue(
            DefaultValue = "5432",
            Description = "The database server port")]
        public int Port { get; set; }

        [ConfigValue(
            Description = "The database name",
            Required = true)]
        public string DatabaseName { get; set; } = string.Empty;

        [ConfigValue(
            Description = "The database username",
            Required = true)]
        public string Username { get; set; } = string.Empty;

        [ConfigSecret(
            Description = "The database password",
            Required = true)]
        public string Password { get; set; } = string.Empty;

        [ConfigValue(
            DefaultValue = "30",
            Description = "Connection timeout in seconds")]
        public int TimeoutSeconds { get; set; }

        [ConfigSecret(
            Description = "SSL certificate for database connection",
            Required = false)]
        public string? SslCertificate { get; set; }
    }
}
