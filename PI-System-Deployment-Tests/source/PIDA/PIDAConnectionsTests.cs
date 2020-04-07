using System;
using System.Collections.Generic;
using System.Linq;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// PIDAConnectionTests Class.
    /// </summary>
    /// <remarks>
    /// This class encapsulates connection test for the PI System Deployment Tests.
    /// </remarks>
    [Collection("PI collection")]
    public class PIDAConnectionsTests : IClassFixture<PIFixture>
    {
        /// <summary>
        /// Constructor for PIDAConnectionTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage PI connection information.</param>
        public PIDAConnectionsTests(ITestOutputHelper output, PIFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private PIFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Exercises windows mappings connection.
        /// </summary>
        /// <remarks>
        /// This test requires that the user running the test should have a windows identity
        /// mapped to a PI Identity.
        /// <para>Test Steps:</para>
        /// <para>Disconnect PI Server</para>
        /// <para>Connect to PI Server again</para>
        /// <para>Check that a PI Identity is used by user for this connection</para>
        /// <para>Check logs for the windows login</para>
        /// </remarks>
        [Fact]
        public void WindowsIdMappingTest()
        {
            Utils.CheckTimeDrift(Fixture, Output);

            // Disconnect from the PISERVER
            Output.WriteLine($"Disconnect from PI Server [{Fixture.PIServer}].");
            Fixture.PIServer.Disconnect();

            AFTime startTime = AFTime.Now.ToPIPrecision();
            string startTimePI = PIDAUtilities.ToPiTimeString(startTime.LocalTime);

            // Connect again to check for the logs for identity used to get into PISERVER
            Output.WriteLine($"Reconnect to PI Server [{Fixture.PIServer}].");
            Fixture.PIServer.Connect();

            // window of time to check for logged messages
            AFTime endTime = startTime + TimeSpan.FromMinutes(5);
            string endTimePI = PIDAUtilities.ToPiTimeString(endTime.LocalTime);
            int expectedMsgID = 7082;

            Output.WriteLine($"Check if user is logged in through Windows Login.");
            AssertEventually.True(() =>
            {
                // Checks for windows login five times
                return PIDAUtilities.FindMessagesInLog(Fixture, startTimePI, endTimePI, expectedMsgID, "*Method: Windows Login*");
            },
            TimeSpan.FromSeconds(15),
            TimeSpan.FromSeconds(3),
            "Windows login not found.");
        }
    }
}
