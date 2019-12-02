using System;
using OSIsoft.AF;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Enumeration of different test requirements for AF tests.
    /// </summary>
    public enum AFTestCondition
    {
        /// <summary>
        /// Specifies that the 2.10.7 Patch is applied
        /// </summary>
        PATCH2107,

        /// <summary>
        /// Specifies that the latest Patch is applied
        /// </summary>
        CURRENTPATCH,
    }

    /// <summary>
    /// AF FactAttribute class for AF Tests
    /// skips tests based on criteria defined in enumeration set.
    /// </summary>
    public sealed class AFFactAttribute : OptionalFactAttribute
    {
        /// <summary>
        /// Skips a test based on the passed condition.
        /// </summary>
        public AFFactAttribute(AFTestCondition feature)
            : base(AFTests.KeySetting, AFTests.KeySettingTypeCode)
        {
            // Return if the Skip property has been changed in the base constructor
            if (!string.IsNullOrEmpty(Skip))
                return;
            if (feature.Equals(AFTestCondition.PATCH2107))
            {
                Version sdkVersion = new Version(AFGlobalSettings.SDKVersion);
                if (sdkVersion < new Version("2.10.7"))
                {
                    Skip = "Warning! You do not have the critical patch: PI AF 2018 SP3 Patch 1 (2.10.7)! Please consider upgrading to avoid data loss! You are currently on " + sdkVersion;
                }
            }
            else if (feature.Equals(AFTestCondition.CURRENTPATCH))
            {
                Version sdkVersion = new Version(AFGlobalSettings.SDKVersion);
                if (sdkVersion < new Version("2.10.7"))
                {
                    Skip = "Warning! You do not have the latest update: PI AF 2018 SP3 Patch 1 (2.10.7)! Please consider upgrading! You are currently on " + sdkVersion;
                }
            }
        }
    }
}
