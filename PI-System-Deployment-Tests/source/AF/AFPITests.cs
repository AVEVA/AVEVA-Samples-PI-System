using System;
using System.Collections.Generic;
using System.Diagnostics.Contracts;
using System.Globalization;
using System.Linq;
using OSIsoft.AF;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class exercises PI DataPipe and PI StateSet operations on the Data Archive.
    /// </summary>
    [Collection("AF collection")]
    public class AFPITests : IClassFixture<AFFixture>, IClassFixture<PIFixture>
    {
        /// <summary>
        /// Constructor for PITests Class
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="afFixture">AF Fixture to manage connection and AF related helper functions.</param>
        /// <param name="piFixture">PI Fixture to manage connection and Data Archive related helper functions.</param>
        public AFPITests(ITestOutputHelper output, AFFixture afFixture, PIFixture piFixture)
        {
            Output = output;
            AFFixture = afFixture;
            PIFixture = piFixture;
        }

        private AFFixture AFFixture { get; }
        private PIFixture PIFixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Exercises PIDataPipe TimeSeries sign up operations.
        /// </summary>
        /// <param name="piPointType">Type of the PI Point to be signed up with the PIDataPipe.</param>
        /// <param name="eventValues">Values to be written to the PI Point and verified received by the PIDataPipe.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create PI Points of the expected type(one for each expected value)</para>
        /// <para>Create a TestSeries PIDataPipe and sign up the PI Points to it</para>
        /// <para>Write one test value to each PI Point(historical and future) and verify the events from the PIDataPipe</para>
        /// <para>Remove the sign ups, dispose the PIDataPipe and delete the test PI Points</para>
        /// </remarks>
        [Theory]
        [InlineData(PIPointType.Int16, new object[] { (short)1, (short)2, (short)3 })]
        [InlineData(PIPointType.Int32, new object[] { 1024, 2048, 4096 })]
        [InlineData(PIPointType.Float32, new object[] { 265.123F, 4.1e23F, 9.2e-19F })]
        [InlineData(PIPointType.Float64, new object[] { 121.11, 1.7e200, 3.5e-275 })]
        [InlineData(PIPointType.String, new string[] { "Test", "String", "Here" })]
        [InlineData(PIPointType.Digital, new object[] { 1, 2, 3 })]
        [InlineData(PIPointType.Timestamp, new string[] { "1/1/2019 12:00:00 AM", "1/2/2019 12:00:00 AM", "1/3/2019 12:00:00 AM" })]
        public void PIDataPipeTimeSeriesTest(PIPointType piPointType, object[] eventValues)
        {
            Contract.Requires(eventValues != null);

            const string PointName = "PIDataPipeTests_PIPoint";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var piDataPipe = new PIDataPipe(AFDataPipeType.TimeSeries);

            var piPointList = new PIPointList();
            var now = AFTime.NowInWholeSeconds;

            try
            {
                Output.WriteLine("Create the Future PI Points with Zero Compression and specified PI Point type.");
                PIFixture.DeletePIPoints(PointName + "*", Output);
                var testPIPoints = PIFixture.CreatePIPoints(PointName + "###", eventValues.Length, new Dictionary<string, object>
                {
                    { PICommonPointAttributes.PointType, piPointType },
                    { PICommonPointAttributes.ExceptionDeviation, 0 },
                    { PICommonPointAttributes.ExceptionMaximum, 0 },
                    { PICommonPointAttributes.Compressing, 0 },
                    { PICommonPointAttributes.DigitalSetName, "Phases" },
                    { PICommonPointAttributes.Future, true },
                });
                Assert.True(testPIPoints.Count() == eventValues.Length, $"Unable to create all the test PI Points.");
                piPointList.AddRange(testPIPoints);

                // Add the PI Point as sign up to the PIDataPipe.
                Output.WriteLine($"Sign up all PI Points with PIDataPipe.");
                var afErrors = piDataPipe.AddSignups(piPointList);
                var prefixErrorMessage = "Adding sign ups to the PIDataPipe was unsuccessful.";
                Assert.True(afErrors == null,
                    userMessage: afErrors?.Errors.Aggregate(prefixErrorMessage, (msg, error) => msg += $" PI Point: [{error.Key.Name}] Error: [{error.Value.Message}] "));

                // Write one data value to each PI Point.
                var expectedAFValues = new AFValues();
                for (int i = 0; i < eventValues.Length; i++)
                {
                    AFValue afValue = null;
                    var timestamp = now + TimeSpan.FromMinutes(i - eventValues.Length);

                    // Special Handling of Input Data for Digital and Timestamp
                    switch (piPointType)
                    {
                        case PIPointType.Digital:
                            afValue = new AFValue(new AFEnumerationValue("Phases", (int)eventValues[i]), timestamp);
                            break;
                        case PIPointType.Timestamp:
                            afValue = new AFValue(new AFTime(eventValues[i], now), timestamp);
                            break;
                        default:
                            afValue = new AFValue(eventValues[i], timestamp);
                            break;
                    }

                    Output.WriteLine($"Writing Value [{eventValues[i]}] with Timestamp [{timestamp}] to PI Point [{piPointList[i].Name}].");
                    piPointList[i].UpdateValue(afValue, AFUpdateOption.InsertNoCompression);

                    // If writing digital states, we need to save the corresponding value for verification.
                    // Since we are using Phases, 0 ~ Phase1, 1 ~ Phase2, etc.
                    if (piPointType == PIPointType.Digital)
                    {
                        int input = (int)eventValues[i];
                        afValue = new AFValue(new AFEnumerationValue($"Phase{input + 1}", input), timestamp);
                    }

                    afValue.PIPoint = piPointList[i];
                    expectedAFValues.Add(afValue);
                }

                // Retry assert to retrieve expected Update Events from the PIDataPipe
                var actualAFValues = new AFValues();
                Output.WriteLine($"Reading Events from the PI DataPipe.");
                AssertEventually.True(() =>
                {
                    var updateEvents = piDataPipe.GetUpdateEvents(eventValues.Length);

                    prefixErrorMessage = "Retrieving Update Events from the PIDataPipe was unsuccessful.";
                    Assert.False(updateEvents.HasErrors,
                        userMessage: updateEvents.Errors?.Aggregate(prefixErrorMessage, (msg, error) => msg += $" PI Point: [{error.Key.Name}] Error: [{error.Value.Message}] "));

                    actualAFValues.AddRange(updateEvents.Results.Select(update => update.Value));
                    if (actualAFValues.Count >= expectedAFValues.Count)
                    {
                        // Verify that all expected update events are received from the PIDataPipe
                        Assert.True(expectedAFValues.Count == actualAFValues.Count, "PIDataPipe returned more events than expected. " +
                            $"Expected Count: {expectedAFValues.Count}, Actual Count: {actualAFValues.Count}.");
                        return true;
                    }

                    return false;
                },
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(0.5),
                "Unable to retrieve events within the time frame.");

                // Verify all received events.
                Output.WriteLine($"Verifying all {actualAFValues.Count} events from the PI DataPipe.");
                for (int i = 0; i < actualAFValues.Count; i++)
                {
                    // Special handling of Output events for Timestamp
                    if (piPointType == PIPointType.Timestamp)
                        actualAFValues[i].Value = new AFTime(actualAFValues[i].Value, now);

                    AFFixture.CheckAFValue(actualAFValues[i], expectedAFValues[i]);
                    Assert.True(object.Equals(actualAFValues[i].PIPoint, expectedAFValues[i].PIPoint),
                        $"Unexpected PI Point Association. Expected: [{expectedAFValues[i].PIPoint}], Actual: [{actualAFValues[i].PIPoint}].");
                }

                // Remove all sign ups from the PIDataPipe
                Output.WriteLine($"Remove all PI Point sign ups from PIDataPipe.");
                afErrors = piDataPipe.RemoveSignups(piPointList);
                prefixErrorMessage = "Removing sign ups to the PIDataPipe was unsuccessful.";
                Assert.True(afErrors == null,
                    userMessage: afErrors?.Errors.Aggregate(prefixErrorMessage, (msg, error) => msg += $" PI Point: [{error.Key.Name}] Error: [{error.Value.Message}] "));

                // Write dummy values to the PI Points and confirm PI DataPipe receives none.
                Output.WriteLine($"Write dummy values to the PI Points.");
                for (int i = 0; i < eventValues.Length; i++)
                {
                    piPointList[i].UpdateValue(new AFValue(eventValues[i], now), AFUpdateOption.InsertNoCompression);
                }

                Output.WriteLine($"Verify no events are received by the PIDataPipe.");
                var noEvents = piDataPipe.GetUpdateEvents(eventValues.Length);
                prefixErrorMessage = "Retrieving Update Events from the PIDataPipe was unsuccessful.";
                Assert.False(noEvents.HasErrors,
                    userMessage: noEvents.Errors?.Aggregate(prefixErrorMessage, (msg, error) => msg += $" PI Point: [{error.Key.Name}] Error: [{error.Value.Message}] "));

                Assert.True(noEvents.Count == 0, "PIDataPipe received events even after removing all sign ups.");
            }
            finally
            {
                piDataPipe.RemoveSignups(piPointList);
                piDataPipe.Dispose();
                PIFixture.DeletePIPoints(PointName + "*", Output);
            }
        }

        /// <summary>
        /// Exercise Create/Read/Update/Delete operations on PIStateSets.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a new state set with specified states</para>
        /// <para>Retrieve the set and confirm the last state is contained in the set</para>
        /// <para>Remove the last state and add a new state, confirm only the new state exists in the set</para>
        /// <para>Delete the set and confirm it no longer can be retrieved</para>
        /// </remarks>
        [Fact]
        public void PIStateSetsTest()
        {
            PIServer piServer = PIFixture.PIServer;
            const string TestState = "|[]{}:;<>,.?/\\\"'~`";
            string[] setValues = { string.Empty, null, "(!@#$%^&*+-=)", "    ", "valid", "valid", "    test    ", "   test       ", TestState };

            const string SetName = "PIStateSetsTests";

            try
            {
                // Create
                Output.WriteLine($"Creating digital state set [{SetName}] on [{piServer.Name}].");
                var set = piServer.StateSets.Add(SetName);
                var stateCount = 0;
                foreach (var state in setValues)
                {
                    set.Add(state, stateCount++);
                }

                set.CheckIn();
                piServer.Refresh();

                // Read
                Output.WriteLine($"Reading digital state set [{SetName}] on [{piServer.Name}].");
                var actualSet = piServer.StateSets[SetName];
                Assert.True(actualSet != null, $"The digital state set [{SetName}] could not be read.");
                Assert.True(actualSet.Contains(TestState), $"The digital state set [{SetName}] did not contain the state [{TestState}].");

                // Update
                Output.WriteLine($"Removing digital state [{TestState}] in set [{SetName}] on [{piServer.Name}].");
                var lastState = set[TestState];
                set.Remove(lastState);
                set.CheckIn();
                piServer.Refresh();
                actualSet = piServer.StateSets[SetName];
                Assert.False(actualSet.Contains(lastState), $"The digital state set [{set}] still contains the state [{TestState}] after removal.");

                const string TestStateNew = "|[]{}:;<>,.?/\\\"'~`New";
                Output.WriteLine($"Adding digital state [{TestStateNew}] in set [{SetName}] on [{piServer.Name}].");
                set.Add(TestStateNew, lastState.Value);
                set.CheckIn();
                piServer.Refresh();
                actualSet = piServer.StateSets[SetName];
                var newState = set[TestStateNew];
                Assert.True(actualSet.Contains(newState), $"The digital state set [{set}] does not contain the state [{TestStateNew}] after being added.");

                // Delete
                Output.WriteLine($"Removing digital state set [{SetName}] on [{piServer.Name}].");
                piServer.StateSets.Remove(SetName);
                piServer.Refresh();
                actualSet = piServer.StateSets[SetName];
                Assert.True(actualSet == null, $"The digital state set [{SetName}] still exists after deletion.");
            }
            finally
            {
                piServer.Refresh();
                if (piServer.StateSets[SetName] != null)
                    piServer.StateSets.Remove(SetName);
            }
        }

        /// <summary>
        /// Create, Read, Update and Delete a PI Point.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point with custom attribute values</para>
        /// <para>Confirm the PI Point is created on the server</para>
        /// <para>Change the values of the PI Points and confirm that the change is reflected</para>
        /// <para>Delete the PI Point</para>
        /// </remarks>
        [Fact]
        public void PIPointTest()
        {
            PIServer piServer = PIFixture.PIServer;
            string namePIPointTag = "PIPointTest_Point";
            string[] myPtAttributes = { PICommonPointAttributes.Step, PICommonPointAttributes.PointType };
            try
            {
                // If PI Point exists, delete it
                PIFixture.RemovePIPointIfExists(namePIPointTag, Output);

                // Create attribute values for the PI Point
                var attributeValues = new Dictionary<string, object>
                {
                    { "pointtype", "float32" },
                    { "step", 0 },
                    { "compressing", 0 },
                    { "excmin", 0 },
                    { "excmax", 0 },
                    { "excdev", 0 },
                    { "excdevpercent", 0 },
                    { "shutdown", 0 },
                };

                // Create PI Point
                Output.WriteLine($"Creating PI Point {namePIPointTag} with custom attributes.");
                var point = piServer.CreatePIPoint(namePIPointTag, attributeValues);

                // Update
                Output.WriteLine($"Confirm PI Point [{namePIPointTag}] was created with correct custom attributes.");
                var returnedPoint = PIPoint.FindPIPoint(piServer, namePIPointTag);
                Assert.True(returnedPoint != null, $"Could not find PI Point [{namePIPointTag}] on Data Archive [{piServer}].");
                var originalAttributes = returnedPoint.GetAttributes(myPtAttributes);
                Assert.True(originalAttributes.Count > 0, $"Could not find any attributes for PI Point [{namePIPointTag}].");
                Assert.False(Convert.ToBoolean(originalAttributes[PICommonPointAttributes.Step], CultureInfo.InvariantCulture),
                    $"Expected the Step PI Point attribute to be originally false for PI Point [{namePIPointTag}].");
                var pointType = originalAttributes[PICommonPointAttributes.PointType].ToString();
                Assert.True(pointType.Equals("Float32", StringComparison.OrdinalIgnoreCase),
                    $"Expected the Point Type for PI Point [{namePIPointTag}] to be Float32, was actually [{pointType}].");

                Output.WriteLine($"Setting Step PI Point attribute to true for {namePIPointTag}.");
                returnedPoint.SetAttribute(PICommonPointAttributes.Step, true);
                returnedPoint.SaveAttributes(new string[] { PICommonPointAttributes.Step });
                Assert.True(returnedPoint.Step, $"Expected the Step PI Point attribute to be true for PI Point [{namePIPointTag}] after being set.");
            }
            finally
            {
                PIFixture.DeletePIPoints(namePIPointTag, Output);
            }
        }

        /// <summary>
        /// Create, Read, Update and Delete multiple PI Points.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create PI Points with default attribute values</para>
        /// <para>Confirm the PI Points are created on the server</para>
        /// <para>Change the values of the PI Points and confirm that the change is reflected</para>
        /// <para>Delete the PI Points</para>
        /// </remarks>
        [Fact]
        public void PIPointsTest()
        {
            PIServer piServer = PIFixture.PIServer;
            int count = 10;
            var pointPrefix = "PIPointsTest_Point";
            try
            {
                // Create PI Point and verify
                Output.WriteLine($"Creating PI Points with prefix [{pointPrefix}] with default attributes and verifying.");
                var points = PIFixture.CreatePIPoints($"{pointPrefix}#", count);
                var returnedPoints = PIPoint.FindPIPoints(piServer, $"{pointPrefix}*");
                Assert.True(returnedPoints.Count() == count, $"Expected to find {count} PI Points on Data Archive [{piServer}], actually found {returnedPoints.Count()}.");

                var timestamp = new AFTime("*-10m");

                // Set Value of PI Points
                Output.WriteLine("Updating PI Points with new values.");
                for (int i = 0; i < returnedPoints.Count(); i++)
                {
                    returnedPoints.ElementAt(i).UpdateValue(new AFValue(i, timestamp), AFUpdateOption.NoReplace);
                }

                // Check for updated values
                Output.WriteLine("Checking PI Points were updated with new values.");
                for (int i = 0; i < count; i++)
                {
                    AssertEventually.Equals(returnedPoints.ElementAt(i).CurrentValue(), new AFValue(Convert.ToSingle(i), timestamp.ToPIPrecision()));
                }

                // Delete PI Points and verify
                Output.WriteLine("Deleting PI Points that were created and verifying.");
                PIFixture.DeletePIPoints($"{pointPrefix}*", Output);
                returnedPoints = PIPoint.FindPIPoints(piServer, $"{pointPrefix}*");
                Assert.True(returnedPoints.Count() == 0,
                    $"Expected to find no PI Points with prefix [{pointPrefix}], but {returnedPoints.Count()} were found.");
            }
            finally
            {
                PIFixture.DeletePIPoints($"{pointPrefix}*", Output);
            }
        }

        /// <summary>
        /// Search for PI Points.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create PI Points and assign custom values</para>
        /// <para>Search for PI Points with different queries</para>
        /// <para>Delete the PI Points</para>
        /// </remarks>
        [Fact]
        public void PIPointSearchTest()
        {
            PIServer piServer = PIFixture.PIServer;
            int numberOfPointsToCreate = 10;
            var pointPrefix = "PIPointSearchTest_Point";

            try
            {
                // Create PI Points
                Output.WriteLine($"Creating PI Points with prefix [{pointPrefix}].");
                var points = PIFixture.CreatePIPoints($"{pointPrefix}#", numberOfPointsToCreate);

                // Assign range of values to defined tags
                for (int i = 0; i < points.Count(); i++)
                {
                    points.ElementAt(i).UpdateValue(new AFValue(Math.Pow(-1, i + 1), null), 0);

                    // Set the Step attribute of half of the PI Points to true and half to false
                    points.ElementAt(i).SetAttribute(PICommonPointAttributes.Step, Convert.ToBoolean(1 * ((i + 1) % 2)));
                    points.ElementAt(i).SaveAttributes();
                }

                // Search PI Points with queries
                var searchQuery = $"Name:'{pointPrefix}*' value:>0";
                Output.WriteLine($"Searching for PI Points with query [{searchQuery}].");
                var parsedQuery = PIPointQuery.ParseQuery(piServer, searchQuery);
                var searchPointsCount = PIPoint.FindPIPoints(piServer, parsedQuery).Count();
                AssertEventually.True(
                    () => PIPoint.FindPIPoints(piServer, parsedQuery).Count() == (numberOfPointsToCreate / 2),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromSeconds(0.5),
                    $"The PI Points count do not match. Expected: {numberOfPointsToCreate / 2}, Actual: {searchPointsCount}.");
                
                searchQuery = $"Name:'{pointPrefix}*'";
                Output.WriteLine($"Searching for PI Points with query [{searchQuery}].");
                parsedQuery = PIPointQuery.ParseQuery(piServer, searchQuery);
                searchPointsCount = PIPoint.FindPIPoints(piServer, parsedQuery).Count();
                AssertEventually.True(
                    () => PIPoint.FindPIPoints(piServer, parsedQuery).Count() == numberOfPointsToCreate,
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromSeconds(0.5),
                    $"The PI Points count do not match. Expected: {numberOfPointsToCreate}, Actual: {searchPointsCount}.");

                searchQuery = $"Name:'{pointPrefix}*' step:=0";
                Output.WriteLine($"Searching for PI Points with query [{searchQuery}].");
                parsedQuery = PIPointQuery.ParseQuery(piServer, searchQuery);
                searchPointsCount = PIPoint.FindPIPoints(piServer, parsedQuery).Count();
                AssertEventually.True(
                    () => PIPoint.FindPIPoints(piServer, parsedQuery).Count() == (numberOfPointsToCreate / 2),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromSeconds(0.5),
                    $"The PI Points count do not match. Expected: {numberOfPointsToCreate / 2}, Actual: {searchPointsCount}.");
            }
            finally
            {
                PIFixture.DeletePIPoints("PIPointSearchTest_Point*", Output);
            }
        }
    }
}
