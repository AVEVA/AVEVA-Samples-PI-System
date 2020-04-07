using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Threading;
using OSIsoft.AF;
using OSIsoft.AF.Analysis;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.EventFrame;
using OSIsoft.AF.PI;
using OSIsoft.AF.Search;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class exercises various Analysis operations for the Analysis Service.
    /// </summary>
    [Collection("AF collection")]
    public class AnalysisTests : IClassFixture<AFFixture>
    {
        // The region elements in Wind Farm database have two analyses which may generate EF based on "Manual Input" value
        // 1. Power Event, the trigger expression is "Manual Input > 10"
        // 2. Power Production SQC, the control limit for "Manual Input" is [0, 100]
        private const double PowerEventTriggerValue = 20.0;
        private const double PowerProductionSQCTriggerValue = -10.0;
        private const double PowerEventsEndValue = 5.0;

        /// <summary>
        /// Constructor for AnalysisTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage AF connection and specific helper functions.</param>
        public AnalysisTests(ITestOutputHelper output, AFFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private AFFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Tests to see if the current patch of PI Analysis is applied
        /// </summary>
        /// <remarks>
        /// Errors if the current patch is not applied with a message telling the user to upgrade
        /// </remarks>
        [Fact]
        public void HaveLatestPatchAnalysis()
        {
            var factAttr = new GenericFactAttribute(TestCondition.ANALYSISCURRENTPATCH, true);
            Assert.NotNull(factAttr);
        }

        /// <summary>
        /// Exercises Analysis Object by doing a Create, Read, Update and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create Analysis</para>
        /// <para>Confirm Analysis was properly created</para>
        /// <para>Rename the Analysis (and confirm)</para>
        /// <para>Delete the Analysis (And confirm)</para>
        /// </remarks>
        [Fact]
        public void AnalysisTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            const string AnalysisName = "OSIsoftTests_AF_AnalysisTest_NameAnalysis";
            const string AnalysisRename = "OSIsoftTests_AF_AnalysisTest_ReNamedAnalysis";

            var testData = new AnalysisTestConfiguration(AnalysisName);

            Fixture.RemoveAnalysisIfExists(AnalysisName, Output);
            Fixture.RemoveAnalysisIfExists(AnalysisRename, Output);

            var analysisCat = db.AnalysisCategories[testData.AnalysisCategoryName];
            if (analysisCat == null) analysisCat = db.AnalysisCategories.Add(testData.AnalysisCategoryName);

            try
            {
                Output.WriteLine($"Create Analysis [{AnalysisName}].");
                var newAnalysis = new AFAnalysis(db, AnalysisName)
                {
                    AnalysisRulePlugIn = db.PISystem.AnalysisRulePlugIns[testData.AnalysisRulePlugIn],
                };
                newAnalysis.Categories.Add(analysisCat);
                newAnalysis.TimeRulePlugIn = db.PISystem.TimeRulePlugIns[testData.AnalysisTimeRulePlugIn];
                newAnalysis.ExtendedProperties.Add(testData.AnalysisExtPropKey, testData.AnalysisExtPropValue);
                db.CheckIn();

                // This operation clears AFSDK cache and assures retrieval from AF server
                db = Fixture.ReconnectToDB();

                Output.WriteLine("Confirm Analysis created and found.");
                var analysisFound = AFAnalysis.FindAnalysis(db.PISystem, newAnalysis.ID);

                // Verify found proper AFAnalysis Object
                Output.WriteLine("Confirm Analysis properties are correct.");
                Assert.True(analysisFound != null, $"Unable to find new Analysis [{AnalysisName}] with ID [{newAnalysis.ID}].");
                string actualAnalysisName = analysisFound.Name;
                Assert.True(
                    actualAnalysisName.Equals(AnalysisName, StringComparison.OrdinalIgnoreCase),
                    $"Name of found Analysis was incorrect. Actual [{actualAnalysisName}], expected [{AnalysisName}].");

                var analysisFindCat = db.AnalysisCategories[testData.AnalysisCategoryName];
                Assert.True(analysisFindCat != null, $"Unable to find Analysis Category [{testData.AnalysisCategoryName}].");

                string actualAnalysisRulePlugIn = analysisFound.AnalysisRulePlugIn.Name;
                Assert.True(
                    actualAnalysisRulePlugIn.Equals(testData.AnalysisRulePlugIn, StringComparison.OrdinalIgnoreCase),
                    $"Analysis Rule PlugIn for Analysis [{AnalysisName}] was [{actualAnalysisRulePlugIn}], expected [{testData.AnalysisRulePlugIn}].");

                int actualAnalysisCategoryCount = analysisFound.Categories.Count();
                const int ExpectedAnalysisCategoryCount = 1;
                Assert.True(
                    actualAnalysisCategoryCount == ExpectedAnalysisCategoryCount,
                    $"Analysis Category Count for Analysis [{AnalysisName}] was [{actualAnalysisCategoryCount}], expected [{ExpectedAnalysisCategoryCount}].");
                var analysisTemplateCat = analysisFound.Categories[testData.AnalysisCategoryName];
                Assert.True(
                    analysisTemplateCat != null,
                    $"Unable to find Analysis Category [{testData.AnalysisCategoryName}] in Analysis Template [{AnalysisName}].");

                string actualAnalysisTimeRulePlugIn = analysisFound.TimeRulePlugIn.Name;
                Assert.True(
                    actualAnalysisTimeRulePlugIn.Equals(testData.AnalysisTimeRulePlugIn, StringComparison.OrdinalIgnoreCase),
                    $"Analysis Rule PlugIn for Analysis [{AnalysisName}] was [{actualAnalysisTimeRulePlugIn}], expected [{testData.AnalysisTimeRulePlugIn}].");

                int actualAnalysisExtPropCount = analysisFound.ExtendedProperties.Count;
                const int ExpectedAnalysisExtPropCount = 1;
                Assert.True(
                    actualAnalysisExtPropCount == ExpectedAnalysisExtPropCount,
                    $"Analysis Rule PlugIn for Analysis [{AnalysisName}] was [{actualAnalysisExtPropCount}], expected [{ExpectedAnalysisExtPropCount}].");
                string actualAnalysisExtPropValue = analysisFound.ExtendedProperties[testData.AnalysisExtPropKey].ToString();
                Assert.True(
                    actualAnalysisExtPropValue.Equals(testData.AnalysisExtPropValue, StringComparison.OrdinalIgnoreCase),
                    $"Analysis Rule PlugIn for Analysis [{AnalysisName}] was [{actualAnalysisExtPropValue}], expected [{testData.AnalysisExtPropValue}].");

                // Rename
                Output.WriteLine($"Rename Analysis [{AnalysisName}] to [{AnalysisRename}].");
                analysisFound.Name = AnalysisRename;
                db.CheckIn();

                // Update test data with new name
                testData.Name = AnalysisRename;

                // This operation clears AFSDK cache and assures retrieval from AF server
                db = Fixture.ReconnectToDB();

                Output.WriteLine("Confirm Analysis renamed.");
                var findRenamedAnalysis = AFAnalysis.FindAnalysis(db.PISystem, newAnalysis.ID);
                Assert.True(findRenamedAnalysis != null, $"Unable to find new renamed Analysis [{AnalysisRename}] with ID [{newAnalysis.ID}].");

                string actualRenamedAnalysisName = findRenamedAnalysis.Name;
                Assert.True(
                    actualRenamedAnalysisName.Equals(AnalysisRename, StringComparison.OrdinalIgnoreCase),
                    $"Found Analysis did not have new name. Was [{actualRenamedAnalysisName}], expected [{AnalysisRename}].");

                Output.WriteLine("Delete Analysis.");
                findRenamedAnalysis.Delete();
                db.CheckIn();

                // This operation clears AFSDK cache and assures retrieval from AF server
                db = Fixture.ReconnectToDB();

                Output.WriteLine($"Verify Analysis was deleted.");
                var postDeleteAnalysis = AFAnalysis.FindAnalysis(db.PISystem, newAnalysis.ID);
                Assert.True(postDeleteAnalysis == null, $"Found Analysis with ID [{newAnalysis.ID}]. Expected it to have been deleted.");
            }
            finally
            {
                Fixture.RemoveAnalysisIfExists(AnalysisName, Output);
                Fixture.RemoveAnalysisIfExists(AnalysisRename, Output);
            }
        }

        /// <summary>
        /// Exercises Analysis Search operation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create several Analyses</para>
        /// <para>Confirm that a search will return the expected Analyses</para>
        /// <para>Delete the Analyses</para>
        /// </remarks>
        [Fact]
        public void AnalysisSearchTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            const string AnalysisSearchBaseName = "OSIsoftTests_AnalysisSearch";
            string analysisSearchObj1Name = $"{AnalysisSearchBaseName}Obj1";
            string analysisSearchObj2Name = $"{AnalysisSearchBaseName}Obj2";
            string analysisSearchObj3Name = $"{AnalysisSearchBaseName}LastObj3";
            string testSearchString = $"{AnalysisSearchBaseName}Obj*";

            try
            {
                // Precheck to make sure analyses do not already exist
                Fixture.RemoveAnalysisIfExists(analysisSearchObj1Name, Output);
                Fixture.RemoveAnalysisIfExists(analysisSearchObj2Name, Output);
                Fixture.RemoveAnalysisIfExists(analysisSearchObj3Name, Output);

                Output.WriteLine("Create Analyses for search test");
                var analysis1 = new AFAnalysis(db, analysisSearchObj1Name);
                var analysis2 = new AFAnalysis(db, analysisSearchObj2Name);
                var analysis3 = new AFAnalysis(db, analysisSearchObj3Name);
                db.CheckIn();

                // This operation clears AFSDK cache and assures retrieval from AF server
                db = Fixture.ReconnectToDB();

                Output.WriteLine($"Execute search for Analyses using search string [{testSearchString}].");
                using (var results = new AFAnalysisSearch(db, string.Empty, testSearchString))
                {
                    int actualAnalysisCount = results.GetTotalCount();
                    const int ExpectedAnalysisCount = 2;
                    Assert.True(
                        actualAnalysisCount == ExpectedAnalysisCount,
                        $"Search string [{testSearchString}] found [{actualAnalysisCount}] Analyses, expected {ExpectedAnalysisCount}.");
                    int actualAnalysisCountViaSearch = 0;
                    foreach (AFAnalysis at in results.FindObjects())
                    {
                        actualAnalysisCountViaSearch++;
                    }

                    int actualAnalysesFound = results.GetTotalCount();
                    Assert.True(
                        actualAnalysisCountViaSearch == ExpectedAnalysisCount,
                        $"Found [{actualAnalysisCountViaSearch}] Analyses, expected {ExpectedAnalysisCount}.");
                }
            }
            finally
            {
                Fixture.RemoveAnalysisIfExists(analysisSearchObj1Name, Output);
                Fixture.RemoveAnalysisIfExists(analysisSearchObj2Name, Output);
                Fixture.RemoveAnalysisIfExists(analysisSearchObj3Name, Output);
            }
        }

        /// <summary>
        /// Exercises Analysis Template Object by doing a Create, Read, Update and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create Analysis Template</para>
        /// <para>Confirm Analysis Template was properly created</para>
        /// <para>Rename the Analysis Template (and confirm)</para>
        /// <para>Delete the Analysis Template (And confirm)</para>
        /// </remarks>
        [Fact]
        public void AnalysisTemplateTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            const string AnalysisTemplateName = "OSIsoftTests_AF_AnalysisTest_NameAnalysis";
            const string AnalysisTemplateRename = "OSIsoftTests_AF_AnalysisTest_ReNamedAnalysis";
            const string AnalysisCategoryName = "OSIsoftTests_AF_AnalysisTest_AnalysisCat1";
            const string AnalysisTemplateRulePlugIn = "Imbalance";
            const string AnalysisTemplateTimeRulePlugIn = "Periodic";
            const string AnalysisTemplateExtPropKey = "OSIsoftTests_AF_AnalysisTest_ExpPropKey";
            const string AnalysisTemplateExtPropValue = "OSIsoftTests_AF_AnalysisTest_ExpPropKey";

            AFCategory analysisCat = db.AnalysisCategories[AnalysisCategoryName];
            if (analysisCat == null) analysisCat = db.AnalysisCategories.Add(AnalysisCategoryName);

            try
            {
                Output.WriteLine($"Create Analysis Template [{AnalysisTemplateName}].");
                var newAnalysisTemplate = new AFAnalysisTemplate(AnalysisTemplateName)
                {
                    AnalysisRulePlugIn = db.PISystem.AnalysisRulePlugIns[AnalysisTemplateRulePlugIn],
                };
                newAnalysisTemplate.Categories.Add(analysisCat);
                newAnalysisTemplate.TimeRulePlugIn = db.PISystem.TimeRulePlugIns[AnalysisTemplateTimeRulePlugIn];
                newAnalysisTemplate.ExtendedProperties.Add(AnalysisTemplateExtPropKey, AnalysisTemplateExtPropValue);
                db.CheckIn();

                // This operation clears AFSDK cache and assures retrieval from AF server
                db = Fixture.ReconnectToDB();

                Output.WriteLine("Confirm Analysis Template created and found.");
                var findAnalysisTemplate = AFAnalysisTemplate.FindAnalysisTemplate(db.PISystem, newAnalysisTemplate.ID);

                // verify found proper Analysis Object
                Output.WriteLine("Confirm Analysis properties are correct.");
                Assert.True(
                    findAnalysisTemplate != null,
                    $"Unable to find new Analysis Template [{AnalysisTemplateName}] with ID [{newAnalysisTemplate.ID}].");

                var analysisFindCat = db.AnalysisCategories[AnalysisCategoryName];
                Assert.True(
                    analysisFindCat != null,
                    $"Unable to find Analysis Category [{AnalysisCategoryName}]. It is used in Element Template [{AnalysisTemplateName}].");

                string actAnalysisTemplateRulePlugIn = findAnalysisTemplate.AnalysisRulePlugIn.Name;
                Assert.True(
                    actAnalysisTemplateRulePlugIn.Equals(AnalysisTemplateRulePlugIn, StringComparison.OrdinalIgnoreCase),
                    $"Analysis Rule PlugIn for Analysis Template [{AnalysisTemplateName}] was [{actAnalysisTemplateRulePlugIn}], expected [{AnalysisTemplateRulePlugIn}].");

                int actualAnalysisCategoryCount = findAnalysisTemplate.Categories.Count();
                Assert.True(
                    actualAnalysisCategoryCount == 1,
                    $"Analysis Category Count for Analysis Template [{AnalysisTemplateName}] was {actualAnalysisCategoryCount}, expected 1.");
                var analysisTemplateCat = findAnalysisTemplate.Categories[AnalysisCategoryName];
                Assert.True(
                    analysisTemplateCat != null,
                    $"Unable to find Analysis Category [{AnalysisCategoryName}] in Analysis Template [{AnalysisTemplateName}].");

                string actualAnalysisTemplateTimeRulePlugIn = findAnalysisTemplate.TimeRulePlugIn.Name;
                Assert.True(
                    actualAnalysisTemplateTimeRulePlugIn.Equals(AnalysisTemplateTimeRulePlugIn, StringComparison.OrdinalIgnoreCase),
                    $"Analysis Rule PlugIn for Analysis Template [{AnalysisTemplateName}] was [{actualAnalysisTemplateTimeRulePlugIn}], expected [{AnalysisTemplateTimeRulePlugIn}].");

                int actualAnalysisTemplateExtPropCount = findAnalysisTemplate.ExtendedProperties.Count;
                Assert.True(
                    actualAnalysisTemplateExtPropCount == 1,
                    $"Analysis Rule PlugIn for Analysis [{AnalysisTemplateName}] was {actualAnalysisTemplateExtPropCount}, expected 1.");
                string actualAnalysisExtPropValue = findAnalysisTemplate.ExtendedProperties[AnalysisTemplateExtPropKey].ToString();
                Assert.True(
                    actualAnalysisExtPropValue.Equals(AnalysisTemplateExtPropValue, StringComparison.OrdinalIgnoreCase),
                    $"Analysis Rule PlugIn for Analysis Template [{AnalysisTemplateName}] was [{actualAnalysisExtPropValue}], expected [{AnalysisTemplateExtPropValue}].");

                // rename
                Output.WriteLine($"Rename Analysis Template [{AnalysisTemplateName}] to [{AnalysisTemplateRename}].");
                findAnalysisTemplate.Name = AnalysisTemplateRename;
                db.CheckIn();

                // This operation clears AFSDK cache and assures retrieval from AF server
                db = Fixture.ReconnectToDB();

                Output.WriteLine("Confirm Analysis Template renamed.");
                var findRenamedAnalysisTemplate = AFAnalysisTemplate.FindAnalysisTemplate(db.PISystem, newAnalysisTemplate.ID);
                Assert.True(
                    findRenamedAnalysisTemplate != null,
                    $"Unable to find new renamed Analysis Template [{AnalysisTemplateRename}] with ID [{newAnalysisTemplate.ID}].");

                string actualRenamedAnalysisTemplateName = findRenamedAnalysisTemplate.Name;
                Assert.True(
                    actualRenamedAnalysisTemplateName.Equals(AnalysisTemplateRename, StringComparison.OrdinalIgnoreCase),
                    $"Found Analysis Template did not have new name. Was [{actualRenamedAnalysisTemplateName}], expected [{AnalysisTemplateRename}].");

                Output.WriteLine("Delete Analysis Template.");
                db.AnalysisTemplates.Remove(AnalysisTemplateRename);
                db.CheckIn();

                // This operation clears AFSDK cache and assures retrieval from AF server
                db = Fixture.ReconnectToDB();

                Output.WriteLine($"Verify Analysis Template was deleted.");
                var postDeleteAnalysisTemplate = AFAnalysisTemplate.FindAnalysisTemplate(db.PISystem, newAnalysisTemplate.ID);
                Assert.True(
                    postDeleteAnalysisTemplate == null,
                    $"Found Analysis Template with ID [{newAnalysisTemplate.ID}]. Expected it to have been deleted.");
            }
            finally
            {
                Fixture.RemoveAnalysisTemplateIfExists(AnalysisTemplateName, Output);
                Fixture.RemoveAnalysisTemplateIfExists(AnalysisTemplateRename, Output);
            }
        }

        /// <summary>
        /// Exercises Analysis Template Search operation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create several Analysis Templates</para>
        /// <para>Confirm that a search will return the expected Analysis Templates</para>
        /// <para>Delete the Analysis Templates</para>
        /// </remarks>
        [Fact]
        public void AnalysisTemplateSearchTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            const string AnalysisTemplateBaseName = "OSIsoftTests_AnalysisTempSearch";
            string analysisTmpltSrchObj1Name = $"{AnalysisTemplateBaseName}Obj1";
            string analysisTmpltSrchObj2Name = $"{AnalysisTemplateBaseName}Obj2";
            string analysisTmpltSrchObj3Name = $"{AnalysisTemplateBaseName}LastObj3";
            string testSearchString = $"{AnalysisTemplateBaseName}Obj*";

            try
            {
                // Precheck to make sure analyses Templates do not already exist
                Fixture.RemoveAnalysisTemplateIfExists(analysisTmpltSrchObj1Name, Output);
                Fixture.RemoveAnalysisTemplateIfExists(analysisTmpltSrchObj2Name, Output);
                Fixture.RemoveAnalysisTemplateIfExists(analysisTmpltSrchObj3Name, Output);

                Output.WriteLine("Create Analysis Templates for search test.");
                db.AnalysisTemplates.Add(analysisTmpltSrchObj1Name);
                db.AnalysisTemplates.Add(analysisTmpltSrchObj2Name);
                db.AnalysisTemplates.Add(analysisTmpltSrchObj3Name);
                db.CheckIn();

                // This operation clears AFSDK cache and assures retrieval from AF server
                db = Fixture.ReconnectToDB();

                Output.WriteLine($"Execute search for Analysis Templates using search string [{testSearchString}].");
                using (var results = new AFAnalysisTemplateSearch(db, string.Empty, testSearchString))
                {
                    const int ExpectedCount = 2;
                    int actualAnalysisTemplateCount = results.GetTotalCount();
                    Assert.True(
                        actualAnalysisTemplateCount == 2,
                        $"Search string [{testSearchString}] found {actualAnalysisTemplateCount} Analysis Templates, expected 2.");

                    int actualAnalysisTemplateSearchCount = 0;
                    foreach (AFAnalysisTemplate at in results.FindObjects())
                    {
                        actualAnalysisTemplateSearchCount++;
                    }

                    Assert.True(
                        actualAnalysisTemplateSearchCount == ExpectedCount,
                        $"Found {actualAnalysisTemplateSearchCount} Analysis Templates, expected {ExpectedCount}.");
                }
            }
            finally
            {
                // cleanup
                Fixture.RemoveAnalysisTemplateIfExists(analysisTmpltSrchObj1Name, Output);
                Fixture.RemoveAnalysisTemplateIfExists(analysisTmpltSrchObj2Name, Output);
                Fixture.RemoveAnalysisTemplateIfExists(analysisTmpltSrchObj3Name, Output);
            }
        }

        /// <summary>
        /// Exercises Analysis Status.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Query running analyses</para>
        /// <para>Confirm no existing analyses are in error</para>
        /// </remarks>
        [Fact]
        public void NoErrorAnalysesTest()
        {
            AFDatabase db = Fixture.AFDatabase;
            const int MaxErrorMessage = 10;

            var service = Fixture.PISystem.AnalysisService;
            Assert.True(service != null, $"Could not connect to the Analysis Service in the PI System [{Fixture.PISystem.Name}].");

            // Test that there are no analyses in error
            var queryString = $@"Path:='\\\\{Fixture.PISystem.Name}\\{db.Name}\\*'";
            Output.WriteLine($"Query precreated analyses and confirm they exist with query string [{queryString}].");
            var results = service.QueryRuntimeInformation(queryString, "name id status statusDetail");
            Assert.True(results.Count() > 0, $"Can't find any analyses in database {db.Name}.");

            // PI Analysis Service may still hold inactive analyses from a database deleted previously.
            Output.WriteLine("Query precreated analyses and confirm there are none in an error state.");
            var analysesInDatabase = AFAnalysis
                .FindAnalyses(db, "*", AFSearchField.Name, AFSortField.Name, AFSortOrder.Ascending, int.MaxValue);
            var analysesInDatabaseCount = analysesInDatabase.Count;
            var inactiveAnalysesCount = results.Count() - analysesInDatabaseCount;
            var analysesInError =
                results.Where(result => result.Any(a => a.ToString().Equals("Error", StringComparison.OrdinalIgnoreCase)));
            var unexpectedAnalysesInErrorCount = Math.Abs(analysesInError.Count() - inactiveAnalysesCount);
            int numInErrorMessage = 0;
            var stringBuilder = new StringBuilder();
            stringBuilder.AppendLine($"Found {unexpectedAnalysesInErrorCount} Analyses in database [{db.Name}] in error status.");
            if (unexpectedAnalysesInErrorCount >= 0)
            {
                foreach (var analysis in analysesInError)
                {
                    if (analysesInDatabase.Any(a => a.UniqueID.Contains(analysis[1])))
                    {
                        numInErrorMessage++;
                        stringBuilder.AppendLine($"Analysis [{analysis[0]}] : [{analysis[1]}] is in an error state with status details of: [{analysis[3]}].");
                    }

                    if (numInErrorMessage == MaxErrorMessage)
                    {
                        stringBuilder.AppendLine($"Printed [{MaxErrorMessage}] analyses out of [{unexpectedAnalysesInErrorCount}].");
                        break;
                    }
                }
            }

            Assert.True(
                unexpectedAnalysesInErrorCount <= 0,
                stringBuilder.ToString());
        }

        /// <summary>
        /// Exercises Analysis Status.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Query running analyses</para>
        /// <para>Confirm existing analyses are evaluating</para>
        /// </remarks>
        [Fact]
        public void AnalysesAreEvaluatingTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            var service = Fixture.PISystem.AnalysisService;
            Assert.True(service != null, "Could not connect to the PI System Analysis Service.");

            var queryString = $@"path:'\\\\{Fixture.PISystem.Name}\\{db.Name}\\*Wind Farm 02*TUR02001*Demo Data - Digital Calcs*'";
            Output.WriteLine($"Query precreated analyses and confirm they are evaluating with query string [{queryString}].");

            // Check for evaluation time
            var trigger = service.QueryRuntimeInformation(
                queryString,
                "lastTriggerTime");
            Assert.True(trigger.Count() == 1, $"Expected 1 result from query [{queryString}], but {trigger.Count()} were found.");
            var firstTriggerTime = new AFTime(trigger.ToList()[0][0]);
            var secondTriggerTime = firstTriggerTime;

            // Check evaluation time again to confirm analyses are evaluating
            AssertEventually.True(() =>
            {
                trigger = service.QueryRuntimeInformation(
                queryString,
                "lastTriggerTime");
                Assert.True(trigger.Count() == 1, $"Expected 1 result from query [{queryString}], but {trigger.Count()} were found.");
                secondTriggerTime = new AFTime(trigger.ToList()[0][0]);

                return secondTriggerTime > firstTriggerTime;
            },
            TimeSpan.FromSeconds(30),
            TimeSpan.FromSeconds(3),
            $"Expected the evaluation time [{secondTriggerTime}] to be later than the first evaluation time [{firstTriggerTime}].");
        }

        /// <summary>
        /// Exercises Periodic PE Analysis Evaluation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Confirm that an existing PE analysis evaluates as expected</para>
        /// </remarks>
        [Fact]
        public void ServiceRunsPeriodicPerformanceEquationAnalysis()
        {
            AFTime testStartTime = AFTime.Now;
            AFDatabase db = Fixture.AFDatabase;

            AFAnalysis analysis;
            string name = "Demo Data - Digital Calcs";
            using (var results = new AFAnalysisSearch(db, string.Empty, $"Name:'{name}'"))
            {
                Assert.True(results.GetTotalCount() > 0, $"Failed to find any analyses with name [{name}].");

                Output.WriteLine("Find periodic analysis and make sure it is evaluating as expected.");
                analysis = results.FindObjects().ElementAt(0);
                Assert.True(analysis.Status == AFStatus.Enabled, $"Analysis [{analysis.Name}] is not enabled.");
            }

            var outputs = analysis.GetOutputs();
            var firstOutput = outputs[0].GetValue();
            var secondOutput = outputs[1].GetValue();

            // Check output type to determine if valid
            for (int i = 0; i < outputs.Count; i++)
            {
                var outputType = outputs[i].GetValue().Value.GetType();
                Assert.True(outputType == typeof(AFEnumerationValue), $"Incorrect output value type. Expected type: [{typeof(AFEnumerationValue)}] Actual type: [{outputType}].");
            }

            AssertEventually.True(() =>
            {
                firstOutput = outputs[0].GetValue();
                return firstOutput.Timestamp.UtcSeconds > testStartTime.UtcSeconds - 10;
            },
            $"Output [{analysis.Name}\\{outputs[0].Name}] has not evaluated in last 10 seconds. " +
                $"Output {AFFixture.DisplayAFValue(firstOutput)} and evaluation started at [{testStartTime}].");

            AssertEventually.True(() =>
            {
                secondOutput = outputs[1].GetValue();
                return secondOutput.Timestamp.UtcSeconds > testStartTime.UtcSeconds - 10;
            },
            $"Output [{analysis.Name}\\{outputs[1].Name}] has not evaluated in last 10 seconds. " +
                $"Output {AFFixture.DisplayAFValue(secondOutput)} and evaluation started at [{testStartTime}].");

            // Digital state outputs are either greater or less than the next output
            var currentValueInt = Convert.ToInt32(firstOutput.Value, CultureInfo.InvariantCulture);
            var currentValue2Int = Convert.ToInt32(secondOutput.Value, CultureInfo.InvariantCulture);
            Assert.True(currentValueInt != currentValue2Int, $"First output value {currentValueInt} expected to be less than or greater than " +
                $"second output value {currentValue2Int}.");
        }

        /// <summary>
        /// Exercises Natural PE Analysis Evaluation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Confirm that existing Natural PE analysis evaluates</para>
        /// </remarks>
        [Fact]
        public void ServiceRunsNaturalPerformanceEquationAnalysis()
        {
            AFDatabase db = Fixture.AFDatabase;

            AFAnalysis analysis;
            string name = "Demo Data - Active Power";
            using (var results = new AFAnalysisSearch(db, string.Empty, $"Name:'{name}'"))
            {
                Assert.True(results.GetTotalCount() > 0, $"Failed to find any Analyses with name [{name}].");

                Output.WriteLine("Find natural analysis and make sure it is evaluating as expected after inserting a new value.");
                analysis = results.FindObjects().ElementAt(0);
                Assert.True(analysis.Status == AFStatus.Enabled, $"Analysis [{analysis.Name}] is not enabled.");
            }

            var input = analysis.GetInputs()[0];
            var currentValue = input.GetValue();
            bool inconsistentBufferingSettings = false;
            try
            {
                input.SetValue(new AFValue(20));
                var output = analysis.GetOutputs()[0];
                var timestampToCompare = AFTime.Now - TimeSpan.FromSeconds(5);
                var timeToCompare = AFTime.Now.UtcSeconds - 5;

                // Check output type to determine if valid
                var outputType = output.GetValue().Value.GetType();
                Assert.True(outputType == typeof(float), $"Incorrect output value type. Expected type: [{typeof(float)}] Actual type: [{outputType}].");

                AssertEventually.True(
                    () => output.GetValue().Timestamp.UtcSeconds > timeToCompare,
                    TimeSpan.FromSeconds(20),
                    TimeSpan.FromSeconds(1),
                    $"Analysis [{analysis.Name}] failed to evaluate for an input trigger value. " +
                    $"Output {AFFixture.DisplayAFValue(output.GetValue())} and attempted to evaluate at [{timestampToCompare}].");
            }
            catch (PIException ex)
            {
                // Handle the specific buffering issue, [-11414] Buffered point does not accept new events
                if (ex.StatusCode == -11414)
                {
                    inconsistentBufferingSettings = true;
                    throw new InvalidOperationException($"Test failed to send data to [{input.PIPoint.Name}] because of inconsistent buffering settings.  " +
                           $"PI Buffer Subsystem was not running locally, while PI Analysis Service running on {Settings.PIAnalysisService} " +
                           $"has sent data to this point via PI Buffer Subsystem.  Please enable PI Buffer Subsystem locally and try again.  " +
                           $"Read OSIsoft KB article KB00093 for more details regarding this error.");
                }

                throw;
            }
            finally
            {
                if (!inconsistentBufferingSettings)
                {
                    input.SetValue(new AFValue(currentValue.Value, AFTime.Now));
                }
            }
        }

        /// <summary>
        /// Exercises EF Analysis Evaluation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Confirm that existing EF analysis evaluates as expected</para>
        /// </remarks>
        [Fact]
        public void ServiceRunsNaturalEFAnalysis()
        {
            EventFrameGenerationTest("Power Event", PowerEventTriggerValue, PowerEventsEndValue);
        }

        /// <summary>
        /// Exercises Roll Up Analysis Evaluation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Confirm that existing roll up analysis evaluates</para>
        /// </remarks>
        [Fact]
        public void ServiceRunsPeriodicRollupAnalysis()
        {
            AFDatabase db = Fixture.AFDatabase;

            AFAnalysis analysis;
            string name = "Lost Power";
            using (var results = new AFAnalysisSearch(db, string.Empty, $"Name:'{name}' Target:'Region 1'"))
            {
                Assert.True(results.GetTotalCount() == 1, $"Failed to find any analyses with name [{name}].");
                Output.WriteLine("Find periodic roll up analysis.");
                analysis = results.FindObjects().FirstOrDefault();
                Assert.True(analysis.Status == AFStatus.Enabled, $"Analysis [{analysis.Name}] is not enabled.");
            }

            // Confirm Rollup is evaluating
            Output.WriteLine("Make sure periodic roll up analysis is evaluating as expected after inserting a new value.");
            var timeToCompare = AFTime.Now.UtcSeconds - 5;
            var output = analysis.GetOutputs()[0];
            AssertEventually.True(
                () => output.GetValue().Timestamp.UtcSeconds > timeToCompare,
                TimeSpan.FromSeconds(20),
                TimeSpan.FromSeconds(1),
                $"Analysis [{analysis.Name}] failed to evaluate for an input trigger value.");
            double expected, receivedOutput;

            // The roll up does a sum of values - let's confirm the roll up is as expected
            bool CompareOutput()
            {
                var afAttrabutes = analysis.GetInputs();
                var expectedResult = afAttrabutes.Select(i => i.GetValue()).Sum(v => Convert.ToDouble(v.Value, CultureInfo.InvariantCulture));
                output = analysis.GetOutputs()[0];

                Output.WriteLine($"Expected results were gathered by summing input from attribute [{afAttrabutes[0].Name}] and totaled to [{expectedResult}].");
                expected = Math.Round(expectedResult, 2);
                receivedOutput = Math.Round(Convert.ToDouble(output.GetValue().Value, CultureInfo.InvariantCulture), 2);
                if (expected != receivedOutput)
                {
                    Output.WriteLine($"Expected Output of [{expected}] but received output of [{receivedOutput}].");
                    return false;
                }

                return true;
            }

            AssertEventually.True(
                () => CompareOutput(),
                TimeSpan.FromSeconds(300),
                TimeSpan.FromSeconds(10),
                $"Analysis [{analysis.Name}] failed to evaluate for an input trigger value.");
        }

        /// <summary>
        /// Exercises SQC Analysis Evaluation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Confirm that existing SQC analysis evaluates as expected</para>
        /// </remarks>
        [Fact]
        public void ServiceRunsNaturalSQCAnalysis()
        {
            EventFrameGenerationTest("Power Production SQC", PowerProductionSQCTriggerValue, PowerEventsEndValue);
        }

        /// <summary>
        /// Exercises Analysis Backfilling.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create one PE analysis</para>
        /// <para>Confirm that analysis backfills as expected</para>
        /// </remarks>
        [Fact]
        public void ServiceBackfillsAnalysis()
        {
            AFDatabase db = Fixture.AFDatabase;

            AFAnalysis analysis;
            string name = "Demo Data - Digital Calcs";
            using (var results = new AFAnalysisSearch(db, string.Empty, $"Name:'{name}'"))
            {
                Assert.True(results.GetTotalCount() > 0, $"Failed to find any analyses with name [{name}].");

                Output.WriteLine("Find periodic analysis (frequency of 2 seconds).");
                analysis = results.FindObjects().ElementAt(0);
                Assert.True(analysis.Status == AFStatus.Enabled, $"Analysis [{analysis.Name}] is not enabled.");
            }

            // Make sure no date exists for 1hr
            var now = AFTime.Now;
            var timeRange = new AFTimeRange("y-1h", "y");
            foreach (var atr in analysis.GetOutputs())
            {
                var values = new AFValues { Attribute = atr };
                AFListData.ReplaceValues(timeRange, new[] { values });
            }

            AssertEventually.Equal(
                0,
                () => analysis.GetOutputs().Sum(atr => atr.GetRecordedValues(timeRange).Count),
                TimeSpan.FromSeconds(60),
                TimeSpan.FromSeconds(3));

            Output.WriteLine("Backfill data");
            var service = Fixture.PISystem.AnalysisService;
            Assert.True(service != null, $"Could not connect to the Analysis Service in the PI System [{Fixture.PISystem.Name}].");
            var response = service.QueueCalculation(new List<AFAnalysis>() { analysis }, timeRange, AFAnalysisService.CalculationMode.FillDataGaps);
            Assert.True(response != null, $"Could not get a response from the Analysis Service in the PI System [{Fixture.PISystem.Name}].");
            Assert.False(Guid.Empty.ToString() == response.ToString(), $"The response from the Analysis Service was an empty GUID.");

            var queryString = $@"Path:='\\\\{Fixture.PISystem.Name}\\{db.Name}\\*'";
            var statusInfo = service.QueryRuntimeInformation(queryString, "id status statusDetail")
                .Where(value => value.Any(a => a.ToString().Equals(analysis.UniqueID, StringComparison.OrdinalIgnoreCase))).ToList()[0];
            Output.WriteLine("Confirm expected number of values are written.");
            var expectedValuesWritten = 1801;
            var finalErrorValue = 0;

            // Status may be up to a minute out of date in error message 
            var outputToCheck = analysis.GetOutputs()[0];
            AssertEventually.True(() =>
            {
                finalErrorValue = outputToCheck.GetRecordedValues(timeRange).Count;
                return finalErrorValue == expectedValuesWritten;
            },
                TimeSpan.FromSeconds(60),
                TimeSpan.FromSeconds(3), $"Found [{finalErrorValue}] written values, but expected [{expectedValuesWritten}]. Analysis Status is [{statusInfo[1]}] with status details of [{statusInfo[2]}]");

            // Make sure values for last 5 minutes are as expected, as sanity check
            // There is a digital value every 2 seconds
            var expectedValues = new List<AFValue>();
            var startTime = new AFTime("y-5m", now) - new AFTimeSpan(TimeSpan.FromSeconds(2));
            for (int i = 0; i < 5; i++)
            {
                for (int j = 0; j < 30; j++)
                {
                    startTime += new AFTimeSpan(TimeSpan.FromSeconds(2));
                    expectedValues.Add(new AFValue(db.EnumerationSets["Modes"].GetByValue(i), startTime));
                }
            }

            expectedValues.Add(new AFValue(db.EnumerationSets["Modes"].GetByValue(0), startTime + new AFTimeSpan(TimeSpan.FromSeconds(2))));
            AnalysisHelper.AssertResults(outputToCheck, new AFTimeRange(new AFTime("y-5m", now), new AFTime("y", now)), expectedValues);
        }

        /// <summary>
        /// Exercises Analysis Recalculation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Confirm that existing PE analysis recalculates as expected</para>
        /// </remarks>
        [Fact]
        public void ServiceRecalculatesAnalysis()
        {
            AFDatabase db = Fixture.AFDatabase;

            AFAnalysis analysis;
            string name = "Demo Data - Digital Calcs";
            using (var results = new AFAnalysisSearch(db, string.Empty, $"Name:'{name}'"))
            {
                Assert.True(results.GetTotalCount() > 0, $"Failed to find any Analyses with name [{name}].");

                Output.WriteLine("Find periodic analysis (frequency of 2 seconds).");
                analysis = results.FindObjects().ElementAt(0);
                Assert.True(analysis.Status == AFStatus.Enabled);
            }

            var output = analysis.GetOutputs()[0];

            Output.WriteLine("Recalculate data.");
            var timeRange = new AFTimeRange("y-1h", "y");
            var service = Fixture.PISystem.AnalysisService;
            Assert.True(service != null, $"Could not connect to the Analysis Service in the PI System [{Fixture.PISystem.Name}].");
            var response = service.QueueCalculation(new List<AFAnalysis>() { analysis }, timeRange, AFAnalysisService.CalculationMode.DeleteExistingData);
            Assert.True(response != null, $"Could not get a response from the Analysis Service in the PI System [{Fixture.PISystem.Name}].");
            Assert.False(Guid.Empty.ToString() == response.ToString(), $"The response from the Analysis Service was an empty GUID.");

            var queryString = $@"Path:='\\\\{Fixture.PISystem.Name}\\{db.Name}\\*'";
            var statusInfo = service.QueryRuntimeInformation(queryString, "id status statusDetail")
                .Where(value => value.Any(a => a.ToString().Equals(analysis.UniqueID, StringComparison.OrdinalIgnoreCase))).ToList()[0];

            // Status may be up to a minute out of date in error message 
            Output.WriteLine("Confirm expected number of values are written.");
            var expectedValuesWritten = 1801;
            var finalErrorValue = 0;
            AssertEventually.True(() =>
            {
                finalErrorValue = output.GetRecordedValues(timeRange).Count;
                return finalErrorValue == expectedValuesWritten;
            },
                TimeSpan.FromSeconds(60),
                TimeSpan.FromSeconds(3), $"Found [{finalErrorValue}] written values, but expected [{expectedValuesWritten}]. Analysis Status is [{statusInfo[1]}] with status details of [{statusInfo[2]}]");

            // Make sure values for last 5 minutes are as expected, as sanity check
            // There is a digital value every 2 seconds
            var now = AFTime.Now;
            var expectedValues = new List<AFValue>();
            var startTime = new AFTime("y-5m", now) - new AFTimeSpan(TimeSpan.FromSeconds(2));
            for (int i = 0; i < 5; i++)
            {
                for (int j = 0; j < 30; j++)
                {
                    startTime += new AFTimeSpan(TimeSpan.FromSeconds(2));
                    expectedValues.Add(new AFValue(db.EnumerationSets["Modes"].GetByValue(i), startTime));
                }
            }

            expectedValues.Add(new AFValue(db.EnumerationSets["Modes"].GetByValue(0), startTime + new AFTimeSpan(TimeSpan.FromSeconds(2))));
            AnalysisHelper.AssertResults(output, new AFTimeRange(new AFTime("y-5m", now), new AFTime("y", now)), expectedValues);
        }

        /// <summary>
        /// Tests EF generation function by analyses of EF generation or SQC types.
        /// </summary>
        /// <param name="analysisTemplateName">Target analysis template name.</param>
        /// <param name="triggerValue">A value to trigger event frame generation.</param>
        /// <param name="endValue">A value to end open event frames.</param>
        private void EventFrameGenerationTest(string analysisTemplateName, double triggerValue, double endValue)
        {
            AFDatabase db = Fixture.AFDatabase;

            AFAnalysis analysis;
            using (var results = new AFAnalysisSearch(db, string.Empty, $"Name:'{analysisTemplateName}'"))
            {
                int totalCount = results.GetTotalCount();
                Assert.True(
                    results.GetTotalCount() > 0,
                    $"Failed to find any Analyses with name [{analysisTemplateName}].");

                // Find natural analysis and make sure it is enabled.
                analysis = results.FindObjects().ElementAt(0);
                Assert.True(analysis.Status == AFStatus.Enabled, $"Analysis [{analysis.Name}] is not enabled.");
            }

            var input = analysis.GetInputs()[0];

            try
            {
                // Make sure no active EFs are present by inserting a value supposed to end the EFs.
                AFTime startTime;
                var currentTime = AFTime.Now.TruncateToWholeSeconds();
                input.SetValue(new AFValue(endValue, currentTime));
                using (var efSearch = new AFEventFrameSearch(
                                        db,
                                        "EventFrames",
                                        AFEventFrameSearchMode.ForwardInProgress,
                                        currentTime - TimeSpan.FromSeconds(1),
                                        $"Analysis:='{analysis.Name}'"))
                {
                    AssertEventually.True(
                        () => efSearch.FindObjects().Count() == 0,
                        TimeSpan.FromSeconds(30),
                        TimeSpan.FromSeconds(1),
                        $"There are still active event frames for analysis [{analysis.Name}], but expect to not have any.");

                    // Sleep 1 second to avoid the same timestamp for two values.
                    Thread.Sleep(TimeSpan.FromSeconds(1));
                    startTime = AFTime.Now.TruncateToWholeSeconds();
                    input.SetValue(new AFValue(triggerValue, startTime));
                }

                // Confirm an event frame is created
                using (var efSearch = new AFEventFrameSearch(
                                    db,
                                    "EventFrames",
                                    AFEventFrameSearchMode.ForwardInProgress,
                                    startTime - TimeSpan.FromSeconds(1),
                                    $"Analysis:='{analysis.Name}'"))
                {
                    AssertEventually.True(
                        () => efSearch.FindObjects().Count() > 0,
                        TimeSpan.FromSeconds(30),
                        TimeSpan.FromSeconds(1),
                        $"Can't find opened event frame for Analysis [{analysis.Name}].");
                    var efs = efSearch.FindObjects();
                    Assert.True(
                        efs.Count() == 1,
                        $"Found {efs.Count()} event frames for Analysis [{analysis.Name}], but expect to have only 1.");
                    Assert.True(
                        efs.ElementAt(0).EndTime == AFTime.MaxValue,
                        $"The event frame [{efs.ElementAt(0).Name}] is closed but expected to be open.");
                }

                // Close EF
                // Sleep 1 second to ensure the end time is later than the start time
                Thread.Sleep(TimeSpan.FromSeconds(1));
                var endTime = AFTime.Now.TruncateToWholeSeconds();
                input.SetValue(new AFValue(endValue, endTime));

                // Confirm the event frame is closed
                using (var efSearch = new AFEventFrameSearch(
                                    db,
                                    "EventFrames",
                                    AFEventFrameSearchMode.ForwardFromStartTime,
                                    startTime - TimeSpan.FromSeconds(1),
                                    $"Analysis:='{analysis.Name}'"))
                {
                    AssertEventually.True(
                        () =>
                        {
                            var efs = efSearch.FindObjects();
                            return efs.Count() > 0 && efs.ElementAt(0).EndTime.TruncateToWholeSeconds() == endTime;
                        },
                        TimeSpan.FromSeconds(30),
                        TimeSpan.FromSeconds(1),
                        $"Can't find closed event frame for Analysis [{analysis.Name}].");
                }
            }
            finally
            {
                input.SetValue(new AFValue(endValue, AFTime.Now));
            }
        }
    }
}
