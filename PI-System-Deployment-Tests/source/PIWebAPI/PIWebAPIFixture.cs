using System;
using System.Collections.Generic;
using System.Configuration;
using System.Linq;
using System.Net;
using System.Text;
using Newtonsoft.Json.Linq;
using OSIsoft.AF;
using OSIsoft.AF.Asset;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// The PIWebAPIFixture is a partial test context class to be shared in PIWebAPI related
    /// xUnit test classes.
    /// </summary>
    /// <remarks>
    /// xUnit.net ensures that the fixture instance will be created before any tests run and
    /// when all tests are done will clean up the fixture object with 'Dispose' call.
    /// This fixture includes helper functions isolated to PI DataArchive related calls.
    /// See Utils.cs for more general test helper functions.
    /// </remarks>
    public sealed partial class PIWebAPIFixture : IDisposable
    {
        private const int Port = 443;
        private const string Website = "piwebapi";

        /// <summary>
        /// Creates an instance of the PIWebAPIFixture class.
        /// </summary>
        public PIWebAPIFixture()
        {
            var clientCopy = Client;
            var configElementCopy = ConfigElement;
            var disableWriteCopy = DisableWrites;
            var anonymousAuthenticationCopy = AnonymousAuthentication;

            GetWebApiClient(ref clientCopy, ref configElementCopy, ref disableWriteCopy, ref anonymousAuthenticationCopy);
            Client = clientCopy;
            ConfigElement = configElementCopy;
            DisableWrites = disableWriteCopy;
            AnonymousAuthentication = anonymousAuthenticationCopy;

            if (SkipReason == null)
            {
                // Only need to set up skip reasons once, save results in static property
                SkipReason = new Dictionary<PIWebAPITestCondition, string>();

                // Authenticate Skip Reason
                string skipReason = null;
                if (AnonymousAuthentication)
                {
                    skipReason = "Test skipped because Anonymous Authentication is allowed.";
                }

                SkipReason.Add(PIWebAPITestCondition.Authenticate, skipReason);

                // Indexed Search Skip Reason
                skipReason = null;
                try
                {
                    var checkForSearch = JObject.Parse(Client.DownloadString(HomePageUrl));
                    if (checkForSearch["Links"]["Search"] == null)
                        skipReason = $"Test skipped because the Search endpoint was not found at [{HomePageUrl}].";
                }
                catch (Exception ex)
                {
                    skipReason = $"Test skipped because PI Web API could not be loaded: [{ex.Message}].";
                }

                SkipReason.Add(PIWebAPITestCondition.IndexedSearch, skipReason);

                // OMF Skip Reason
                skipReason = null;
                try
                {
                    var checkForOMF = JObject.Parse(Client.DownloadString(HomePageUrl));
                    if (checkForOMF["Links"]["Omf"] == null)
                        skipReason = $"Test skipped because the OMF endpoint was not found at [{HomePageUrl}].";
                }
                catch (Exception ex)
                {
                    skipReason = $"Test skipped because PI Web API could not be loaded: [{ex.Message}].";
                }

                SkipReason.Add(PIWebAPITestCondition.Omf, skipReason);
            }
        }

        /// <summary>
        /// Collection of reasons to skip tests. Used by PIWebAPIFactAttribute.
        /// </summary>
        public static Dictionary<PIWebAPITestCondition, string> SkipReason { get; private set; }

        /// <summary>
        /// The WebClient used to for REST endpoint calls.
        /// </summary>
        public WebClient Client { get; private set; } = new WebClient { UseDefaultCredentials = true };

        /// <summary>
        /// The URL used for PI Web API home page.
        /// </summary>
        public string HomePageUrl => $"https://{Settings.PIWebAPI}:{Port}/{Website}";

        /// <summary>
        /// The AFFixture used to communicate directly with the test PI System.
        /// </summary>
        public AFFixture AFFixture { get; private set; } = new AFFixture();

        /// <summary>
        /// The PIFixture used to communicate directly with the test PI Server.
        /// </summary>
        public PIFixture PIFixture { get; private set; } = new PIFixture();

        /// <summary>
        /// Represents whether PI Web API configuration disallows write actions.
        /// </summary>
        public bool DisableWrites { get; private set; }

        /// <summary>
        /// The AF Element where PI Web API configuration is stored.
        /// </summary>
        public AFElement ConfigElement { get; private set; }

        /// <summary>
        /// Represents whether PI Web API is configured to use Anonymous authentication.
        /// </summary>
        public bool AnonymousAuthentication { get; private set; }

        /// <summary>
        /// Cleans up resources when tests are finished.
        /// </summary>
        public void Dispose()
        {
            AFFixture.Dispose();
            PIFixture.Dispose();
            Client.Dispose();
            ServicePointManager.ServerCertificateValidationCallback = null;
        }

        internal static void GetWebApiClient(ref WebClient client, ref AFElement configElement, ref bool disableWrites, ref bool anonymousAuthentication)
        {
            PISystem pisys = AFFixture.GetPISystemFromConfig();
            if (client == null)
                client = new WebClient { UseDefaultCredentials = true };

            client.Headers.Add("X-Requested-With", "XMLHttpRequest");

            ServicePointManager.ServerCertificateValidationCallback = null;
            if (Settings.SkipCertificateValidation)
#pragma warning disable CA5359 // Do Not Disable Certificate Validation
                ServicePointManager.ServerCertificateValidationCallback = (a, b, c, d) => true;
#pragma warning restore CA5359 // Do Not Disable Certificate Validation

            var configurationElement = Settings.PIWebAPI.Split('.')[0];
            if (!string.IsNullOrEmpty(Settings.PIWebAPIConfigurationInstance))
            {
                configurationElement = Settings.PIWebAPIConfigurationInstance;
            }

            var path = $"\\\\{Settings.AFServer}\\Configuration\\OSIsoft\\PI Web API\\{configurationElement}\\System Configuration";
            var results = AFElement.FindElementsByPath(new string[] { path }, pisys);
            configElement = results.FirstOrDefault();
            if (!Equals(configElement, null))
            {
                disableWrites = (bool)configElement.Attributes["DisableWrites"].GetValue().Value;
                var methods = (string[])configElement.Attributes["AuthenticationMethods"].GetValue().Value;
                if (methods.Length > 0)
                {
                    if (string.Equals(methods[0], "Basic", StringComparison.OrdinalIgnoreCase))
                    {
                        client.UseDefaultCredentials = false;
                        var credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes(Settings.PIWebAPIUser + ":" + Settings.PIWebAPIPassword));
                        client.Headers[HttpRequestHeader.Authorization] = "Basic " + credentials;
                    }
                    else if (string.Equals(methods[0], "Anonymous", StringComparison.OrdinalIgnoreCase))
                    {
                        anonymousAuthentication = true;
                    }
                }
                else
                {
                    throw new InvalidOperationException("PI Web API Authentication Methods are not specified in the Configuration database.");
                }
            }
        }
    }
}
