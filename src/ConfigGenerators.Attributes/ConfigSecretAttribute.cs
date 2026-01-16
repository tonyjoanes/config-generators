using System;

namespace ConfigGenerators.Attributes
{
    /// <summary>
    /// Marks a property as a secret that should be stored in Azure Key Vault.
    /// </summary>
    [AttributeUsage(AttributeTargets.Property, AllowMultiple = false, Inherited = true)]
    public sealed class ConfigSecretAttribute : Attribute
    {
        /// <summary>
        /// Optional description of this secret.
        /// </summary>
        public string? Description { get; set; }

        /// <summary>
        /// Whether this secret is required.
        /// </summary>
        public bool Required { get; set; } = true;
    }
}
