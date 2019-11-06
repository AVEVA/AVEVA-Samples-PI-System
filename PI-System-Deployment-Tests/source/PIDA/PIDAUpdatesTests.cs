using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using OSIsoft.AF;
using OSIsoft.AF.Data;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests the ability to sign up for updates on a PI Point
    /// on the PI Data Archive.
    /// </summary>
    [Collection("PI collection")]
    public class PIDAUpdatesTests : IClassFixture<PIFixture>
    {
        /// <summary>
        /// Constructor for PIDAUpdatesTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage PI connection information.</param>
        public PIDAUpdatesTests(ITestOutputHelper output, PIFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private PIFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Exercises signing up for time series events on a PI Point and receiving event notifications.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Create a PI Point with compression off</para>
        /// <para>Sign up for time-series updates on this PI Point</para>
        /// <para>Send a number of events to this PI Point and verify that they are all received</para>
        /// <para>Delete all newly created PI Points</para>
        /// </remarks>
        [Fact]
        public void TimeSeriesUpdatesTest()
        {
            // Construct a unique PI Point name
            string pointNameFormat = $"TimeSeriesUpdateTestPoint{AFTime.Now}";

            bool signupCompleted = false;
            using (var myDataPipe = new PIDataPipe(AFDataPipeType.TimeSeries))
            {
                Output.WriteLine($"Create a PI Point on [{Settings.PIDataArchive}] with compression off.");
                var points = Fixture.CreatePIPoints(pointNameFormat, 1, true);

                try
                {
                    Output.WriteLine($"Sign up for time-series updates on PI Point [{pointNameFormat}].");
                    myDataPipe.AddSignups(points.ToList());
                    signupCompleted = true;

                    var startTime = AFTime.Now.ToPIPrecision() + TimeSpan.FromDays(-1);
                    int eventCount = 1000;
                    int totalCount = 0;

                    // Send events to each PI Point, the event's value is calculated from the timestamp
                    Output.WriteLine($"Write {eventCount} events to the new PI Point.");
                    Fixture.SendTimeBasedPIEvents(startTime, eventCount, points.ToList());

                    // Checks if Update Events are retrieved a few times
                    Output.WriteLine($"Get the update events.");

                    var eventsRetrieved = new AFListResults<PIPoint, AFDataPipeEvent>();
                    AssertEventually.True(() =>
                    {
                        eventsRetrieved = myDataPipe.GetUpdateEvents(eventCount);
                        totalCount += eventsRetrieved.Count();
                        return totalCount == eventCount;
                    },
                    TimeSpan.FromSeconds(60),
                    TimeSpan.FromSeconds(1),
                    $"Failed to retrieve {eventCount} update events, retrieved {totalCount} instead.");
                    Output.WriteLine("Retrieved update events successfully.");
                }
                finally
                {
                    if (signupCompleted)
                        myDataPipe.RemoveSignups(points.ToList());

                    Output.WriteLine("Delete all newly created PI Points.");
                    Fixture.DeletePIPoints(pointNameFormat, Output);
                }
            }
        }

        /// <summary>
        /// Exercises signing up for PI Point changes and receiving change notifications.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Create a PI Point (change #1)</para>
        /// <para>Rename(change #2) and delete(change #3) the PI Point to cause a change</para>
        /// <para>Sign up for updates on this PI Point</para>
        /// <para>Verify 3 changes count is received through the sign up</para>
        /// </remarks>
        [Fact]
        public void PointUpdatesTest()
        {
            // Construct a unique PI Point name
            string pointNameFormat = $"PointUpdateTestPoint{AFTime.Now}";

            // Expected number of changes
            const int ExpectedChangeCount = 3;
            var nameOfPointToDelete = pointNameFormat;

            Utils.CheckTimeDrift(Fixture, Output);
            PIPointChangesCookie cookie = null;
            try
            {
                // Initialize to start monitoring changes
                Output.WriteLine($"Prepare to receive PI Point change notifications.");
                Fixture.PIServer.FindChangedPIPoints(int.MaxValue, null, out cookie);

                // Perform the operation 10 times...
                Output.WriteLine($"Create PI Points and process change notifications.");
                for (int loopIndex = 0; loopIndex < 10; loopIndex++)
                {
                    // Create a new PI Point which should cause a change (#1)
                    PIPoint testPoint = Fixture.PIServer.CreatePIPoint(pointNameFormat);
                    nameOfPointToDelete = pointNameFormat;

                    // Edit the PI Point's name to cause a change (#2)
                    testPoint.Name = string.Concat(testPoint.Name, "_Renamed");
                    nameOfPointToDelete = testPoint.Name;

                    // Delete the PI Point which should cause a change (#3)
                    Fixture.PIServer.DeletePIPoint(testPoint.Name);

                    // Sleep a bit to make sure all processing has completed
                    Thread.Sleep(TimeSpan.FromSeconds(3));

                    // Log changes that have occurred since the last call
                    var changes = Fixture.PIServer.FindChangedPIPoints(
                        int.MaxValue, cookie, out cookie, new PIPointList() { testPoint });

                    if (changes != null)
                    {
                        foreach (var info in changes)
                        {
                            Output.WriteLine($"Change [{info.Action}] made on point with ID [{info.ID}].");
                            Assert.True(testPoint.ID == info.ID, $"Expected change on point with ID: [{testPoint.ID}], Actual change point ID: [{info.ID}].");
                        }

                        Assert.True(changes.Count == ExpectedChangeCount,
                            $"Expected the number of change to be {ExpectedChangeCount}, but there were actually {changes.Count} on iteration {loopIndex + 1}.");
                    }
                }

                Output.WriteLine("Retrieved PI Point change notifications successfully.");
            }
            finally
            {
                Fixture.DeletePIPoints($"{pointNameFormat}*", Output);
                Fixture.DeletePIPoints($"{nameOfPointToDelete}*", Output);

                cookie?.Dispose();
            }
        }
    }
}
