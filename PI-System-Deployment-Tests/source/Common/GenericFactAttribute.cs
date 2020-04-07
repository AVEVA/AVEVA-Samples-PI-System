using System;
using System.Data.OleDb;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text;
using Newtonsoft.Json.Linq;
using OSIsoft.AF;
using OSIsoft.AF.Asset;
using OSIsoft.AF.PI;
using OSIsoft.PINotifications.Client;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Enumeration of different test requirements for AF tests.
    /// </summary>
    public enum TestCondition
    {
        /// <summary>
        /// Specifies that the latest Patch of PI AF Client is applied
        /// </summary>
        AFCLIENTCURRENTPATCH,

        /// <summary>
        /// Specifies that the 2.10.7 Patch of PI AF is applied
        /// </summary>
        AFPATCH2107,

        /// <summary>
        /// Specifies that the latest Patch of the PI AF Server is applied
        /// </summary>
        AFSERVERCURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of Analysis is applied
        /// </summary>
        ANALYSISCURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of PI Data Link is applied
        /// </summary>
        DATALINKCURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of PI Notifications is applied
        /// </summary>
        NOTIFICATIONSCURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of PI Data Archive is applied
        /// </summary>
        PIDACURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of PI SQL Client OLEDB is applied
        /// </summary>
        PISQLOLEDBCURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of PI SQL Client ODBC is applied
        /// </summary>
        PISQLODBCCURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of PI Web API is applied
        /// </summary>
        PIWEBAPICURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of RTQP Engine is applied
        /// </summary>
        RTQPCURRENTPATCH,

        /// <summary>
        /// Specifies that the latest Patch of PI Vision is applied
        /// </summary>
        PIVISIONCURRENTPATCH,
    }

    /// <summary>
    /// AF FactAttribute class for AF Tests
    /// skips tests based on criteria defined in enumeration set.
    /// </summary>
    public sealed class GenericFactAttribute : OptionalFactAttribute
    {
        private static Version _afClientCurrentVersion = new Version("2.10.8.440");
        private static string _afClientCurrentVersionString = "PI AF Client 2018 SP3 Patch 2 (2.10.8)";

        private static Version _afServerCurrentVersion = new Version("2.10.8.440");
        private static string _afServerCurrentVersionString = "PI AF Server 2018 SP3 Patch 2 (2.10.8)";

        private static Version _analysisCurrentVersion = new Version("2.10.6.195");
        private static string _analysisCurrentVersionString = "PI Analysis Service 2018 SP3";

        private static Version _notificationsCurrentVersion = new Version("2.10.5.9050");
        private static string _notificationsCurrentVersionString = "PI Notifications 2012";

        private static Version _dataArchiveCurrentVersion = new Version("3.4.435.604");
        private static string _dataArchiveCurrentVersionString = "PI Data Archive 2018 SP3 Patch 1";

        private static Version _dataLinkCurrentVersion = new Version("5.5.2.0");
        private static string _dataLinkCurrentVersionString = "PI DataLink 2019 SP1 Patch 1";

        private static Version _rtqpCurrentVersion = new Version("01.07.19246.2");
        private static string _rtqpCurrentVersionString = "RTQP Engine 2018 R2";

        private static Version _sqlClientOLEDBCurrentVersion = new Version("4.1.19190.2");
        private static string _sqlClientOLEDBCurrentVersionString = "PI SQL Client 2018 R2";

        private static Version _sqlClientODBCCurrentVersion = new Version("4.1.19190.2");
        private static string _sqlClientODBCCurrentVersionString = "PI SQL Client 2018 R2";

        private static Version _webAPICurrentVersion = new Version("1.12.0.6145");
        private static string _webAPICurrentVersionString = "PI Web API 2019 Patch 1";

        private static Version _visionCurrentVersion = new Version("3.4.1.0");
        private static string _visionCurrentVersionString = "PI Vision 2019 Patch 1";

        /// <summary>
        /// Skips a test based on the passed condition.
        /// </summary>
        public GenericFactAttribute(TestCondition feature, bool error)
            : base(AFTests.KeySetting, AFTests.KeySettingTypeCode)
        {
            string afVersion = AFGlobalSettings.SDKVersion;
            string piHomeDir = string.Empty;

            // Return if the Skip property has been changed in the base constructor
            if (!string.IsNullOrEmpty(Skip))
                return;
            string piHome64 = null;
            string piHome32 = null;
            DataLinkUtils.GetPIHOME(ref piHome64, 1);
            DataLinkUtils.GetPIHOME(ref piHome32, 0);
            switch (feature)
            {
                case TestCondition.AFCLIENTCURRENTPATCH:
                    Version sdkVersion = new Version(afVersion);
                    if (sdkVersion < _afClientCurrentVersion)
                    {
                        Skip = $@"Warning! You do not have the latest update: {_afClientCurrentVersionString}! Please consider upgrading! You are currently on {sdkVersion}";
                    }

                    break;
                case TestCondition.AFPATCH2107:
                    sdkVersion = new Version(afVersion);
                    if (sdkVersion < new Version("2.10.7"))
                    {
                        Skip = $@"Warning! You do not have the critical patch: PI AF 2018 SP3 Patch 1 (2.10.7)! Please consider upgrading to avoid data loss! You are currently on {sdkVersion}";
                    }

                    break;
                case TestCondition.AFSERVERCURRENTPATCH:
                    Version serverVersion = new Version(AFFixture.GetPISystemFromConfig().ServerVersion);
                    if (serverVersion < _afServerCurrentVersion)
                    {
                        Skip = $@"Warning! You do not have the latest update: {_afServerCurrentVersionString}! Please consider upgrading! You are currently on {serverVersion}";
                    }

                    break;
                case TestCondition.ANALYSISCURRENTPATCH:
                    Version analysisVer = new Version(AFFixture.GetPISystemFromConfig().AnalysisRulePlugIns["PerformanceEquation"].Version);
                    if (analysisVer < _analysisCurrentVersion)
                    {
                        Skip = $@"Warning! You do not have the latest update: {_analysisCurrentVersionString}! Please consider upgrading! You are currently on {analysisVer}";
                    }

                    break;
                case TestCondition.DATALINKCURRENTPATCH:
                    string afDataDLLPath = @"Excel\OSIsoft.PIDataLink.AFData.dll";

                    DataLinkUtils.GetPIHOME(ref piHomeDir);
                    Version dataLinkVersion = new Version(FileVersionInfo.GetVersionInfo(Path.Combine(piHomeDir, afDataDLLPath)).FileVersion);
                    if (dataLinkVersion < _dataLinkCurrentVersion)
                    {
                        Skip = $@"Warning! You do not have the latest update: {_dataLinkCurrentVersionString}! Please consider upgrading! You are currently on {dataLinkVersion}";
                    }

                    break;
                case TestCondition.NOTIFICATIONSCURRENTPATCH:
                    PISystem system = AFFixture.GetPISystemFromConfig();
                    var configstore = new PINotificationsConfigurationStore(system);
                    PINotificationsWCFClientManager wcfClient = new PINotificationsWCFClientManager(configstore);
                    var serviceStatus = wcfClient.GetServiceStatus();
                    wcfClient.Dispose();
                    Version notificationsVersion = new Version(serviceStatus.Version);
                    if (notificationsVersion < _notificationsCurrentVersion)
                    {
                        Skip = $@"Warning! You do not have the latest update: {_notificationsCurrentVersionString}! Please consider upgrading! You are currently on {notificationsVersion}";
                    }

                    break;
                case TestCondition.PIDACURRENTPATCH:
                    PIServer serv = new PIServers()[Settings.PIDataArchive];
                    serv.Connect();
                    Version pidaVersion = new Version(serv.ServerVersion);
                    if (pidaVersion < _dataArchiveCurrentVersion)
                    {
                        Skip = $@"Warning! You do not have the latest update: {_dataArchiveCurrentVersionString}! Please consider upgrading! You are currently on {pidaVersion}";
                    }

                    break;
                case TestCondition.PISQLOLEDBCURRENTPATCH:
                    string sqlpath64OLEDB = Path.Combine(piHome64, @"SQL\SQL Client\OLEDB\PISQLOLEDB64.dll");
                    string sqlpath32OLEDB = Path.Combine(piHome32, @"SQL\SQL Client\OLEDB\PISQLOLEDB.dll");
                    if (File.Exists(sqlpath64OLEDB))
                    {
                        Version piSqlVersion = new Version(FileVersionInfo.GetVersionInfo(sqlpath64OLEDB).FileVersion);
                        if (piSqlVersion < _sqlClientOLEDBCurrentVersion)
                        {
                            Skip = $@"Warning! You do not have the latest update: {_sqlClientOLEDBCurrentVersionString}! Please consider upgrading! You are currently on {piSqlVersion}";
                        }
                    }

                    if (File.Exists(sqlpath32OLEDB))
                    {
                        Version piSqlVersion = new Version(FileVersionInfo.GetVersionInfo(sqlpath32OLEDB).FileVersion);
                        if (piSqlVersion < _sqlClientOLEDBCurrentVersion)
                        {
                            Skip = $@"Warning! You do not have the latest update: {_sqlClientOLEDBCurrentVersionString}! Please consider upgrading! You are currently on {piSqlVersion}";
                        }
                    }

                    break;
                case TestCondition.PISQLODBCCURRENTPATCH:
                    string sqlpath64ODBC = Path.Combine(piHome64, @"SQL\SQL Client\ODBC\PISQLODBCB64.dll");
                    string sqlpath32ODBC = Path.Combine(piHome32, @"SQL\SQL Client\ODBC\PISQLODBC.dll");
                    if (File.Exists(sqlpath64ODBC))
                    {
                        Version piSqlVersion = new Version(FileVersionInfo.GetVersionInfo(sqlpath64ODBC).FileVersion);
                        if (piSqlVersion < _sqlClientODBCCurrentVersion)
                        {
                            Skip = $@"Warning! You do not have the latest update: {_sqlClientODBCCurrentVersionString}! Please consider upgrading! You are currently on {piSqlVersion}";
                        }
                    }

                    if (File.Exists(sqlpath32ODBC))
                    {
                        Version piSqlVersion = new Version(FileVersionInfo.GetVersionInfo(sqlpath32ODBC).FileVersion);
                        if (piSqlVersion < _sqlClientODBCCurrentVersion)
                        {
                            Skip = $@"Warning! You do not have the latest update: {_sqlClientODBCCurrentVersionString}! Please consider upgrading! You are currently on {piSqlVersion}";
                        }
                    }

                    break;
                case TestCondition.PIWEBAPICURRENTPATCH:
                    var url = $"https://{Settings.PIWebAPI}:{443}/piwebapi/system";

                    WebClient client = new WebClient { UseDefaultCredentials = true };
                    AFElement elem = new AFElement();
                    bool disableWrites = false;
                    bool anonymousAuth = false;
                    JObject data = new JObject();

                    try
                    {
                        PIWebAPIFixture.GetWebApiClient(ref client, ref elem, ref disableWrites, ref anonymousAuth);
                        data = JObject.Parse(client.DownloadString(url));
                    }
                    catch
                    {
                        throw new InvalidOperationException($"Could not retrieve PI Web API version from server {Settings.PIWebAPI}!");
                    }
                    finally
                    {
                        client.Dispose();
                    }
                    
                    var productVersion = (string)data["ProductVersion"];
                    Version piWebAPIVersion = new Version(productVersion);
                    if (piWebAPIVersion < _webAPICurrentVersion)
                    {
                        Skip = $@"Warning! You do not have the latest update: {_webAPICurrentVersionString}! Please consider upgrading! You are currently on {piWebAPIVersion}";
                    }

                    break;
                case TestCondition.RTQPCURRENTPATCH:
                    string connectionString = $"Provider=PISQLClient.1;Data Source={Settings.AFDatabase};Location={Settings.AFServer};Integrated Security=SSPI;OLE DB Services=-2";
                    using (var connection = new OleDbConnection(connectionString))
                    {
                        connection.Open();

                        try
                        {
                            using (var command = new OleDbCommand("SELECT Version FROM System.Diagnostics.Version WHERE Item='Query Processor'", connection))
                            {
                                string tempVersion = (string)command.ExecuteScalar();
                                Version rtqpVersion = new Version(tempVersion);
                                if (rtqpVersion < _rtqpCurrentVersion)
                                {
                                    Skip = $@"Warning! You do not have the latest update: {_rtqpCurrentVersionString}! Please consider upgrading! You are currently on {rtqpVersion}";
                                }
                            }
                        }
                        catch (Exception)
                        {
                            Skip = $@"Warning! You do not have the latest update: {_rtqpCurrentVersionString}! Please consider upgrading!";
                        }
                    }

                    break;
                case TestCondition.PIVISIONCURRENTPATCH:
                    string path = Settings.PIVisionServer;
                    if (path.EndsWith("/#/", StringComparison.OrdinalIgnoreCase))
                        path = path.Substring(0, path.Length - 3);
                    
                    string visionUrl = $"{path}/Utility/permissions/read";

                    var visionProductVersion = string.Empty;
                    using (var visionClient = new WebClient { UseDefaultCredentials = true })
                    {
                        visionClient.Headers.Add("X-Requested-With", "XMLHttpRequest");
                        visionProductVersion = visionClient.DownloadString(visionUrl);
                    }

                    Version piVisionVersion = new Version();
                    if (!string.IsNullOrWhiteSpace(visionProductVersion))
                    {
                        piVisionVersion = new Version(visionProductVersion);
                    }
                    else
                    {
                        throw new InvalidOperationException($"Could not retrieve PI Vision version from server {Settings.PIVisionServer}!");
                    }

                    if (piVisionVersion < _visionCurrentVersion)
                    {
                        Skip = $@"Warning! You do not have the latest update: {_visionCurrentVersionString}! Please consider upgrading! You are currently on {piVisionVersion}";
                    }

                    break;
            }

            if (error && !string.IsNullOrEmpty(Skip))
            {
                throw new Exception(Skip);
            }
        }
    }
}
