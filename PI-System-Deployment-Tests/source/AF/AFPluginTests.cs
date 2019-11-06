using System;
using System.Collections.Generic;
using System.Diagnostics.Contracts;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Threading;
using OSIsoft.AF;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;
using Xunit.Sdk;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests the ability to assign, read and update PlugIn data
    /// in the AF Server.
    /// </summary>
    [Collection("AF collection")]
    public class AFPluginTests : IClassFixture<AFFixture>, IClassFixture<PIFixture>
    {
        /// <summary>
        /// Constructor for PluginTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="afFixture">AF Fixture to manage connection and AF related helper functions.</param>
        /// <param name="piFixture">PI Fixture to manage connection and Data Archive related helper functions.</param>
        public AFPluginTests(ITestOutputHelper output, AFFixture afFixture, PIFixture piFixture)
        {
            Output = output;
            AFFixture = afFixture;
            PIFixture = piFixture;
        }

        private AFFixture AFFixture { get; }

        private PIFixture PIFixture { get; }

        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Exercises the GetValue and SetValue operations of PI Point Data Reference.
        /// </summary>
        /// <param name="expectedValue">Expected Value from the Attribute.</param>
        /// <param name="piPointType">Type of the PI Point.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create the PI Point with the expected PI Point Type</para>
        /// <para>Create an Element with an Attribute(with PI Point Data Reference)</para>
        /// <para>Set the expected value and verify it was written to the PI Point using Get Value</para>
        /// <para>Delete the Element and PI Point</para>
        /// </remarks>
        [Theory]
        [InlineData((short)1, PIPointType.Int16)]
        [InlineData((int)1, PIPointType.Int32)]
        [InlineData(50F, PIPointType.Float16)]
        [InlineData(10e11F, PIPointType.Float32)]
        [InlineData((double)10e-25, PIPointType.Float64)]
        [InlineData((int)1, PIPointType.Digital)]
        [InlineData("Test String", PIPointType.String)]
        [InlineData("Test Blob String", PIPointType.Blob)]
        [InlineData("1/1/2019 12:00:00 AM", PIPointType.Timestamp)]
        public void PIPointDRGetSetValueTest(object expectedValue, PIPointType piPointType)
        {
            const string TestName = "PIPointTests";
            const string PointName = TestName + "_PIPoint";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            var now = AFTime.Now;
            var today = new AFTime("t", now);
            try
            {
                // Create the PI Point with the expected PI Point Type
                Output.WriteLine($"Create PI Point [{PointName}] with Type [{piPointType}] on PI Server [{piServer.Name}].");
                PIFixture.DeletePIPoints(PointName, Output);
                PIPoint piPoint = PIFixture.CreatePIPoints(PointName, 1, new Dictionary<string, object>()
                {
                    { PICommonPointAttributes.PointType, piPointType },
                    { PICommonPointAttributes.DigitalSetName, "Phases" },
                }).FirstOrDefault();
                Assert.True(piPoint != default, $"Unable to create PI Point [{PointName}] with Point Type [{piPointType}] on [{Settings.PIDataArchive}].");

                // Create an Element with an Attribute on the AFDatabase. Assign the PI Point Data Reference and set the expected value.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = $@"\\{piServer.Name}\{PointName};ReadOnly=false";

                // Special Handling of Input Data for Blob and Timestamp PI Point Types
                switch (piPointType)
                {
                    case PIPointType.Blob:
                        // Construct Byte Array/Blob input object from test string.
                        expectedValue = Encoding.ASCII.GetBytes((string)expectedValue);
                        break;

                    case PIPointType.Timestamp:
                        // Construct AFTime input object from the DateTime test string.
                        expectedValue = new AFTime(expectedValue, now);
                        break;
                }

                Output.WriteLine($"Set attribute [{AttributeName}] to expected value [{expectedValue}].");
                var expectedAFValue = new AFValue(expectedValue, today);
                attribute.SetValue(expectedAFValue);
                db.CheckIn();

                // Adding additional properties for verification
                if (piPointType == PIPointType.Digital)
                {
                    int input = (int)expectedValue;
                    expectedAFValue = new AFValue(new AFEnumerationValue($"Phase{input + 1}", input), today);
                }

                expectedAFValue.Attribute = attribute;
                Thread.Sleep(TimeSpan.FromSeconds(0.5));

                // Verify the value received by the PIServer.
                AFValue actualAFValue = attribute.GetValue();

                // Special handling of output data for Digital States, Blob and Timestamp PI Points
                switch (piPointType)
                {
                    case PIPointType.Blob:
                        var byteArray = actualAFValue.Value as byte[];
                        Assert.True(byteArray != null, "Unable to extract Blob data from the attribute.");
                        Assert.True(byteArray.SequenceEqual((byte[])expectedValue), "Expected and Actual Blob values are not equal.");
                        Assert.True(actualAFValue.Timestamp.Equals(today),
                            $"AF Values do not have the same timestamp values. Expected Timestamp: [{today}], Actual Timestamp: [{actualAFValue.Timestamp}].");
                        Assert.True(actualAFValue.Attribute.Equals(attribute),
                            $"AF Values do not have the same timestamp values. Expected Timestamp: [{today}], Actual Timestamp: [{actualAFValue.Timestamp}].");
                        break;

                    case PIPointType.Timestamp:
                        actualAFValue.Value = new AFTime(actualAFValue.Value, now);
                        AFFixture.CheckAFValue(actualAFValue, expectedAFValue);
                        break;

                    default:
                        AFFixture.CheckAFValue(actualAFValue, expectedAFValue);
                        break;
                }
            }
            catch (PIException ex)
            {
                Output.WriteLine($"PI Server [{ex.Server}] operation failed: [{ex.Message}].");
                throw;
            }
            finally
            {
                PIFixture.DeletePIPoints(PointName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises the CreateConfig functionality of the PI Point Data Reference.
        /// </summary>
        /// <param name="piPointType">Type of the PI Point.</param>
        /// <param name="pointClassName">Name of the PI Point Class.</param>
        /// <param name="future">Identifies if the PI Point can handle future values or not.</param>
        /// <param name="step">Step On/Off.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with an Attribute(with PI Point Data Reference)</para>
        /// <para>Create and assign the ConfigString to the attribute.</para>
        /// <para>Call CreateConfig to create the PI Point.</para>
        /// <para>Verify the PI Point was created and confirm all expected PI Point attributes.</para>
        /// <para>Delete the Element and PI Point</para>
        /// </remarks>
        [Theory]
        [InlineData(PIPointType.Int16, "base", 0, false)]
        [InlineData(PIPointType.Int32, "classic", 0, true)]
        [InlineData(PIPointType.Float16, "base", 1, false)]
        [InlineData(PIPointType.Float32, "classic", 1, true)]
        [InlineData(PIPointType.Float64, "classic", 0, false)]
        [InlineData(PIPointType.String, "base", 1, true)]
        [InlineData(PIPointType.Digital, "base", 1, true)]
        [InlineData(PIPointType.Timestamp, "classic", 0, true)]
        [InlineData(PIPointType.Blob, "base", 0, true)]

        public void PIPointDRCreateConfigTest(PIPointType piPointType, string pointClassName, int future, bool step)
        {
            const string TestName = "PIPointDRCreateConfigTest";
            const string PointName = TestName + "_Point";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;

            // Create the test ConfigString
            string configString = $@"\\{piServer.Name}\{PointName};ptclassname ={pointClassName};pointtype={piPointType};future={future};step={step}";

            try
            {
                // Create an Element with an Attribute in the AF database. Assign the ConfigString to the attribute and call CreateConfig().
                PIFixture.DeletePIPoints(PointName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                Output.WriteLine($"Set Attribute [{AttributeName}] with ConfigString [{configString}].");
                attribute.ConfigString = configString;
                db.CheckIn();

                Output.WriteLine($"Call CreateConfig() on attribute [{AttributeName}] to create PI Point [{PointName}].");
                attribute.DataReference.CreateConfig();

                Thread.Sleep(TimeSpan.FromSeconds(0.5));

                // Verify the PI Point (with all expected attributes) is created successfully.
                Output.WriteLine($"Verifying PI Point was created with Name: [{PointName}], Class: [{pointClassName}], " +
                    $"PointType: [{piPointType}], Step: [{step}] and Future: [{future}].");
                var piPoint = PIPoint.FindPIPoint(piServer, PointName);
                piPoint.LoadAttributes(new string[] { PICommonPointAttributes.Step, PICommonPointAttributes.Future });
                bool actualFuture = piPoint.Future;
                bool actualStep = piPoint.Step;

                Assert.True(piPoint.Name.Equals(PointName, StringComparison.OrdinalIgnoreCase),
                    $"PI Point Names do not match. Expected: [{PointName}], Actual: [{piPoint.Name}].");
                Assert.True(piPoint.PointClass.Name.Equals(pointClassName, StringComparison.OrdinalIgnoreCase),
                    $"PI Point Class does not match. Expected: [{pointClassName}], Actual: [{piPoint.PointClass.Name}].");
                Assert.True(piPoint.PointType.Equals(piPointType),
                    $"PI Point Type does not match. Expected: [{piPointType}], Actual: [{piPoint.PointType}].");
                Assert.True(actualFuture == (future == 0 ? false : true),
                    $"PI Point Future Attribute does not match. Expected: [{future}], Actual: [{actualFuture}].");
                Assert.True(actualStep == step,
                    $"PI Point Step Attribute does not match. Expected: [{step}], Actual: [{actualStep}].");

                // Verify that the ConfigString is truncated after PI Point creation
                db.Refresh();
                attribute = db.Elements[ElementName].Attributes[AttributeName];
                string expConfigString = $@"\\{piServer.Name}?{piServer.ID}\{PointName}?{piPoint.ID}";

                Output.WriteLine($"Verify if the ConfigString is truncated to [{expConfigString}].");
                Assert.True(attribute.ConfigString.Equals(expConfigString, StringComparison.InvariantCultureIgnoreCase),
                    $"ConfigString was not truncated after PI Point creation. " +
                    $"Expected Config: [{expConfigString}], Actual Config: [{attribute.ConfigString}].");
            }
            finally
            {
                PIFixture.DeletePIPoints(PointName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises the Event-Weighted TimeRange Methods of PI Point Data Reference.
        /// </summary>
        /// <param name="inputValues">Input values for the test.</param>
        /// <param name="methodName">Name of the Time Range Method.</param>
        /// <param name="expectedResult">Expected Result of the time range method against input values.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a test PI Point and write input values to it</para>
        /// <para>Create an Element with an Attribute(with PI Point Data Reference PlugIn)</para>
        /// <para>Create and assign the ConfigString with the time range method attributes to the attribute.</para>
        /// <para>Verify the result of the PI Point attribute is as expected</para>
        /// <para>Delete the Element and PI Point</para>
        /// </remarks>
        [Theory]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Count", 4.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Maximum", 4.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Minimum", 1.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Total", 10.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Average", 2.5)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "StartTime", 1)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "EndTime", 4.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Range", 3.0)]
        [InlineData(new double[] { 1, 3, 5, 7 }, "Delta", 6)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "StandardDeviation", 1.29)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "PopulationStandardDeviation", 1.12)]
        public void PIPointDREventWeightedTimeRangeTest(double[] inputValues, string methodName, double expectedResult)
        {
            Contract.Requires(inputValues != null);

            const string TestName = "PIPointDREventWeightedTimeRangeTest";
            const string PointName = TestName + "_Point";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            DateTime now = AFTime.Now.LocalTime;

            // Create a test ConfigString with the TimeRange Method.
            string relativeTime = $"-{inputValues.Length - 1}m";
            string configString =
                $@"\\{piServer.Name}\{PointName};TimeMethod=TimeRange;TimeRangeMethod={methodName};" +
                $"TimeRangeBasis=EventWeighted;RelativeTime={relativeTime};TimeRangeMinPercentGood=0";
            try
            {
                // Create the test PI Point
                Output.WriteLine($"Create a PI Point [{PointName}] on the PIServer [{piServer.Name}].");
                PIFixture.DeletePIPoints(PointName, Output);
                PIPoint piPoint = PIFixture.CreatePIPoints(PointName, 1, turnoffCompression: true).FirstOrDefault();
                Assert.True(piPoint != default, $"Unable to create PI Point [{PointName}] on [{Settings.PIDataArchive}].");

                // Write the test input values to the PI Point
                for (int i = 1; i <= inputValues.Length; i++)
                {
                    var timestamp = now.AddMinutes(i - inputValues.Length);
                    Output.WriteLine($"Writing Value [{inputValues[i - 1]}] with TimeStamp [{timestamp}] to PI Point [{piPoint}].");
                    piPoint.UpdateValue(new AFValue(inputValues[i - 1], timestamp), AFUpdateOption.InsertNoCompression);
                }

                // Create an Element and an Attribute. Assign PI Point Data Reference to the Attribute
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = configString;

                // Verify the TimeRange Method works using Timestamp as expected.
                Output.WriteLine($"Verifying the TimeRange Method [{methodName}] using Timestamp works as expected.");

                AssertEventually.True(() =>
                {
                    object result = attribute.GetValue(now).Value;
                    if (result is IConvertible)
                    {
                        double actualResult = ((IConvertible)result).ToDouble(CultureInfo.InvariantCulture);

                        // Round the result up 2 decimal places
                        actualResult = Math.Round(actualResult, 2);
                        Assert.True(expectedResult == actualResult,
                            $"Unexpected Result received for Method [{methodName}]. Expected Result: [{expectedResult}], Actual Result: [{actualResult}].");
                        return true;
                    }
                    else
                    {
                        Output.WriteLine($"Unsuccessful attempt. Value Received: [{result}].");
                    }

                    return false;
                },
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(0.5),
                "Unable to retrieve expected value within the time frame.");

                // Verify the TimeRange Method using TimeRange works as expected.
                Output.WriteLine($"Verifying the TimeRange Method [{methodName}] using TimeRange works as expected.");

                AssertEventually.True(() =>
                {
                    object result = attribute.GetValue(new AFTimeRange(now.AddMinutes(-inputValues.Length + 1), now)).Value;
                    if (result is IConvertible)
                    {
                        double actualResult = ((IConvertible)result).ToDouble(CultureInfo.InvariantCulture);

                        // Round the result up 2 decimal places
                        actualResult = Math.Round(actualResult, 2);
                        Assert.True(expectedResult == actualResult,
                            $"Unexpected Result received for Method [{methodName}]. Expected Result: [{expectedResult}], Actual Result: [{actualResult}].");
                        return true;
                    }
                    else
                    {
                        Output.WriteLine($"Unsuccessful attempt. Value Received: [{result}].");
                    }

                    return false;
                },
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(0.5),
                "Unable to retrieve expected value within the time frame.");
            }
            catch (FormatException ex)
            {
                Output.WriteLine($"Value from the attribute was not a double. Message: [{ex.Message}].");
                throw;
            }
            catch (PIException ex)
            {
                Output.WriteLine($"PI Server [{ex.Server}] operation failed. Message: [{ex.Message}].");
                throw;
            }
            finally
            {
                PIFixture.DeletePIPoints(PointName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises the Event-Weighted TimeRange Methods of PI Point Data Reference.
        /// </summary>
        /// <param name="inputValues">Input values for the test.</param>
        /// <param name="methodName">Name of the Time Range Method.</param>
        /// <param name="expectedResult">Expected Result of the time range method against input values.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a test PI Point and write input values to it</para>
        /// <para>Create an Element with an Attribute(with PI Point Data Reference PlugIn)</para>
        /// <para>Create and assign the ConfigString with the time range method attributes to the attribute</para>
        /// <para>Verify the result of the PI Point attribute is as expected</para>
        /// <para>Delete the Element and PI Point</para>
        /// </remarks>
        [Theory]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Count", 3.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Maximum", 4.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Minimum", 2.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Total", 9.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Average", 3)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "StartTime", 1)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "EndTime", 2)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Range", 2.0)]
        [InlineData(new double[] { 1, 3, 5, 7 }, "Delta", 4)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "StandardDeviation", 1)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "PopulationStandardDeviation", 0.82)]
        public void PIPointDREventWeightedTimeRangeOverrideTest(double[] inputValues, string methodName, double expectedResult)
        {
            Contract.Requires(inputValues != null);

            const string TestName = "PIPointDREventWeightedTimeRangeOverrideTest";
            const string PointName = TestName + "_Point";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            DateTime now = AFTime.Now.LocalTime;

            string relativeTime = $"-2m";

            // Create a test ConfigString with the TimeRange Method.
            string configString =
                $@"\\{piServer.Name}\{PointName};TimeMethod=TimeRangeOverride;TimeRangeMethod={methodName};" +
                $"RelativeTime={relativeTime};TimeRangeBasis=EventWeighted;TimeRangeMinPercentGood=0";
            try
            {
                // Create the test PI Point
                Output.WriteLine($"Create a PI Point [{PointName}] on the PIServer [{piServer.Name}].");
                PIFixture.DeletePIPoints(PointName, Output);
                PIPoint piPoint = PIFixture.CreatePIPoints(PointName, 1, turnoffCompression: true).FirstOrDefault();
                Assert.True(piPoint != default, $"Unable to create PI Point [{PointName}] on [{Settings.PIDataArchive}].");

                // Write the test input values to the PI Point
                for (int i = 1; i <= inputValues.Length; i++)
                {
                    var timestamp = now.AddMinutes(i - inputValues.Length);
                    Output.WriteLine($"Writing Value [{inputValues[i - 1]}] with TimeStamp [{timestamp}] to PI Point [{piPoint}].");
                    piPoint.UpdateValue(new AFValue(inputValues[i - 1], timestamp), AFUpdateOption.InsertNoCompression);
                }

                // Create an Element and an Attribute. Assign PI Point Data Reference to the Attribute
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = configString;

                // Verify the TimeRange Method works as expected.
                Output.WriteLine($"Verifying the TimeRange Method [{methodName}] works as expected.");

                AssertEventually.True(() =>
                {
                    object result = attribute.GetValue(new AFTimeRange(now.AddMinutes(-1), now)).Value;
                    if (result is IConvertible)
                    {
                        double actualResult = ((IConvertible)result).ToDouble(CultureInfo.InvariantCulture);

                        // Round the result up 2 decimal places
                        actualResult = Math.Round(actualResult, 2);
                        Assert.True(expectedResult == actualResult,
                            $"Unexpected Result received for Method [{methodName}]. Expected Result: [{expectedResult}], Actual Result: [{actualResult}].");
                        return true;
                    }
                    else
                    {
                        Output.WriteLine($"Unsuccessful attempt. Value Received: [{result}].");
                    }

                    return false;
                },
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(0.5),
                "Unable to retrieve expected value within the time frame.");
            }
            catch (FormatException ex)
            {
                Output.WriteLine($"Value from the attribute was not a double. Message: [{ex.Message}].");
                throw;
            }
            catch (PIException ex)
            {
                Output.WriteLine($"PI Server [{ex.Server}] operation failed. Message: [{ex.Message}].");
                throw;
            }
            finally
            {
                PIFixture.DeletePIPoints(PointName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises the Time-Weighted TimeRange Methods of PI Point Data Reference.
        /// </summary>
        /// <param name="inputValues">Input values for the test.</param>
        /// <param name="methodName">Name of the Time Range Method.</param>
        /// <param name="expectedResult">Expected Result of the time range method against input values.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a test PI Point and write input values to it</para>
        /// <para>Create an Element with an Attribute(with PI Point Data Reference)</para>
        /// <para>Create and assign the ConfigString with the time range method attributes to the attribute</para>
        /// <para>Verify the result of the PI Point attribute is as expected</para>
        /// <para>Delete the Element and PI Point</para>
        /// </remarks>
        [Theory]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Count", 180.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Maximum", 4.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Minimum", 1.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Total", 0.01)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Average", 2.5)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "StartTime", 1.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "EndTime", 4.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Delta", 3.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "Range", 3.0)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "StandardDeviation", 0.87)]
        [InlineData(new double[] { 1, 2, 3, 4 }, "PopulationStandardDeviation", 0.87)]
        public void PIPointDRTimeWeightedTimeRangeTest(double[] inputValues, string methodName, double expectedResult)
        {
            Contract.Requires(inputValues != null);

            const string TestName = "PIPointDRTimeWeightedTimeRangeTest";
            const string PointName = TestName + "_Point";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;

            DateTime now = AFTime.Now.LocalTime;

            // Create a test ConfigString with a placeholder for the TimeRange Method Name.
            string configString = $@"\\{piServer.Name}\{PointName};TimeMethod=TimeRange;TimeRangeMethod={methodName};TimeRangeBasis=TimeWeighted;"
                                        + $"RelativeTime=-{inputValues.Length - 1}m;TimeRangeMinPercentGood=0";
            try
            {
                // Create the test PI Point
                Output.WriteLine($"Create a PI Point [{PointName}] on the PIServer [{piServer.Name}].");
                PIFixture.DeletePIPoints(PointName, Output);
                PIPoint piPoint = PIFixture.CreatePIPoints(PointName, 1, turnoffCompression: true).FirstOrDefault();
                Assert.True(piPoint != default, $"Unable to create PI Point [{PointName}] on [{Settings.PIDataArchive}].");

                // Write the test input values to the PI Point
                for (int i = 1; i <= inputValues.Length; i++)
                {
                    var timestamp = now.AddMinutes(i - inputValues.Length);
                    Output.WriteLine($"Writing Value [{inputValues[i - 1]}] with TimeStamp [{timestamp}] to PI Point [{piPoint}].");
                    piPoint.UpdateValue(new AFValue(inputValues[i - 1], timestamp), AFUpdateOption.InsertNoCompression);
                }

                // Create an Element and an Attribute. Assign PI Point Data Reference to the Attribute
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = configString;

                // Verify the TimeRange Method with Timestamp works as expected.
                Output.WriteLine($"Verifying the TimeRange Method [{methodName}] with Timestamp works as expected.");

                AssertEventually.True(() =>
                {
                    object result = attribute.GetValue(now).Value;
                    if (result is IConvertible)
                    {
                        double actualResult = ((IConvertible)result).ToDouble(CultureInfo.InvariantCulture);

                        // Round the result up 2 decimal places
                        actualResult = Math.Round(actualResult, 2);
                        Assert.True(expectedResult == actualResult,
                            $"Unexpected Result received for Method [{methodName}]. Expected Result: [{expectedResult}], Actual Result: [{actualResult}].");
                        return true;
                    }
                    else
                    {
                        Output.WriteLine($"Unsuccessful attempt. Value Received: [{result}].");
                    }

                    return false;
                },
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(0.5),
                "Unable to retrieve expected value using Timestamp within the time frame.");

                // Verify the TimeRange Method works with TimeRange as expected.
                Output.WriteLine($"Verifying the TimeRange Method [{methodName}] with TimeRange works as expected.");

                AssertEventually.True(() =>
                {
                    object result = attribute.GetValue(new AFTimeRange(now.AddMinutes(-(inputValues.Length - 1)), now)).Value;
                    if (result is IConvertible)
                    {
                        double actualResult = ((IConvertible)result).ToDouble(CultureInfo.InvariantCulture);

                        // Round the result up 2 decimal places
                        actualResult = Math.Round(actualResult, 2);
                        Assert.True(expectedResult == actualResult,
                            $"Unexpected Result received for Method [{methodName}]. Expected Result: [{expectedResult}], Actual Result: [{actualResult}].");
                        return true;
                    }
                    else
                    {
                        Output.WriteLine($"Unsuccessful attempt. Value Received: [{result}].");
                    }

                    return false;
                },
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(0.5),
                "Unable to retrieve expected value using Timestamp within the time frame.");
            }
            catch (FormatException ex)
            {
                Output.WriteLine($"Value from the attribute was not a double. Message: [{ex.Message}].");
                throw;
            }
            catch (PIException ex)
            {
                Output.WriteLine($"PI Server [{ex.Server}] operation failed. Message: [{ex.Message}].");
                throw;
            }
            finally
            {
                PIFixture.DeletePIPoints(PointName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises the Time Methods of PI Point Data Reference.
        /// </summary>
        /// <param name="inputValues">Input values for the test PI Points.</param>
        /// <param name="timeMethod">Name of the Time Method.</param>
        /// <param name="expectedResult">Expected Result of the time method against input values.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a test PI Point and write input values to it</para>
        /// <para>Create an Element with an Attribute(with PI Point Data Reference)</para>
        /// <para>Create and assign the ConfigString with the time method to the attribute</para>
        /// <para>Write the test input values to the PI Point and verify the result of the PI Point attribute</para>
        /// <para>Delete the Element and PI Point</para>
        /// </remarks>
        [Theory]
        [InlineData(new double[] { 1, 2, 3, 4, 5 }, "Before", 2.0)]
        [InlineData(new double[] { 1, 2, 3, 4, 5 }, "AtOrBefore", 3.0)]
        [InlineData(new double[] { 1, 2, 3, 4, 5 }, "AtOrAfter", 3.0)]
        [InlineData(new double[] { 1, 2, 3, 4, 5 }, "After", 4.0)]
        [InlineData(new double[] { 1, 2, 3, 4, 5 }, "ExactTime", 3.0)]
        [InlineData(new double[] { 1, 2, 3, 4, 5 }, "Automatic", 3.0)]
        [InlineData(new double[] { 1, 2, 3, 4, 5 }, "Interpolated", 3.0)]
        public void PIPointDRTimeMethodTest(double[] inputValues, string timeMethod, double expectedResult)
        {
            Contract.Requires(inputValues != null);

            const string TestName = "PIPointDRTimeMethodTest";
            const string PointName = TestName + "_Point";
            const string ElementName = TestName + "_Element";
            const string AttributeName = TestName + "_Attribute";

            AFDatabase db = AFFixture.AFDatabase;
            PIServer piServer = PIFixture.PIServer;
            AFTime now = AFTime.NowInWholeSeconds;

            // Create a test ConfigString with the Time Method.
            string configString = $@"\\{piServer.Name}\{PointName};TimeMethod={timeMethod};";
            try
            {
                // Create a PI Point and write the test input values to the PIPoint
                Output.WriteLine($"Create a PI Point [{PointName}] on the PIServer [{piServer.Name}].");
                PIFixture.DeletePIPoints(PointName, Output);
                PIPoint piPoint = PIFixture.CreatePIPoints(PointName, 1, new Dictionary<string, object>
                    {
                        { PICommonPointAttributes.ExceptionDeviation, 0 },
                        { PICommonPointAttributes.ExceptionMaximum, 0 },
                        { PICommonPointAttributes.Compressing, 0 },
                        { PICommonPointAttributes.Future, true },
                    }).FirstOrDefault();
                Assert.True(piPoint != default, $"Unable to create PI Point [{PointName}] on [{Settings.PIDataArchive}].");

                for (int i = 0; i < inputValues.Length; i++)
                {
                    var timestamp = now + TimeSpan.FromHours(i - (inputValues.Length / 2));
                    Output.WriteLine($"Write Value [{inputValues[i]}] with Timestamp [{timestamp}] to PI Point [{piPoint}].");
                    var afValue = new AFValue(inputValues[i], timestamp);
                    piPoint.UpdateValue(afValue, AFUpdateOption.InsertNoCompression);
                }

                // Create an Element and an Attribute. Assign PI Point Data Reference to the Attribute
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = AFDataReference.GetPIPointDataReference(db.PISystem);
                attribute.ConfigString = configString;

                // Verify the Time Method works as expected. Use a retry loop to get the expected value.
                Output.WriteLine($"Verifying the Time Method [{timeMethod}] works as expected. ConfigString: [{configString}].");

                AssertEventually.True(() =>
                {
                    object result = attribute.GetValue(now).Value;
                    if (result is IConvertible)
                    {
                        double actualResult = ((IConvertible)result).ToDouble(CultureInfo.InvariantCulture);

                        // Round the result up 3 decimal places
                        actualResult = Math.Round(actualResult, 3);
                        Assert.True(expectedResult == actualResult,
                            $"Unexpected Result for Time Method [{timeMethod}]. Expected Result: [{expectedResult}], Actual Result: [{actualResult}].");
                        return true;
                    }
                    else
                    {
                        Output.WriteLine($"Unsuccessful attempt. Value Received: [{result}].");
                    }

                    return false;
                },
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(0.5),
                "Unable to retrieve expected value within the time frame.");
            }
            catch (FormatException ex)
            {
                Output.WriteLine($"Value from the attribute was not a double. Message: [{ex.Message}].");
                throw;
            }
            catch (PIException ex)
            {
                Output.WriteLine($"PI Server [{ex.Server}] operation failed. Message: [{ex.Message}].");
                throw;
            }
            finally
            {
                PIFixture.DeletePIPoints(PointName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises Table Lookup PlugIn Functions.
        /// </summary>
        /// <param name="whereClause">The test where clause.</param>
        /// <param name="timeColumnSpecification">The test time column specification.</param>
        /// <param name="timestamp">The test timestamp to make GetValue call.</param>
        /// <param name="expectedResult">The expected value of the attribute.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Get an AFTable with a time, asset, and value column</para>
        /// <para>Create an Element with an Attribute</para>
        /// <para>Confirm that the test ConfigString will return the expected Attribute value</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData("WHERE Turbine = 'TUR10001'", "", "*", 32.0558968)]
        [InlineData("WHERE Turbine = 'TUR10002'", "", "*", 39.5425339)]
        [InlineData("WHERE Turbine = 'TUR10003'", "", "*", 38.6076965)]
        [InlineData("", ";TC=Installation Date", "2010-05-14T20:00:00-04:00", 32.0558968)]
        [InlineData("", ";TC=Installation Date", "2010-05-18T20:00:00-04:00", 38.6076965)]
        [InlineData("", ";TC=Installation Date", "2010-05-29T20:00:00-04:00", 39.5425339)]
        public void TableLookupFunctionTest(string whereClause, string timeColumnSpecification, string timestamp, object expectedResult)
        {
            Contract.Requires(expectedResult != null);

            const string TableName = "Location";
            const string ElementName = "TableLookupFunctionTests_Element";
            const string AttributeName = "TableLookupFunctionTests_Attribute";

            // Get a reference to the Table Lookup Data Reference
            AFDatabase db = AFFixture.AFDatabase;
            AFPlugIn tableLookupDR = GetDataReferencePlugIn(db.PISystem, "Table Lookup");
            Assert.True(tableLookupDR != null, "Unable to access Table Lookup Data Reference PlugIn.");

            try
            {
                // Get a premade AFTable in the AF Database
                Output.WriteLine($"Getting premade table [{TableName}].");
                AFTable table = db.Tables[TableName];
                var timeColumn = table.Table.Columns["Installation Date"];
                var assetColumn = table.Table.Columns["Turbine"];
                var valueColumn = table.Table.Columns["Elevation"];

                // Create an Element in the AF Database and assign Table Lookup Data Reference
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = tableLookupDR;
                db.CheckIn();

                // Verify Expected value and Actual value is equal
                Output.WriteLine($"Asserting if the Table Lookup Function works as expected.");
                var configString = $"SELECT Elevation FROM [{TableName}] {whereClause}{timeColumnSpecification}";
                attribute.ConfigString = configString;
                double actualValue = (double)attribute.GetValue(new AFTime(timestamp)).Value;
                Assert.True(expectedResult.Equals(actualValue), $"Table Lookup Function does not work as expected. Test ConfigString: [{attribute.ConfigString}], " +
                    $"Expected Result: [{expectedResult}], Actual Result: [{actualValue}].");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises Table Lookup PlugIn Substitution Parameters.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an AFTable with an asset and value column</para>
        /// <para>Create an Element with an Attribute(with Table Lookup PlugIn) and a Parent Element</para>
        /// <para>Confirm that a Table Lookup with the ConfigString will return the expected Attribute value</para>
        /// <para>Delete the Element, Parent Element, and Table</para>
        /// </remarks>
        [Fact]
        public void TableLookupSubstitutionParamsTest()
        {
            const string TableName = "TableLookupFunctionTests_Table";
            const string ParentElementName = "TLSubstParamsTests_ParentElement";
            const string ElementName = "TLSubstParamsTests_Element";
            const string ElementDescription = "This is a test element description.";
            const string ParentAttributeName = "SBSubstParamsTests_ParentAttribute";
            const string ChildAttributeName = "SBSubstParamsTests_ChildAttribute";
            const string AttributeDescription = "This is a test attribute description.";

            const string ElementPath = ParentElementName + "\\" + ElementName;

            // Get a reference to the Table Lookup Data Reference
            AFDatabase db = AFFixture.AFDatabase;
            AFPlugIn tableLookupDR = GetDataReferencePlugIn(db.PISystem, "Table Lookup");
            Assert.True(tableLookupDR != null, "Unable to access Table Lookup Data Reference PlugIn.");

            try
            {
                // Create an AFTable in the AF Database
                Output.WriteLine($"Creating table [{TableName}] with an asset and value column.");
                AFFixture.RemoveTableIfExists(TableName, Output);
                AFTable table = db.Tables.Add(TableName);
                var assetColumn = table.Table.Columns.Add("asset");
                assetColumn.DataType = typeof(string);
                var valueColumn = table.Table.Columns.Add("value");
                valueColumn.DataType = typeof(double);

                // Create an Element with a Parent Element and an Attribute and assign Table Lookup Data Reference.
                AFFixture.RemoveElementIfExists(ParentElementName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);

                Output.WriteLine($"Create Parent Element [{ParentElementName}] and Child Element [{ElementName}] with " +
                    $"Parent Attribute [{ParentAttributeName}] and Child Attribute [{ChildAttributeName}] in the AF Database [{db.Name}].");
                AFElement parentElement = db.Elements.Add(ParentElementName);
                AFElement element = parentElement.Elements.Add(ElementName);
                element.Description = ElementDescription;
                AFAttribute parentAttribute = element.Attributes.Add(ParentAttributeName);
                parentAttribute.DataReferencePlugIn = tableLookupDR;
                AFAttribute childAttribute = parentAttribute.Attributes.Add(ChildAttributeName);
                childAttribute.DataReferencePlugIn = tableLookupDR;
                childAttribute.Description = AttributeDescription;

                // Create the Test Data (this cannot be suppled as InlineData to the test beforehand
                // as it relies on Element and Attribute ID which can be accessed only after the element is created.
                (string substitutionString, string substitutionValue, double expectedValue)[] substitutionParamsTestData =
                {
                    ("%System%", AFFixture.PISystem.Name, 0),
                    ("%Database%", Settings.AFDatabase, 1),
                    ("%Element%", ElementName, 2),
                    ("%ElementID%", element.ID.ToString(), 3),
                    ("%ElementDescription%", ElementDescription, 4),
                    ("%ElementPath%", ElementPath, 5),
                    ("%Attribute%", ChildAttributeName, 6),
                    ("%AttributeID%", childAttribute.ID.ToString(), 7),
                    ("%Description%", AttributeDescription, 8),
                    (@"%..\Element%", ParentElementName, 9),
                    (@"%..|Attribute%", ParentAttributeName, 10),
                };

                foreach (var (substitutionString, substitutionValue, expectedValue) in substitutionParamsTestData)
                {
                    table.Table.Rows.Add(substitutionValue, expectedValue);
                }

                table.CacheInterval = TimeSpan.Zero;

                db.CheckIn();

                void VerifyResult(string testString, double expectedResult)
                {
                    Output.WriteLine($"Testing Substitution Parameter [{testString}].");
                    childAttribute.ConfigString = $"SELECT value FROM [{TableName}] WHERE asset = '{testString}'";
                    AFValue value = childAttribute.GetValue();
                    double actualValue = (double)value.Value;
                    Assert.True(actualValue == expectedResult,
                        userMessage: Environment.NewLine + $"Substitution Parameter [{testString}] works unexpectedly - " +
                                        $"Expected Result: [{expectedResult}], Actual Result: [{actualValue}].");
                }

                // We use Assert.All instead of iterating through the collection, as we would like to test all the
                // input data, instead of breaking the test in between because of any one failure PI Point.
                Assert.All(substitutionParamsTestData, inputTestData => VerifyResult(inputTestData.substitutionString, inputTestData.expectedValue));
            }
            catch (AllException e)
            {
                string errorMessage = "Table Lookup Substitution Parameters Test Failed.";
                foreach (var failure in e.Failures)
                {
                    var ex = failure as TrueException;
                    errorMessage += ex?.UserMessage ?? failure.Message;
                }

                throw new XunitException(errorMessage);
            }
            finally
            {
                AFFixture.RemoveTableIfExists(TableName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);
                AFFixture.RemoveElementIfExists(ParentElementName, Output);
            }
        }

        /// <summary>
        /// Exercises String Builder PlugIn Functions.
        /// </summary>
        /// <param name="configString">The test ConfigString for StringBuilder.</param>
        /// <param name="expectedResult">The expected value of the Attribute.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with an Attribute(with StringBuilder PlugIn)</para>
        /// <para>Confirm that String Builder with the test ConfigString will return the expected Attribute value</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData("Left(\"Sample\", 1)", "S")]
        [InlineData("Right(\"Sample\", 1)", "e")]
        [InlineData("Mid(\"Sample\",2,3)", "amp")]
        [InlineData("LCase(\"Sample\")", "sample")]
        [InlineData("UCase(\"Sample\")", "SAMPLE")]
        [InlineData("Trim(\"     Sample  \")", "Sample")]
        [InlineData("LTrim(\"        Sample  \")", "Sample  ")]
        [InlineData("RTrim(\"  Sample      \")", "  Sample")]
        [InlineData("Replace(\"Sample\", \"ample\", \"tand\")", "Stand")]
        public void StringBuilderFunctionTest(string configString, string expectedResult)
        {
            Contract.Requires(expectedResult != null);

            const string ElementName = "StringBuilderFunctionTests_Element";
            const string AttributeName = "StringBuilderFunctionTests_Attribute";

            // Get a reference to the String Builder Data Reference
            AFDatabase db = AFFixture.AFDatabase;
            AFPlugIn stringBuilderDR = GetDataReferencePlugIn(db.PISystem, "String Builder");
            Assert.True(stringBuilderDR != null, "Unable to access String Builder Data Reference PlugIn.");

            try
            {
                // Create an Element in the AF Database and assign String Builder Data Reference
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = stringBuilderDR;
                db.CheckIn();

                // Verify Expected value and Actual value is equal
                Output.WriteLine($"Asserting if the String Builder Function works as expected.");
                attribute.ConfigString = configString;
                string actualValue = (string)attribute.GetValue().Value;
                Assert.True(expectedResult.Equals(actualValue, StringComparison.OrdinalIgnoreCase),
                    $"StringBuilder Function does not work as expected. Test ConfigString: [{configString}], " +
                    $"Expected Result: [{expectedResult}], Actual Result: [{actualValue}].");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises String Builder PlugIn Substitution Parameters.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with an Attribute(with StringBuilder PlugIn) and a Parent Element</para>
        /// <para>Confirm that a String Builder with the ConfigString will return the expected Attribute value</para>
        /// <para>Delete the Element and Parent Element</para>
        /// </remarks>
        [Fact]
        public void StringBuilderSubstitutionParamsTest()
        {
            const string ParentElementName = "SBSubstParamsTests_ParentElement";
            const string ElementName = "SBSubstParamsTests_Element";
            const string ElementDescription = "This is a test element description.";
            const string ParentAttributeName = "SBSubstParamsTests_ParentAttribute";
            const string ChildAttributeName = "SBSubstParamsTests_ChildAttribute";
            const string AttributeDescription = "This is a test attribute description.";

            const string ElementPath = ParentElementName + "\\" + ElementName;
            const string ParentElementPath = ParentElementName;

            // Get a reference to the String Builder Data Reference
            AFDatabase db = AFFixture.AFDatabase;
            AFPlugIn stringBuilderDR = GetDataReferencePlugIn(db.PISystem, "String Builder");
            Assert.True(stringBuilderDR != null, "Unable to access String Builder Data Reference PlugIn.");

            try
            {
                // Create an Element with a Parent Element and an Attribute and assign String Builder Data Reference.
                AFFixture.RemoveElementIfExists(ParentElementName, Output);
                AFFixture.RemoveElementIfExists(ElementName, Output);

                Output.WriteLine($"Create Parent Element [{ParentElementName}] and Child Element [{ElementName}] with " +
                    $"Parent Attribute [{ParentAttributeName}] and Child Attribute [{ChildAttributeName}] in the AF Database [{db.Name}].");
                AFElement parentElement = db.Elements.Add(ParentElementName);
                AFElement element = parentElement.Elements.Add(ElementName);
                element.Description = ElementDescription;
                AFAttribute parentAttribute = element.Attributes.Add(ParentAttributeName);
                parentAttribute.DataReferencePlugIn = stringBuilderDR;
                AFAttribute childAttribute = parentAttribute.Attributes.Add(ChildAttributeName);
                childAttribute.DataReferencePlugIn = stringBuilderDR;
                childAttribute.Description = AttributeDescription;
                db.CheckIn();

                // Create the Test Data (this cannot be suppled as InlineData to the test beforehand
                // as it relies on Element and Attribute ID which can be accessed only after the element is created.
                var substituionParamsTestData = new Dictionary<string, string>()
                {
                    { "%System%", AFFixture.PISystem.Name },
                    { "%Database%", Settings.AFDatabase },
                    { "%Element%", ElementName },
                    { "%ElementID%", element.ID.ToString() },
                    { "%ElementDescription%", ElementDescription },
                    { "%ElementPath%", ElementPath },
                    { "%Attribute%", ChildAttributeName },
                    { "%AttributeID%", childAttribute.ID.ToString() },
                    { "%Description%", AttributeDescription },
                    { @"%..\Element%", ParentElementName },
                    { @"%..\ElementPath%", ParentElementPath },
                    { @"%..|Attribute%", ParentAttributeName },
                };

                void VerifyResult(string testString, string expectedResult)
                {
                    Output.WriteLine($"Testing Substitution Parameter [{testString}].");
                    childAttribute.ConfigString = testString;
                    AFValue value = childAttribute.GetValue();
                    string actualValue = value.Value.ToString();
                    Assert.True(expectedResult.Equals(actualValue, System.StringComparison.InvariantCultureIgnoreCase),
                        userMessage: Environment.NewLine + $"Substitution Parameter [{testString}] works unexpectedly - " +
                                        $"Expected Result: [{expectedResult}], Actual Result: [{actualValue}].");
                }

                // We use Assert.All instead of iterating through the collection, as we would like to test all the
                // input data, instead of breaking the test in between because of any one failure PI Point.
                Assert.All(substituionParamsTestData, inputTestData => VerifyResult(inputTestData.Key, inputTestData.Value));
            }
            catch (AllException e)
            {
                string errorMessage = "String Builder Substitution Parameters Test Failed.";
                foreach (var failure in e.Failures)
                {
                    var ex = failure as TrueException;
                    errorMessage += ex?.UserMessage ?? failure.Message;
                }

                throw new XunitException(errorMessage);
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
                AFFixture.RemoveElementIfExists(ParentElementName, Output);
            }
        }

        /// <summary>
        /// Exercises Uri Builder PlugIn operations with simple Urls.
        /// </summary>
        /// <param name="configString">The test ConfigString for UriBuilder.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with an Attribute(with UriBuilder PlugIn)</para>
        /// <para>Set the ConfigString to the Uri from the test data and verify that the value was set correctly</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData("http://sampleurl.com/")]
        [InlineData("http://sampleurl.com:80/")]
        [InlineData("http://sampleurl.com/Path")]
        [InlineData("http://sampleurl.com/Path/Path2")]
        [InlineData("http://sampleurl.com:80/a=1")]
        [InlineData("https://sampleurl.com:80/")]
        public void UriBuilderSimpleUrlTest(string configString)
        {
            Contract.Requires(configString != null);

            const string ElementName = "UriBuilderSimpleUrlTests_Element";
            const string AttributeName = "UriBuilderSimpleUrlTests_Attribute";

            // Get a reference to the Uri Builder Reference
            AFDatabase db = AFFixture.AFDatabase;
            AFPlugIn uriBuilderDR = GetDataReferencePlugIn(db.PISystem, "Uri Builder");
            Assert.True(uriBuilderDR != null, "Unable to access Uri Builder Data Reference PlugIn.");

            try
            {
                // Create an Element and an Attribute and assign the Uri Builder Data Reference.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = uriBuilderDR;
                attribute.ConfigString = configString;
                db.CheckIn();

                // Verify Expected value and Actual value is equal
                Output.WriteLine($"Asserting if the Uri Builder works correctly with ConfigString [{configString}].");
                AFValue value = attribute.GetValue();
                Assert.True(configString.Equals(value.Value),
                    $"Expected the attribute [{AttributeName}] to have a value equal to the ConfigString [{configString}], but it was actually [{value.Value}].");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises Uri Builder PlugIn operation with Substitution Param.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with an Attribute(with UriBuilder PlugIn)</para>
        /// <para>Set the ConfigString to the url with substitution parameter and verify that the value was set correctly</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Fact]
        public void UriBuilderSubstitutionTest()
        {
            const string ElementName = "UriBuilderSimpleUrlTests_Element";
            const string AttributeName = "UriBuilderSimpleUrlTests_Attribute";

            // Get a reference to the Uri Builder Reference
            AFDatabase db = AFFixture.AFDatabase;
            AFPlugIn uriBuilderDR = GetDataReferencePlugIn(db.PISystem, "Uri Builder");
            Assert.True(uriBuilderDR != null, "Unable to access Uri Builder Data Reference PlugIn.");

            try
            {
                // Create an Element and an Attribute and assign the Uri Builder Data Reference.
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = uriBuilderDR;
                db.CheckIn();

                // Verify Expected value and Actual value is equal
                var configString = @"http://sampleurl.com:80/a %Element%";
                Output.WriteLine($"Asserting if the Uri Builder works correctly with ConfigString [{configString}].");
                attribute.ConfigString = configString;
                AFValue value = attribute.GetValue();
                var expectedValue = @"http://sampleurl.com:80/a%20" + element.Name;
                Assert.True(value.Value.Equals(expectedValue),
                    $"Expected the attribute [{AttributeName}] to have a value of [{expectedValue}], but it was actually [{value.Value}].");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercise GetValue calls on PI Point Array Data Reference.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an element with a PI Point Array Data Reference attribute that references raw PI Point data</para>
        /// <para>Verify that GetValue calls on the attribute retrieve proper type and status</para>
        /// <para>Add another PI Point Array Data Reference Attribute that references time average of PI Point data</para>
        /// <para>Verify that GetValue calls on the attribute retrieve proper type and status</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Fact]
        public void PIPointArrayGetValueTest()
        {
            const string ElementName = "PIPointArray_GetValueTests_Element";

            try
            {
                PIServer piServer = PIFixture.PIServer;
                AFDatabase db = AFFixture.AFDatabase;

                Output.WriteLine($"Adding Element [{ElementName}] to AF database [{db.Name}].");
                AFFixture.RemoveElementIfExists(ElementName, Output);
                var element = db.Elements.Add(ElementName);

                var concatPointNames = new StringBuilder("OSIsoftTests.Region 0.Wind Farm 00.TUR00000.Random");
                for (var i = 1; i < 5; i++)
                {
                    concatPointNames.Append($"|OSIsoftTests.Region 0.Wind Farm 00.TUR0000{i}.Random");
                }

                // Attribute with raw data
                var attributeName = "PIPointArray_GetValueTests_Region0_WindFarm00_Random";
                var configString = $"\\\\{piServer.Name}\\{concatPointNames}";
                var attr = AddPIPointArrayAttribute(db, element, attributeName, typeof(float), configString);

                Output.WriteLine($"Verify GetValue call for attribute [{attributeName}].");
                var attrValue = attr.GetValue();
                Assert.True(attrValue.Value.GetType().Equals(typeof(float[])),
                    $"Expected the attribute [{attributeName}] to have a value type of 'float[]'," +
                    $" but it was actually '{attrValue.Value.GetType()}'.");

                var status = attrValue.Status;
                Assert.True(status == AFValueStatus.Good,
                    $"Expected the attribute [{attributeName}] to have a value status of 'Good', but it was actually '{status}'.");

                // Attribute with time averaged data
                attributeName = "PIPointArray_GetValueTests_Region0_WindFarm00_Random_TimeRangeAvg";
                configString = $"\\\\{piServer.Name}\\{concatPointNames};TimeRangeMethod=Average;";
                attr = AddPIPointArrayAttribute(db, element, attributeName, typeof(float), configString);

                AFTime end = AFTime.Now.UtcTime.AddMinutes(-10);
                AFTime start = end.UtcTime.AddHours(-1);
                var timeRange = new AFTimeRange(start, end);

                Output.WriteLine($"Verify GetValue call for attribute [{attributeName}].");
                attrValue = attr.GetValue(timeRange);
                Assert.True(attrValue.Value.GetType().Equals(typeof(float[])),
                    $"Expected the attribute [{attributeName}] to have a value type of 'float[]'," +
                    $" but it was actually '{attrValue.Value.GetType()}'.");

                status = attrValue.Status;
                Assert.True(status == AFValueStatus.Good,
                    $"Expected the attribute [{attributeName}] to have a value status of 'Good', but it was actually '{status}'.");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises Formula PlugIn Functions.
        /// </summary>
        /// <param name="configString">The test ConfigString for Formula.</param>
        /// <param name="expectedResult">The expected value of the Attribute.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with an Attribute(with Formula PlugIn)</para>
        /// <para>Confirm that Formula with the test ConfigString will return the expected Attribute value</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Theory]
        [InlineData("[abs(-4)]", 4)]
        [InlineData("[acos(1)]", 0.0)]
        [InlineData("[ceiling(4.1)]", 5)]
        [InlineData("[cos(0)]", 1)]
        [InlineData("[Remainder(12,3)]", 0)]
        [InlineData("[sqrt(64)]", 8)]
        [InlineData("[log(10)]", 1)]
        [InlineData("[sqrt(676)]", 26)]
        [InlineData("[pow(4,4)]", 256)]
        [InlineData("[Roundfrac(Pi(), 4)]", 3.1416)]
        [InlineData("[max(43.12, 33.11)]", 43.12)]
        public void FormulaFunctionTest(string configString, double expectedResult)
        {
            const string ElementName = "FormulaFunctionTests_Element";
            const string AttributeName = "FormulaFunctionTests_Attribute";

            // Get a reference to the Formula Data Reference
            AFDatabase db = AFFixture.AFDatabase;
            AFPlugIn formulaDR = GetDataReferencePlugIn(db.PISystem, "Formula");
            Assert.True(formulaDR != null, "Unable to access Formula Data Reference PlugIn.");

            try
            {
                // Create an Element in the AF Database and assign Formula Data Reference
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}] with Attribute [{AttributeName}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute = element.Attributes.Add(AttributeName);
                attribute.DataReferencePlugIn = formulaDR;
                db.CheckIn();

                // Verify Expected value and Actual value is equal
                Output.WriteLine($"Asserting if the Formula Function works as expected with ConfigString [{configString}].");
                attribute.ConfigString = configString;
                double actualValue = (double)attribute.GetValue().Value;
                Assert.True(expectedResult.Equals(actualValue), $"Formula Function does not work as expected. Test ConfigString [{configString}], " +
                    $"Expected Result: [{expectedResult}], Actual Result: [{actualValue}].");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises Formula PlugIn Substitution Parameters
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with Formula Attributes</para>
        /// <para>Confirm that attribute with the Formula ConfigString will return the expected Attribute value</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Fact]
        public void FormulaAttributeVariablesTest()
        {
            const string ElementName = "Formula_AttributeVariablesTest";
            const string Attribute1 = "AttributeA";
            const string Attribute2 = "AttributeB";
            const string Attribute3 = "AttributeC";
            const string Attribute_Formula = "Attribute_Formula";

            // Get a reference to the Formula Reference
            AFDatabase db = AFFixture.AFDatabase;
            AFPlugIn formulaDR = GetDataReferencePlugIn(db.PISystem, "Formula");
            Assert.True(formulaDR != null, "Unable to access Formula Data Reference PlugIn.");

            try
            {
                // Create an Element in the AF Database and assign Formula Data Reference
                AFFixture.RemoveElementIfExists(ElementName, Output);
                Output.WriteLine($"Create Element [{ElementName}] in the AF Database [{db.Name}].");
                AFElement element = db.Elements.Add(ElementName);
                AFAttribute attribute1 = element.Attributes.Add(Attribute1);
                AFAttribute attribute2 = element.Attributes.Add(Attribute2);
                AFAttribute attribute3 = element.Attributes.Add(Attribute3);
                AFAttribute attribute4 = element.Attributes.Add(Attribute_Formula);
                attribute1.DataReferencePlugIn = formulaDR;
                attribute3.DataReferencePlugIn = formulaDR;
                attribute4.DataReferencePlugIn = formulaDR;
                db.CheckIn();

                // Verify Expected value and Actual value is equal
                Output.WriteLine($"Asserting if the Formula Function works as expected.");
                attribute1.ConfigString = "[1/3]";
                attribute2.SetValue(0.3, null);
                attribute3.ConfigString = "A=AttributeA;B=AttributeB;[ceiling(A-B)]";
                attribute4.ConfigString = "A=AttributeA;B=AttributeB;C=AttributeC;[if A > B then C else 0]";
                double actualValue = (double)attribute4.GetValue().Value;
                double expectedResult = 1;
                Assert.True(expectedResult.Equals(actualValue), $"Formula Function does not work as expected. Test ConfigString: [{attribute4.ConfigString}], " +
                    $"Expected Result: [{expectedResult}], Actual Result: [{actualValue}].");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Returns the AF Data Reference PlugIn.
        /// </summary>
        /// <param name="piSystem">Reference to the PI System.</param>
        /// <param name="plugInName">Name of the AF Data Reference PlugIn.</param>
        /// <returns>Returns the requested DataReference PlugIn.</returns>
        private static AFPlugIn GetDataReferencePlugIn(PISystem piSystem, string plugInName)
            => piSystem?.DataReferencePlugIns[plugInName];

        private AFAttribute AddPIPointArrayAttribute(AFDatabase db, AFElement element, string attributeName, Type type, string configString)
        {
            var plugIn = GetDataReferencePlugIn(db.PISystem, "PI Point Array");
            Assert.True(plugIn != null, "Unable to access PI Point Array Data Reference PlugIn.");

            var attr = element.Attributes.Add(attributeName);
            attr.DataReferencePlugIn = plugIn;
            attr.ConfigString = configString;
            attr.Type = type.MakeArrayType();

            Output.WriteLine($"Add PI Point Array Data Reference attribute [{attributeName}] to element [{element.Name}]. " +
                $"Attribute ConfigString: [{configString}]. Attribute Type: '{attr.Type.Name}'.");
            db.CheckIn();

            return attr;
        }
    }
}
