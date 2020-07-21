using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Net;
using Newtonsoft.Json.Linq;
using OSIsoft.AF;
using OSIsoft.AF.PI;
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
        /// Checks if the current user has the required permissions for running the AF tests.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a new AF Fixture</para>
        /// <para>Get AF Security for each System collection needed</para>
        /// <para>Check the System collection AF Security for the current user</para>
        /// </remarks>
        [Fact]
        public void CheckMinimumAFSecurity()
        {
            using (var fixture = new AFFixture())
            {
                var system = fixture.PISystem;
                Assert.True(system.UOMDatabase.Security.CanWrite, "The current user must have Write permission on the UOMDatabase.");

                foreach (var securityItem in Enum.GetValues(typeof(AFSecurityItem)))
                {
                    var security = system.GetSecurity((AFSecurityItem)securityItem);

                    switch (securityItem)
                    {
                        case AFSecurityItem.AnalysisTemplate:
                        case AFSecurityItem.Category:
                        case AFSecurityItem.Database:
                        case AFSecurityItem.EnumerationSet:
                        case AFSecurityItem.NotificationContactTemplate:
                        case AFSecurityItem.NotificationRuleTemplate:
                        case AFSecurityItem.Table:
                            Assert.True(security.CanRead &&
                                security.CanWrite &&
                                security.CanDelete, "The current user must have Read, Write, and Delete permission to the following System collections:\n" +
                                "\tAnalysis Templates\n" +
                                "\tCategories\n" +
                                "\tDatabases\n" +
                                "\tEnumeration Sets\n" +
                                "\tNotification Contact Templates\n" +
                                "\tNotification Rule Templates\n" +
                                "\tTables");
                            break;
                        case AFSecurityItem.EventFrame:
                        case AFSecurityItem.Transfer:
                            Assert.True(security.CanReadData &&
                                security.CanWriteData &&
                                security.CanDelete &&
                                security.CanAnnotate, "The current user must have Read Data, Write Data, Annotate, and Delete permission to the following System collections:\n" +
                                "\tEvent Frames\n" +
                                "\tTransfers");
                            break;
                        case AFSecurityItem.Analysis:
                            Assert.True(security.CanRead &&
                                security.CanWrite &&
                                security.CanDelete &&
                                security.CanExecute, "The current user must have Read, Write, Execute, and Delete permission to the Analyses System collection.");
                            break;
                        case AFSecurityItem.Element:
                        case AFSecurityItem.ElementTemplate:
                            Assert.True(security.CanRead &&
                                security.CanReadData &&
                                security.CanWrite &&
                                security.CanWriteData &&
                                security.CanDelete, "The current user must have Read, Write, Read Data, Write Data, and Delete permission to the following System collections:\n" +
                                "\tElements\n" +
                                "\tElement Templates");

                            var identities = system.CurrentUserIdentities;
                            var instancedSystem = fixture.GetInstancedSystem();
                            if ((AFSecurityItem)securityItem == AFSecurityItem.Element)
                            {
                                Assert.True(security.CanAnnotate, "The current user must have Annotate permission to the Elements System collection.");
                            }
                            else
                            {
                                var elementTemplateToken = instancedSystem.GetSecurity(AFSecurityItem.ElementTemplate).Token;
                                elementTemplateToken.SecurityItem = AFSecurityItem.EventFrame;
                                var tokens = new List<AFSecurityRightsToken>() { elementTemplateToken };
                                var dict = AFSecurity.CheckSecurity(instancedSystem, identities, tokens);
                                Assert.True(dict[elementTemplateToken.ObjectId].CanAnnotate(), "The current user must have Annotate permission to the Element Templates System collection.");
                            }

                            instancedSystem.Disconnect();
                            break;
                        case AFSecurityItem.NotificationRule:
                            Assert.True(security.CanRead &&
                                security.CanWrite &&
                                security.CanDelete &&
                                security.CanSubscribe, "The current user must have Read, Write, Subscribe, and Delete permission to the Notification Rules System collection.");
                            break;
                    }
                }
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
        /// Checks if the current user has Read/Write, Read/Write Data, and Delete permissions to the
        /// OSIsoft\RTQP Engine\Custom Objects element in the Configuration database on the AF Server.
        /// </summary>
        /// <remarks>
        /// <para>Test Steps:</para>
        /// <para>Create a new AF Fixture</para>
        /// <para>Get the security of the configuration element</para>
        /// <para>Check if the Read/Write, Read/Write Data, and Delete permissions are present</para>
        /// </remarks>
        [Fact]
        public void CheckMinimumPISQLClientSecurity()
        {
            using (var fixture = new AFFixture())
            {
                if (Settings.PISqlClientTests)
                {
                    var fullElementPath = @"OSIsoft\RTQP Engine\Custom Objects";
                    var element = fixture.PISystem.Databases.ConfigurationDatabase?.Elements[fullElementPath];

                    if (!(element is null))
                    {
                        Assert.True(element.Security.CanRead && element.Security.CanWrite,
                            $"The user does not have Read/Write permissions on the {fullElementPath} element in the Configuration database.");
                        Assert.True(element.Security.CanReadData && element.Security.CanWriteData,
                            $"The user does not have Read/Write Data permissions on the {fullElementPath} element in the Configuration database.");
                        Assert.True(element.Security.CanDelete,
                            $"The user does not have Delete permissions on the {fullElementPath} element in the Configuration database.");
                    }
                    else
                    {
                        Assert.True(false, $"Could not find element {fullElementPath} in the configuration directory.");
                    }
                }
                else
                {
                    Output.WriteLine($"'PISQLClientTests' setting value is set to 'false' or not set at all. Check if user has minimum security privileges was skipped.");
                }
            }
        }

        /// <summary>
        /// Checks if the current user has Read/Write access to PIARCADMIN, PIPOINT, and PIDS Database Security tables,
        /// and checks if the current user has Read access to PIARCDATA and PIMSGSS Database Security table.
        /// </summary>
        /// <remarks>
        /// <para>Test Steps:</para>
        /// <para>Create new PI Fixture</para>
        /// <para>Get PI identities assigned to current user</para>
        /// <para>Get security rights for the PIARCADMIN, PIARCDATA, PIMSGSS, PIPOINTS, and PIDS tables</para>
        /// <para>Check if any identity has ReadWrite access to both tables</para>
        /// </remarks>
        [Fact]
        public void CheckMinimumDataArchiveSecurity()
        {
            using (var piFixture = new PIFixture())
            {
                // Get full list of PI identities assigned to current user
                var identities = piFixture.PIServer.CurrentUserIdentities;

                // Get security info for PIARCADMIN, PIARCDATA, PIMSGSS, PIPOINTS, and PIDS entries in DB security table
                string piarcadminTableName = "PIARCADMIN";
                string piarcdataTableName = "PIARCDATA";
                string pimsgssTableName = "PIMSGSS";
                string pipointTableName = "PIPOINT";
                string pidsTableName = "PIDS";

                PIDatabaseSecurity piarcadminDbSecurity = piFixture.PIServer.DatabaseSecurities[piarcadminTableName];
                PIDatabaseSecurity piarcdataDbSecurity = piFixture.PIServer.DatabaseSecurities[piarcdataTableName];
                PIDatabaseSecurity pimsgssDbSecurity = piFixture.PIServer.DatabaseSecurities[pimsgssTableName];
                PIDatabaseSecurity pipointDbSecurity = piFixture.PIServer.DatabaseSecurities[pipointTableName];
                PIDatabaseSecurity pidsDbSecurity = piFixture.PIServer.DatabaseSecurities[pidsTableName];

                string piarcadminSecurityString = piarcadminDbSecurity.SecurityString;
                string piarcdataSecurityString = piarcdataDbSecurity.SecurityString;
                string pimsgssSecurityString = pimsgssDbSecurity.SecurityString;
                string pipointSecurityString = pipointDbSecurity.SecurityString;
                string pidsSecurityString = pidsDbSecurity.SecurityString;

                var piarcadminSecurityRights = PIDatabaseSecurity.GetSecurityRights(piarcadminSecurityString);
                var piarcdataSecurityRights = PIDatabaseSecurity.GetSecurityRights(piarcdataSecurityString);
                var pimsgssSecurityRights = PIDatabaseSecurity.GetSecurityRights(pimsgssSecurityString);
                var pipointSecurityRights = PIDatabaseSecurity.GetSecurityRights(pipointSecurityString);
                var pidsSecurityRights = PIDatabaseSecurity.GetSecurityRights(pidsSecurityString);

                Assert.True(identities.Any(i =>
                {
                    var piarcadminLooksGood = piarcadminSecurityRights.Any(x =>
                        x.Key.Equals(i.Name, StringComparison.CurrentCultureIgnoreCase) && x.Value.CanRead() && x.Value.CanWrite());

                    var piarcdataLooksGood = piarcdataSecurityRights.Any(x =>
                        x.Key.Equals(i.Name, StringComparison.CurrentCultureIgnoreCase) && x.Value.CanRead());

                    var pimsgssLooksGood = pimsgssSecurityRights.Any(x =>
                        x.Key.Equals(i.Name, StringComparison.CurrentCultureIgnoreCase) && x.Value.CanRead());

                    var pipointLooksGood = pipointSecurityRights.Any(x =>
                        x.Key.Equals(i.Name, StringComparison.CurrentCultureIgnoreCase) && x.Value.CanRead() && x.Value.CanWrite());

                    var pidsLooksGood = pidsSecurityRights.Any(x =>
                        x.Key.Equals(i.Name, StringComparison.CurrentCultureIgnoreCase) && x.Value.CanRead() && x.Value.CanWrite());

                    return piarcadminLooksGood && piarcdataLooksGood && pimsgssLooksGood && pipointLooksGood && pidsLooksGood;
                }), $"Expected, but did not find, {AFSecurityRights.ReadWrite} access to PIARCADMIN, PIPOINTS, and PIDS tables " +
                    $"or {AFSecurityRights.Read} to PIARCDATA and PIMSGSS for user {piFixture.PIServer.CurrentUserName}.");
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
                            $"Failed to load PI Manual Logger home page. Encountered a WebException:{Environment.NewLine}{ex}");
                    }
                }
            }
        }

        /// <summary>
        /// Checks if the current user has db_datareader, db_datawriter, and execute permissions 
        /// on PI Manual Logger stored procedures in the PimlWindows database.
        /// </summary>
        /// <remarks>
        /// <para>Test Steps:</para>
        /// <para>Get SQL Roles assigned to current user</para>
        /// <para>Check if the db_datareader and db_datawriter roles are present</para>
        /// <para>Get SQL Objects assigned to the current user</para>
        /// <para>Check if the SQL Objects have execute permission</para>
        /// </remarks>
        [Fact]
        public void CheckMinimumManualLoggerSecurity()
        {
            var impersonationUserSetting = Settings.PIManualLoggerWebImpersonationUser;

            if (string.IsNullOrEmpty(Settings.PIManualLogger))
            {
                Output.WriteLine($"'PIManualLogger' setting value is not set in app.config. Check if minimum security check was skipped.");
            } 
            else if (string.IsNullOrEmpty(Settings.PIManualLoggerSQL))
            {
                Output.WriteLine($"'PIManualLoggerSQL' setting value is not set in app.config. Check if minimum security check was skipped.");
            }
            else
            {
                var hasDataReader = false;
                var hasDataWriter = false;
                string currentUser;

                if (!string.IsNullOrEmpty(impersonationUserSetting))
                {
                    currentUser = impersonationUserSetting;
                } 
                else
                {
                    currentUser = $@"{Environment.UserDomainName}\{Environment.UserName}";
                    if (string.IsNullOrWhiteSpace(Environment.UserDomainName))
                    {
                        currentUser = Environment.UserName;
                    }
                }

                var connectionString = $"Server={Settings.PIManualLoggerSQL};Database=PimlWindows;Integrated Security=SSPI";
                var query = "SELECT DP1.name AS DatabaseRoleName\n" +
                    "FROM sys.database_role_members AS DRM\n" +
                    "RIGHT OUTER JOIN sys.database_principals AS DP1\n" +
                    "\tON DRM.role_principal_id = DP1.principal_id\n" +
                    "LEFT OUTER JOIN sys.database_principals AS DP2\n" +
                    "\tON DRM.member_principal_id = DP2.principal_id\n" +
                    "WHERE (DP1.name = 'db_datareader' OR DP1.name = 'db_datawriter')\n" +
                    "AND DP2.name = @userName\n" + 
                    "ORDER BY DP1.name;\n";

                using (var connection = new SqlConnection(connectionString))
                {
                    connection.Open();
                    using (var command = new SqlCommand(query, connection))
                    {
                        command.Parameters.AddWithValue("userName", currentUser);
                        using (SqlDataReader reader = command.ExecuteReader())
                        {
                            while (reader.Read())
                            {
                                var dbRole = reader["DatabaseRoleName"].ToString().ToUpperInvariant();

                                if (dbRole.Equals("DB_DATAREADER", StringComparison.InvariantCultureIgnoreCase))
                                {
                                    hasDataReader = true;
                                }

                                if (dbRole.Equals("DB_DATAWRITER", StringComparison.InvariantCultureIgnoreCase))
                                {
                                    hasDataWriter = true;
                                }
                            }
                        }
                    }
                }

                Assert.True(hasDataReader, $"The user {currentUser} does not have the db_datareader role on the PimlWindows Database.");
                Assert.True(hasDataWriter, $"The user {currentUser} does not have the db_datawriter role on the PimlWindows Database.");

                query = "SELECT OBJECT_NAME(major_id) as ObjectName, permission_name as PermissionName\n" +
                        "FROM sys.database_permissions p\n" +
                        "WHERE USER_NAME(grantee_principal_id) = @userName\n" +
                        "AND class = 1";

                var storedProcedures = new List<string>() 
                {
                    "GetAllPreviousValuesForItem",
                    "GetDigitalStatesForDigitalSet",
                    "GetPreviousNumericValueForItemByDataItemName",
                    "InsertOrUpdatePreviousValueEventForItem",
                    "GetTourIDsForUserSID",
                    "GetUserForUserSID",
                    "DoesTourRunIDExist",
                    "DeleteTourRunByID",
                    "GetGlobalOptions",
                    "GetTourOptionsForDataEntry",
                };

                using (var connection = new SqlConnection(connectionString))
                {
                    connection.Open();
                    using (var command = new SqlCommand(query, connection))
                    {
                        command.Parameters.AddWithValue("userName", currentUser);
                        using (SqlDataReader reader = command.ExecuteReader())
                        {
                            while (reader.Read())
                            {
                                var dbObject = reader["ObjectName"].ToString();
                                var dbPermission = reader["PermissionName"].ToString().ToUpperInvariant();

                                if (dbPermission.Equals("EXECUTE", StringComparison.InvariantCultureIgnoreCase))
                                {
                                    storedProcedures.Remove(dbObject);
                                }
                            }
                        }
                    }
                }

                foreach (var item in storedProcedures)
                {
                    Assert.True(item == null, $"The user {currentUser} does not have execute permissions on {item} object");
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
                            $"Failed to load PI Web API home page. Encountered a WebException:{Environment.NewLine}{ex}");
                    }
                }
            }
        }

        /// <summary>
        /// Checks the permissions of the root PI Vision folder to determine if user has PI Vision Admin rights.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check if PI Vision Server is set in the App.Config</para>
        /// <para>If config is not set, skip check</para>
        /// <para>If config is set, create new Vision fixture</para>
        /// <para>With the fixture, attempt check for root folder permissions in PI Vision</para>
        /// </remarks>
        [Fact]
        public async void CheckPermissionsOfVision3RootFolder()
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
                    Output.WriteLine("Check permissions of root folder.");
                    using (var response = await fixture.GetFolderPermissions("0").ConfigureAwait(false))
                    {
                        Assert.True(response.IsSuccessStatusCode, "PI Vision cannot access root folder permissions. " +
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
