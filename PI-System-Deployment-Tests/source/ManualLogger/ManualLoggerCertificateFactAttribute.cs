namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Manual Logger FactAttribute for test requiring valid certificate.
    /// </summary>
    public sealed class ManualLoggerCertificateFactAttribute : OptionalFactAttribute
    {
        /// <summary>
        /// Skips test if certificate validation is disabled.
        /// </summary>
        public ManualLoggerCertificateFactAttribute()
            : base(ManualLoggerTests.KeySetting, ManualLoggerTests.KeySettingTypeCode)
        {
            // Return if the Skip property has been changed in the base constructor
            if (!string.IsNullOrEmpty(Skip))
                return;

            if (Settings.SkipCertificateValidation)
                Skip = "Test skipped because this test is intended for certificate validation, and SkipCertificateValidation is set to True.";
        }
    }
}
