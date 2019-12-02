using System;
using System.Collections.Generic;
using System.Globalization;
using OSIsoft.AF;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.Diagnostics;
using OSIsoft.AF.EventFrame;
using OSIsoft.AF.Search;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests the ability to create, read, update, and delete Event Frames
    /// in the AF Server.
    /// </summary>
    [Collection("AF collection")]
    public class EFTests : IClassFixture<AFFixture>
    {
        /// <summary>
        /// Constructor for EFTEsts Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage AF connection and specific helper functions.</param>
        public EFTests(ITestOutputHelper output, AFFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private AFFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Exercises AF Event Frame by doing a Create, Read, Update and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a Event Frame</para>
        /// <para>Confirm Event Frame was properly created</para>
        /// <para>Rename the Event Frame (And confirm)</para>
        /// <para>Delete the Event Frame (And confirm)</para>
        /// </remarks>
        [Fact]
        public void EventFrameTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            const string EventFrameName = "OSIsoftTests_AF_InitEF#1A";
            const string EventFrameRename = "OSIsoftTests_AF_EventFrameTest_NewName";

            var testData = new EventFrameTestConfiguration(EventFrameName);

            try
            {
                Output.WriteLine($"Create Event Frame [{EventFrameName}].");
                var evtfr1 = FullEventFrameCreate(db, testData);
                db.CheckIn();

                Output.WriteLine("Confirm Event Frame created and found.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                evtfr1 = AFEventFrame.FindEventFrame(db.PISystem, evtfr1.ID);
                FullEventFrameVerify(db, evtfr1.ID, testData, Output);

                Output.WriteLine($"Rename Event Frame to [{EventFrameRename}].");
                evtfr1.Name = EventFrameRename;
                db.CheckIn();

                // Update test data with new name
                testData.Name = EventFrameRename;

                Output.WriteLine($"Verify Event Frame [{EventFrameRename}] found on reread.");
                db = Fixture.ReconnectToDB();
                evtfr1 = AFEventFrame.FindEventFrame(db.PISystem, evtfr1.ID);
                FullEventFrameVerify(db, evtfr1.ID, testData, Output);

                Output.WriteLine($"Delete Event Frame [{EventFrameRename}].");
                evtfr1.Delete();
                db.CheckIn();

                Output.WriteLine($"Confirm Event Frame deleted.");
                db = Fixture.ReconnectToDB();
                var deletedEFSearch = AFEventFrame.FindEventFrame(db.PISystem, evtfr1.ID);
                Assert.True(deletedEFSearch == null, $"Event Frame [{EventFrameRename}] was not deleted as expected.");
            }
            finally
            {
                Fixture.RemoveElementIfExists(testData.EventFrameElementName, Output);
            }
        }

        /// <summary>
        /// Exercises AF Event Frame Search operation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create several Event Frames</para>
        /// <para></para>Confirm that a search will return the expected Event Frames</para>
        /// <para></para>Delete the Event Frames</para>
        /// </remarks>
        [Fact]
        public void EventFrameSearchTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            string baseEFNameText = $"OSIsoftTests_AF_EFSrchTst - {DateTime.UtcNow.ToString(AFFixture.DateTimeFormat, CultureInfo.InvariantCulture)}_";
            string ef1Name = $"{baseEFNameText}EF1";
            string ef2Name = $"{baseEFNameText}EF2";
            string ef3Name = $"{baseEFNameText}LastEF";
            string eventFrameSearchTxt = $"'{baseEFNameText}EF*'";

            try
            {
                Output.WriteLine($"Create Event Frames for search.");
                _ = new AFEventFrame(db, ef1Name);
                _ = new AFEventFrame(db, ef2Name);
                _ = new AFEventFrame(db, ef3Name);
                db.CheckIn();

                Output.WriteLine($"Execute search for Event Frames using search string [{eventFrameSearchTxt}].");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                using (var searchResults = new AFEventFrameSearch(db, string.Empty, eventFrameSearchTxt))
                {
                    int actualEventsFramesFound = searchResults.GetTotalCount();
                    const int ExpectedEventFrames = 2;
                    Assert.True(actualEventsFramesFound == ExpectedEventFrames, $"Search string [{eventFrameSearchTxt}] found " +
                        $"{actualEventsFramesFound} Event Frames, expected {ExpectedEventFrames}.");

                    int actualEventFramesFoundWithSearch = 0;
                    foreach (AFEventFrame at in searchResults.FindObjects())
                    {
                        actualEventFramesFoundWithSearch++;
                    }

                    Assert.True(actualEventFramesFoundWithSearch == ExpectedEventFrames,
                        $"Only able to find {actualEventFramesFoundWithSearch} Elements returned using Search string " +
                        $"[{eventFrameSearchTxt}], expected {ExpectedEventFrames}.");
                }
            }
            finally
            {
                Fixture.RemoveEventFrameIfExists(ef1Name, Output);
                Fixture.RemoveEventFrameIfExists(ef2Name, Output);
                Fixture.RemoveEventFrameIfExists(ef3Name, Output);
            }
        }

        /// <summary>
        /// Exercises AF Event Frame Attribute Search operation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Event Frame with several Attributes</para>
        /// <para>Confirm that a search within the Event Frame will return the expected attributes</para>
        /// <para>Delete the Event Frame</para>
        /// </remarks>
        [Fact]
        public void EventFrameAttributeSearchTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            string ef1Name = $"OSIsoftTests_EFAttributeSearchTest - {DateTime.UtcNow.ToString(AFFixture.DateTimeFormat, CultureInfo.InvariantCulture)}_EF1";
            const string AttributeBaseName = "OSIsoftTests_Attr";
            string attrib1Name = $"{AttributeBaseName}#1";
            string attrib2Name = $"{AttributeBaseName}#2";
            string attrib3Name = $"{AttributeBaseName}LAST#3";

            try
            {
                Output.WriteLine($"Create event frame [{ef1Name}] and add attributes.");
                var eventframe1 = new AFEventFrame(db, ef1Name);
                eventframe1.Attributes.Add(attrib1Name);
                eventframe1.Attributes.Add(attrib2Name);
                eventframe1.Attributes.Add(attrib3Name);
                db.CheckIn();

                string searchString = @"EventFrame:{ Name:'" + ef1Name + "' } Name:'" + AttributeBaseName + "#*'";
                Output.WriteLine($"Search in event frame with search string [{searchString}].");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                using (var results = new AFAttributeSearch(db, "a search", searchString))
                {
                    Output.WriteLine($"Review attributes found in search.");
                    int actualRunningCount = 0;
                    foreach (AFAttribute at in results.FindObjects())
                    {
                        actualRunningCount++;
                    }

                    int actualCount = results.GetTotalCount();
                    const int ExpectedCount = 2;
                    Assert.True(actualCount == ExpectedCount,
                        $"Attribute search in EventFrame [{ef1Name}] found {actualCount}, expected {ExpectedCount}.");
                    Assert.True(actualRunningCount == ExpectedCount,
                        $"Attribute search in EventFrame [{ef1Name}] found {actualRunningCount} attributes, expected {ExpectedCount}.");
                }
            }
            finally
            {
                Fixture.RemoveEventFrameIfExists(ef1Name, Output);
            }
        }

        /// <summary>
        /// Exercises AF Event Frames in a hierarchy.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create several Event Frames and layer them in a hierarchy</para>
        /// <para>Confirm the Event Frames at lowest level can be reached</para>
        /// <para>Delete the Event Frames</para>
        /// </remarks>
        [Fact]
        public void EventFrameHierarchyTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            string uniqueText = DateTime.UtcNow.ToString(AFFixture.DateTimeFormat, CultureInfo.InvariantCulture);
            string rootEFName = $"OSIsoftTests_AF_EventFrameHierarchyTest_{uniqueText}RootElem";
            string ef1Name = $"OSIsoftTests_AF_EventFrameHierarchyTest_{uniqueText}EF1";
            string ef2Name = $"OSIsoftTests_AF_EventFrameHierarchyTest_{uniqueText}EF2";
            string ef3Name = $"OSIsoftTests_AF_EventFrameHierarchyTest_{uniqueText}EF3";
            string ef4Name = $"OSIsoftTests_AF_EventFrameHierarchyTest_{uniqueText}EF4";

            try
            {
                Output.WriteLine($"Create root Event Frame [{rootEFName}] with hierarchy 4 Event Frames deep.");
                var rootEF = new AFEventFrame(db, ef1Name);
                var ef1 = new AFEventFrame(db, ef1Name);
                var ef2 = new AFEventFrame(db, ef2Name);
                var ef3 = new AFEventFrame(db, ef3Name);
                var ef4 = new AFEventFrame(db, ef4Name);

                rootEF.EventFrames.Add(ef1);
                ef1.EventFrames.Add(ef2);
                ef2.EventFrames.Add(ef3);
                ef3.EventFrames.Add(ef4);
                db.CheckIn();

                Output.WriteLine("Check that event frame hierarchy was created correctly.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var foundRootEF = AFEventFrame.FindEventFrame(db.PISystem, rootEF.ID);
                Assert.True(foundRootEF != null, $"Created Event Frame [{rootEFName}] not found with ID [{rootEF.ID}].");
                AFEventFrame lastEFInHeirarchy =
                    foundRootEF.EventFrames[ef1Name].EventFrames[ef2Name].EventFrames[ef3Name].EventFrames[ef4Name];
                Assert.True(lastEFInHeirarchy != null, $"Search down hierarchy from root did not find Event Frame.");
                Assert.True(lastEFInHeirarchy.Name.Equals(ef4Name,
                    StringComparison.OrdinalIgnoreCase),
                    $"Event Frame found at bottom of hierarchy from root [{rootEFName}]" +
                    $" was named [{lastEFInHeirarchy.Name}], expected [{ef4Name}].");
            }
            finally
            {
                Fixture.RemoveEventFrameIfExists(rootEFName, Output);
                Fixture.RemoveEventFrameIfExists(ef1Name, Output);
                Fixture.RemoveEventFrameIfExists(ef2Name, Output);
                Fixture.RemoveEventFrameIfExists(ef3Name, Output);
                Fixture.RemoveEventFrameIfExists(ef4Name, Output);
            }
        }

        /// <summary>
        /// Exercises AF Event Frame Attribute Value Setting operation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Event Frame with three attributes</para>
        /// <para>Set the Event Frame attributes with different types of values</para>
        /// <para>Confirm the Event Frame attributes have correct values</para>
        /// <para>Repeat the last two steps</para>
        /// <para>Delete the Event Frames</para>
        /// </remarks>
        [Fact]
        public void EventFrameAttributeSetValueTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            string ef1Name = $"OSIsoftTests_AF_EFAttrSrchTst - {DateTime.UtcNow.ToString(AFFixture.DateTimeFormat, CultureInfo.InvariantCulture)}_EF1";
            const string Attribute1Name = "OSIsoftTests_EFAttr#1";
            const string Attribute2Name = "OSIsoftTests_EFAttr#2";
            const string Attribute3Name = "OSIsoftTests_EFAttr#3";
            const double DoubleValue1 = 123.456;
            const int IntegerValue2 = 2;
            const string StringValue3 = "value";

            try
            {
                Output.WriteLine($"Create event frame [{ef1Name}] and add 3 attributes.");
                var newEF = new AFEventFrame(db, ef1Name);

                Output.WriteLine($"Create attribute [{Attribute1Name}] with a double value.");
                var attr1 = newEF.Attributes.Add(Attribute1Name);
                attr1.Type = typeof(double);
                attr1.SetValue(DoubleValue1, null);

                Output.WriteLine($"Create attribute [{Attribute2Name}] with an integer value.");
                var attr2 = newEF.Attributes.Add(Attribute2Name);
                attr2.Type = typeof(int);
                attr2.SetValue(IntegerValue2, null);

                Output.WriteLine($"Create attribute [{Attribute3Name}] with a string value.");
                var attr3 = newEF.Attributes.Add(Attribute3Name);
                attr3.Type = typeof(string);
                attr3.SetValue(StringValue3, null);
                db.CheckIn();

                Output.WriteLine($"Confirm event frame creation.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var readEventFrame = AFEventFrame.FindEventFrame(db.PISystem, newEF.ID);

                Output.WriteLine($"Check attribute 1 value.");
                var actualAttribute1Value = readEventFrame.Attributes[Attribute1Name].GetValue();
                var actualAttribute1Type = actualAttribute1Value.ValueType;
                Assert.True(actualAttribute1Type == typeof(double), $"Value read from Attribute [{Attribute1Name}] " +
                    $"did not have expected type [{actualAttribute1Type}], expected [{typeof(double)}].");
                Assert.True(actualAttribute1Value.ValueAsDouble() == DoubleValue1, $"Value for Attribute [{Attribute1Name}]" +
                    $" was [{actualAttribute1Value.ValueAsDouble()}], expected [{DoubleValue1}].");

                Output.WriteLine($"Check attribute 2 value.");
                var actualAttribute2Value = readEventFrame.Attributes[Attribute2Name].GetValue();
                var actualAttribute2Type = actualAttribute2Value.ValueType;
                Assert.True(actualAttribute2Type == typeof(int), $"Value read from Attribute [{Attribute2Name}]" +
                    $" did not have expected type [{actualAttribute2Type}], expected [{typeof(int)}].");
                Assert.True(actualAttribute2Value.ValueAsDouble() == IntegerValue2, $"Value for Attribute [{Attribute2Name}]" +
                    $" was [{actualAttribute2Value.ValueAsInt32()}], expected [{IntegerValue2}].");

                Output.WriteLine($"Check attribute 3 value.");
                var actualAttribute3Value = readEventFrame.Attributes[Attribute3Name].GetValue();
                var actualAttribute3Type = actualAttribute3Value.ValueType;
                Assert.True(actualAttribute3Type == typeof(string), $"Value read from Attribute [{Attribute3Name}]" +
                    $" did not have expected type [{actualAttribute3Type}], expected [{typeof(string)}].");
                Assert.True(actualAttribute3Value.Value.ToString() == StringValue3, $"Value for Attribute [{Attribute3Name}]" +
                    $" was [{actualAttribute3Value.Value.ToString()}], expected [{StringValue3}].");

                attr1 = readEventFrame.Attributes[Attribute1Name];
                attr2 = readEventFrame.Attributes[Attribute2Name];
                attr3 = readEventFrame.Attributes[Attribute3Name];

                Output.WriteLine("Set attribute values for the second time.");
                attr1.SetValue(DoubleValue1, null);
                attr2.SetValue(IntegerValue2, null);
                attr3.SetValue(StringValue3, null);
                db.CheckIn();

                db = Fixture.ReconnectToDB();
                readEventFrame = AFEventFrame.FindEventFrame(db.PISystem, newEF.ID);

                Output.WriteLine($"Recheck attribute 1 value.");
                var actualAttribute1Value2 = readEventFrame.Attributes[Attribute1Name].GetValue();
                var actualAttribute1Type2 = actualAttribute1Value2.ValueType;
                Assert.True(actualAttribute1Type2 == typeof(double), $"Value read from Attribute [{Attribute1Name}]" +
                    $" did not have expected type [{actualAttribute1Type2}], expected [{typeof(double)}].");
                Assert.True(actualAttribute1Value2.ValueAsDouble() == DoubleValue1, $"Value for Attribute [{Attribute1Name}]" +
                    $" was [{actualAttribute1Value2.ValueAsDouble()}], expected [{DoubleValue1}].");

                Output.WriteLine($"Recheck attribute 2 value.");
                var actualAttribute2Value2 = readEventFrame.Attributes[Attribute2Name].GetValue();
                var actualAttribute2Type2 = actualAttribute2Value2.ValueType;
                Assert.True(actualAttribute2Type2 == typeof(int), $"Value read from Attribute [{Attribute2Name}]" +
                    $" did not have expected type [{actualAttribute2Type2}], expected [{typeof(int)}].");
                Assert.True(actualAttribute2Value2.ValueAsDouble() == IntegerValue2, $"Value for Attribute [{Attribute2Name}]" +
                    $" was [{actualAttribute2Value.ValueAsInt32()}], expected [{IntegerValue2}].");

                Output.WriteLine($"Check attribute 3 value.");
                var actualAttribute3Value2 = readEventFrame.Attributes[Attribute3Name].GetValue();
                var actualAttribute3Type2 = actualAttribute3Value2.ValueType;
                Assert.True(actualAttribute3Type2 == typeof(string), $"Value read from Attribute [{Attribute3Name}]" +
                    $" did not have expected type [{actualAttribute3Type2}], expected [{typeof(string)}].");
                Assert.True(actualAttribute3Value2.Value.ToString() == StringValue3, $"Value for Attribute [{Attribute3Name}]" +
                    $" was [{actualAttribute3Value2.Value.ToString()}], expected [{StringValue3}].");
            }
            finally
            {
                Fixture.RemoveEventFrameIfExists(ef1Name, Output);
            }
        }

        /// <summary>
        /// Runs Event Frame search queries with query strings from ClassData.
        /// </summary>
        /// <param name="query">A query string for AFEventFrameSearch.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Run event frame search query</para>
        /// </remarks>
        [Theory]
        [InlineData("Name:*Tur00*")]
        [InlineData("ElementName:Tur00*")]
        [InlineData("start:>y")]
        public void EventFrameQueryTest(string query)
        {
            Output.WriteLine($"Attempt event frame search with query [{query}].");
            RunEFQuery(query);
        }

        /// <summary>
        /// Tests to see if the 2.10.7 patch was correctly applied
        /// </summary>
        /// <remarks>
        /// Checks the server rpc calls to verify the 2.10.7 patch was correctly applied
        /// </remarks>
        [AFFact(AFTestCondition.PATCH2107)]
        public void EventFrameAFSDK2018SP3Patch1Check()
        {
            AFEventFrame ef = null;
            try
            {
                AFRpcMetric[] rpcBefore = Fixture.AFDatabase.PISystem.GetClientRpcMetrics();
                ef = new AFEventFrame(Fixture.AFDatabase, "OSIsoftTests_Patch2107Applied_EF1");
                ef.CheckIn();
                ef.SetEndTime("*");
                ef.CheckIn();
                AFRpcMetric[] rpcAfter = Fixture.AFDatabase.PISystem.GetClientRpcMetrics();
                IList<AFRpcMetric> rpcDiff = AFRpcMetric.SubtractList(rpcAfter, rpcBefore);
                foreach (AFRpcMetric rpcMetric in rpcDiff)
                {
                    Assert.False(rpcMetric.Name.Equals("getcheckoutinfo", StringComparison.InvariantCultureIgnoreCase), "Error: GetCheckOutInfo rpc was still called after Checkin with 2018 SP3 Patch 1!");
                }
            }
            finally
            {
                if (ef != null)
                {
                    ef.Delete();
                    Fixture.AFDatabase.PISystem.CheckIn();
                }
            }
        }

        /// <summary>
        /// Performs an event frame search based on a query string
        /// </summary>
        /// <param name="query">Valid AF query</param>
        /// <param name="pageSize">Pagesize (Defaults to 1000)</param>
        private void RunEFQuery(string query, int pageSize = 1000)
        {
            AFDatabase db = Fixture.AFDatabase;

            using (var search = new AFEventFrameSearch(
                  database: db,
                  name: "EFQueryTest",
                  query: query))
            {
                int startIndex = 0;

                var coll = search.FindObjects(startIndex: startIndex, pageSize: pageSize);
                int totalEFExamined = 0;
                int valuesCapturedCount = 0;
                foreach (AFEventFrame ef in coll)
                {
                    totalEFExamined++;

                    if (ef.AreValuesCaptured)
                        valuesCapturedCount++;
                }

                Output.WriteLine($"Found {totalEFExamined} Event Frames in [{db.GetPath()}] for a query of [{query}].");
                Output.WriteLine($"{valuesCapturedCount} Event Frame's AreValuesCaptured are true.");
            }
        }

        /// <summary>
        /// Routine to create a complex event frame for use in testing.
        /// </summary>
        /// <param name="db">The AF Database where the event frame should be created.</param>
        /// <param name="efData">Data used to create the event frame.</param>
        /// <returns>Fully created event frame object is returned.</returns>
        /// <remarks>
        /// The Event Frame created in this routine can be verified using the FullEventFrameVerify() routine.
        /// </remarks>
        private AFEventFrame FullEventFrameCreate(AFDatabase db, EventFrameTestConfiguration efData)
        {
            var attrCat = db.AttributeCategories[efData.AttributeCategoryName];
            if (attrCat == null) attrCat = db.AttributeCategories.Add(efData.AttributeCategoryName);
            var elemCat = db.ElementCategories[efData.ElementCategoryName];
            if (elemCat == null) elemCat = db.ElementCategories.Add(efData.ElementCategoryName);

            var elem = db.Elements[efData.EventFrameElementName];
            if (elem == null) elem = db.Elements.Add(efData.EventFrameElementName);
            if (elem.IsDirty) elem.ApplyChanges();

            var newEventFrame = new AFEventFrame(db, efData.Name);

            var attr1 = newEventFrame.Attributes.Add(efData.Attribute1Name);
            attr1.Categories.Add(attrCat);
            attr1.Type = typeof(AFFile);
            var attr2 = newEventFrame.Attributes.Add(efData.Attribute2Name);
            attr2.Type = typeof(double);
            attr2.SetValue(efData.Attribute2Value, null);
            var attr3 = newEventFrame.Attributes.Add(efData.Attribute3Name);
            attr3.DataReferencePlugIn = db.PISystem.DataReferencePlugIns[efData.DataReferencePlugInName];
            attr3.ConfigString = efData.DataReferenceConfigString;

            newEventFrame.Categories.Add(elemCat);
            newEventFrame.EventFrames.Add(efData.ChildEventFrame);
            newEventFrame.ExtendedProperties.Add(efData.ExtPropKey, efData.ExtPropValue);
            newEventFrame.ReferencedElements.Add(elem);

            var ann = new AFAnnotation(newEventFrame)
            {
                Name = efData.AnnotationName,
                Value = efData.AnnotationValue,
            };
            ann.Save();

            return newEventFrame;
        }

        /// <summary>
        /// Verifies a complex event frame object.
        /// </summary>
        /// <param name="db">The AF Database that contains the event frame being verified.</param>
        /// <param name="evtfrmId">ID (GUID) of the event frame to be verified.</param>
        /// <param name="expData">Expected Data to check the event frame.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <remarks>
        /// This routine is used to verify event frames created using the FullEventFrameCreate() routine.
        /// </remarks>
        private void FullEventFrameVerify(AFDatabase db, Guid evtfrmId, EventFrameTestConfiguration expData, ITestOutputHelper output)
        {
            var eventFrameFound = AFEventFrame.FindEventFrame(db.PISystem, evtfrmId);
            Assert.True(eventFrameFound != null, $"Unable to find Event Frame [{expData.Name}] with ID [{evtfrmId}].");
            string actEFName = eventFrameFound.Name;
            Assert.True(actEFName.Equals(expData.Name, StringComparison.OrdinalIgnoreCase),
                $"Element Template found with ID [{evtfrmId}] had name [{actEFName}], expected [{expData.Name}].");

            Assert.True(db.AttributeCategories[expData.AttributeCategoryName] != null,
                $"Check Failed. Attribute Category [{expData.AttributeCategoryName}] not found.");
            Assert.True(db.ElementCategories[expData.ElementCategoryName] != null,
                $"Check Failed. Element Category [{expData.ElementCategoryName}] not found.");

            output.WriteLine("Check Event Frame Attributes.");
            int actualAttributeCount = eventFrameFound.Attributes.Count;
            Assert.True(actualAttributeCount == 3, $"Event Frame Attribute Count Failed. Actual {actualAttributeCount}, expected 3.");
            var attr1 = eventFrameFound.Attributes[expData.Attribute1Name];
            Assert.True(attr1 != null, $"Event Frame [{expData.Name}] did not have attribute [{expData.Attribute1Name}] as expected.");
            Assert.True(attr1.Categories[expData.AttributeCategoryName] != null,
                $"Attribute [{expData.Attribute1Name}] in Event Frame [{expData.Name}]" +
                $" did not have category [{expData.AttributeCategoryName}] as expected.");

            var attr2 = eventFrameFound.Attributes[expData.Attribute2Name];
            Assert.True(attr2 != null, $"Event Frame [{expData.Name}] did not have attribute [{expData.Attribute2Name}] as expected.");
            Assert.True(expData.Attribute2Value == attr2.GetValue().ValueAsDouble(),
                $"Event Frame [{expData.Name}] attribute [{expData.Attribute2Name}] data was" +
                $" [{attr2.GetValue().ValueAsDouble()}], expected [{expData.Attribute2Value}].");

            var attr3 = eventFrameFound.Attributes[expData.Attribute3Name];
            Assert.True(attr3 != null, $"Event Frame [{expData.Name}] did not have attribute [{expData.Attribute3Name}] as expected.");
            Assert.True(attr3.DataReferencePlugIn == db.PISystem.DataReferencePlugIns[expData.DataReferencePlugInName],
                $"Attribute [{expData.Attribute3Name}] in Event Frame [{expData.Name}]" +
                $" did not have data reference PlugIn [{expData.DataReferencePlugInName}] as expected.");
            Assert.True(attr3.ConfigString == expData.DataReferenceConfigString,
                $"Attribute [{expData.Attribute3Name}] in Event Frame [{expData.Name}] data reference ConfigString was" +
                $" [{attr3.ConfigString}], expected [{expData.DataReferenceConfigString}].");

            output.WriteLine("Check Event Frame Categories.");
            int actualEventFrameCategoriesCount = eventFrameFound.Categories.Count;
            const int ExpectedEventFrameCategoriesCount = 1;
            Assert.True(actualEventFrameCategoriesCount == ExpectedEventFrameCategoriesCount,
                $"Category Count in Event Frame [{expData.Name}] was " +
                $"{actualEventFrameCategoriesCount}, expected {ExpectedEventFrameCategoriesCount}.");
            Assert.True(eventFrameFound.Categories[expData.ElementCategoryName] != null,
                $"Category [{expData.ElementCategoryName}] not found in Event Frame [{expData.Name}] as expected.");

            output.WriteLine("Check Child Event Frames.");
            int actualEventFrameCount = eventFrameFound.EventFrames.Count;
            const int ExpectedEventFrameCount = 1;
            Assert.True(actualEventFrameCount == ExpectedEventFrameCount,
                $"Count in Event Frame [{expData.Name}] was {actualEventFrameCount}, expected {ExpectedEventFrameCount}.");
            Assert.True(eventFrameFound.EventFrames[expData.ChildEventFrame] != null,
                $"Child Event Frame [{expData.ChildEventFrame}] not found in Event Frame [{expData.Name}] as expected.");

            output.WriteLine("Check Extended properties.");
            int actualExtPropertiesCount = eventFrameFound.ExtendedProperties.Count;
            const int ExpectedExtPropertiesCount = 1;
            Assert.True(actualExtPropertiesCount == ExpectedExtPropertiesCount,
                $"ExtendedProperties Count in Event Frame [{expData.Name}] was {actualExtPropertiesCount}, expected {ExpectedExtPropertiesCount}.");
            string actualExtPropValue = eventFrameFound.ExtendedProperties[expData.ExtPropKey].ToString();
            Assert.True(actualExtPropValue.Equals(expData.ExtPropValue, StringComparison.OrdinalIgnoreCase),
                $"ExtendedProperty Key [{expData.ExtPropKey}] in Event Frame [{expData.Name}]" +
                $" had Value [{actualExtPropValue}], expected [{expData.ExtPropValue}].");

            output.WriteLine("Check Referenced Element.");
            int actualRefdElementsCount = eventFrameFound.ReferencedElements.Count;
            const int ExpectedRefdElementsCount = 1;
            Assert.True(actualRefdElementsCount == ExpectedRefdElementsCount,
                $"Referenced Element Count in Event Frame [{expData.Name}] was {actualRefdElementsCount}, expected {ExpectedRefdElementsCount}.");
            Assert.True(actualExtPropValue.Equals(expData.ExtPropValue, StringComparison.OrdinalIgnoreCase),
                $"Referenced Element [{expData.EventFrameElementName}] not found in Event Frame [{expData.Name}] as expected.");

            output.WriteLine("Check Event Frame Annotations.");
            var annotations = eventFrameFound.GetAnnotations();
            int actualAnnotationsCount = annotations.Count;
            const int ExpectedAnnotationsCount = 1;
            Assert.True(actualAnnotationsCount == ExpectedAnnotationsCount,
                $"Annotations Count in Event Frame [{expData.Name}] was {actualAnnotationsCount}, expected {ExpectedAnnotationsCount}.");
            Assert.True(annotations[0].Name.Equals(expData.AnnotationName, StringComparison.OrdinalIgnoreCase),
                $"Annotations[0] Name in Event Frame [{expData.Name}] was [{annotations[0].Name}], expected [{expData.AnnotationName}].");
            Assert.True(annotations[0].Value.ToString().Equals(expData.AnnotationValue, StringComparison.OrdinalIgnoreCase),
                $"Annotations[0] Value in Event Frame [{expData.Name}] was [{annotations[0].Value.ToString()}], expected [{expData.AnnotationValue}].");
        }
    }
}
