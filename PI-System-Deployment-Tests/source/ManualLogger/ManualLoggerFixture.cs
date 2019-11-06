using System;
using System.Configuration;
using System.IO;
using System.Net;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// The ManualLoggerFixture is a test context class to be shared in ManualLogger related
    /// xUnit test classes.
    /// </summary>
    /// <remarks>
    /// xUnit.net ensures that the fixture instance will be created before any tests run and
    /// when all tests are done will clean up the fixture object with 'Dispose' call.
    /// This fixture includes helper functions isolated to PI DataArchive related calls.
    /// See Utils.cs for more general test helper functions.
    /// </remarks>
    public sealed class ManualLoggerFixture : IDisposable
    {
        private const string Website = "piml.web";

        /// <summary>
        /// Creates an instance of the ManualLoggerFixture.
        /// </summary>
        public ManualLoggerFixture()
        {
            Client.Headers.Add(HttpRequestHeader.ContentType, "application/json; charset=utf-8");
            if (Settings.SkipCertificateValidation)
                ServicePointManager.ServerCertificateValidationCallback = (a, b, c, d) => true;

            string installPath = Utils.GetRemoteEnvironmentVariable(Settings.PIManualLogger, "pihome").Replace(':', '$');
            if (!string.IsNullOrEmpty(installPath))
            {
                string webConfigPath = $"\\\\{Settings.PIManualLogger}\\{installPath}\\Piml.Web\\Web.config";
                if (File.Exists(webConfigPath))
                {
                    var fileMap = new ExeConfigurationFileMap()
                    {
                        ExeConfigFilename = webConfigPath,
                    };
                    WebConfig = ConfigurationManager.OpenMappedExeConfiguration(fileMap, ConfigurationUserLevel.None);
                }

                string webConfigPreviousPath = $"\\\\{Settings.PIManualLogger}\\{installPath}\\Piml.Web\\Web.config.previous";
                if (File.Exists(webConfigPreviousPath))
                {
                    var fileMap = new ExeConfigurationFileMap()
                    {
                        ExeConfigFilename = webConfigPreviousPath,
                    };
                    WebConfigPrevious = ConfigurationManager.OpenMappedExeConfiguration(fileMap, ConfigurationUserLevel.None);
                }
            }
        }

        /// <summary>
        /// The WebClient used to for REST endpoint calls.
        /// </summary>
        public WebClient Client { get; } = new WebClient { UseDefaultCredentials = true };

        /// <summary>
        /// The current Configuration of Manual Logger.
        /// </summary>
        public Configuration WebConfig { get; }

        /// <summary>
        /// The previous Configuration of Manual Logger, if the installation has been upgraded.
        /// </summary>
        public Configuration WebConfigPrevious { get; }

        /// <summary>
        /// The URL used for Manual Logger home page.
        /// </summary>
        public string HomePageUrl => $"https://{Settings.PIManualLogger}:{Settings.PIManualLoggerPort}/{Website}";

        /// <summary>
        /// Cleans up resources when tests are finished.
        /// </summary>
        public void Dispose()
        {
            Client.Dispose();
            ServicePointManager.ServerCertificateValidationCallback = null;
        }
    }
}
