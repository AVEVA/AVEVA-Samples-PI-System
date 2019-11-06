using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using Newtonsoft.Json.Linq;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// These tests verify components that MUST be running and available for other PI Product tests to execute properly.
    /// </summary>
    /// <remarks>
    /// This class of tests will be run by the Test for PI System Deployment script prior to any of the other Test Classes.
    /// If any issues are found by these preliminary checks, the remainder of the test classes will not be run.
    /// </remarks>
    public class PreliminaryChecks
    {
        /// <summary>
        /// Constructor for PreliminaryChecks Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        public PreliminaryChecks(ITestOutputHelper output)
        {
            Output = output;
        }

        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Outputs product versions of AFServer, PIDA, and AFSDK.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create new AF and PI Fixtures</para>
        /// <para>Output version number of AFServer, PIDA, and AFSDK</para>
        /// </remarks>
        [Fact]
        public void CheckProductVersion()
        {
            Output.WriteLine($"AFSDK Version: {AF.AFGlobalSettings.SDKVersion}");
            using (var affixture = new AFFixture())
            {
                Assert.True(affixture.PISystem != null, $"AF Server [{affixture.PISystem}] could not be found.");
                Output.WriteLine($"AF Server Version: {affixture.PISystem.ServerVersion}");
            }

            using (var pifixture = new PIFixture())
            {
                Assert.True(pifixture.PIServer != null, $"PI Server [{pifixture.PIServer}] could not be found.");
                Output.WriteLine($"PI Data Archive Version: {pifixture.PIServer.ServerVersion}");
            }
        }

        /// <summary>
        /// Checks PI Data Archive Service is running.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create new PI Fixture</para>
        /// <para>Check if specific PI Data Archive Windows service is running</para>
        /// </remarks>
        /// <param name="service">Name of PI Data Archive Windows service to check.</param>
        [Theory]
        [InlineData("piarchss")]
        [InlineData("pibackup")]
        [InlineData("pibasess")]
        [InlineData("pilicmgr")]
        [InlineData("pimsgss")]
        [InlineData("pinetmgr")]
        [InlineData("pisnapss")]
        [InlineData("piupdmgr")]
        public void CheckDataArchiveServiceTest(string service)
        {
            using (var fixture = new PIFixture())
            {
                Utils.CheckServiceRunning(fixture.PIServer.ConnectionInfo.Host, service, Output);
            }
        }

        /// <summary>
        /// Checks PI AF Service is running.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create new AF Fixture</para>
        /// <para>Check that AF Windows Service is running</para>
        /// </remarks>
        [Fact]
        public void CheckAFServiceTest()
        {
            var service = "AFService";

            using (var fixture = new AFFixture())
            {
                Utils.CheckServiceRunning(fixture.PISystem.ConnectionInfo.Host, service, Output);
            }
        }

        /// <summary>
        /// Checks PI Analysis Service is running.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check that PI Analysis Manager Windows Service is running</para>
        /// </remarks>
        [Fact]
        public void CheckAnalysisServiceTest()
        {
            var service = "PIAnalysisManager";
            Utils.CheckServiceRunning(Settings.PIAnalysisService, service, Output);
        }

        /// <summary>
        /// Checks PI Notification Service is running.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check if PI Notification Service is set in the App.Config</para>
        /// <para>If config is not set, skip check</para>
        /// <para>If config is set, check if PI Notifications Service is running</para>
        /// </remarks>
        [Fact]
        public void CheckNotificationServiceTest()
        {
            var service = "PINotificationsService";

            if (string.IsNullOrEmpty(Settings.PINotificationsService))
                Output.WriteLine($"'PINotificationsService' value not set in app.config. Check if [{service}] is running was skipped.");
            else
                Utils.CheckServiceRunning(Settings.PINotificationsService, service, Output);
        }

        /// <summary>
        /// Checks PI SQL DAS (RTQP Engine) service is running.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check value of PI SQL Client Tests in the App.Config</para>
        /// <para>If config is true, check if Rtqp Engine Service is running</para>
        /// <para>If config is false, skip check</para>
        /// </remarks>
        [Fact]
        public void CheckRtqpEngineServiceTest()
        {
            var service = "PISqlDas.Rtqp";

            using (var fixture = new AFFixture())
            {
                if (Settings.PISqlClientTests)
                    Utils.CheckServiceRunning(fixture.PISystem.ConnectionInfo.Host, service, Output);
                else
                    Output.WriteLine($"'PISQLClientTests' setting value is set to 'false' or not set at all. Check if [{service}] (required by PI SQL Client) is running was skipped.");
            }
        }

        /// <summary>
        /// Checks the current user is mapped to piadmins group.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create new PI Fixture</para>
        /// <para>Get current user's identities</para>
        /// <para>Check that piadmins is one of the user's identities</para>
        /// </remarks>
        [Fact]
        public void CheckPIAdminsMappingTest()
        {
            using (var piFixture = new PIFixture())
            {
                Output.WriteLine($"Check if current user has required PI Identity of " +
                    $"[{PIFixture.RequiredPIIdentity}] for the PI Data Archive server [{piFixture.PIServer.Name}].");
                IList<PIIdentity> identities = piFixture.PIServer.CurrentUserIdentities;

                Assert.True(
                    identities.Any(x => x.Name.Equals(PIFixture.RequiredPIIdentity, StringComparison.OrdinalIgnoreCase)),
                    $"The current user does not have the required PI Identity of [{PIFixture.RequiredPIIdentity}], " +
                    $"please add a new mapping to it in PI Data Archive server [{piFixture.PIServer.Name}].");
            }
        }

        /// <summary>
        /// Checks the current user can send date to PI Points.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Find a PI Point taking manaul input</para>
        /// <para>Write a single event</para>
        /// <para>Read the event to ensure that the write was successful</para>
        /// </remarks>
        [Fact]
        public void CheckPIPointWritePermissionTest()
        {
            using (var piFixture = new PIFixture())
            {
                // Find the target a PI Point
                string manualInputPoint = @"OSIsoftTests.Region 1.Manual Input";
                Output.WriteLine($"Search for PI Point [{manualInputPoint}].");
                var point = PIPoint.FindPIPoint(piFixture.PIServer, manualInputPoint);

                // Prepare the event to be written
                var eventToWrite = new AFValue((float)Math.PI, (AFTime.Now + TimeSpan.FromSeconds(1)).ToPIPrecision());

                // Send the event to be written
                Output.WriteLine($"Write an event to PI Point [{manualInputPoint}].");
                point.UpdateValue(eventToWrite, AFUpdateOption.InsertNoCompression);

                // Read the current value to verify that the event was written successfully
                Output.WriteLine($"Verify the event has been sent to PI Point [{manualInputPoint}].");
                AssertEventually.True(
                    () => eventToWrite.Equals(point.CurrentValue()),
                    $"Failed to send data to PI Point [{manualInputPoint}] on {piFixture.PIServer.Name}.  Please check if the running user has write access to PI Data Archive.  " +
                    $"If buffering is configured, make sure PI Buffer Subsystem connects to PI Data Archive with appropriate PI mappings.");
            }
        }

        /// <summary>
        /// Checks PI DataLink is installed locally.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check value of PI DataLink Tests in the App.Config</para>
        /// <para>If config is true, check if PI DataLink is installed locally</para>
        /// <para>If config is false, skip check</para>
        /// </remarks>
        [Fact]
        public void CheckPIDataLinkTest()
        {
            if (Settings.PIDataLinkTests)
            {
                Output.WriteLine("Check if PI DataLink is installed locally.");
                Assert.True(DataLinkUtils.DataLinkIsInstalled(), "PI DataLink is not installed locally.");
            }
            else
            {
                Output.WriteLine($"'PIDataLinkTests' setting value is set to 'false' or not set at all. Check if PI DataLink is installed locally was skipped.");
            }
        }

        /// <summary>
        /// Checks PI Manual Logger home page loads.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Checks if PI Manual Logger is set in the App.Config</para>
        /// <para>If config is not filled out, skip test</para>
        /// <para>If config is filled out, create new Manual Logger fixture</para>
        /// <para>With the fixture, attempt to load PI Manual Logger home page</para>
        /// </remarks>
        [Fact]
        public void CheckManualLoggerHomePageTest()
        {
            if (string.IsNullOrEmpty(Settings.PIManualLogger))
            {
                Output.WriteLine($"'PIManualLogger' setting value is not set in app.config. Check if home page loads was skipped.");
            }
            else
            {
                using (var fixture = new ManualLoggerFixture())
                {
                    try
                    {
                        Output.WriteLine($"Load PI Manual Logger home page [{fixture.HomePageUrl}].");
                        var homeData = fixture.Client.DownloadString(fixture.HomePageUrl);
                        Assert.True(!string.IsNullOrEmpty(homeData),
                            "Failed to load PI Manual Logger home page. The service may be stopped or in a bad state.");
                    }
                    catch (WebException ex)
                    {
                        Assert.True(ex.Status != WebExceptionStatus.TrustFailure,
                            "Failed to load PI Manual Logger home page because its certificate is not trusted. It is strongly " +
                            "recommended to use a trusted certificate, but if desired, this check can be bypassed by setting " +
                            "SkipCertificateValidation to True in the App.config.");
                        Assert.True(ex.Status == WebExceptionStatus.TrustFailure,
                            $"Failed to load PI Manual Logger home page. Encountered a WebException:{Environment.NewLine}{ex.ToString()}");
                    }
                }
            }
        }

        /// <summary>
        /// Checks PI Web API service is running.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check if PI Web API is set in the App.Config</para>
        /// <para>If config is not set, skip test</para>
        /// <para>If config is set, get machine name that Web API is ran on</para>
        /// <para>Check that Web API is running</para>
        /// </remarks>
        [Fact]
        public void CheckPIWebAPIServiceTest()
        {
            var service = "piwebapi";

            if (string.IsNullOrEmpty(Settings.PIWebAPI))
            {
                Output.WriteLine($"'PIWebAPI' setting value is not set in app.config. Check if [{service}] is running was skipped.");
            }
            else
            {
                // Strip off any domain information for this check
                string machine = Settings.PIWebAPI.Split('.')[0];
                Utils.CheckServiceRunning(machine, service, Output);
            }
        }

        /// <summary>
        /// Checks PI Web API home page loads.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check if PI Web API is set in the App.Config</para>
        /// <para>If config is not set, skip check</para>
        /// <para>If config is set, create new Web API fixture</para>
        /// <para>With the fixture, attempt to load PI Web API home page</para>
        /// <para>If PI Web API home page fail to load, check if Kerberos delegation is the issue</para>
        /// </remarks>
        [Fact]
        public void CheckPIWebAPIHomePageTest()
        {
            const int E_FAIL = unchecked((int)0x80004005);

            if (string.IsNullOrEmpty(Settings.PIWebAPI))
            {
                Output.WriteLine($"'PIWebAPI' setting value is not set in app.config. Check if home page loads was skipped.");
            }
            else
            {
                using (var fixture = new PIWebAPIFixture())
                {
                    try
                    {
                        Output.WriteLine($"Load PI Web API home page [{fixture.HomePageUrl}].");
                        var homeData = JObject.Parse(fixture.Client.DownloadString(fixture.HomePageUrl));
                        Assert.True(!string.IsNullOrEmpty((string)homeData["Links"]["Self"]),
                            "Failed to load PI Web API home page. The service may be stopped or in a bad state.");
                    }
                    catch (WebException ex)
                    {
                        if (ex.InnerException != null)
                        {
                            if (ex.InnerException.HResult == E_FAIL)
                                Output.WriteLine("Failed to load PI Web API home page. Check Kerberos delegation configuration.");
                        }

                        Assert.True(ex.Status != WebExceptionStatus.TrustFailure,
                            "Failed to load PI Web API home page because its certificate is not trusted. It is strongly " +
                            "recommended to use a trusted certificate, but if desired, this check can be bypassed by setting " +
                            "SkipCertificateValidation to True in the App.config.");
                        Assert.True(ex.Status == WebExceptionStatus.TrustFailure,
                            $"Failed to load PI Web API home page. Encountered a WebException:{Environment.NewLine}{ex.ToString()}");
                    }
                }
            }
        }

        /// <summary>
        /// Creates a test Display Folder in PI Vision if missing.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check if PI Vision Server is set in the App.Config</para>
        /// <para>If config is not set, skip check</para>
        /// <para>If config is set, create new Vision fixture</para>
        /// <para>With the fixture, attempt to create display folder in PI Vision</para>
        /// </remarks>
        [Fact]
        public async void CreatePIVisionDisplayFolderTest()
        {
            if (string.IsNullOrEmpty(Settings.PIVisionServer))
            {
                Output.WriteLine($"'PIVisionServer' setting value is not set in app.config. " +
                    $"Create a test display folder was skipped.");
            }
            else
            {
                using (var fixture = new Vision3Fixture())
                {
                    Output.WriteLine("Create a new display folder into the database.");
                    using (var response = await fixture.FindOrCreateTestFolder().ConfigureAwait(false))
                    {
                        Assert.True(response.IsSuccessStatusCode, "PI Vision cannot save a display folder. " +
                            Vision3Fixture.CommonVisionIssues);
                    }
                }
            }
        }

        /// <summary>
        /// Checks connection to machines by pinging.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Get machine name based on settingName</para>
        /// <para>If machine is not set and is not required, skip check</para>
        /// <para>If machine is not set and is required, fail assertion</para>
        /// <para>If machine is set, ping machine</para>
        /// </remarks>
        /// <param name="settingName">Name of app.config setting to check.</param>
        [Theory]
        [InlineData("PIDataArchive")]
        [InlineData("AFServer")]
        [InlineData("PIAnalysisService")]
        [InlineData("PINotificationsService")]
        [InlineData("PIWebAPI")]
        [InlineData("PIWebAPICrawler")]
        [InlineData("PIVisionServer")]
        [InlineData("PIManualLogger")]
        public void CheckConnectionPing(string settingName)
        {
            Output.WriteLine($"Get name of machine running [{settingName}].");
            string machine = Utils.GetMachineName(settingName);

            if (string.IsNullOrEmpty(machine))
            {
                if (settingName == "PIDataArchive" || settingName == "AFServer" || settingName == "PIAnalysisService")
                    Assert.True(false, $"Config not filled out for [{settingName}].");

                if (settingName == "PIWebAPICrawler" && !string.IsNullOrEmpty(Settings.PIWebAPI))
                    Output.WriteLine($"PIWebAPI and PIWebAPICrawler both running on [{Settings.PIWebAPI}].");
                else
                    Output.WriteLine($"[{settingName}] setting value is not set in app.config. Check if [{settingName}] machine is connectible was skipped.");
            }
            else
            {
                Output.WriteLine($"Ping machine [{machine}].");
                Assert.True(Utils.PingHost(machine, settingName), $"Can't ping [{machine}]. Check firewall settings for [{machine}] running [{settingName}].");
            }
        }
    }
}
