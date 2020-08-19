using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using OSIsoft.AF.Asset;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests the ability to verify PI Points can be queried
    /// and get updated events
    /// </summary>
    [Collection("PI collection")]
    public class PIDATests : IClassFixture<PIFixture>
    {
        /// <summary>
        /// Constructor for PIDATests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage connection and specific helper functions</param>
        public PIDATests(ITestOutputHelper output, PIFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private PIFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Tests to see if the current patch of the PI Data Archive is applied
        /// </summary>
        /// <remarks>
        /// Errors if the current patch is not applied with a message telling the user to upgrade
        /// </remarks>
        [Fact]
        public void HaveLatestPatchDataArchive()
        {
            var factAttr = new GenericFactAttribute(TestCondition.PIDACURRENTPATCH, true);
            Assert.NotNull(factAttr);
        }

        /// <summary>
        /// Sends data to a set of new PI Points and verifies all events are archived. Then removes the PI Points.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive
        /// <para>Test Steps:</para>
        /// <para>Create a number of PI Points with compression off.</para>
        /// <para>Send a number of events to each PI Point, the event's value is calculated from the timestamp.</para>
        /// <para>Verify all events are archived.</para>
        /// <para>Delete all newly created PI Points.</para>
        /// </remarks>
        [Fact]
        public void ArchiveEventsTest()
        {
            int pointCount = 10;

            // Construct a unique PI Point name format using AFTime and '#'
            string pointPrefix = $"ArchiveEventsTest{AFTime.Now}";
            string pointName = $"{pointPrefix}###";

            try
            {
                Output.WriteLine($"Create {pointCount} PI Points on [{Settings.PIDataArchive}] with compression off.");
                IEnumerable<PIPoint> points = Fixture.CreatePIPoints(pointName, pointCount, true);
                var startTime = AFTime.Now.ToPIPrecision() + TimeSpan.FromDays(-1);
                int sleepTimeInSeconds = 5;

                // Send a number of events to each PI Point, the event's value is calculated from the timestamp
                int eventCount = 1000;
                Output.WriteLine($"Write {eventCount} events to each new PI Point.");
                Fixture.SendTimeBasedPIEvents(startTime, eventCount, points.ToList());

                // Sleep between sending and retrieving events
                Thread.Sleep(TimeSpan.FromSeconds(sleepTimeInSeconds));

                // Read PI events using a larger max event count, 2 * eventCount
                Output.WriteLine("Read all events from each PI Point.");
                IDictionary<string, AFValues> events = Fixture.ReadPIEvents(points, startTime, 2 * eventCount);

                // Check the total event count
                Output.WriteLine("Verify all events are archived.");
                int totalCount = events.Sum(evt => evt.Value.Count);
                Assert.True(pointCount * eventCount == totalCount,
                    $"Actual event count of {totalCount} is different from the expected event count of {pointCount * eventCount}.");

                // Check the data integrity of each PI Point
                Output.WriteLine("Verify the data integrity of all events.");
                Parallel.ForEach(events,
                    kvp =>
                    {
                        // Despite large max event count, the query should return the fed event count
                        Assert.True(eventCount == kvp.Value.Count,
                            $"Event count of {kvp.Value.Count} for [{kvp.Key}] is different from the expected event count of {eventCount}.");
                        kvp.Value.ForEach(value => Assert.True((float)value.Value == PIFixture.ConvertTimeStampToFloat(value.Timestamp),
                            $"[{kvp.Key}] shows unexpected value of [{value.Value}] at [{value.Timestamp}]."));
                    });
            }
            finally
            {
                Output.WriteLine("Delete all newly created PI Points.");
                Fixture.DeletePIPoints($"{pointPrefix}*", Output);
            }
        }

        /// <summary>
        /// Reads data from a set of SineWave PI Points and verifies the periodic pattern.
        /// </summary>
        /// <remarks>
        /// This test requires read access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Find a set of SineWave PI Points</para>
        /// <para>Read PI events from those PI Points in the past one day</para>
        /// <para>Verify the periodic pattern by comparing the events a half and a full wavelength apart</para>
        /// </remarks>
        [Fact]
        public void SineWaveEventsTest()
        {
            string query = $"name:{PIFixture.SineWavePointNameMask} AND PointSource:{PIFixture.TestPIPointSource}";

            Output.WriteLine($"Start to verify the SineWave wave pattern in PI Points matching [{query}] in the past one day.");
            IList<IEnumerable<PIPointQuery>> queries = PIPointQuery.ParseQuery(Fixture.PIServer, query);
            IEnumerable<PIPoint> pointList = PIPoint.FindPIPoints(Fixture.PIServer, queries).ToList();
            IDictionary<string, AFValues> sineEvents = Fixture.ReadPIEvents(pointList, new AFTime("*-1d"), AFTime.Now);

            int totalCheckedEventCount = 0;
            foreach (KeyValuePair<string, AFValues> kvp in sineEvents)
            {
                // Use Distinct() in case there are duplicate archived events
                var timedEvents = kvp.Value.Distinct().ToDictionary(val => val.Timestamp.LocalTime, val => val.ValueAsDouble());

                // Start for the oldest event and check events one by one
                foreach (KeyValuePair<DateTime, double> evt in timedEvents)
                {
                    var timestampAfterAHalfWave = evt.Key.AddSeconds(PIFixture.SineWaveLengthInHours * 1800);
                    var timestampAfterOneWave = evt.Key.AddSeconds(PIFixture.SineWaveLengthInHours * 3600);

                    if (timedEvents.ContainsKey(timestampAfterAHalfWave) && timedEvents.ContainsKey(timestampAfterOneWave))
                    {
                        // Based on the SineWave pattern, the current value should be equal to -1 * the value
                        // after a half wave and the value after a full wave.
                        Assert.True(
                            Math.Abs(evt.Value - (-1 * timedEvents[timestampAfterAHalfWave])) < PIFixture.Epsilon,
                            $"Found events in [{kvp.Key}] at [{evt.Key}] and [{timestampAfterAHalfWave}] not matching the SineWave pattern.");
                        Assert.True(
                            Math.Abs(evt.Value - timedEvents[timestampAfterOneWave]) < PIFixture.Epsilon,
                            $"Found events in [{kvp.Key}] at [{evt.Key}] and [{timestampAfterOneWave}] not matching the SineWave pattern.");

                        totalCheckedEventCount++;
                    }
                    else
                    {
                        // If the data set does not contain a key of timestampAfterOneWave, it means we have reached the end of set.
                        break;
                    }
                }
            }

            Output.WriteLine($"Successfully verified a total of {totalCheckedEventCount} SineWave values in {sineEvents.Count} PI Points.");
        }

        /// <summary>
        /// Retrieves PI events for multiple use cases from ClassData.
        /// </summary>
        /// <param name="pointMask">Name of PI POint on which to run query.</param>
        /// <param name="startTime">Starting time for query.</param>
        /// <param name="endTime">Ending time for query.</param>
        /// <remarks>
        /// This test requires read access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Execute PI data query using given data</para>
        /// <para>Record the pi event count found</para>
        /// </remarks>
        [Theory]
        [InlineData("OSIsoftTests.Region*Random", "-1h", "*-12h", 0.5, 1.5)]
        [InlineData("OSIsoftTests.Region*SineWave", "-6m", "*-12h", -10.0, 10.0)]
        [InlineData("OSIsoftTests.Region 1.Wind Farm 12.TUR12003.SineWave", "-4d", "*", -10.0, 10.0)]
        [InlineData("OSIsoftTests.Region 1.Wind Farm 12.TUR12004.SineWave", "-1h", "*", -10.0, 10.0)]
        public void ArchiveQueryTest(string pointMask, string startTime, string endTime, double minValue, double maxValue)
        {
            var now = AFTime.Now;
            var st = new AFTime(startTime, now);
            var et = new AFTime(endTime, now);

            Output.WriteLine($"Start to execute PI Data Archive queries on PI Points matching [{pointMask}] " +
                $"between [{st}] and [{et}].");

            IList<IEnumerable<PIPointQuery>> queries = PIPointQuery.ParseQuery(Fixture.PIServer, pointMask);
            IEnumerable<PIPoint> pointList = PIPoint.FindPIPoints(Fixture.PIServer, queries).ToList();
            IDictionary<string, AFValues> events = Fixture.ReadPIEvents(pointList, st, et);

            // Verify all event values are in the expected range
            foreach (var ptvaluespair in events)
            {
                foreach (var val in ptvaluespair.Value.Where(val => val.IsGood))
                {
                    var convertedValue = Convert.ToDouble(val.Value, CultureInfo.InvariantCulture);
                    Assert.True(convertedValue >= minValue && convertedValue <= maxValue,
                        $"[{ptvaluespair.Key}] has a value [{val.Value}] outside of expected data range of " +
                        $"[{minValue} ~ {maxValue}]");
                }
            }

            Output.WriteLine($"Found {events.Sum(kvp => kvp.Value.Count)} PI events.");
        }

        /// <summary>
        /// Verifies the PI Point count for a given PI Point mask is expected.
        /// </summary>
        /// <param name="query">Query string for PI Point search.</param>
        /// <param name="expectedCount">Expected PI Point count from search.</param>
        /// <remarks>
        /// This test requires read access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Execute PI Data Archive PI Point search</para>
        /// <para>Check whether the returned number is expected</para>
        /// ref. https://techsupport.osisoft.com/Documentation/PI-AF-SDK/html/b8fbb6da-7a4b-4570-a09d-7f2b85ed204d.htm
        /// </remarks>
        [Theory]
        [InlineData("PointSource:=OSIsoftTests", 814)]
        [InlineData("tag:=\"*Region 0*\" AND PointSource:=OSIsoftTests", 407)]
        [InlineData("tag:=\"*Wind Farm 0*\" AND PointSource:=OSIsoftTests", 400)]
        [InlineData("tag:=\"*Wind Farm 00*\" AND PointSource:=OSIsoftTests", 100)]
        [InlineData("tag:=*TUR12003* AND PointSource:=OSIsoftTests", 19)]
        [InlineData("tag:=\"*Lost Power*\" AND PointSource:=OSIsoftTests", 50)]
        [InlineData("tag:=*SineWave AND PointSource:=OSIsoftTests", 40)]
        public void PointSearchTest(string query, int expectedCount)
        {
            Output.WriteLine($"Search for PI Points using the query [{query}]. Expect to find {expectedCount} PI Points.");
            IList<IEnumerable<PIPointQuery>> queries = PIPointQuery.ParseQuery(Fixture.PIServer, query);
            IEnumerable<PIPoint> pointList = PIPoint.FindPIPoints(Fixture.PIServer, queries).ToList();
            int actualCount = pointList.Count();

            Assert.True(actualCount == expectedCount,
                $"Query [{query}] resulted in {actualCount} PI Points, expected {expectedCount}.");
        }
    }
}
