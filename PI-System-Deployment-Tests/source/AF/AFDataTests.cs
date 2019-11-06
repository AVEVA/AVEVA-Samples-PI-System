using System;
using System.Collections.Generic;
using System.Diagnostics.Contracts;
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
    /// This class exercises various PI Point Data methods on PI Points created on the Data Archive
    /// in the AF Server.
    /// </summary>
    [Collection("AF collection")]
    public class AFDataTests : IClassFixture<AFFixture>, IClassFixture<PIFixture>
    {
        /// <summary>
        /// Constructor for AFDataTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="afFixture">AF Fixture to manage connection and AF related helper functions.</param>
        /// <param name="piFixture">PI Fixture to manage connection and Data Archive related helper functions.</param>
        public AFDataTests(ITestOutputHelper output, AFFixture afFixture, PIFixture piFixture)
        {
            Output = output;
            AFFixture = afFixture;
            PIFixture = piFixture;
        }

        private AFFixture AFFixture { get; }

        private PIFixture PIFixture { get; }

        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Exercises RecordedValue Method.
        /// </summary>
        /// <param name="inputValues">Array of input values.</param>
        /// <param name="inputTimestamps">Array of input timestamps.</param>
        /// <param name="step">Step attribute for the PI Point.</param>
        /// <param name="retrievalMode">Retrieval mode used as argument into RecordedValue call.</param>
        /// <param name="recordedValueTimestamp">Timestamp passed as argument into RecordedValue call.</param>
        /// <param name="expectedResult">The expected value of the Attribute.</param>
        /// <param name="outputTimeString">Timestamp of the event returned by RecordedValue.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point</para>
        /// <para>Create an Element with an Attribute pointing at the PI Point</para>
        /// <para>Make RecordedValue call against Attribute and check values returned</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData(new object[] { 3f, 4f, 5f }, new object[] { "y", "y+12h", "t" }, false, "After", "y+12h", 5f, "t")]
        [InlineData(new object[] { 3f, 4f, 5f }, new object[] { "y", "y+12h", "t" }, false, "AtOrAfter", "y+12h", 4f, "y+12h")]
        [InlineData(new object[] { 3f, 4f, 5f }, new object[] { "y", "y+12h", "t" }, false, "AtOrBefore", "y+12h", 4f, "y+12h")]
        [InlineData(new object[] { 3f, 4f, 5f }, new object[] { "y", "y+12h", "t" }, false, "Auto", "y+12h", 4f, "y+12h")]
        [InlineData(new object[] { 3f, 4f, 5f }, new object[] { "y", "y+12h", "t" }, false, "Before", "y+12h", 3f, "y")]
        [InlineData(new object[] { 3f, 4f, 5f }, new object[] { "y", "y+12h", "t" }, false, "Exact", "y+12h", 4f, "y+12h")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, false, "After", "y+12h", 5f, "t")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, false, "AtOrAfter", "y+12h", 5f, "t")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, false, "AtOrBefore", "y+12h", 3f, "y")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, false, "Auto", "y+12h", 4f, "y+12h")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, false, "Before", "y+12h", 3f, "y")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, false, "Exact", "y+12h", "No Data", "y+12h")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, true, "After", "y+12h", 5f, "t")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, true, "AtOrAfter", "y+12h", 5f, "t")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, true, "AtOrBefore", "y+12h", 3f, "y")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, true, "Auto", "y+12h", 3f, "y")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, true, "Before", "y+12h", 3f, "y")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, true, "Exact", "y+12h", "No Data", "y+12h")]
        public void RecordedValueTest(object[] inputValues, object[] inputTimestamps, bool step, string retrievalMode, string recordedValueTimestamp, object expectedResult, string outputTimeString)
        {
            Contract.Requires(inputValues != null);
            Contract.Requires(inputTimestamps != null);
            Contract.Requires(expectedResult != null);

            const string TestName = "RecordedValueTests";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;

            try
            {
                Assert.True(inputValues.Length == inputTimestamps.Length,
                    $"For retrievalMode {retrievalMode}, the number of input values does not equal the number of input timestamps.");

                // Create the PI Point
                PIFixture.DeletePIPoints(PointName, Output);
                Output.WriteLine($"Creating PI Point [{PointName}] with Step attribute value {step}.");
                PIFixture.CreatePIPoints(PointName, 1, new Dictionary<string, object>() { { PICommonPointAttributes.Step, step } });

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point DR and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";
                db.CheckIn();

                // Write values to Data Archive
                for (int i = 0; i < inputValues.Length; i++)
                {
                    if (inputValues[i] != null)
                    {
                        attribute.Data.UpdateValue(new AFValue(attribute, inputValues[i], new AFTime(inputTimestamps[i], now)), AFUpdateOption.Insert);
                    }
                }

                // Determine min and max times of inputs
                var minTime = AFTime.MaxValue;
                var maxTime = AFTime.MinValue;
                for (int i = 0; i < inputTimestamps.Length; i++)
                {
                    if (inputTimestamps[i] != null)
                    {
                        var tmpTime = new AFTime(inputTimestamps[i], now);
                        if (tmpTime < minTime)
                            minTime = tmpTime;
                        if (tmpTime > maxTime)
                            maxTime = tmpTime;
                    }
                }

                var expectedValueCount = inputValues.Where(val => val != null).Count();

                // Wait at least 10 times to wait for data to get to Data Archive
                AssertEventually.True(
                    () => attribute.Data.RecordedValues(new AFTimeRange(minTime, maxTime), AFBoundaryType.Inside, null, null, false).Count == expectedValueCount,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromSeconds(0.5),
                    $"Did not find the [{expectedValueCount}] expected values in [{attribute.Name}] from the Data Archive.");

                AFValue expectedValue = null;
                if (expectedResult.ToString() == "No Data")
                    expectedValue = new AFValue(attribute, new AFEnumerationValue("No Data", 248), new AFTime(outputTimeString, now), null, AFValueStatus.Bad);
                else
                    expectedValue = new AFValue(attribute, expectedResult, new AFTime(outputTimeString, now));

                Output.WriteLine("Calling RecordedValues() and checking values.");
                var actualValue = new AFValue();
                switch (retrievalMode)
                {
                    case "After":
                        actualValue = attribute.Data.RecordedValue(new AFTime(recordedValueTimestamp, now), AFRetrievalMode.After, null);
                        break;
                    case "AtOrAfter":
                        actualValue = attribute.Data.RecordedValue(new AFTime(recordedValueTimestamp, now), AFRetrievalMode.AtOrAfter, null);
                        break;
                    case "AtOrBefore":
                        actualValue = attribute.Data.RecordedValue(new AFTime(recordedValueTimestamp, now), AFRetrievalMode.AtOrBefore, null);
                        break;
                    case "Auto":
                        actualValue = attribute.Data.RecordedValue(new AFTime(recordedValueTimestamp, now), AFRetrievalMode.Auto, null);
                        break;
                    case "Before":
                        actualValue = attribute.Data.RecordedValue(new AFTime(recordedValueTimestamp, now), AFRetrievalMode.Before, null);
                        break;
                    case "Exact":
                        actualValue = attribute.Data.RecordedValue(new AFTime(recordedValueTimestamp, now), AFRetrievalMode.Exact, null);
                        break;
                    default:
                        Assert.True(false, $"Invalid retrieval mode {retrievalMode}.");
                        break;
                }

                AFFixture.CheckAFValue(actualValue, expectedValue);
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                PIFixture.DeletePIPoints(PointName, Output);
            }
        }

        /// <summary>
        /// Exercises RecordedValues Method.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point</para>
        /// <para>Create an Element with an Attribute pointing at the PI Point</para>
        /// <para>Make RecordedValues call against Attribute and check values returned</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Fact]
        public void RecordedValuesTest()
        {
            const string TestName = "RecordedValuesTests";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;
            var yesterday = new AFTime("y", now);
            var today = new AFTime("t", now);
            var tr = new AFTimeRange(yesterday, today);

            try
            {
                // Create the PI Point
                PIFixture.DeletePIPoints(PointName, Output);
                Output.WriteLine($"Creating PI Point {PointName}");
                PIFixture.CreatePIPoints(PointName, 1);

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point DR and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";
                db.CheckIn();

                var expectedValues = new AFValues
                {
                    new AFValue(attribute, 3, yesterday),
                    new AFValue(attribute, 5, today),
                };

                // Send some values to the PI Point
                attribute.Data.UpdateValues(expectedValues, AFUpdateOption.Insert);

                AFValues actualValues = null;

                // Wait at least 10 times to wait for data to get to Data Archive
                AssertEventually.True(
                    () => attribute.Data.RecordedValues(tr, AFBoundaryType.Inside, null, null, false).Count > 1,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromSeconds(0.5),
                    $"Both values are not found in the Data Archive in the time range [{tr}].");

                // Verifies values
                Output.WriteLine("Calling RecordedValues() and checking values.");
                actualValues = attribute.Data.RecordedValues(tr, AFBoundaryType.Inside, null, null, false);
                AFFixture.CheckAFValues(actualValues, expectedValues, Output);
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                PIFixture.DeletePIPoints(PointName, Output);
            }
        }

        /// <summary>
        /// Exercises RecordedValuesByCount Method.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point</para>
        /// <para>Create an Element with an Attribute pointing at the PI Point</para>
        /// <para>Make RecordedValuesByCount call against Attribute and check values returned</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Fact]
        public void RecordedValuesByCountTest()
        {
            const string TestName = "RecordedValuesTests";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;
            var yesterday = new AFTime("y", now);
            var today = new AFTime("t", now);
            var readStartTime = yesterday + TimeSpan.FromHours(12);
            var tr = new AFTimeRange(yesterday, today);

            try
            {
                // Create the PI Point
                PIFixture.DeletePIPoints(PointName, Output);
                Output.WriteLine($"Creating PI Point [{PointName}].");
                PIFixture.CreatePIPoints(PointName, 1);

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point DR and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";
                db.CheckIn();

                var expectedValue1 = new AFValue(attribute, 3, yesterday);
                var expectedValue2 = new AFValue(attribute, 5, today);

                // Send some values to the PI Point
                attribute.Data.UpdateValue(expectedValue1, AFUpdateOption.Insert);
                attribute.Data.UpdateValue(expectedValue2, AFUpdateOption.Insert);

                // Wait at least 10 times to wait for data to get to Data Archive
                AssertEventually.True(
                    () => attribute.Data.RecordedValues(tr, AFBoundaryType.Inside, null, null, false).Count > 1,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromSeconds(0.5),
                    $"Both values are not found in the Data Archive in the time range {tr}.");

                Output.WriteLine("Calling RecordedValuesByCount() and checking values.");
                AFValues actualValues1 = attribute.Data.RecordedValuesByCount(readStartTime, 1, false, AFBoundaryType.Inside, null, null, false);
                AFValues actualValues2 = attribute.Data.RecordedValuesByCount(readStartTime, 1, true, AFBoundaryType.Inside, null, null, false);

                if (actualValues1.Count == 1)
                {
                    AFFixture.CheckAFValue(actualValues1[0], expectedValue1);
                }
                else
                {
                    Assert.True(false, $"Incorrect number of values returned for the time range {yesterday} - {readStartTime}. Expected: 1, Actual: {actualValues1.Count}.");
                }

                if (actualValues2.Count == 1)
                {
                    AFFixture.CheckAFValue(actualValues2[0], expectedValue2);
                }
                else
                {
                    Assert.True(false, $"Incorrect number of values returned for the time range {readStartTime} - {today}. Expected: 1, Actual: {actualValues2.Count}.");
                }
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                PIFixture.DeletePIPoints(PointName, Output);
            }
        }

        /// <summary>
        /// Exercises InterpolatedValue Method.
        /// </summary>
        /// <param name="inputValues">Array of input values.</param>
        /// <param name="inputTimestamps">Array of input timestamps.</param>
        /// <param name="step">Step attribute for the PI Point.</param>
        /// <param name="interpolatedValueTimestamp">Timestamp passed as argument into InterpolatedValue call.</param>
        /// <param name="expectedResult">The expected value of the Attribute.</param>
        /// <param name="outputTimeString">Timestamp of the event returned by InterpolatedValue.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point</para>
        /// <para>Create an Element with an Attribute pointing at the PI Point</para>
        /// <para>Make InterpolatedValue call against Attribute and check values returned</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, false, "y+12h", 4f, "y+12h")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, true, "y+12h", 3f, "y+12h")]
        public void InterpolatedValueTest(object[] inputValues, object[] inputTimestamps, bool step, string interpolatedValueTimestamp, object expectedResult, string outputTimeString)
        {
            Contract.Requires(inputValues != null);
            Contract.Requires(inputTimestamps != null);

            const string TestName = "InterpolatedValueTests";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;

            try
            {
                Assert.True(inputValues.Length == inputTimestamps.Length,
                    $"The number of input values {inputValues.Length} does not equal the number of input timestamps {inputTimestamps.Length}.");

                // Create the PI Point
                PIFixture.DeletePIPoints(PointName, Output);
                Output.WriteLine($"Creating PI Point [{PointName}].");
                PIFixture.CreatePIPoints(PointName, 1, new Dictionary<string, object>() { { PICommonPointAttributes.Step, step } });

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point DR and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";
                db.CheckIn();

                // Write values to Data Archive
                for (int i = 0; i < inputValues.Length; i++)
                {
                    if (inputValues[i] != null)
                    {
                        attribute.Data.UpdateValue(new AFValue(attribute, inputValues[i], new AFTime(inputTimestamps[i], now)), AFUpdateOption.Insert);
                    }
                }

                // Determine min and max times of inputs
                var minTime = AFTime.MaxValue;
                var maxTime = AFTime.MinValue;
                for (int i = 0; i < inputTimestamps.Length; i++)
                {
                    if (inputTimestamps[i] != null)
                    {
                        var tmpTime = new AFTime(inputTimestamps[i], now);
                        if (tmpTime < minTime)
                            minTime = tmpTime;
                        if (tmpTime > maxTime)
                            maxTime = tmpTime;
                    }
                }

                var tr = new AFTimeRange(minTime, maxTime);

                // Wait at least 10 times to wait for data to get to Data Archive
                AssertEventually.True(
                    () => attribute.Data.RecordedValues(tr, AFBoundaryType.Inside, null, null, false).Count > 1,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromSeconds(0.5),
                    $"Both values are not found in the Data Archive in the time range [{tr}].");

                var expectedValue = new AFValue(attribute, expectedResult, new AFTime(outputTimeString, now));

                Output.WriteLine($"Calling InterpolatedValue() on attribute [{AttributeName}] and checking values.");
                AFValue actualValue = attribute.Data.InterpolatedValue(new AFTime(interpolatedValueTimestamp, now), null);
                Assert.True(actualValue != null, $"InterpolatedValue() call on attribute [{AttributeName}] did not return any data.");

                db.Refresh(); // Ensure we are not getting cached data
                AFFixture.CheckAFValue(actualValue, expectedValue);
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                PIFixture.DeletePIPoints(PointName, Output);
            }
        }

        /// <summary>
        /// Exercises InterpolatedValues Method.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point</para>
        /// <para>Create an Element with an Attribute pointing at the PI Point</para>
        /// <para>Make InterpolatedValues call against Attribute and check values returned</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Fact]
        public void InterpolatedValuesTest()
        {
            const string TestName = "InterpolatedValuesTests";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;
            var yesterday = new AFTime("y", now);
            var today = new AFTime("t", now);
            var tr = new AFTimeRange(yesterday, today);

            try
            {
                // Create the PI Point
                PIFixture.DeletePIPoints(PointName, Output);
                Output.WriteLine($"Creating PI Point [{PointName}].");
                PIFixture.CreatePIPoints(PointName, 1);

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point DR and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";
                db.CheckIn();

                var expectedValues = new AFValues
                {
                    new AFValue(attribute, 3, yesterday),
                    new AFValue(attribute, 5, today),
                };

                // Send some values to the PI Point
                attribute.Data.UpdateValues(expectedValues, AFUpdateOption.Insert);

                // Wait at least 10 times to wait for data to get to Data Archive
                AssertEventually.True(
                    () => attribute.Data.RecordedValues(tr, AFBoundaryType.Inside, null, null, false).Count > 1,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromSeconds(0.5),
                    $"Both values are not found in the Data Archive in the time range [{tr}].");

                // Verify values
                Output.WriteLine("Calling InterpolatedValues() and checking values.");
                AFValues actualValues = attribute.Data.InterpolatedValues(tr, new AFTimeSpan(days: 2), null, null, false);

                if (actualValues.Count == 2)
                    AFFixture.CheckAFValues(actualValues, expectedValues, Output);
                else
                    Assert.True(false, $"Incorrect number of events. Expected: 2, Actual: {actualValues.Count}.");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                PIFixture.DeletePIPoints(PointName, Output);
            }
        }

        /// <summary>
        /// Exercises EndOfStream Method.
        /// </summary>
        /// <param name="inputValues">Array of input values.</param>
        /// <param name="inputTimestamps">Array of input timestamps.</param>
        /// <param name="expectedResult">The expected value of the Attribute.</param>
        /// <param name="outputTimeString">Timestamp of the event returned by RecordedValue.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point</para>
        /// <para>Create an Element with an Attribute pointing at the PI Point</para>
        /// <para>Make EndOfStream call against Attribute and check values returned</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "y", null, "t" }, 5f, "t")]
        [InlineData(new object[] { 3f, null, 5f }, new object[] { "t", null, "t+2d" }, 5f, "t+2d")]
        public void EndOfStreamTest(object[] inputValues, object[] inputTimestamps, object expectedResult, string outputTimeString)
        {
            Contract.Requires(inputValues != null);
            Contract.Requires(inputTimestamps != null);

            const string TestName = "EndOfStreamTests";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;

            try
            {
                // Create the PI Point
                Output.WriteLine($"Creating PI Point [{PointName}].");
                PIFixture.DeletePIPoints(PointName, Output);
                PIFixture.CreatePIPoints(PointName, 1, new Dictionary<string, object>() { { PICommonPointAttributes.Future, 1 } });

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point DR and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";
                db.CheckIn();

                // Write values to Data Archive
                for (int i = 0; i < inputValues.Length; i++)
                {
                    if (inputValues[i] != null)
                    {
                        attribute.Data.UpdateValue(new AFValue(attribute, inputValues[i], new AFTime(inputTimestamps[i], now)), AFUpdateOption.Insert);
                    }
                }

                // Determine min and max times of inputs
                var minTime = AFTime.MaxValue;
                var maxTime = AFTime.MinValue;
                for (int i = 0; i < inputTimestamps.Length; i++)
                {
                    if (inputTimestamps[i] != null)
                    {
                        var tmpTime = new AFTime(inputTimestamps[i], now);
                        if (tmpTime < minTime)
                            minTime = tmpTime;
                        if (tmpTime > maxTime)
                            maxTime = tmpTime;
                    }
                }

                // Calculate the expected values count
                int expectedCount = inputValues.Count(s => s != null);

                // Wait for data to get to Data Archive
                AssertEventually.True(
                    () => attribute.Data.RecordedValues(new AFTimeRange(minTime, maxTime), AFBoundaryType.Inside, null, null, false).Count == expectedCount,
                    "No values in the Data Archive.");

                var expectedValue = new AFValue(attribute, expectedResult, new AFTime(outputTimeString, now));

                Output.WriteLine("Calling EndOfStrem() and checking values.");
                AFValue actualValue = attribute.Data.EndOfStream(null);

                AFFixture.CheckAFValue(actualValue, expectedValue);
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                PIFixture.DeletePIPoints(PointName, Output);
            }
        }

        /// <summary>
        /// Exercises AFDataPipe sign up operations.
        /// </summary>
        /// <param name="piPointType">Type of the PI Point signed up with the AFDataPipe.</param>
        /// <param name="eventValues">Values to be written to the PI Point.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a test PI Point and Element with an Attribute. Assign PIPoint DR to it</para>
        /// <para>Create a AFDataPipe and sign up the attribute to it</para>
        /// <para>Send test values to the attributes and verify the events from the AFDataPipe</para>
        /// <para>Remove the sign ups, dispose the AFDataPipe and delete the test PI Points and AF Element</para>
        /// </remarks>
        [Theory]
        [InlineData(PIPointType.Int16, new object[] { (short)1, (short)2, (short)3 })]
        [InlineData(PIPointType.Int32, new object[] { 1024, 2048, 4096 })]
        [InlineData(PIPointType.Float32, new object[] { 265.123F, 4.1e23F, 9.2e-19F })]
        [InlineData(PIPointType.Float64, new object[] { 121.11, 1.7e200, 3.5e-275 })]
        [InlineData(PIPointType.String, new string[] { "Test", "String", "Here" })]
        [InlineData(PIPointType.Digital, new object[] { 1, 2, 3 })]
        [InlineData(PIPointType.Timestamp, new string[] { "1/1/2019 12:00:00 AM", "1/2/2019 12:00:00 AM", "1/3/2019 12:00:00 AM" })]
        public void AFDataPipeTest(PIPointType piPointType, object[] eventValues)
        {
            Contract.Requires(eventValues != null);

            const string TestName = "AFDataPipeTest";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";
            const string PointName = TestName + "_PIPoint";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = new AFTime("t");
            var afDataPipe = new AFDataPipe();

            try
            {
                // Create the test PI Points with Zero Compression and specified PI Point type.
                PIFixture.DeletePIPoints(PointName, Output);
                Output.WriteLine($"Creating PI Point [{PointName}].");
                PIPoint piPoint = PIFixture.CreatePIPoints(PointName, 1, new Dictionary<string, object>
                {
                    { PICommonPointAttributes.PointType, piPointType },
                    { PICommonPointAttributes.ExceptionDeviation, 0 },
                    { PICommonPointAttributes.ExceptionMaximum, 0 },
                    { PICommonPointAttributes.Compressing, 0 },
                    { PICommonPointAttributes.DigitalSetName, "Phases" },
                }).FirstOrDefault();

                Assert.True(piPoint != default, $"Unable to create PI Point [{PointName}] on the PIServer [{piServer}].");

                // Create an Element with an Attribute and assign the PI Point DR.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Creating Element {ElementName} with attribute {AttributeName}.");
                var element = db.Elements.Add(ElementName);
                var attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{piPoint.Name};ReadOnly=false";

                db.CheckIn();

                Output.WriteLine($"Add the Attribute [{AttributeName}] as sign up to the AFDataPipe.");
                var afErrors = afDataPipe.AddSignups(element.Attributes);
                var prefixErrorMessage = "Adding sign ups to the AFDataPipe was unsuccessful.";
                Assert.True(afErrors == null,
                    userMessage: afErrors?.Errors.Aggregate(prefixErrorMessage, (msg, error) => msg += $" Attribute: [{error.Key.Name}] Error: [{error.Value.Message}] "));

                // Write the data PI Point values.
                var expectedAFValues = new AFValues();
                for (int i = 0; i < eventValues.Length; i++)
                {
                    AFValue afValue = null;
                    var timestamp = now - TimeSpan.FromMinutes(eventValues.Length - i);

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

                    attribute.SetValue(afValue);

                    // Save the attribute info and status as the expected value for verification.
                    // Also, for Digital values save the corresponding State Result
                    if (piPointType == PIPointType.Digital)
                    {
                        int input = (int)eventValues[i];
                        afValue = new AFValue(new AFEnumerationValue($"Phase{input + 1}", input), timestamp);
                    }

                    afValue.Attribute = attribute;
                    afValue.Status = AFValueStatus.Good;
                    expectedAFValues.Add(afValue);
                }

                // Retry assert to retrieve expected Update Events from the AFDataPipe
                var actualAFValues = new AFValues();

                AssertEventually.True(() =>
                {
                    var updateEvents = afDataPipe.GetUpdateEvents();
                    prefixErrorMessage = "Retrieving Update Events from the AFDataPipe was unsuccessful.";
                    Assert.False(updateEvents.HasErrors,
                        userMessage: updateEvents.Errors?.Aggregate(prefixErrorMessage, (msg, error) => msg += $" Attribute: [{error.Key.Name}] Error: [{error.Value.Message}] "));

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

                for (int i = 0; i < actualAFValues.Count; i++)
                {
                    switch (piPointType)
                    {
                        // Special handling of Output events for Timestamp
                        case PIPointType.Timestamp:
                            actualAFValues[i].Value = new AFTime(actualAFValues[i].Value, now);
                            AFFixture.CheckAFValue(actualAFValues[i], expectedAFValues[i]);
                            break;

                        // For all other PI Point types.
                        default:
                            AFFixture.CheckAFValue(expectedAFValues[i], actualAFValues[i]);
                            break;
                    }
                }

                Output.WriteLine("Remove all sign ups from the AFDataPipe.");
                afErrors = afDataPipe.RemoveSignups(element.Attributes);
                prefixErrorMessage = "Removing sign ups to the AFDataPipe was unsuccessful.";
                Assert.True(afErrors == null,
                    userMessage: afErrors?.Errors.Aggregate(prefixErrorMessage, (msg, error) => msg += $" Attribute: [{error.Key.Name}] Error: [{error.Value.Message}] "));

                // Write dummy values
                Output.WriteLine($"Write dummy values to the Attribute.");
                for (int i = 0; i < eventValues.Length; i++)
                {
                    attribute.SetValue(new AFValue(eventValues[i], now));
                }

                // Verify that no events are received by the AFDataPipe.
                Output.WriteLine($"Verify no events are received by the AFDataPipe.");
                var noEvents = afDataPipe.GetUpdateEvents();
                prefixErrorMessage = "Retrieving Update Events from the AFDataPipe was unsuccessful.";
                Assert.False(noEvents.HasErrors,
                    userMessage: noEvents.Errors?.Aggregate(prefixErrorMessage, (msg, error) => msg += $" Attribute: [{error.Key.Name}] Error: [{error.Value.Message}] "));

                Assert.True(noEvents.Count == 0, $"AFDataPipe should not receive any more events but {noEvents.Count} were received.");
            }
            finally
            {
                afDataPipe.RemoveSignups(afDataPipe.GetSignups());
                afDataPipe.Dispose();
                PIFixture.DeletePIPoints(PointName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises AFDataPipe sign up with Formula Attribute(containing PI Point DR Attributes).
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with four PI Point DR Attributes and one Formula Attribute</para>
        /// <para>Create an AFDataPipe and sign up the formula attribute</para>
        /// <para>Write test values to the PI Point Attributes and verify the formula attribute value from the AFDataPipe</para>
        /// <para>Remove the sign up, dispose the AFDataPipe and delete the test PI Points and AF Element</para>
        /// </remarks>
        [Fact]
        public void AFDataPipeFormulaSignupTest()
        {
            const string TestName = "AFDataPipeFormulaSignupTest";
            const string ElementName = TestName + "_Element";
            const string AttrNamePrefix = "Attribute"; // Keep the name simple for formula ConfigString
            const string PointNamePrefix = TestName + "_PIPoint";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;            
            var afDataPipe = new AFDataPipe();
            Utils.CheckTimeDrift(PIFixture, Output);
            var now = AFTime.Now;

            // Construct the ConfigString for the formula attribute. Set up the input values for each attribute.
            // Derive the expected output based on the formula and input values.
            var formulaInput = new double[] { 12.7, 21.3, 15.8, 18.5 };
            var formula = $"A=Attribute1;B=Attribute2;C=Attribute3;D=Attribute4;" +
                                   $"[roundfrac(abs(A/D)-ceiling(B*C),3)]";
            double formulaResult = Math.Round(Math.Abs(formulaInput[0] / formulaInput[3])
                - Math.Ceiling(formulaInput[1] * formulaInput[2]), 3);
            try
            {
                // Create the test PI Points
                PIFixture.DeletePIPoints(PointNamePrefix + "*", Output);
                Output.WriteLine($"Creating PI Points with prefix [{PointNamePrefix}].");
                var piPointList = PIFixture.CreatePIPoints(PointNamePrefix + "#", 4, turnoffCompression: true).ToList();

                // Create an Element with four PI Point DR Attributes (one for each test PI Point)
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Creating Element [{ElementName}] with attributes with prefix [{AttrNamePrefix}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttributes attributes = element.Attributes;
                for (int i = 1; i <= 4; i++)
                {
                    AFAttribute attribute = element.Attributes.Add(AttrNamePrefix + i);
                    attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                    attribute.ConfigString = $@"\\{piServer.Name}\{piPointList[i - 1].Name};ReadOnly=false";
                }

                // Create an Attribute with a Formula DR. Assign the formula ConfigString.
                var formulaAttribute = element.Attributes.Add(AttrNamePrefix + "Formula");
                formulaAttribute.DataReferencePlugIn = db.PISystem.DataReferencePlugIns["Formula"];
                formulaAttribute.ConfigString = formula;

                db.CheckIn();

                // Sign up the formula attribute to the AFDataPipe
                Output.WriteLine("Adding sign up for formula attribute to AF Data Pipe.");
                var afErrors = afDataPipe.AddSignups(new List<AFAttribute> { formulaAttribute });
                var prefixErrorMessage = "Adding sign ups to the AFDataPipe was unsuccessful.";
                Assert.True(afErrors == null,
                    userMessage: afErrors?.Errors.Aggregate(prefixErrorMessage, (msg, error) => msg += $" Attribute: [{error.Key.Name}] Error: [{error.Value.Message}] "));

                // Write the test input data PI Point values
                for (int i = 1; i <= 4; i++)
                {
                    attributes[$"{AttrNamePrefix}{i}"].Data.UpdateValue(new AFValue(formulaInput[i - 1], now + TimeSpan.FromSeconds(i)), AFUpdateOption.Insert);

                    AssertEventually.True(
                        () => attributes[$"{AttrNamePrefix}{i}"].Data.RecordedValues(new AFTimeRange(now - TimeSpan.FromSeconds(10), AFTime.MaxValue), AFBoundaryType.Inside, null, null, false).Last().Value.ToString() == formulaInput[i - 1].ToString(null, null),
                        TimeSpan.FromSeconds(20),
                        TimeSpan.FromSeconds(1),
                        $"Incorrect value found in point [{AttrNamePrefix}{i}] from the Data Archive.");
                }

                // Retrieve the update events from the AFDataPipe
                AFValue actualAFValue = null;
                var updateEvents = afDataPipe.GetUpdateEvents();
                Assert.False(updateEvents.HasErrors,
                        userMessage: updateEvents.Errors?.Aggregate(prefixErrorMessage, (msg, error) => msg += $" Attribute: [{error.Key.Name}] Error: [{error.Value.Message}]"));

                AssertEventually.True(() =>
                {
                    updateEvents.AddResults(afDataPipe.GetUpdateEvents());
                    prefixErrorMessage = "Retrieving Update Events from the AFDataPipe was unsuccessful.";
                    Assert.False(updateEvents.HasErrors,
                        userMessage: updateEvents.Errors?.Aggregate(prefixErrorMessage, (msg, error) => msg += $" Attribute: [{error.Key.Name}] Error: [{error.Value.Message}]"));
                    if (updateEvents.Count == 4)
                    {
                        actualAFValue = updateEvents.Last().Value as AFValue;
                        if (actualAFValue?.Value is double || actualAFValue?.Value is int)
                        {
                            Assert.True(actualAFValue.ValueAsDouble() == formulaResult,
                                $"Unexpected Formula Result. Expected: [{formulaResult}], Actual: [{actualAFValue.Value}].");
                            Assert.True(actualAFValue.Status == AFValueStatus.Good,
                                $"Unexpected Status. Expected: [{AFValueStatus.Good}], Actual: [{actualAFValue.Status}].");
                            Assert.True(Equals(actualAFValue.Attribute, formulaAttribute),
                                $"Unexpected Attribute. Expected: [{formulaAttribute}], Actual: [{actualAFValue.Attribute}].");
                            return true;
                        }
                    }

                    Output.WriteLine($"Number of Updated events returns: {updateEvents.Count}.");
                    return false;
                },
                "Update Events did not return the expected formula event.");

                // Remove sign up from the AFDataPipe
                Output.WriteLine("Removing sign up for formula attribute to AF Data Pipe.");
                afErrors = afDataPipe.RemoveSignups(new List<AFAttribute> { formulaAttribute });
                prefixErrorMessage = "Removing sign ups to the AFDataPipe was unsuccessful.";
                Assert.True(afErrors == null,
                    afErrors?.Errors.Aggregate(prefixErrorMessage, (msg, error) => msg += $" Attribute: [{error.Key.Name}] Error: [{error.Value.Message}] "));
            }
            finally
            {
                afDataPipe.RemoveSignups(afDataPipe.GetSignups());
                afDataPipe.Dispose();
                PIFixture.DeletePIPoints(PointNamePrefix + "*", Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises PlotValues Method.
        /// </summary>
        /// <param name="inputValues">Array of input values.</param>
        /// <param name="step">Step attribute for the PI Point.</param>
        /// <param name="intervals">Number of intervals for the PlotValues call.</param>
        /// <param name="resultIndex">The indices of the inputValues array used to compose the expected results.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point</para>
        /// <para>Create an Element with an Attribute pointing at the PI Point</para>
        /// <para>Make PlotValues call against Attribute and check values returned</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData(new object[] { 1f, 7f, 3f, 4f, 5f, 2f, 7f, 12f, 1f, 10f }, false, 1, new object[] { 0, 7, 8 })]
        [InlineData(new object[] { 1f, 7f, 3f, 4f, 5f, 2f, 7f, 12f, 1f, 10f }, true, 1, new object[] { 0, 7, 8 })]
        [InlineData(new object[] { 1f, 2f, 7f, 4f, 5f, 6f, 3f, 8f, 12f, 10f }, false, 2, new object[] { 0, 2, 4, 5, 6, 8, 8 })]
        [InlineData(new object[] { 1f, 2f, 7f, 4f, 5f, 6f, 3f, 8f, 12f, 10f }, true, 2, new object[] { 0, 2, 4, 5, 6, 8, 8 })]
        public void PlotValueTest(object[] inputValues, bool step, int intervals, object[] resultIndex)
        {
            Contract.Requires(inputValues != null);
            Contract.Requires(resultIndex != null);

            const string TestName = "PlotValuesTest";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;

            try
            {
                // Create the PI Point
                PIFixture.DeletePIPoints(PointName, Output);
                Output.WriteLine($"Creating PI Point [{PointName}].");
                PIFixture.CreatePIPoints(PointName, 1, new Dictionary<string, object>() { { PICommonPointAttributes.Step, step }, { PICommonPointAttributes.Future, 1 } });

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point DR and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";
                db.CheckIn();

                var timeInterval = new AFTimeSpan(TimeSpan.FromMinutes(1));
                var firstValueTime = new AFTime("y", now);
                var lastValueTime = timeInterval.Multiply(firstValueTime, inputValues.Length - 1);

                // Write values to Data Archive
                var inputAFValues = new AFValues(inputValues.Length);
                for (int i = 0; i < inputValues.Length; i++)
                {
                    if (inputValues[i] != null)
                    {
                        inputAFValues.Add(new AFValue(attribute, inputValues[i], timeInterval.Multiply(firstValueTime, i)));
                    }
                }

                attribute.Data.UpdateValues(inputAFValues, AFUpdateOption.Insert);

                // Wait at least 10 times to wait for data to get to Data Archive
                AssertEventually.True(
                    () => attribute.Data.RecordedValues(new AFTimeRange(firstValueTime, lastValueTime), AFBoundaryType.Inside, null, null, false).Count == inputValues.Length,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromSeconds(0.5),
                    "Recorded values not equal to input values.");

                // Build up expected values collection
                var expected = new AFValues(resultIndex.Length);
                foreach (var index in resultIndex)
                {
                    expected.Add(inputAFValues[(int)index]);
                }

                var queryTimeRange = new AFTimeRange(firstValueTime, timeInterval.Multiply(firstValueTime, inputValues.Length - 2));

                Output.WriteLine($"Calling PlotValues() and checking values.");
                var actual = attribute.Data.PlotValues(queryTimeRange, intervals, null);

                AFFixture.CheckAFValues(actual, expected, Output);
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                PIFixture.DeletePIPoints(PointName, Output);
            }
        }

        /// <summary>
        /// Exercises Summary Method.
        /// </summary>
        /// <param name="inputValues">Array of input values.</param>
        /// <param name="calcBasis">Calculation bases (i.e. TimeWeighted, EventWeighted, etc).</param>
        /// <param name="results">Expected values returned.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a PI Point</para>
        /// <para>Create an Element with an Attribute pointing at the PI Point</para>
        /// <para>Make Summary call against Attribute and check values returned</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData(new object[] { 1f, 7f, 3f, 4f, 5f, 2f, 7f, 10f, 1f, 12f }, "TimeWeighted", new object[] { 100d, 0.027083d, 4.875d, 1f, 10f, 9d, 2.803457d, 2.803457d, 480d, 0.027083d })]
        [InlineData(new object[] { 1f, 7f, 3f, 4f, 5f, 2f, 7f, 10f, 1f, 12f }, "EventWeighted", new object[] { 100d, 40d, 4.44444d, 1f, 10f, 9d, 3.08671d, 2.91018d, 9, 40d })]
        public void SummaryTest(object[] inputValues, string calcBasis, object[] results)
        {
            Contract.Requires(inputValues != null);
            Contract.Requires(results != null);

            const string TestName = "SummaryTest";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;

            try
            {
                // Create the PI Point
                PIFixture.DeletePIPoints(PointName, Output);
                Output.WriteLine($"Creating PI Point [{PointName}].");
                PIFixture.CreatePIPoints(PointName, 1, new Dictionary<string, object>() { { PICommonPointAttributes.Future, 1 } });

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point DR and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";
                db.CheckIn();

                var timeInterval = new AFTimeSpan(TimeSpan.FromMinutes(1));
                var firstValueTime = new AFTime("y", now);
                var lastValueTime = timeInterval.Multiply(firstValueTime, inputValues.Length - 1);

                // Write values to Data Archive
                var inputAFValues = new AFValues(inputValues.Length);
                for (int i = 0; i < inputValues.Length; i++)
                {
                    if (inputValues[i] != null)
                    {
                        inputAFValues.Add(new AFValue(attribute, inputValues[i], timeInterval.Multiply(firstValueTime, i)));
                    }
                }

                attribute.Data.UpdateValues(inputAFValues, AFUpdateOption.Insert);

                // Wait at least 10 times to wait for data to get to Data Archive
                AssertEventually.True(
                    () => attribute.Data.RecordedValues(new AFTimeRange(firstValueTime, lastValueTime), AFBoundaryType.Inside, null, null, false).Count == inputValues.Length,
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromSeconds(0.5),
                    "Recorded values not equal to input values.");

                var queryTimeRange = new AFTimeRange(firstValueTime, timeInterval.Multiply(firstValueTime, inputValues.Length - 2));
                var enumValues = Enum.GetValues(typeof(AFSummaryTypes));

                // Build up expected values collection
                var expected = new Dictionary<AFSummaryTypes, AFValue>();
                for (int i = 0; i < results.Length; i++)
                {
                    expected.Add((AFSummaryTypes)enumValues.GetValue(i), new AFValue(attribute, results[i], queryTimeRange.EndTime, null, AFValueStatus.Good));
                }

                Output.WriteLine($"Calling Summary() and checking values.");
                IDictionary<AFSummaryTypes, AFValue> actual = new Dictionary<AFSummaryTypes, AFValue>();
                if (calcBasis == "TimeWeighted")
                    actual = attribute.Data.Summary(queryTimeRange, AFSummaryTypes.All, AFCalculationBasis.TimeWeighted, AFTimestampCalculation.Auto);
                else if (calcBasis == "EventWeighted")
                    actual = attribute.Data.Summary(queryTimeRange, AFSummaryTypes.All, AFCalculationBasis.EventWeighted, AFTimestampCalculation.Auto);

                int j = 0;
                foreach (var summaryType in actual)
                {
                    if (summaryType.Key == AFSummaryTypes.PercentGood)
                    {
                        AFFixture.CheckAFValue(summaryType.Value, new AFValue(attribute, results[j], queryTimeRange.StartTime, AFFixture.PISystem.UOMDatabase.UOMs["percent"], AFValueStatus.Good));
                    }
                    else if (summaryType.Key == AFSummaryTypes.Maximum)
                    {
                        AFFixture.CheckAFValue(summaryType.Value, new AFValue(attribute, results[j], queryTimeRange.EndTime - timeInterval, null, AFValueStatus.Good));
                    }
                    else if (summaryType.Key == AFSummaryTypes.Count)
                    {
                        if (calcBasis == "TimeWeighted")
                            AFFixture.CheckAFValue(summaryType.Value, new AFValue(attribute, results[j], queryTimeRange.StartTime, AFFixture.PISystem.UOMDatabase.UOMs["s"], AFValueStatus.Good));
                        else if (calcBasis == "EventWeighted")
                            AFFixture.CheckAFValue(summaryType.Value, new AFValue(attribute, results[j], queryTimeRange.StartTime, AFFixture.PISystem.UOMDatabase.UOMs["count"], AFValueStatus.Good));
                    }
                    else
                    {
                        AFFixture.CheckAFValue(summaryType.Value, new AFValue(attribute, results[j], queryTimeRange.StartTime, null, AFValueStatus.Good));
                    }

                    j++;
                }
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                PIFixture.DeletePIPoints(PointName, Output);
            }
        }
    }
}
