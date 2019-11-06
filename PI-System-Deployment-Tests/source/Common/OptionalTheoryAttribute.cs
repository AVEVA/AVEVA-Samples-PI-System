using System;
using Xunit;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Skips a theory test based on the setting value.
    /// </summary>
    public class OptionalTheoryAttribute : TheoryAttribute
    {
        /// <summary>
        /// Constructor for the OptionalTheoryAttribute class.
        /// </summary>
        /// <param name="setting">Name of setting in the App.config file.</param>
        /// <param name="type">Type of setting value in the App.config file.</param>
        public OptionalTheoryAttribute(string setting, TypeCode type)
        {
            switch (type)
            {
                case TypeCode.Boolean:
                    try
                    {
                        if (!Settings.GetBooleanValue(setting))
                        {
                            Skip = $"Test skipped because '{setting}' setting is missing or its value is 'False' in App.config file.";
                        }
                    }
                    catch (InvalidOperationException e)
                    {
                        // When the setting has a non-boolean value, an InvalidOperationException will be thrown.
                        Skip = e.Message;
                    }

                    break;
                case TypeCode.String:
                    if (string.IsNullOrWhiteSpace(Settings.GetValue(setting)))
                    {
                        Skip = $"Test skipped because '{setting}' setting is missing or its value is empty in App.config file.";
                    }

                    break;
                default:
                    throw new InvalidOperationException($"{type} is not a supported setting type.");
            }
        }
    }
}
