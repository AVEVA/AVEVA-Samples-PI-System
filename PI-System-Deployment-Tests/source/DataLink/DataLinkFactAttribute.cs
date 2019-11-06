using System;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Skips a test based on the passed condition.
    /// </summary>
    public sealed class DataLinkFactAttribute : OptionalFactAttribute
    {
        /// <summary>
        /// Constructor for the DataLinkFactAttribute class.
        /// </summary>
        public DataLinkFactAttribute()
            : base(DataLinkAFTests.KeySetting, DataLinkAFTests.KeySettingTypeCode)
        {
            // Return if the Skip property has been changed in the base constructor
            if (!string.IsNullOrEmpty(Skip))
                return;

            try
            {
                // Skip DataLink tests if we can't create an AFLibrary instance
                if (!DataLinkUtils.DataLinkIsInstalled())
                    Skip = "Test skipped because DataLink was not installed.";
            }
            catch (Exception ex)
            {
                Skip = $"Test skipped because DataLink could not be loaded due to the error [{ex.Message}].";
            }
        }
    }
}
