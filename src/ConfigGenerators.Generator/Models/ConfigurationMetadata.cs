using System.Collections.Generic;

namespace ConfigGenerators.Generator.Models
{
    public class ConfigurationMetadata
    {
        public List<ConfigEntry> ConfigEntries { get; set; } = new List<ConfigEntry>();
        public List<SecretEntry> SecretEntries { get; set; } = new List<SecretEntry>();
    }

    public class ConfigEntry
    {
        public string Key { get; set; } = string.Empty;
        public string Type { get; set; } = "config";
        public string ValueType { get; set; } = string.Empty;
        public string? DefaultValue { get; set; }
        public string? Description { get; set; }
        public bool Required { get; set; }
        public string? SectionDescription { get; set; }
    }

    public class SecretEntry
    {
        public string Key { get; set; } = string.Empty;
        public string Type { get; set; } = "secret";
        public string ValueType { get; set; } = string.Empty;
        public string? Description { get; set; }
        public bool Required { get; set; }
        public string? SectionDescription { get; set; }
    }
}
