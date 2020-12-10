namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Xunit TheoryAttribute class for PI System Deployment Tests that
    /// skips tests based on criteria defined in enumeration set.
    /// </summary>
    public sealed class GenericTheoryAttribute : OptionalTheoryAttribute
    {
        /// <summary>
        /// Skips a test based on the passed condition.
        /// </summary>
        public GenericTheoryAttribute(TestCondition feature, bool error)
                : base(AFTests.KeySetting, AFTests.KeySettingTypeCode)
        {
            // Return if the Skip property has been changed in the base constructor
            if (!string.IsNullOrEmpty(Skip))
                return;

            GenericAttribute.InitializeSkip(feature, error, out string skip);
            Skip = skip;
        }
    }
}
