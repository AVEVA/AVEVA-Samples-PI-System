using System;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Enumeration of different test requirements for PI Web API tests.
    /// </summary>
    public enum PIWebAPITestCondition
    {
        /// <summary>
        /// Specifies test that requires optional OMF feature of PI Web API.
        /// </summary>
        Omf,

        /// <summary>
        /// Specifies test that requires optional Indexed Search feature of PI Web API.
        /// </summary>
        IndexedSearch,

        /// <summary>
        /// Specifies test that requires anonymous authentication to be disabled.
        /// </summary>
        Authenticate,
    }

    /// <summary>
    /// PI Web API FactAttribute class for PI Web API Tests
    /// skips tests based on criteria defined in enumeration set.
    /// </summary>
    public sealed class PIWebAPIFactAttribute : OptionalFactAttribute
    {
        /// <summary>
        /// Skips a test based on the passed condition.
        /// </summary>
        public PIWebAPIFactAttribute(PIWebAPITestCondition feature)
            : base(PIWebAPITests.KeySetting, PIWebAPITests.KeySettingTypeCode)
        {
            // Return if the Skip property has been changed in the base constructor
            if (!string.IsNullOrEmpty(Skip))
                return;

            try
            {
                if (PIWebAPIFixture.SkipReason == null)
                {
                    using (var fixture = new PIWebAPIFixture())
                    {
                        // Constructor will create SkipReason collection, then dispose will clean up
                    }
                }

                Skip = PIWebAPIFixture.SkipReason[feature];
            }
            catch (Exception ex)
            {
                Skip = $"Test skipped due to the initialization error [{ex.Message}].";
            }
        }
    }
}
