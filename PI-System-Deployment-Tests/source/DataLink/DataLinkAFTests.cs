using System;
using System.Globalization;
using System.Reflection;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// These tests simulate the calls that the 'PI DataLink add-in to Excel' makes to AF through AFData.dll.
    /// </summary>
    [Collection("AF collection")]
    public class DataLinkAFTests : IClassFixture<AFFixture>
    {
        internal const string KeySetting = "PIDataLinkTests";
        internal const TypeCode KeySettingTypeCode = TypeCode.Boolean;

        private const string AFDataPath = DataLinkUtils.AFDataDLLPath;
        private const string AFDataAssemblyName = DataLinkUtils.AFLibraryType;
        private readonly dynamic _afLib;

        /// <summary>
        /// Constructor for DataLinkAFTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage AF connection and specific helper functions.</param>
        public DataLinkAFTests(ITestOutputHelper output, AFFixture fixture)
        {
            Output = output;
            Fixture = fixture;
            string pipcPath = null;

            try
            {
                // Get the PIPC directory
                DataLinkUtils.GetPIHOME(ref pipcPath);

                // Get DataLink's AFData.dll and AFLibrary class
                var assembly = Assembly.LoadFrom(pipcPath + AFDataPath);
                Type classType = assembly.GetType(AFDataAssemblyName);

                // Create AFLibrary class instance
                _afLib = Activator.CreateInstance(classType);
            }
            catch (Exception)
            {
                // When PI DataLink is not installed locally, the exception will be caught here without further actions.
                // Then DataLinkFact will handle the error and skip the test.
            }
        }

        private AFFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Tests to see if the current patch of PI DataLink is applied
        /// </summary>
        /// <remarks>
        /// Errors if the current patch is not applied with a message telling the user to upgrade
        /// </remarks>
        [Fact]
        public void HaveLatestPatchDataLink()
        {
            var factAttr = new GenericFactAttribute(TestCondition.DATALINKCURRENTPATCH, true);
            Assert.NotNull(factAttr);
        }

        /// <summary>
        /// Use DataLink library to search for Event Frames that started within the last 12 hours.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Search for existing event frame(s) that started within the last 12 hours</para>
        /// <para>Verify at least one event frame was found</para>
        /// <para>Verify the found event frame(s) start time is within the last 12 hours</para>
        /// </remarks>
        [DataLinkFact]
        public void EFSearchTest()
        {
            string searchStartTime = "*-12h";
            string searchEndTime = "*";

            // Allocate 10000 "rows" for results
            _afLib.SetXLCallerParams(0, 0, 10000, 0, 2);

            string rootPath = "\\\\" + Fixture.PISystem.Name + "\\" + Fixture.AFDatabase.Name;

            Output.WriteLine($"Search for existing event frames within the range [{searchStartTime}] to [{searchEndTime}].");
            object calcData = _afLib.AFEFDat(rootPath, searchStartTime, searchEndTime, 0, "*", "*", "*", "*", "*", string.Empty, string.Empty,
                "starting in range", "start time ascending", string.Empty, string.Empty, string.Empty, string.Empty,
                string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, string.Empty,
                string.Empty, string.Empty, string.Empty, string.Empty, "{EN},{ST},{ET},{DU},{EFT},{PE}",
                string.Empty, string.Empty, 0, 0);

            var results = (Array)calcData;
            int count = results.GetUpperBound(0);

            Output.WriteLine("Make sure at least one event frame was retrieved.");
            Assert.True(count > 0, "Expected to find at least one Event Frame but none were found.");

            Output.WriteLine($"Verify the found event frame(s) start time is within [{searchStartTime}] and [{searchEndTime}].");
            var expectedEFStartTimeRangeMin = new AFTime(searchStartTime).LocalTime;
            var expectedEFStartTimeRangeMax = new AFTime(searchEndTime).LocalTime;
            for (int i = 1; i < count; i++)
            {
                if (string.IsNullOrWhiteSpace(Convert.ToString(results.GetValue(i, 0), CultureInfo.InvariantCulture)))
                    break;

                // PI DataLink displays the timestamp in local time
                var efStartTime = DateTime.FromOADate(Convert.ToDouble(results.GetValue(i, 1), CultureInfo.InvariantCulture));
                Assert.True(
                    efStartTime >= expectedEFStartTimeRangeMin &&
                    efStartTime <= expectedEFStartTimeRangeMax,
                    $"All returned event frames from the search should have started between [{expectedEFStartTimeRangeMin}] " +
                    $"and [{expectedEFStartTimeRangeMax}]. Actual event frame start time was [{efStartTime}].");
            }
        }

        /// <summary>
        /// Use DataLink library to search for AF elements created from the "turbine" element template.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Search for AF elements created from the "turbine" element template</para>
        /// <para>Verify at least one element was found</para>
        /// <para>Verify the found element(s) start with "TUR"</para>
        /// </remarks>
        [DataLinkFact]
        public void AssetFilterSearchTest()
        {
            // Allocate 10000 "rows" for results
            _afLib.SetXLCallerParams(0, 0, 10000, 0, 2);

            string rootPath = "\\\\" + Fixture.PISystem.Name + "\\" + Fixture.AFDatabase.Name;
            char[] separatorArray = new char[] { '\\' };

            Output.WriteLine($"Search for elements created from the [{AFFixture.TurbineTemplateName}] element template.");
            object afElements = _afLib.AFSearch(rootPath, AFFixture.TurbineTemplateName, 0, "*", "*", "*", string.Empty, string.Empty,
                string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, string.Empty,
                string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, 0);

            var results = (Array)afElements;
            int count = results.GetUpperBound(0);

            Output.WriteLine("Make sure at least one element was retrieved.");
            Assert.True(count > 0, "Expected to find calculation data for at least one Event Frame but none were found.");

            Output.WriteLine("Verify the found element(s) start with 'TUR'.");
            for (int i = 0; i < count; i++)
            {
                // Each result is a full path ending with the element name
                string[] result = Convert.ToString(results.GetValue(i, 0), CultureInfo.InvariantCulture).Split(separatorArray);
                if (!string.IsNullOrWhiteSpace(result[result.Length - 1]))
                {
                    // All element names should begin with the "TUR" prefix
                    Assert.True(result[result.Length - 1].StartsWith("TUR", StringComparison.OrdinalIgnoreCase),
                        $"Expected the element name to start with 'TUR', but the name is [{result[result.Length - 1]}].");
                }
            }
        }
    }
}
