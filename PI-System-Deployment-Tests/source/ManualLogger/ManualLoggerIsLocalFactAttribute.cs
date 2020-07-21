using System;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Skips a test based on the passed condition.
    /// </summary>
    public sealed class ManualLoggerIsLocalFactAttribute : OptionalFactAttribute
    {
        /// <summary>
        /// Constructor for the ManualLoggerFactAttribute class.
        /// </summary>
        public ManualLoggerIsLocalFactAttribute()
            : base(ManualLoggerTests.KeySetting, ManualLoggerTests.KeySettingTypeCode)
        {
            // Return if the Skip property has been changed in the base constructor
            if (!string.IsNullOrEmpty(Skip))
                return;

            try
            {
                // Skip the test if Manual Logger isn't installed on the local machine.
                if (!Utils.IsRunningOnTargetServer(Settings.PIManualLogger))
                    Skip = "Test skipped because PI Manual Logger is not installed on the local machine.";
            }
            catch (Exception ex)
            {
                Skip = $"Test skipped because PI Manual Logger could not be loaded due to the error [{ex.Message}].";
            }
        }
    }
}
