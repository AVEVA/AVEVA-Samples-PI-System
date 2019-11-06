using System;
using System.Diagnostics.Contracts;
using System.Management;
using System.Net.NetworkInformation;
using System.ServiceProcess;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// General Test Helper functions are included in this class.
    /// </summary>
    /// <remarks>
    /// These general purpose test helper functions are available to be used in any of the tests.
    /// See also the Fixture classes for more functions specific to a product being tested (e.g. PI DataArchive or AF).
    /// </remarks>
    public static class Utils
    {
        /// <summary>
        /// Check that the service is running on the machine.
        /// </summary>
        /// <param name="machineName">Name of machine where services are running.</param>
        /// <param name="serviceToCheck">Name of service expected to be running.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public static void CheckServiceRunning(string machineName, string serviceToCheck, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            using (var svcController = new ServiceController
            {
                MachineName = machineName,
                ServiceName = serviceToCheck,
            })
            {
                output.WriteLine($"Check service [{serviceToCheck}] running on [{machineName}].");
                ServiceControllerStatus status = svcController.Status;
                output.WriteLine($" service: [{serviceToCheck}], status: {status}");
                Assert.True(status == ServiceControllerStatus.Running, $"Service [{serviceToCheck}] not running as expected on [{machineName}].");
            }
        }

        /// <summary>
        /// Gets the machine name of service.
        /// </summary>
        /// <param name="settingName">Name of the setting for the service in app config settings file.</param>
        /// <returns>Name of machine running that service.</returns>
        public static string GetMachineName(string settingName)
        {
            switch (settingName)
            {
                case "PIDataArchive":
                    using (var pifixture = new PIFixture())
                        return pifixture.PIServer.ConnectionInfo.Host;
                case "AFServer":
                    using (var affixture = new AFFixture())
                        return affixture.PISystem.ConnectionInfo.Host;
                case "PIAnalysisService":
                    return Settings.PIAnalysisService;
                case "PINotificationsService":
                    return Settings.PINotificationsService;
                case "PIWebAPI":
                    return Settings.PIWebAPI;
                case "PIWebAPICrawler":
                    return Settings.PIWebAPICrawler;
                case "PIVisionServer":
                    if (string.IsNullOrWhiteSpace(Settings.PIVisionServer))
                        return string.Empty;
                    return Settings.PIVisionServer.Split('/')[2].Split(':')[0];
                case "PIManualLogger":
                    return Settings.PIManualLogger;
                default:
                    return $"Invalid setting name '{settingName}' specified.";
            }
        }

        /// <summary>
        /// Checks if Test Machine and Data Archive Server time differes by more than five seconds.
        /// </summary>
        /// <param name="piServer">Fixture to manage PI connection information.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public static void CheckTimeDrift(PIFixture piServer, ITestOutputHelper output)
        {
            Contract.Requires(output != null && piServer != null);
            output.WriteLine($"Check to make sure test machine and the Data Archive server time are within tolerance range.");

            const int MaxDriftInSeconds = 5;
            var serverTime = piServer.PIServer.ServerTime;
            var clientTime = AFTime.Now;
            var timeDiff = Math.Abs((clientTime - serverTime).TotalSeconds);
            Assert.True(timeDiff < MaxDriftInSeconds, $"Test machine and the Data Archive server time differs by [{timeDiff}] seconds, which is greater than maximum allowed of {MaxDriftInSeconds} seconds.");
        }

        /// <summary>
        /// Tries to ping the specified machine.
        /// </summary>
        /// <param name="machineName">Name or address of machine being pinged.</param>
        /// <returns>Returns true if the ping request to the specified machine was successful.</returns>
        public static bool PingHost(string machineName, string service)
        {
            using (var pinger = new Ping())
            {
                PingReply reply;
                try
                {
                    reply = pinger.Send(machineName);
                }
                catch (Exception e)
                {
                    throw new Exception($"Machine [{machineName}] for [{service}] cannot be found: " + e);
                }

                return reply.Status == IPStatus.Success;
            }
        }

        /// <summary>
        /// Gets the value of an Environment Variable from a remote machine
        /// </summary>
        /// <param name="machine">Machine name to query</param>
        /// <param name="variable">Environment Variable name, e.g. PIHOME</param>
        /// <returns>The value of the Environment Variable, or empty string if not found</returns>
        public static string GetRemoteEnvironmentVariable(string machine, string variable)
        {
            var path = new ManagementPath($"\\\\{machine}");
            var options = new ConnectionOptions()
            {
                Impersonation = ImpersonationLevel.Impersonate,
                EnablePrivileges = true,
            };
            var mscope = new ManagementScope(path, options);
            var selectQuery = new SelectQuery($"select * from Win32_Environment where Name='{variable}'");
            using (var searcher = new ManagementObjectSearcher(mscope, selectQuery, null))
            {
                var objectCollection = searcher.Get();
                foreach (var envVar in objectCollection)
                {
                    return envVar["VariableValue"].ToString();
                }
            }

            return string.Empty;
        }
    }
}
