using System;

namespace ConfigGenerators.Attributes
{
    /// <summary>
    /// Marks a property as a standard configuration value (Azure App Configuration).
    /// </summary>
    [AttributeUsage(AttributeTargets.Property, AllowMultiple = false, Inherited = true)]
    public sealed class ConfigValueAttribute : Attribute
    {
        /// <summary>
        /// Optional default value for this configuration entry.
        /// </summary>
        public string? DefaultValue { get; set; }

        /// <summary>
        /// Optional description of this configuration value.
        /// </summary>
        public string? Description { get; set; }

        /// <summary>
        /// Whether this configuration value is required.
        /// </summary>
        public bool Required { get; set; } = false;
    }
}
