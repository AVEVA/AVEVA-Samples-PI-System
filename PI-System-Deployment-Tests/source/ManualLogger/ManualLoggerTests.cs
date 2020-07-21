using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Web.Configuration;
using System.Xml.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests various features of PI Manual Logger.
    /// </summary>
    public class ManualLoggerTests : IClassFixture<ManualLoggerFixture>
    {
        internal const string KeySetting = "PIManualLogger";
        internal const string PortSetting = "PIManualLoggerPort";
        internal const string SQLSetting = "PIManualLoggerSQL";
        internal const string ImpersonationUserSetting = "PIManualLoggerWebImpersonationUser";
        internal const TypeCode KeySettingTypeCode = TypeCode.String;
        internal const string NoPreviousWebConfig = "Did not find a Web.config.previous file. This expected for new installations of PI Manual Logger.";
        private const string ConnectionName = "PIMLDB";

        /// <summary>
        /// Constructor for ManualLoggerTests class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage Manual Logger connection and specific helper functions.</param>
        public ManualLoggerTests(ITestOutputHelper output, ManualLoggerFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private ManualLoggerFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Tests to see if the current PI Manual Logger Web patch is applied.
        /// </summary>
        /// <remarks>
        /// The test will be skipped if it is not run against PI Manual Logger Web on the test machine.
        /// Errors if the current patch is not applied with a message telling the user to upgrade.
        /// </remarks>
        [ManualLoggerIsLocalFact]
        public void HaveLatestPatchManualLoggerWeb()
        {
            var factAttr = new GenericFactAttribute(TestCondition.MANUALLOGGERWEBCURRENTPATCH, true);
            Assert.NotNull(factAttr);
        }

        /// <summary>
        /// Verifies that the PI Manual Logger API is running.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Call CheckConnection API</para>
        /// <para>Verify response indicates API is online</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void APIConnectionTest()
        {
            string url = $"{Fixture.HomePageUrl}/api/checkconnection";
            Output.WriteLine($"Verify Manual Logger API is running through {url}.");
            string content = Fixture.Client.DownloadString(url);
            bool isOnline = JsonConvert.DeserializeObject<bool>(content);
            Assert.True(isOnline, "PI Manual Logger API is not online. Verify the IIS and the web site are running.");
        }

        /// <summary>
        /// Verifies that the PI Manual Logger API makes connection to the SQL database.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Call CheckDBConnection API</para>
        /// <para>Verify response indicates SQL database is online</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void APIDBConnectionTest()
        {
            string url = $"{Fixture.HomePageUrl}/api/checkdbconnection";
            Output.WriteLine($"Verify connection to the Manual Logger SQL Database through {url}.");
            string content = Fixture.Client.DownloadString(url);
            var conn = JObject.Parse(content);
            Assert.True((bool)conn["online"], "PI Manual Logger API indicates the database is not online. Verify SQL is running and connection "
                + "between IIS server and SQL server.");
        }

        /// <summary>
        /// Verifies that the PI Manual Logger API detects the current user name.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Call Username API</para>
        /// <para>Verify response includes a username</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void APIUsernameTest()
        {
            string url = $"{Fixture.HomePageUrl}/api/username";
            Output.WriteLine($"Verify the current Manual Logger API username through {url}.");
            string content = Fixture.Client.DownloadString(url);
            string userName = JsonConvert.DeserializeObject<string>(content);
            Assert.True(!string.IsNullOrEmpty(userName), "Failed to get current user name via PI Manual Logger API.");
        }

        /// <summary>
        /// Verifies Web.config connection string was not changed by upgrade.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Only run if we detect a pre-upgrade web.config file</para>
        /// <para>Verify that the connection string in the current web.config match the pre-upgrade version</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void UpgradeConnectionStringTest()
        {
            // Only test if we find a Web.config.previous file
            if (!Equals(Fixture.WebConfigPrevious, null))
            {
                string previous = Fixture.WebConfigPrevious.ConnectionStrings.ConnectionStrings[ConnectionName].ConnectionString;
                Assert.True(Fixture.WebConfig != null,
                    $"Web.config could not be loaded. Verify web.config exists for this installation of PI Manual Logger.");

                Output.WriteLine("Verify Web.config connection string was not changed by upgrade.");
                string current = Fixture.WebConfig.ConnectionStrings.ConnectionStrings[ConnectionName].ConnectionString;
                Assert.True(string.Equals(previous, current, StringComparison.OrdinalIgnoreCase),
                    $"Connection string [{current}] does not match the connection string in the previous Web.config file [{previous}].");
            }
            else
            {
                Output.WriteLine(NoPreviousWebConfig);
            }
        }

        /// <summary>
        /// Verifies Web.config application level settings were not changed by upgrade.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Only run if we detect a pre-upgrade web.config file</para>
        /// <para>Verify that the AppSettings in the current web.config match the pre-upgrade version</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void UpgradeApplicationSettingsTest()
        {
            // Only test if we find a Web.config.previous file
            if (!Equals(Fixture.WebConfigPrevious, null))
            {
                Assert.True(Fixture.WebConfig != null,
                    $"Web.config could not be loaded. Verify web.config exists for this installation of PI Manual Logger.");

                Output.WriteLine("Verify Web.config application level settings were not changed by upgrade.");
                foreach (string key in Fixture.WebConfigPrevious.AppSettings.Settings.AllKeys)
                {
                    Assert.True(Equals(Fixture.WebConfigPrevious.AppSettings.Settings[key], Fixture.WebConfig.AppSettings.Settings[key]),
                        $"Application setting [{key}] does not match the setting in the previous Web.config file. " +
                        $"Current: {Fixture.WebConfig.AppSettings.Settings[key]}, Previous: {Fixture.WebConfigPrevious.AppSettings.Settings[key]}");
                }
            }
            else
            {
                Output.WriteLine(NoPreviousWebConfig);
            }
        }

        /// <summary>
        /// Verifies Web.config application level settings are valid.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Verify that DigitalStateSortOrder, GetHistoricalValuesFromPI, and DefaultToGridView exist in the current Web.config file with valid values</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void ApplicationSettingsTest()
        {
            string[] keys = { "DigitalStateSortOrder", "GetHistoricalValuesFromPI", "DefaultToGridView" };
            string[][] validValues =
            {
                new string[] { "CodeAsc", "CodeDesc", "NameAsc", "NameDesc" },
                new string[] { "True", "False" },
                new string[] { "True", "False" },
            };

            Output.WriteLine("Verify that DigitalStateSortOrder, GetHistoricalValuesFromPI, and DefaultToGridView exist in the current Web.config file with valid values.");
            for (int i = 0; i < keys.Length; i++)
            {
                string key = keys[i];
                string[] values = validValues[i];
                Assert.True(Fixture.WebConfig != null, $"Web.config could not be loaded. Verify web.config exists for this installation of PI Manual Logger.");
                Assert.True(Fixture.WebConfig.AppSettings.Settings.AllKeys.Any(k =>
                    string.Equals(k, key, StringComparison.OrdinalIgnoreCase)),
                    $"Application setting [{key}] missing from Web.config file.");
                string value = Fixture.WebConfig.AppSettings.Settings[key].Value;
                Assert.True(values.Any(v => string.Equals(v, value, StringComparison.OrdinalIgnoreCase)),
                    $"Application setting [{key}] in Web.config has invalid value [{value}]. Valid values are [{string.Join(", ", values)}].");
            }
        }

        /// <summary>
        /// Verifies Web.config security settings were not changed by upgrade.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Only run if we detect a pre-upgrade web.config file</para>
        /// <para>Verify that the security settings in the system.web section of the current web.config match the pre-upgrade version</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void UpgradeSecuritySettingsTest()
        {
            // Only test if we find a Web.config.previous file
            if (!Equals(Fixture.WebConfigPrevious, null))
            {
                Assert.True(Fixture.WebConfig != null,
                    $"Web.config could not be loaded. Verify web.config exists for this installation of PI Manual Logger.");

                Output.WriteLine("Verify Web.config security settings were not changed by upgrade.");
                string section = "system.web";
                var previous = (SystemWebSectionGroup)Fixture.WebConfigPrevious.GetSectionGroup(section);
                var current = (SystemWebSectionGroup)Fixture.WebConfig.GetSectionGroup(section);
                Assert.True(Equals(previous.Authentication, current.Authentication),
                    "Security setting [authentication] in section System.Web does not match the setting in the previous Web.config file. " +
                    $"Current: [{current.Authentication}], Previous: [{previous.Authentication}]");
                Assert.True(Equals(previous.Identity, current.Identity),
                    "Security setting [identity] in section System.Web does not match the setting in the previous Web.config file. " +
                    $"Current: [{current.Identity}], Previous: [{previous.Identity}]");
            }
            else
            {
                Output.WriteLine(NoPreviousWebConfig);
            }
        }

        /// <summary>
        /// Verifies Web.config web server settings were not changed by upgrade.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Only run if we detect a pre-upgrade web.config file</para>
        /// <para>Verify that the custom headers in the system.webServer section of the current web.config match the pre-upgrade version</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void UpgradeWebServerSettingsTest()
        {
            // Only test if we find a Web.config.previous file
            if (!Equals(Fixture.WebConfigPrevious, null))
            {
                string section = "system.webServer";
                string childElement = "httpProtocol";
                string grandChildElement = "customHeaders";

                XElement previous;
                using (var reader = new StringReader(Fixture.WebConfigPrevious.GetSection(section).SectionInformation.GetRawXml()))
                {
                    previous = XDocument.Load(reader).Element(section).Element(childElement).Element(grandChildElement);
                    Assert.True(Fixture.WebConfig != null, $"Web.config could not be loaded. Verify web.config exists for this installation of PI Manual Logger.");
                }

                XElement current;
                using (var reader = new StringReader(Fixture.WebConfig.GetSection(section).SectionInformation.GetRawXml()))
                {
                    current = XDocument.Load(reader).Element(section).Element(childElement).Element(grandChildElement);
                }

                string[] headers = { "X-Frame-Options", "X-Content-Type-Options", "X-Download-Options", "X-XSS-Protection" };
                Output.WriteLine("Verify that the custom headers in the system.webServer section of the current web.config match the pre-upgrade version.");
                foreach (var previousElement in previous.Elements().Where(e => headers.Any(h =>
                    string.Equals(e.Attribute("name").Value, h, StringComparison.OrdinalIgnoreCase))))
                {
                    string name = previousElement.Attribute("name").Value;
                    var currentElement = current.Elements().First(e => e.Attribute("name").Value == name);
                    string previousValue = previousElement.Attribute("value").Value;
                    string currentValue = currentElement.Attribute("value").Value;
                    Assert.True(Equals(previousValue, currentValue),
                        $"Web server custom header setting [{name}] does not match the setting in the previous Web.config file. " +
                        $"Current: [{currentValue}], Previous: [{previousValue}]");
                }
            }
            else
            {
                Output.WriteLine(NoPreviousWebConfig);
            }
        }

        /// <summary>
        /// Verifies Web.config web server settings are valid.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Verify that there is a modules element node with a remove child node in the system.webServer section of the Web.config</para>
        /// <para>Verify that there is a staticContent element node with remove and mimeMap child nodes in the system.webServer section of the Web.config</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void WebServerSettingsTest()
        {
            string section = "system.webServer";
            Assert.True(Fixture.WebConfig != null, $"Web.config could not be loaded. Verify web.config exists for this installation of PI Manual Logger.");
            XElement config;
            using (var reader = new StringReader(Fixture.WebConfig.GetSection(section).SectionInformation.GetRawXml()))
            {
                config = XDocument.Load(reader).Element(section);
            }

            Output.WriteLine("Verify that there is a modules element node with a remove child node in the system.webServer section of the Web.config.");
            var modules = config.Element("modules");
            Assert.True(modules != null, "Modules element is missing from system.webServer section of Web.config.");
            var remove = modules?.Element("remove");
            Output.WriteLine("Verify that there is a staticContent element node with remove and mimeMap child nodes in the system.webServer section of the Web.config.");
            Assert.True(remove != null, "Modules > Remove element is missing from system.webServer section of Web.config.");

            var staticContent = config.Element("staticContent");
            Assert.True(staticContent != null, "StaticContent element is missing from system.webServer section of Web.config.");
            remove = staticContent?.Element("remove");
            Assert.True(remove != null, "StaticContent > Remove element is missing from system.webServer section of Web.config.");
            var mimeMap = staticContent?.Element("mimeMap");
            Assert.True(mimeMap != null, "StaticContent > MimeMap element is missing from system.webServer section of Web.config.");
        }

        /// <summary>
        /// Verifies HTTPS/SSL settings for offline mode.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Verify there is an SSL certificate on the PI Manual Logger machine</para>
        /// <para>Verify the SSL certificate has reached its effective date</para>
        /// <para>Verify the SSL certificate has not reached its expiration date</para>
        /// <para>Verify the SSL certificate using basic validation policy</para>
        /// </remarks>
        [ManualLoggerCertificateFact]
        public void HttpsSettingsTest()
        {
            try
            {
                Output.WriteLine("Verify there is an SSL certificate on the PI Manual Logger machine.");
                using (var tcpClient = new TcpClient(Settings.PIManualLogger, Settings.PIManualLoggerPort))
                {
                    NetworkStream tcpStream = tcpClient.GetStream();
                    using (var sslStream = new SslStream(tcpStream, false))
                    {
                        sslStream.AuthenticateAsClient(Settings.PIManualLogger);
                        using (var cert = new X509Certificate2(sslStream.RemoteCertificate))
                        {
                            DateTime eff = Convert.ToDateTime(cert.GetEffectiveDateString(), CultureInfo.InvariantCulture).Date;
                            DateTime exp = Convert.ToDateTime(cert.GetExpirationDateString(), CultureInfo.InvariantCulture).Date;
                            DateTime now = DateTime.Now.Date;
                            Assert.True(eff < now, $"The server certificate is not yet valid, its effective date is [{eff.ToString("d", CultureInfo.InvariantCulture)}].");
                            Assert.True(exp > now, $"The server certificate is expired, its expiration date was [{exp.ToString("d", CultureInfo.InvariantCulture)}].");
                            Assert.True(cert.Verify(), $"The server certificate could not be verified.");
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Assert.True(false,
                    $"Failed to get the server certificate. Ensure the PI Manual Logger Web machine has an https binding with a certificate. Exception Message [{ex.Message}].");
            }
        }
    }
}
