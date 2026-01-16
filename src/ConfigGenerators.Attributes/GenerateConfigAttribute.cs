using System;

namespace ConfigGenerators.Attributes
{
    /// <summary>
    /// Marks a configuration class to be included in generated configuration files.
    /// </summary>
    [AttributeUsage(AttributeTargets.Class, AllowMultiple = false, Inherited = false)]
    public sealed class GenerateConfigAttribute : Attribute
    {
        /// <summary>
        /// The configuration section name (e.g., "Database", "Logging").
        /// If not specified, the class name will be used.
        /// </summary>
        public string? SectionName { get; }

        /// <summary>
        /// Optional description of this configuration section.
        /// </summary>
        public string? Description { get; set; }

        public GenerateConfigAttribute(string? sectionName = null)
        {
            SectionName = sectionName;
        }
    }
}
