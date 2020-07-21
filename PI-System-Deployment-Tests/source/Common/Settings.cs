using System;
using System.Configuration;
using System.Security.Cryptography;
using System.Text;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class provides access to the appSettings section in the app.config file.
    /// </summary>
    internal static class Settings
    {
        public static string PIDataArchive => GetValue("PIDataArchive", isRequired: true);
        public static string AFServer => GetValue("AFServer", isRequired: true);
        public static string AFDatabase => GetValue("AFDatabase", isRequired: true);
        public static string PIAnalysisService => GetValue("PIAnalysisService", isRequired: true);
        public static string PINotificationsService => GetValue(NotificationTests.KeySetting);
        public static string PINotificationsRecipientEmailAddress => "OSItest@test.com";
        public static string PIWebAPI => GetValue(PIWebAPITests.KeySetting);
        public static string PIWebAPICrawler => GetValue("PIWebAPICrawler");
        public static string PIWebAPIUser => DecryptSetting(GetValue("PIWebAPIUser"));
        public static string PIWebAPIPassword => DecryptSetting(GetValue("PIWebAPIPassword"));
        public static string PIWebAPIConfigurationInstance => GetValue("PIWebAPIConfigurationInstance");
        public static string PIVisionServer => GetValue(Vision3Tests.KeySetting);
        public static string PIManualLogger => GetValue(ManualLoggerTests.KeySetting);
        public static int PIManualLoggerPort => GetIntegerValue(ManualLoggerTests.PortSetting, isRequired: true);
        public static string PIManualLoggerSQL => GetValue(ManualLoggerTests.SQLSetting);
        public static string PIManualLoggerWebImpersonationUser => GetValue(ManualLoggerTests.ImpersonationUserSetting);
        public static bool PIDataLinkTests => GetBooleanValue(DataLinkAFTests.KeySetting);
        public static bool PISqlClientTests => GetBooleanValue(PISystemDeploymentTests.PISqlClientTests.KeySetting);
        public static bool SkipCertificateValidation => GetBooleanValue("SkipCertificateValidation");

        /// <summary>
        /// Gets the string value from the AppSettings section of the App.config file.
        /// </summary>
        /// <param name="settingName">Name of the setting.</param>
        /// <param name="isRequired">If true, the setting to be used is required (default false).</param>
        /// <returns>The setting value for the specified name.</returns>
        /// <exception cref="ArgumentNullException">
        /// This exception if thrown if the isRequired parameter is true and the setting value is not specified.
        /// </exception>
        public static string GetValue(string settingName, bool isRequired = false)
        {
            string settingValue = ConfigurationManager.AppSettings[settingName];

            if (isRequired && string.IsNullOrWhiteSpace(settingValue))
                throw new ArgumentNullException($"The setting '{settingName}' is missing in App.config.");
            return settingValue;
        }

        /// <summary>
        /// Gets the Boolean value from the AppSettings section of the App.config file.
        /// </summary>
        /// <param name="settingName">Name of the setting.</param>
        /// <param name="isRequired">If true, the setting to be used is required (default false).</param>
        /// <returns>
        /// The converted Boolean value for the given setting name.
        /// Returns false if a not-required setting is missing.
        /// <exception cref="ArgumentNullException">
        /// This exception if thrown if the isRequired parameter is true and the setting value is not specified.
        /// </exception>
        /// </returns>
        /// <exception cref="InvalidOperationException">
        /// This exception if thrown the setting value can not be converted to a Boolean.
        /// </exception>
        public static bool GetBooleanValue(string settingName, bool isRequired = false)
        {
            string settingValue = GetValue(settingName, isRequired);

            if (string.IsNullOrWhiteSpace(settingValue))
                return false;

            if (bool.TryParse(settingValue, out bool result))
                return result;

            throw new InvalidOperationException($"The setting '{settingName}' has an invalid value in App.config.");
        }

        /// <summary>
        /// Gets the integer value from the AppSettings section of the App.config file.
        /// </summary>
        /// <param name="settingName">Name of the setting.</param>
        /// <param name="isRequired">If true, the setting to be used is required (default false).</param>
        /// <returns>
        /// The converted integer value for the given setting name.
        /// Returns 0 if a not-required setting is missing.
        /// </returns>
        /// <exception cref="ArgumentNullException">
        /// This exception if thrown if the isRequired parameter is true and the setting value is not specified.
        /// </exception>
        /// <exception cref="InvalidOperationException">
        /// This exception if thrown if the setting value can not be converted to an integer.
        /// </exception>
        public static int GetIntegerValue(string settingName, bool isRequired = false)
        {
            string settingValue = GetValue(settingName, isRequired);

            if (string.IsNullOrWhiteSpace(settingValue))
                return 0;

            if (int.TryParse(settingValue, out int result))
                return result;

            throw new InvalidOperationException($"The setting '{settingName}' has an invalid value in App.config.");
        }

        /// <summary>
        /// Parses an encrypted string from the App.config file.
        /// </summary>
        /// <param name="encryptedString">The string encrypted as a byte array.</param>
        /// <returns>The byte array from the encrypted string.</returns>
        private static byte[] ParseEncryptedString(string encryptedString)
        {
            string[] arr = encryptedString.Split('-');
            byte[] array = new byte[arr.Length];

            for (int i = 0; i < arr.Length; i++)
            {
                array[i] = Convert.ToByte(arr[i], 16);
            }

            return array;
        }

        /// <summary>
        /// Unencrypts an encrypted setting from the App.config file.
        /// </summary>
        /// <param name="setting">The value of the encrypted setting.</param>
        /// <returns>The unencrypted string.</returns>
        private static string DecryptSetting(string setting)
        {
            byte[] encyptedBytes = ParseEncryptedString(setting);

            string encryptionKey = GetValue("PIWebAPIEncryptionID");
            byte[] encryptionKeyBytes = ParseEncryptedString(encryptionKey);

            try
            {
                byte[] bytes = ProtectedData.Unprotect(encyptedBytes, encryptionKeyBytes, DataProtectionScope.CurrentUser);
                return Encoding.ASCII.GetString(bytes);
            }
            catch (CryptographicException ex)
            {
                throw new CryptographicException("Ensure you are running as the same user that encrypted the PI Web API credentials.", ex);
            }
        }
    }
}
