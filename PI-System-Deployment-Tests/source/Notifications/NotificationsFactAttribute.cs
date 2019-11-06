using System;
using OSIsoft.AF;
using OSIsoft.AF.Asset;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// The customized FactAttribute for notifications.
    /// If the target PI System doesn't have SMTP server configured, the test with
    /// this attribute will be skipped.
    /// </summary>
    public sealed class NotificationsFactAttribute : OptionalFactAttribute
    {
        private const string OSIsoft = "OSIsoft";
        private const string PIANO = "PIANO";
        private const string DeliveryChannel = "DeliveryChannel";
        private const string SMTPServer = "SMTPServer";
        private const string SMTPServerPort = "SMTPServerPort";
        private const string PlugInGuid = "194caabd-7307-4e86-b25e-4ddbdc370d2c";

        private static PISystem _piSystem;
        private static bool? _smtpServerIsConfigured;
        private static string _smtpServerErrorMessage;

        /// <summary>
        /// Constructor for the NotificationsFactAttribute class.
        /// </summary>
        public NotificationsFactAttribute()
            : base(NotificationTests.KeySetting, NotificationTests.KeySettingTypeCode)
        {
            // Return if the Skip property has been changed in the base constructor
            if (!string.IsNullOrEmpty(Skip))
                return;

            try
            {
                if (!_smtpServerIsConfigured.HasValue)
                {
                    (_smtpServerIsConfigured, _smtpServerErrorMessage) = SMTPServerIsConfigured();
                }

                if (_smtpServerIsConfigured.HasValue && !_smtpServerIsConfigured.Value)
                {
                    Skip = $"The test is skipped because the SMTP server is not configured or is not configured properly " +
                        $"for the email delivery channel. Reason: [{_smtpServerErrorMessage}].";
                }
            }
            catch (Exception)
            {
                Skip = "Test is skipped because the SMTP server is not configured or is not configured properly" +
                    " for the email delivery channel.";
            }
        }

        private static (bool, string) SMTPServerIsConfigured()
        {
            if (_piSystem == null)
            {
                var systems = new PISystems();
                if (systems.Contains(Settings.AFServer))
                {
                    _piSystem = systems[Settings.AFServer];
                    _piSystem.Connect();
                }
                else
                {
                    return (false, $"The AF Server [{Settings.AFServer}] does not exist or is not configured.");
                }
            }

            var configurationDb = _piSystem.Databases.ConfigurationDatabase;
            if (configurationDb != null)
            {
                if (configurationDb.Elements.Contains(OSIsoft))
                {
                    var pianoElement = configurationDb.Elements[OSIsoft].Elements[PIANO];
                    if (pianoElement != null)
                    {
                        var emailPlugInElement = pianoElement.Elements[DeliveryChannel];
                        if (emailPlugInElement != null)
                        {
                            var subEmailPlugInElement = emailPlugInElement.Elements[PlugInGuid];
                            if (subEmailPlugInElement != null)
                            {
                                if (ElementHasValidAttribute(subEmailPlugInElement, SMTPServer)
                                    && ElementHasValidAttribute(subEmailPlugInElement, SMTPServerPort))
                                {
                                    return (true, null);
                                }

                                return (false, "The email PlugIn doesn't have a valid SMTP server configuration.");
                            }

                            return (false, $"The [{PlugInGuid}] element is not found in the [{DeliveryChannel}] element in the configuration database.");
                        }

                        return (false, $"The [{DeliveryChannel}] element is not found in the [{PIANO}] element in the configuration database.");
                    }

                    return (false, $"The [{PIANO}] element is not found in the [{OSIsoft}] element in the configuration database.");
                }

                return (false, $"The [{OSIsoft}] element is not found in the configuration database.");
            }

            return (false, "The configuration database is not found.");
        }

        private static bool ElementHasValidAttribute(AFElement element, string attributeName)
        {
            var propertyAttribute = element.Attributes[attributeName];
            if (propertyAttribute != null)
            {
                var propertyValue = propertyAttribute.GetValue();
                if (propertyValue != null)
                {
                    if (propertyValue.Value == null)
                        return false;
                    if (propertyValue.Value is Exception)
                        return false;
                    if (propertyValue.Value is string stringValue && string.IsNullOrWhiteSpace(stringValue))
                        return false;
                    return true;
                }
            }

            return false;
        }
    }
}
