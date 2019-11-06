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
        /// This test requires that the user running the test should have their windows identity
        /// mapped to piadmins before running the test.
        /// <para>Test Steps:</para>
        /// <para>Disconnect PI Server</para>
        /// <para>Connect to PI Server again</para>
        /// <para>Check that piadmins is one of the user identities for this connection</para>
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

            Output.WriteLine($"Check if {PIFixture.RequiredPIIdentity} is one of the user identities.");
            AssertEventually.True(() =>
                {
                    // The test server is expected to have a mapping for the user running the tests mapped to piadmins.
                    // check piadmins identity is in the list
                    // Then we check if the Windows Login method is used
                    IList<PIIdentity> myCurrentList = Fixture.PIServer.CurrentUserIdentities;
                    myCurrentList.Single(x => x.Name.Equals(PIFixture.RequiredPIIdentity, StringComparison.OrdinalIgnoreCase));

                    // Checks for windows login five times
                    return PIDAUtilities.FindMessagesInLog(Fixture, startTimePI, endTimePI, expectedMsgID, "*Method: Windows Login*");
                },
                TimeSpan.FromSeconds(15),
                TimeSpan.FromSeconds(3),
                "Windows login not found.");
        }
    }
}
