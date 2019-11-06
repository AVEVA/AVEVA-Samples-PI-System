using System;
using System.Diagnostics.Contracts;
using System.Globalization;
using System.Reflection;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// These tests simulate the calls that the PI DataLink add-in to Excel makes to PI through AFData.dll.
    /// </summary>
    [Collection("PI collection")]
    public class DataLinkPIDATests : IClassFixture<PIFixture>
    {
        private const string AFDataPath = DataLinkUtils.AFDataDLLPath;
        private const string AFDataAssemblyName = DataLinkUtils.AFLibraryType;
        private const string PointName = @"OSIsoftTests.Region 0.Wind Farm 00.TUR00000.SineWave";
        private readonly string _pointPath;
        private readonly dynamic _afLib;

        /// <summary>
        /// Constructor for DataLinkPIDATests class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage PI connection and specific helper functions.</param>
        public DataLinkPIDATests(ITestOutputHelper output, PIFixture fixture)
        {
            Contract.Requires(fixture != null);

            Output = output;
            Fixture = fixture;
            _pointPath = $@"\\{fixture.PIServer.Name}\{PointName}";
            string pipcPath = null;

            try
            {
                // Get the PIPC directory
                DataLinkUtils.GetPIHOME(ref pipcPath);

                // Get DataLink's AFData.dll and AFLibrary class
                var assembly = Assembly.LoadFrom(pipcPath + AFDataPath);
                var classType = assembly.GetType(AFDataAssemblyName);

                // Create AFLibrary class instance
                _afLib = Activator.CreateInstance(classType);
            }
            catch (Exception)
            {
                // When PI DataLink is not installed locally, the exception will be caught here without further actions.
                // Then DataLinkFact will handle the error and skip the test.
            }
        }

        private PIFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Get the current value for a test "SineWave" PI Point using DataLink's AFData library.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Get the current value for a test "SineWave" PI Point</para>
        /// <para>Verify the value is between 0 and 100</para>
        /// </remarks>
        [DataLinkFact]
        public void CurrentValueTest()
        {
            // Zeroth array member is discarded by AFLibrary
            var pointArray = new string[] { string.Empty, PointName };

            Output.WriteLine("Get the current value for a test 'SineWave' PI Point.");
            object currVal = _afLib.AFCurrVal(pointArray, 0, Fixture.PIServer);
            double result = Convert.ToDouble(((Array)currVal).GetValue(0, 0), CultureInfo.InvariantCulture);

            // SineWave values lie between 0 and 100
            Assert.True(Math.Abs(result) <= 100.0,
                $"Expected the absolute value of the 'SineWave' PI Point value to be " +
                $"less than or equal to 100, but it was actually [{Math.Abs(result)}].");
        }

        /// <summary>
        /// Get the archive value for a test "SineWave" PI Point at midnight using DataLink's AFData library.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Get the midnight value for a test "SineWave" PI Point</para>
        /// <para>Verify the value is between 0 and 100</para>
        /// </remarks>
        [DataLinkFact]
        public void ArchiveValueTest()
        {
            // Note: zeroth array member is discarded by AFData
            var pointArray = new string[] { string.Empty, PointName };
            object objTime = "t";

            Output.WriteLine("Get the midnight value for a test 'SineWave' PI Point.");
            object arcVal = _afLib.AFArcVal(pointArray, objTime, 0, Fixture.PIServer, "auto");
            double result = Convert.ToDouble(((System.Array)arcVal).GetValue(0, 0), CultureInfo.InvariantCulture);

            // SineWave values lie between 0 and 100
            Assert.True(Math.Abs(result) <= 100.0,
                $"Expected the absolute value of the 'SineWave' PI Point value to be " +
                $"less than or equal to 100, but it was actually [{Math.Abs(result)}].");
        }

        /// <summary>
        /// Get compressed values for a test "SineWave" PI Point between 1 and 2 hours ago using DataLink's AFData library.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Get the compressed values for a test "SineWave" PI Point between 1 and 2 hours ago</para>
        /// <para>Verify the values are between 0 and 100</para>
        /// </remarks>
        [DataLinkFact]
        public void CompressedDataTest()
        {
            string searchStartTime = "*-2h";
            string searchEndTime = "*-1h";

            // allocate 10000 "rows" for results
            _afLib.SetXLCallerParams(0, 0, 10000, 0, 2);

            Output.WriteLine($"Get the compressed values for a test 'SineWave' PI Point within the range [{searchStartTime}] to [{searchEndTime}].");
            object compDat = _afLib.AFCompDat(PointName, searchStartTime, searchEndTime, 0, Fixture.PIServer, "inside");
            var results = (Array)compDat;

            int count = Convert.ToInt32(results.GetValue(0, 0), CultureInfo.InvariantCulture);
            for (int i = 1; i <= count; i++)
            {
                double result = Convert.ToDouble(results.GetValue(i, 0), CultureInfo.InvariantCulture);

                // SineWave values lie between 0 and 100
                Assert.True(Math.Abs(result) <= 100.0,
                $"Expected the absolute value of the 'SineWave' PI Point value to be " +
                $"less than or equal to 100, but it was actually [{Math.Abs(result)}].");
            }
        }

        /// <summary>
        /// Get sampled values at 1 hour intervals for a test "SineWave" PI Point for the past 10 hours using DataLink's AFData library.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Get sampled values at 1 hour intervals for a test "SineWave" PI Point for the past 10 hours</para>
        /// <para>Verify the values are between 0 and 100</para>
        /// </remarks>
        [DataLinkFact]
        public void SampledDataTest()
        {
            string searchStartTime = "*-10h";
            string searchEndTime = "*";
            string searchIntervalTime = "1h";

            // Allocate 10 "rows" for results
            _afLib.SetXLCallerParams(0, 0, 10, 0, 2);

            Output.WriteLine($"Get sampled values at [{searchIntervalTime}] intervals for a test 'SineWave' PI Point within the range [{searchStartTime}] to [{searchEndTime}].");
            object sampDat = _afLib.AFSampDat(PointName, searchStartTime, searchEndTime, searchIntervalTime, 0, Fixture.PIServer);
            var results = (Array)sampDat;

            int count = results.Length;
            for (int i = 0; i < count; i++)
            {
                double result = Convert.ToDouble(results.GetValue(i, 0), CultureInfo.InvariantCulture);

                // SineWave values lie between 0 and 100
                Assert.True(Math.Abs(result) <= 100.0,
                $"Expected the absolute value of the 'SineWave' PI Point value to be " +
                $"less than or equal to 100, but it was actually [{Math.Abs(result)}].");
            }
        }

        /// <summary>
        /// Use the time data function to get the values for a test "SineWave" PI Point at several
        /// timestamps (i.e. 10 hours ago, 3 hours ago, 30 mins ago and 3 hours ago).
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Use the time data function to get the values for a test "SineWave" PI Point at several timestamps</para>
        /// <para>Verify the values are between 0 and 100</para>
        /// </remarks>
        [DataLinkFact]
        public void TimedDataTest()
        {
            // Allocate 3 "rows" for results
            _afLib.SetXLCallerParams(0, 0, 2, 0, 2);

            var timeArray = new string[] { string.Empty, "*-10h", "*-3h", "*-30m" };

            Output.WriteLine($"Use the time data function to get the value for a test 'SineWave' PI Point at several timestamps: [{timeArray.ToString()}].");
            object timedData = _afLib.AFTimeDat(PointName, timeArray, Fixture.PIServer, "interpolated");
            var results = (Array)timedData;

            int count = results.Length;
            for (int i = 0; i < count; i++)
            {
                double result = Convert.ToDouble(results.GetValue(i, 0), CultureInfo.InvariantCulture);

                // SineWave values lie between 0 and 100
                Assert.True(Math.Abs(result) <= 100.0,
                $"Expected the absolute value of the 'SineWave' PI Point value to be " +
                $"less than or equal to 100, but it was actually [{Math.Abs(result)}].");
            }
        }

        /// <summary>
        /// Use DataLink's TimeFiltered function to calculate the amount of time that "SineWave" is greater than 50.
        /// Do this calculation hourly for the past day and request the results be returned in seconds.
        /// </summary>
        /// <remarks>
        /// <para>
        /// Remember, results from corresponding performance-equation functions and asset-analytics functions,
        /// such as TimeGE or TimeGT, are more accurate than those from the Time Filtered function. Also, results
        /// from the Time Filtered function vary slightly depending on your PI Data Archive version.
        /// </para>
        /// Test Steps:
        /// <para>Use DataLink's TimeFiltered function to calculate the amount of time that "SineWave" is greater than 50</para>
        /// <para>Verify the calculated time results are between 0 and 1 hour</para>
        /// </remarks>
        [DataLinkFact]
        public void TimeFilteredTest()
        {
            // Allocate 24 "row" for results
            _afLib.SetXLCallerParams(0, 0, 23, 0, 2);

            string filterExpression = $"'{_pointPath}'>1";

            Output.WriteLine("Use DataLink's TimeFiltered function to calculate the amount of time that 'SineWave' is greater than 1.");
            object sampDat = _afLib.AFTimeFilter(filterExpression, "y", "t", "1h", "seconds", 0, Fixture.PIServer); // Request results in units of seconds
            var results = (Array)sampDat;

            int count = results.Length;
            for (int i = 0; i < count; i++)
            {
                double result = Convert.ToDouble(results.GetValue(i, 0), CultureInfo.InvariantCulture);

                // Each result should be between 0 and 3600 seconds (i.e. between 0 and 1 hour)
                Assert.True(Math.Abs(result) <= 3600,
                $"Expected the absolute value of the calculated value to be " +
                $"less than or equal to 3600, but it was actually [{Math.Abs(result)}].");
            }
        }

        /// <summary>
        /// Use DataLink's Calculated Data function to return the "count" for a test "SineWave" PI Point over the previous day.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Use the calculated data function to return the count for a test "SineWave" PI Point over the previous day</para>
        /// <para>Verify the calculated value is equal to the number of seconds in a day</para>
        /// </remarks>
        [DataLinkFact]
        public void CalculatedDataTest()
        {
            // allocate 1 "row" for results
            _afLib.SetXLCallerParams(0, 0, 1, 0, 2);

            // note: zeroth array member is discarded by AFData
            var pointArray = new string[] { string.Empty, PointName };

            // get hourly sums for the past day
            Output.WriteLine("Use the calculated data function to return the count for a test 'SineWave' PI Point over the previous day.");
            object calcData = _afLib.AFCalcDat(pointArray, "y", "t", string.Empty, "count", 1.0, 0, Fixture.PIServer);
            var results = (Array)calcData;
            double result = Convert.ToDouble(results.GetValue(0, 0), CultureInfo.InvariantCulture);

            // count should equal the number of seconds in a day
            Assert.True(result == 86400,
                $"Expected the calculated value to be equal to 86400, but it was actually [{result}].");
        }
    }
}
