using System;
using System.Globalization;
using System.Linq;
using OSIsoft.AF;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.EventFrame;
using OSIsoft.AF.Modeling;
using OSIsoft.AF.Search;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests the ability to create, read, update, and delete asset meta-data
    /// in the AF Server.
    /// </summary>
    [Collection("AF collection")]
    public class AFTests : IClassFixture<AFFixture>
    {
        internal const string KeySetting = "AFServer";
        internal const TypeCode KeySettingTypeCode = TypeCode.String;

        /// <summary>
        /// Constructor for AFTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage the AF connection and specific helper functions.</param>
        public AFTests(ITestOutputHelper output, AFFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private AFFixture Fixture { get; }

        private ITestOutputHelper Output { get; }
 
        /// <summary>
        /// Runs element search queries from Inline query strings.
        /// </summary>
        /// <param name="query">A query string for AFElementSearch.</param>
        /// <param name="expectedCount">The expected number of elements.</param>
        /// <remarks>
        /// Test Steps:
        /// <para>Execute AFElements Search Query using user data</para>
        /// <para>Verify correct element count using user data</para>
        /// </remarks>
        [Theory]
        [InlineData("Name:=*", AFFixture.TotalElementCount)]
        [InlineData("Name:=Region*", AFFixture.TotalRegionCount)]
        [InlineData("Name:=\"Wind Farm*\"", AFFixture.TotalWindFarmCount)]
        [InlineData("Name:=TUR*", AFFixture.TotalTurbineCount)]
        [InlineData("Name:=TUR00000", 1)]
        [InlineData("Template:=Region", AFFixture.TotalRegionCount)]
        [InlineData("Template:=Farm", AFFixture.TotalWindFarmCount)]
        [InlineData("Template:=Turbine", AFFixture.TotalTurbineCount)]
        public void ElementQueryTest(string query, int expectedCount)
        {
            using (var piFixture = new PIFixture())
            {
                Utils.CheckTimeDrift(piFixture, Output);
            }

            Output.WriteLine($"Execute element search query [{query}].");
            using (var search = new AFElementSearch(
                database: Fixture.AFDatabase,
                name: "elmntSearch",
                query: query))
            {
                int actualCount = search.GetTotalCount();
                Output.WriteLine($"There are {actualCount} elements matching [{query}].");
                Assert.True(actualCount == expectedCount, $"Query [{query}] resulted in {actualCount} elements, expected {expectedCount}.");
            }
        }

        /// <summary>
        /// Exercises AF Element attribute hierarchy.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with layered attributes</para>
        /// <para>Confirm the Attributes can be reached</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Fact]
        public void AttributeHierarchyTest()
        {
            const string RootElementName = "OSIsoftTests_AF_AttributeHierarchyTest_RootElement";
            const string AttributeName1 = "OSIsoftTests_Attribute1";
            const string AttributeName2 = "OSIsoftTests_Attribute2";
            const string AttributeName3 = "OSIsoftTests_Attribute3";
            const string AttributeName4 = "OSIsoftTests_Attribute4";

            AFDatabase db = Fixture.AFDatabase;

            try
            {
                // Precheck to make sure elements names do not already exist
                Fixture.RemoveElementIfExists(RootElementName, Output);

                Output.WriteLine($"Create root element [{RootElementName}] with hierarchy 4 attributes deep.");
                var rootElement = db.Elements.Add(RootElementName);
                var attribute1 = rootElement.Attributes.Add(AttributeName1);
                var attribute2 = attribute1.Attributes.Add(AttributeName2);
                var attribute3 = attribute2.Attributes.Add(AttributeName3);
                var attribute4 = attribute3.Attributes.Add(AttributeName4);
                db.CheckIn();

                Output.WriteLine("Check that element created hierarchy correctly.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var attributeCheck = db.Elements[RootElementName].Attributes[AttributeName1].Attributes[AttributeName2].Attributes[AttributeName3].Attributes[AttributeName4];
                Assert.True(attributeCheck.Name.Equals(attribute4.Name, StringComparison.OrdinalIgnoreCase), $"Unable to trace hierarchy from rootElement [{RootElementName}].");
            }
            finally
            {
                Fixture.RemoveElementIfExists(RootElementName, Output);
            }
        }

        /// <summary>
        /// Exercises AF Attribute Category Object by doing a Create, Read, Update and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Attribute Category</para>
        /// <para>Confirm Category was properly created</para>
        /// <para>Rename the Category (and confirm)</para>
        /// <para>Delete the Category (And confirm)</para>
        /// </remarks>
        [Fact]
        public void AttributeCategoryTest()
        {
            const string CategoryName = "OSIsoftTests_AF_AttributeCategoryTest_Cat#0";
            const string CategoryRename = "OSIsoftTests_AF_AttributeCategoryTest_Cat#1";

            AFDatabase db = Fixture.AFDatabase;

            // Precheck to make sure elements names do not already exist
            Fixture.RemoveAttributeCategoryIfExists(CategoryName, Output);
            Fixture.RemoveAttributeCategoryIfExists(CategoryRename, Output);

            try
            {
                Output.WriteLine($"Create category [{CategoryName}].");
                var newCategory = db.AttributeCategories.Add(CategoryName);
                db.CheckIn();

                Output.WriteLine("Confirm category created and found.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var findCategory = AFCategory.FindCategory(db.PISystem, newCategory.ID);
                Assert.True(findCategory != null, $"Unable to find newly created category [{CategoryName}] with ID [{newCategory.ID}].");

                Output.WriteLine($"Rename category to [{CategoryRename}].");
                findCategory.Name = CategoryRename;
                db.CheckIn();

                Output.WriteLine($"Verify category [{CategoryRename}] found on reread.");
                db = Fixture.ReconnectToDB();
                var renamedCategory = db.AttributeCategories[CategoryRename];
                Assert.True(renamedCategory != null, $"Unable to find renamed category [{CategoryRename}].");
                var oldNameCategory = db.AttributeCategories[CategoryName];
                Assert.True(oldNameCategory == null, $"Found category named [{CategoryName}] but it should have been renamed to [{CategoryRename}].");

                Output.WriteLine($"Delete category [{CategoryRename}].");
                db.AttributeCategories.Remove(CategoryRename);
                db.CheckIn();

                Output.WriteLine($"Confirm category deleted.");
                db = Fixture.ReconnectToDB();
                var deletedCategory = AFCategory.FindCategory(db.PISystem, renamedCategory.ID);
                Assert.True(deletedCategory == null, $"Category [{CategoryRename}] was not deleted as expected.");
            }
            finally
            {
                Fixture.RemoveAttributeCategoryIfExists(CategoryName, Output);
                Fixture.RemoveAttributeCategoryIfExists(CategoryRename, Output);
            }
        }

        /// <summary>
        /// Exercises AF Element Object by doing a Create, Read, Update and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para> Create an Element</para>
        /// <para>Confirm Element was properly created</para>
        /// <para>Rename the Element (and confirm)</para>
        /// <para>Delete the Element (And confirm)</para>
        /// </remarks>
        [Fact]
        public void ElementsTest()
        {
            // Create set of data that defines the element to be created
            const string ElementName = "OSIsoftTests_AF_ElementsTest_Elem#1";
            const string ElementRename = "OSIsoftTests_AF_ElementsTest_NewName";

            AFDatabase db = Fixture.AFDatabase;

            // Precheck to make sure elements names do not already exist
            Fixture.RemoveElementIfExists(ElementName, Output);
            Fixture.RemoveElementIfExists(ElementRename, Output);

            var testData = new ElementTestConfiguration(ElementName);
            Output.WriteLine($"Create element [{ElementName}].");
            try
            {
                var elementCreated = FullElementCreate(db, testData);
                db.CheckIn();

                Output.WriteLine("Confirm element created and found.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var foundElement = AFElement.FindElement(db.PISystem, elementCreated.ID);
                FullElementVerify(db, foundElement.ID, testData, Output);

                Output.WriteLine($"Rename element to [{ElementRename}].");
                foundElement.Name = ElementRename;
                db.CheckIn();
                testData.Name = ElementRename;

                Output.WriteLine($"Verify element [{ElementRename}] found on reread.");
                db = Fixture.ReconnectToDB();
                foundElement = db.Elements[ElementRename];
                FullElementVerify(db, foundElement.ID, testData, Output);
                var oldNamedElement = db.Elements[ElementName];
                Assert.True(oldNamedElement == null, $"Found element named [{ElementName}] but it should have been renamed to [{ElementRename}].");

                Output.WriteLine($"Delete Element [{ElementRename}].");
                foundElement.Delete();
                db.CheckIn();

                Output.WriteLine($"Confirm deletion of element.");
                db = Fixture.ReconnectToDB();
                var deletedElementSearch = AFElement.FindElement(db.PISystem, elementCreated.ID);
                Assert.True(deletedElementSearch == null, $"Element [{ElementRename}] was not deleted as expected.");
            }
            finally
            {
                Fixture.RemoveElementIfExists(ElementName, Output);
                Fixture.RemoveElementIfExists(ElementRename, Output);
            }
        }

        /// <summary>
        /// Exercises AF Element Search operation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create several Elements</para>
        /// <para>Confirm that a search will return the expected Elements</para>
        /// <para>Delete the Elements</para>
        /// </remarks>
        [Fact]
        public void ElementSearchTest()
        {
            const string ElementSearchBaseName = "OSIsoftTests_ElementSearch";

            AFDatabase db = Fixture.AFDatabase;
            string elementName1 = $"{ElementSearchBaseName}Obj1";
            string elementName2 = $"{ElementSearchBaseName}Obj2";
            string elementName3 = $"{ElementSearchBaseName}LASTObj3";
            string testSearchString = $"{ElementSearchBaseName}Obj*";

            try
            {
                // Precheck to make sure elements names do not already exist
                Fixture.RemoveElementIfExists(elementName1, Output);
                Fixture.RemoveElementIfExists(elementName2, Output);
                Fixture.RemoveElementIfExists(elementName3, Output);

                Output.WriteLine("Create elements to for searching.");
                db.Elements.Add(elementName1);
                db.Elements.Add(elementName2);
                db.Elements.Add(elementName3);
                db.CheckIn();

                Output.WriteLine($"Execute search for elements using search string [{testSearchString}].");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                int expectedCount = 2;
                using (var results = new AFElementSearch(db, string.Empty, testSearchString))
                {
                    int actualFoundCount = results.GetTotalCount();
                    Assert.True(actualFoundCount == expectedCount,
                        $"Search string [{testSearchString}] found {actualFoundCount} Elements, expected {expectedCount}.");

                    int actualRunningCount = 0;
                    foreach (AFElement at in results.FindObjects())
                    {
                        actualRunningCount++;
                    }

                    Assert.True(actualRunningCount == expectedCount, $"Found {actualRunningCount} Elements, expected {expectedCount}.");
                }
            }
            finally
            {
                Fixture.RemoveElementIfExists(elementName1, Output);
                Fixture.RemoveElementIfExists(elementName2, Output);
                Fixture.RemoveElementIfExists(elementName3, Output);
            }
        }

        /// <summary>
        /// Exercises AF Element Attribute Search operation.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element with several Attributes</para>
        /// <para>Confirm that a search will return the expected Attributes</para>
        /// <para>Delete the Element</para>
        /// </remarks>
        [Fact]
        public void ElementAttributeSearchTest()
        {
            const string ElementName = "OSIsoftTests_AF_ElementAttributesSearchTest_Elem#1";
            const string AttributeBaseName = "OSIsoftTests_AF_ElementAttributesSearchTest_Attrib";

            AFDatabase db = Fixture.AFDatabase;
            string attribute1Name = $"{AttributeBaseName}#1";
            string attribute2Name = $"{AttributeBaseName}#2";
            string attribute3Name = $"{AttributeBaseName}LastAttrib";

            // Precheck to make sure elements names do not already exist
            Fixture.RemoveElementIfExists(ElementName, Output);

            try
            {
                Output.WriteLine($"Create element named [{ElementName}] and add attributes.");
                var element1 = db.Elements.Add(ElementName);
                element1.Attributes.Add(attribute1Name);
                element1.Attributes.Add(attribute2Name);
                element1.Attributes.Add(attribute3Name);
                db.CheckIn();

                string searchString = @"Element:{ Name:'" + ElementName + "' } Name:'" + AttributeBaseName + "#*'";
                Output.WriteLine($"Search in element [{searchString}].");
                db = Fixture.ReconnectToDB();
                using (var results = new AFAttributeSearch(db, "a search", searchString))
                {
                    Output.WriteLine($"Review attributes found in search.");
                    int actualRunningCount = 0;
                    foreach (AFAttribute attribs in results.FindObjects())
                    {
                        actualRunningCount++;
                    }

                    int actualAttributesFound = results.GetTotalCount();
                    int expectedCount = 2;
                    Assert.True(actualAttributesFound == expectedCount,
                        $"Attribute search in Element [{ElementName}] found " +
                        $"{actualAttributesFound}, expected {expectedCount}.");
                    Assert.True(actualRunningCount == expectedCount,
                        $"Attribute search in Element [{ElementName}] found " +
                        $"{actualRunningCount} attributes, expected {expectedCount}.");
                }
            }
            finally
            {
                Fixture.RemoveElementIfExists(ElementName, Output);
            }
        }

        /// <summary>
        /// Exercises AF Element Template Object by doing a Create, Read, Update and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Element Template</para>
        /// <para>Confirm Element Template was properly created</para>
        /// <para>Rename the Element Template (and confirm)</para>
        /// <para>Delete the Element Template (And confirm)</para>
        /// </remarks>
        [Fact]
        public void ElementTemplateTest()
        {
            const string ElementTemplateName = "OSIsoftTests_ElementTemplateTest_ElemTemp#1";
            const string ElementTemplateRename = "OSIsoftTests_ElementTemplateTest_ElemTempRename";

            AFDatabase db = Fixture.AFDatabase;

            // Precheck to make sure element templates do not already exist
            Fixture.RemoveElementTemplateIfExists(ElementTemplateName, Output);
            Fixture.RemoveElementTemplateIfExists(ElementTemplateRename, Output);

            var testData = new ElementTemplateTestConfiguration(ElementTemplateName);

            try
            {
                Output.WriteLine($"Create Element Template [{ElementTemplateName}].");
                var elementTemplateCreated = FullElementTemplateCreate(db, testData);
                db.CheckIn();

                Output.WriteLine($"Confirm Element Template creation.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var foundElementTemplate = AFElementTemplate.FindElementTemplate(db.PISystem, elementTemplateCreated.ID);
                FullElementTemplateVerify(db, elementTemplateCreated.ID, testData);

                Output.WriteLine($"Rename Element Template to [{ElementTemplateRename}].");
                foundElementTemplate.Name = ElementTemplateRename;
                testData.Name = ElementTemplateRename;
                db.CheckIn();

                Output.WriteLine($"Confirm Element Template renamed.");
                db = Fixture.ReconnectToDB();
                FullElementTemplateVerify(db, elementTemplateCreated.ID, testData);

                Output.WriteLine($"Delete Element Template.");
                var rereadElemTemplate = AFElementTemplate.FindElementTemplate(db.PISystem, elementTemplateCreated.ID);
                db.ElementTemplates.Remove(rereadElemTemplate);
                db.CheckIn();

                Output.WriteLine($"Confirm Element Template deleted.");
                db = Fixture.ReconnectToDB();
                var postDeleteElemTemplate = AFElementTemplate.FindElementTemplate(db.PISystem, elementTemplateCreated.ID);
                Assert.True(postDeleteElemTemplate == null, $"Element [{ElementTemplateRename}] was not deleted as expected.");
            }
            finally
            {
                Fixture.RemoveElementTemplateIfExists(ElementTemplateName, Output);
                Fixture.RemoveElementTemplateIfExists(ElementTemplateRename, Output);
            }
        }

        /// <summary>
        /// Exercises AF Elements in a hierarchy.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create several Elements and layer them in a hierarchy</para>
        /// <para>Confirm the Element at lowest level can be reached</para>
        /// <para>Delete the Elements</para>
        /// </remarks>
        [Fact]
        public void ElementHierarchyTest()
        {
            const string RootElementName = "OSIsoftTests_AF_ElemHierarchyTest_RootElem";
            const string Element1Name = "OSIsoftTests_AF_ElementHierarchyTest_e1";
            const string Element2Name = "OSIsoftTests_AF_ElementHierarchyTest_e2";
            const string Element3Name = "OSIsoftTests_AF_ElementHierarchyTest_e3";
            const string Element4Name = "OSIsoftTests_AF_ElementHierarchyTest_e4";

            AFDatabase db = Fixture.AFDatabase;

            try
            {
                // Precheck to make sure elements names do not already exist
                Fixture.RemoveElementIfExists(RootElementName, Output);
                Fixture.RemoveElementIfExists(Element1Name, Output);
                Fixture.RemoveElementIfExists(Element2Name, Output);
                Fixture.RemoveElementIfExists(Element3Name, Output);
                Fixture.RemoveElementIfExists(Element4Name, Output);

                Output.WriteLine($"Create root element [{RootElementName}] with hierarchy 4 elements deep.");
                var rootElement = db.Elements.Add(RootElementName);
                var element1 = new AFElement(Element1Name);
                var element2 = new AFElement(Element2Name);
                var element3 = new AFElement(Element3Name);
                var element4 = new AFElement(Element4Name);

                rootElement.Elements.Add(element1);
                element1.Elements.Add(element2);
                element2.Elements.Add(element3);
                element3.Elements.Add(element4);
                db.CheckIn();

                Output.WriteLine("Check that element hierarchy created correctly.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var lastElementInHeirarchy =
                    db.Elements[RootElementName].Elements[Element1Name].Elements[Element2Name].Elements[Element3Name].Elements[Element4Name];
                Assert.True(lastElementInHeirarchy != null, $"Search down hierarchy from root did not find element.");
                Assert.True(lastElementInHeirarchy.Name.Equals(Element4Name, StringComparison.OrdinalIgnoreCase),
                    $"Element found at bottom of hierarchy from root [{RootElementName}]" +
                    $" was named [{lastElementInHeirarchy.Name}], expected [{Element4Name}].");
            }
            finally
            {
                Fixture.RemoveElementIfExists(RootElementName, Output);
                Fixture.RemoveElementIfExists(Element1Name, Output);
                Fixture.RemoveElementIfExists(Element2Name, Output);
                Fixture.RemoveElementIfExists(Element3Name, Output);
                Fixture.RemoveElementIfExists(Element4Name, Output);
            }
        }

        /// <summary>
        /// Exercises AF Enumeration Set Object by performing Create, Read and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an Enumeration Set</para>
        /// <para>Confirm Enumeration Set was properly created</para>
        /// <para>Delete the Enumeration Set (And confirm)</para>
        /// </remarks>
        [Fact]
        public void EnumerationSetTest()
        {
            const string EnumerationSetName = "OSIsoftTests_InitEnumSet#1A";
            const string Enum1InSet = "Enum1";
            const string Enum2InSet = "Enum2";

            AFDatabase db = Fixture.AFDatabase;

            try
            {
                // Prior to creating enumeration set - make sure it does not already exist
                Output.WriteLine($"Check that EnumerationSet named [{EnumerationSetName}] does not exist.");
                Fixture.RemoveEnumerationSetIfExists(EnumerationSetName, Output);

                Output.WriteLine($"Create EnumerationSet named [{EnumerationSetName}].");
                var initEnumSet = db.EnumerationSets.Add(EnumerationSetName);
                initEnumSet.Add(Enum1InSet, 1);
                initEnumSet.Add(Enum2InSet, 2);
                db.CheckIn();

                Output.WriteLine($"Reread EnumerationSet named [{EnumerationSetName}] and check contents.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                AFEnumerationSet readEnumSet = db.EnumerationSets[EnumerationSetName];

                var newlyCreatedEnumSet = AFEnumerationSet.FindEnumerationSet(db.PISystem, readEnumSet.ID);
                Assert.True(newlyCreatedEnumSet != null,
                    $"Did not find the enumeration set [{EnumerationSetName}] with ID [{readEnumSet.ID}] on PI System [{db.PISystem.Name}].");
                Assert.True(newlyCreatedEnumSet.Count == 2,
                    $"Expected 2 enumerations in the enumeration set [{EnumerationSetName}], but {newlyCreatedEnumSet.Count} were found.");
                Assert.True(newlyCreatedEnumSet[Enum1InSet] != null,
                    $"Did not find the enumeration [{Enum1InSet}] in the enumeration set [{EnumerationSetName}].");
                Assert.True(newlyCreatedEnumSet[Enum2InSet] != null,
                    $"Did not find the enumeration [{Enum2InSet}] in the enumeration set [{EnumerationSetName}].");

                Output.WriteLine($"Remove EnumerationSet named [{EnumerationSetName}].");
                db.EnumerationSets.Remove(readEnumSet.Name);
                db.CheckIn();

                Output.WriteLine($"Confirm EnumerationSet removed.");
                db = Fixture.ReconnectToDB();
                var postDeleteEnumSet = AFEnumerationSet.FindEnumerationSet(db.PISystem, readEnumSet.ID);
                Assert.True(postDeleteEnumSet == null, $"Found the enumeration set [{EnumerationSetName}] after deletion.");
            }
            finally
            {
                Fixture.RemoveEnumerationSetIfExists(EnumerationSetName, Output);
            }
        }

        /// <summary>
        /// Exercises AF Table Object by doing a Create, Read, Update and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a Table</para>
        /// <para>Confirm Table was properly created</para>
        /// <para>Rename the Table (And confirm)</para>
        /// <para>Delete the Table (And confirm)</para>
        /// </remarks>
        [Fact]
        public void TableTest()
        {
            const string TableName = "OSIsoftTests_AF_TableTest_Table1";
            const string TableRename = "OSIsoftTests_AF_TableTest_Table2";
            const string TableCategoryName = "OSIsoftTests_AF_TableTest_TblCat1";
            const string TableExtPropKey = "OSIsoftTests_ExtPropKey";
            const string TableExtPropValue = "OSIsoftTests_ExtPropKey";

            AFDatabase db = Fixture.AFDatabase;
            var category = db.TableCategories[TableCategoryName];
            if (category == null) category = db.TableCategories.Add(TableCategoryName);
            db.CheckIn();

            Fixture.RemoveTableIfExists(TableName, Output);
            Fixture.RemoveTableIfExists(TableRename, Output);

            try
            {
                Output.WriteLine($"Create Table named [{TableName}].");
                var newTable = db.Tables.Add(TableName);
                newTable.Categories.Add(category);
                newTable.SetExtendedProperty(string.Empty, TableExtPropKey, TableExtPropValue);
                db.CheckIn();

                Output.WriteLine("Confirm Table created and found.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var foundTable = AFTable.FindTable(db.PISystem, newTable.ID);
                Assert.True(foundTable != null, $"Unable to find new Table [{TableName}] with ID [{newTable.ID}].");

                // Verify found proper Table Object
                Output.WriteLine("Confirm Table properties are correct.");
                int actualTableCategoryCount = foundTable.Categories.Count();
                const int ExpectedTableCategoryCount = 1;
                Assert.True(actualTableCategoryCount == ExpectedTableCategoryCount,
                    $"Table [{TableName}] had Category count {actualTableCategoryCount}, expected {ExpectedTableCategoryCount}.");
                var foundCategory = foundTable.Categories[TableCategoryName];
                Assert.True(foundCategory != null, $"Unable to find new Category [{TableCategoryName}] in Table [{TableName}].");

                string actualExtPropValue = foundTable.GetExtendedProperty(string.Empty, TableExtPropKey).ToString();
                Assert.True(foundCategory != null,
                    $"ExtendedProperty for Key [{TableExtPropKey}] in Table [{TableName}] was [{actualExtPropValue}], expected [{TableExtPropValue}].");

                Output.WriteLine($"Rename Table to [{TableRename}].");
                foundTable.Name = TableRename;
                db.CheckIn();

                Output.WriteLine($"Confirm Table Renamed.");
                db = Fixture.ReconnectToDB();
                var renamedTable = db.Tables[TableRename];
                Assert.True(renamedTable != null, $"Did not find table that was renamed to [{TableRename}].");
                var oldNameTable = db.Tables[TableName];
                Assert.True(oldNameTable == null,
                    $"Table with old name [{TableName}] still found after attempted rename to [{TableRename}].");

                Output.WriteLine($"Remove Table [{TableRename}].");
                db.Tables.Remove(TableRename);
                db.CheckIn();

                Output.WriteLine($"Confirm Table Deleted.");
                db = Fixture.ReconnectToDB();
                var postDeleteTable = db.Tables[TableRename];
                Assert.True(postDeleteTable == null, $"Found table [{TableRename}]. Expected it to be deleted.");
            }
            finally
            {
                Fixture.RemoveTableIfExists(TableName, Output);
                Fixture.RemoveTableIfExists(TableRename, Output);
            }
        }

        /// <summary>
        /// Exercises AF Transfer Object by performing Create, Read, Update and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a Transfer</para>
        /// <para>Confirm Transfer was properly created</para>
        /// <para>Rename the Transfer (And confirm)</para>
        /// <para>Delete the Transfer (And confirm)</para>
        /// </remarks>
        [Fact]
        public void TransferTest()
        {
            AFDatabase db = Fixture.AFDatabase;

            // Create set of data that defines the element to be created
            string baseTransferNameText = $"OSIsoftTests_AF_TransferTst - {DateTime.UtcNow.ToString(AFFixture.DateTimeFormat, CultureInfo.InvariantCulture)}_";
            string transferName = $"{baseTransferNameText}1";
            string transferRename = $"{baseTransferNameText}Rename";
            var testData = new TransferTestConfiguration(transferName);

            try
            {
                Output.WriteLine($"Create Transfer named [{transferName}].");
                var newTransfer = FullTransferCreate(db, testData);
                db.CheckIn();

                Output.WriteLine($"Check Transfer [{transferName}] properties.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                newTransfer = AFTransfer.FindTransfer(db.PISystem, newTransfer.ID);
                FullTransferVerify(db, newTransfer.ID, testData, Output);

                Output.WriteLine($"Rename Transfer to [{transferRename}].");
                newTransfer.Name = transferRename;
                db.CheckIn();

                testData.Name = transferRename;

                Output.WriteLine($"Check Transfer [{transferRename}] properties.");
                db = Fixture.ReconnectToDB();
                var rereadTransfer = AFTransfer.FindTransfer(db.PISystem, newTransfer.ID);
                FullTransferVerify(db, newTransfer.ID, testData, Output);

                Output.WriteLine($"Delete Transfer named [{transferRename}].");
                rereadTransfer.Delete();
                db.CheckIn();

                Output.WriteLine($"Confirm deletion of Transfer named [{transferRename}].");
                db = Fixture.ReconnectToDB();
                var postDeleteTransfer = AFTransfer.FindTransfer(db.PISystem, newTransfer.ID);
                Assert.True(postDeleteTransfer == null, $"Found Transfer that was expected to be deleted.");
            }
            finally
            {
                Fixture.RemoveTransferIfExists(transferName, Output);
                Fixture.RemoveTransferIfExists(transferRename, Output);
            }
        }

        /// <summary>
        /// Exercises AF Unit Of Measure Object by performing Create, Read and Delete operations.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a Unit Of Measure</para>
        /// <para>Confirm Unit Of Measure was properly created</para>
        /// <para>Delete the Unit Of Measure (And confirm)</para>
        /// </remarks>
        [Fact]
        public void UnitOfMeasureTest()
        {
            const string UOMClassName = "OSIsoftTests_UnitOfMeasureTest_UOM";
            const string UOMUnitName = "OSIsoftTests_Unit";
            const string UOMAbbreviation = "OSIsoftTests_Abbr";

            AFDatabase db = Fixture.AFDatabase;

            try
            {
                // Precheck to make sure UOM Class does not already exist
                Fixture.RemoveUOMClassIfExists(UOMClassName, Output);

                Output.WriteLine($"Create UOM Class [{UOMClassName}] and UOM [{UOMUnitName}].");
                var newUOMClass = db.PISystem.UOMDatabase.UOMClasses.Add(UOMClassName, UOMUnitName, UOMAbbreviation);
                var newUOM = db.PISystem.UOMDatabase.UOMs[UOMUnitName];
                db.PISystem.CheckIn();

                Output.WriteLine("Confirm UOM Class created.");
                db = Fixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                var uomClassFound = db.PISystem.UOMDatabase.UOMClasses[UOMClassName];
                Assert.True(uomClassFound != null, $"Unable to find new UOM Class [{UOMClassName}].");

                var uomObjFind = db.PISystem.UOMDatabase.UOMs[UOMUnitName];
                Assert.True(uomObjFind != null, $"Unable to find new UOM [{UOMUnitName}].");

                Output.WriteLine($"Delete UOM Class [{UOMClassName}].");
                db.PISystem.UOMDatabase.UOMClasses.Remove(newUOMClass);
                db.PISystem.CheckIn();

                Output.WriteLine("Confirm UOM Class deleted.");
                db = Fixture.ReconnectToDB();
                var postDeleteUOM = db.PISystem.UOMDatabase.UOMs[UOMUnitName];
                Assert.True(postDeleteUOM == null, $"Found UOM [{UOMUnitName}] after deletion.");
                var postDeleteUOMClass = db.PISystem.UOMDatabase.UOMClasses[UOMClassName];
                Assert.True(postDeleteUOMClass == null, $"Found UOM Class[{UOMClassName}] after deletion.");
            }
            finally
            {
                Fixture.RemoveUOMClassIfExists(UOMClassName, Output);
            }
        }

        /// <summary>
        /// Tests to see if the current patch is applied
        /// </summary>
        /// <remarks>
        /// Skips if the current patch is not applied with a message telling the user to upgrade
        /// </remarks>
        [AFFact(AFTestCondition.CURRENTPATCH)]
        public void HaveLatestPatch()
        {  
        }

        /// <summary>
        /// Routine to create an element with attributes, a port, categories and annotation.
        /// </summary>
        /// <param name="db">The AF Database where the element should be created.</param>
        /// <param name="testData">Data used to the create element.</param>
        /// <returns>Fully created element object is returned.</returns>
        /// <remarks>
        /// The Element created in this routine can be verified using the FullElementVerify() routine.
        /// </remarks>
        private AFElement FullElementCreate(AFDatabase db, ElementTestConfiguration testData)
        {
            // Add attribute category if it does not exist
            var attrCat = db.AttributeCategories[testData.AttributeCategoryName];
            if (attrCat == null) attrCat = db.AttributeCategories.Add(testData.AttributeCategoryName);

            // Add element category if it does not exist
            var elemCat = db.ElementCategories[testData.ElementCategoryName];
            if (elemCat == null) elemCat = db.ElementCategories.Add(testData.ElementCategoryName);

            var newElementObject = db.Elements.Add(testData.Name);
            var attr1 = newElementObject.Attributes.Add(testData.Attribute1Name);
            attr1.Type = typeof(AFFile);
            attr1.Categories.Add(attrCat);
            var attr2 = newElementObject.Attributes.Add(testData.Attribute2Name);
            attr2.Type = typeof(double);
            attr2.SetValue(testData.Attribute2Value, null);
            var attr3 = newElementObject.Attributes.Add(testData.Attribute3Name);
            attr3.DataReferencePlugIn = db.PISystem.DataReferencePlugIns[testData.DataReferencePlugInName];
            attr3.ConfigString = testData.DataReferenceConfigString;

            newElementObject.Categories.Add(elemCat);
            newElementObject.Elements.Add(testData.ChildElementName);
            newElementObject.ExtendedProperties.Add(testData.ExtPropKey, testData.ExtPropValue);

            var port = newElementObject.Ports.Add(testData.PortName);
            port.AllowedElementCategories.Add(elemCat);

            var annotation = new AFAnnotation(newElementObject)
            {
                Name = testData.AnnotationName,
                Value = testData.AnnotationValue,
            };
            annotation.Save();

            return newElementObject;
        }

        /// <summary>
        /// Verifies a complex Element.
        /// </summary>
        /// <param name="db">The AF Database that contains the element being verified.</param>
        /// <param name="elementID">ID (GUID) of the element to be verified.</param>
        /// <param name="expData">Expected Data used to check element.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <remarks>
        /// This routine is used to verify Elements created using the FullElementCreate() routine.
        /// </remarks>
        private void FullElementVerify(AFDatabase db, Guid elementID, ElementTestConfiguration expData, ITestOutputHelper output)
        {
            var elementFound = AFElement.FindElement(db.PISystem, elementID);
            Assert.True(elementFound != null, $"Unable to find element [{expData.Name}] with ID [{elementID}].");
            string actualElementName = elementFound.Name;
            Assert.True(actualElementName.Equals(expData.Name, StringComparison.OrdinalIgnoreCase),
                $"Name on element was [{actualElementName}], expected [{expData.Name}].");
            Assert.True(db.AttributeCategories[expData.AttributeCategoryName] != null,
                $"Check Failed. Attribute Category [{expData.AttributeCategoryName}] not found.");
            Assert.True(db.ElementCategories[expData.ElementCategoryName] != null,
                $"Check Failed. Element Category [{expData.ElementCategoryName}] not found.");

            output.WriteLine("Check Element Attributes.");
            int actualAttributeCount = elementFound.Attributes.Count;
            const int ExpectedAttributeCount = 3;
            Assert.True(actualAttributeCount == ExpectedAttributeCount, $"Attribute Count Failed. Actual: {actualAttributeCount}, expected: {ExpectedAttributeCount}.");
            var attr1 = elementFound.Attributes[expData.Attribute1Name];
            Assert.True(attr1 != null, $"Element [{expData.Name}] did not have attribute [{expData.Attribute1Name}] as expected.");
            Assert.True(attr1.Categories[expData.AttributeCategoryName] != null,
                $"Attribute [{expData.Attribute1Name}] in Element [{expData.Name}] did not have category [{expData.AttributeCategoryName}] as expected.");

            var attr2 = elementFound.Attributes[expData.Attribute2Name];
            Assert.True(attr2 != null, $"Element [{expData.Name}] did not have attribute [{expData.Attribute2Name}] as expected.");
            Assert.True(expData.Attribute2Value == attr2.GetValue().ValueAsDouble(),
                $"Element [{expData.Name}] attribute [{expData.Attribute2Name}] data was [{attr2.GetValue().ValueAsDouble()}], expected [{expData.Attribute2Value}].");

            var attr3 = elementFound.Attributes[expData.Attribute3Name];
            Assert.True(attr3 != null, $"Element [{expData.Name}] did not have attribute [{expData.Attribute3Name}] as expected.");
            Assert.True(attr3.DataReferencePlugIn == db.PISystem.DataReferencePlugIns[expData.DataReferencePlugInName],
                $"Attribute [{expData.Attribute3Name}] in Element [{expData.Name}] did not have data reference PlugIn [{expData.DataReferencePlugInName}] as expected.");
            Assert.True(attr3.ConfigString.Equals(expData.DataReferenceConfigString, StringComparison.OrdinalIgnoreCase),
                $"Attribute [{expData.Attribute3Name}] in Element [{expData.Name}] data reference ConfigString" +
                $" was [{attr3.ConfigString}], expected [{expData.DataReferenceConfigString}].");

            output.WriteLine("Check Element Categories.");
            int actualElemCatCount = elementFound.Categories.Count;
            const int ExpectedElementCount = 1;
            Assert.True(actualElemCatCount == ExpectedElementCount,
                $"Category Count in Element [{expData.Name}] was {actualElemCatCount}, expected {ExpectedElementCount}.");
            Assert.True(elementFound.Categories[expData.ElementCategoryName] != null,
                $"Category [{expData.ElementCategoryName}] not found in Element [{expData.Name}] as expected.");

            output.WriteLine("Check Child Elements.");
            int actualChildElemCount = elementFound.Elements.Count;
            const int ExpectedChildElementCount = 1;
            Assert.True(actualChildElemCount == ExpectedChildElementCount,
                $"Expect Child Element Count in Element [{expData.Name}] was {actualChildElemCount}, expected {ExpectedChildElementCount}.");
            Assert.True(elementFound.Elements[expData.ChildElementName] != null,
                $"Child Element [{expData.ChildElementName}] not found in Element [{expData.Name}] as expected.");

            output.WriteLine("Check Extended properties.");
            int actualExtPropertiesCount = elementFound.ExtendedProperties.Count;
            const int ExpectedExtPropertiesCount = 1;
            Assert.True(actualExtPropertiesCount == ExpectedExtPropertiesCount,
                $"ExtendedProperties Count in Element [{expData.Name}] was {actualExtPropertiesCount}, expected {ExpectedExtPropertiesCount}.");
            string actExtPropValue = elementFound.ExtendedProperties[expData.ExtPropKey].ToString();
            Assert.True(actExtPropValue.Equals(expData.ExtPropValue, StringComparison.OrdinalIgnoreCase),
                $"ExtendedProperty Key [{expData.ExtPropKey}] in Element [{expData.Name}] had Value [{actExtPropValue}], expected [{expData.ExtPropValue}].");

            output.WriteLine("Check Element Ports.");
            int actualPortCount = elementFound.Ports.Count;
            const int ExpectedPortCount = 1;
            Assert.True(actualPortCount == ExpectedPortCount,
                $"Port Count in Element [{expData.Name}] was {actualPortCount}, expected {ExpectedPortCount}.");
            AFPort port = elementFound.Ports[expData.PortName];
            Assert.True(port != null, $"Port [{expData.PortName}] not found in Element [{expData.Name}] as expected.");
            Assert.True(port.AllowedElementCategories[expData.ElementCategoryName] != null,
                $"Port [{expData.PortName}] did not contain AlloweElemCategory [{expData.ElementCategoryName}] as expected.");

            output.WriteLine("Check Element Annotations.");
            var annotations = elementFound.GetAnnotations();
            int actualAnnotationsCount = annotations.Count;
            const int ExpectedAnnotationsCount = 1;
            Assert.True(actualAnnotationsCount == ExpectedAnnotationsCount,
                $"Annotations Count in Element [{expData.Name}] was {actualAnnotationsCount}, expected {ExpectedAnnotationsCount}.");
            Assert.True(annotations[0].Name.Equals(expData.AnnotationName, StringComparison.OrdinalIgnoreCase),
                $"Annotations[0] Name in Element [{expData.Name}] was [{annotations[0].Name}], expected [{expData.AnnotationName}].");
            Assert.True(annotations[0].Value.ToString().Equals(expData.AnnotationValue, StringComparison.OrdinalIgnoreCase),
                $"Annotations[0] Value in Element [{expData.Name}] was [{annotations[0].Value.ToString()}], expected [{expData.AnnotationValue}].");
        }

        /// <summary>
        /// Creates a complex Transfer for use in testing.
        /// </summary>
        /// <param name="db">The AF Database where the transfer should be created.</param>
        /// <param name="transferData">Data used to create the transfer.</param>
        /// <returns>Fully created transfer object is returned.</returns>
        /// <remarks>
        /// The Transfer created in this routine can be verified using the FullTransferVerify() routine.
        /// </remarks>
        private AFTransfer FullTransferCreate(AFDatabase db, TransferTestConfiguration transferData)
        {
            // Add attribute category if it does not exist
            var attrCat = db.AttributeCategories[transferData.AttributeCategoryName];
            if (attrCat == null) attrCat = db.AttributeCategories.Add(transferData.AttributeCategoryName);

            // Add element category if it does not exist
            AFCategory elemCat = db.ElementCategories[transferData.ElementCategoryName];
            if (elemCat == null) elemCat = db.ElementCategories.Add(transferData.ElementCategoryName);

            var newTransferObject = db.AddTransfer(transferData.Name);
            var attr1 = newTransferObject.Attributes.Add(transferData.Attribute1Name);
            attr1.Type = typeof(AFFile);
            attr1.Categories.Add(attrCat);
            var attr2 = newTransferObject.Attributes.Add(transferData.Attribute2Name);
            attr2.Type = typeof(double);
            attr2.SetValue(transferData.Attribute2Value, null);
            var attr3 = newTransferObject.Attributes.Add(transferData.Attribute3Name);
            attr3.DataReferencePlugIn = db.PISystem.DataReferencePlugIns[transferData.DataReferencePlugInName];
            attr3.ConfigString = transferData.DataReferenceConfigString;

            var port = newTransferObject.Ports.Add(transferData.PortName);
            port.AllowedElementCategories.Add(elemCat);

            newTransferObject.Categories.Add(elemCat);

            var annotation = new AFAnnotation(newTransferObject)
            {
                Name = transferData.AnnotationName,
                Value = transferData.AnnotationValue,
            };
            annotation.Save();

            return newTransferObject;
        }

        /// <summary>
        /// Verifies a transfer object.
        /// </summary>
        /// <param name="db">The AF Database that contains the transfer being verified.</param>
        /// <param name="transferID">ID (GUID) of the transfer to be verified.</param>
        /// <param name="expData">Expected Data to use to verify the transfer.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <remarks>
        /// This routine is used to verify Transfers created using the FullTransferCreate() routine.
        /// </remarks>
        private void FullTransferVerify(AFDatabase db, Guid transferID, TransferTestConfiguration expData, ITestOutputHelper output)
        {
            var transferFound = AFTransfer.FindTransfer(db.PISystem, transferID);
            Assert.True(transferFound != null, $"Unable to find transfer [{expData.Name}] with ID [{transferID}].");
            string actTransferName = transferFound.Name;
            Assert.True(actTransferName.Equals(expData.Name, StringComparison.OrdinalIgnoreCase),
                $"Element Template found with ID [{transferID}] had name [{actTransferName}], expected [{expData.Name}].");
            Assert.True(db.AttributeCategories[expData.AttributeCategoryName] != null,
                $"Check Failed. Attribute Category [{expData.AttributeCategoryName}] not found for Transfer [{expData.Name}].");
            Assert.True(db.ElementCategories[expData.ElementCategoryName] != null,
                $"Check Failed. Element Category [{expData.ElementCategoryName}] not found for Transfer [{expData.Name}].");

            output.WriteLine("Check Transfer Attributes.");
            int actualAttributeCount = transferFound.Attributes.Count;
            int expectedAttributeCount = 3;
            Assert.True(actualAttributeCount == expectedAttributeCount, $"Attribute Count Failed. Actual: {actualAttributeCount}, expected: {expectedAttributeCount} for Transfer [{expData.Name}].");
            var attr1 = transferFound.Attributes[expData.Attribute1Name];
            Assert.True(attr1 != null, $"Transfer [{expData.Name}] did not have attribute [{expData.Attribute1Name}] as expected.");
            Assert.True(attr1.Categories[expData.AttributeCategoryName] != null,
                $"Attribute [{expData.Attribute1Name}] in Transfer [{expData.Name}] did not have category [{expData.AttributeCategoryName}] as expected.");

            var attr2 = transferFound.Attributes[expData.Attribute2Name];
            Assert.True(attr2 != null, $"Transfer [{expData.Name}] did not have attribute [{expData.Attribute2Name}] as expected.");
            Assert.True(expData.Attribute2Value == attr2.GetValue().ValueAsDouble(),
                $"Transfer [{expData.Name}] attribute [{expData.Attribute2Name}] data was [{attr2.GetValue().ValueAsDouble()}], expected [{expData.Attribute2Value}].");

            var attr3 = transferFound.Attributes[expData.Attribute3Name];
            Assert.True(attr3 != null, $"Transfer [{expData.Name}] did not have attribute [{expData.Attribute3Name}] as expected.");
            Assert.True(attr3.DataReferencePlugIn == db.PISystem.DataReferencePlugIns[expData.DataReferencePlugInName],
                $"Attribute [{expData.Attribute3Name}] in Transfer [{expData.Name}] did not have data reference PlugIn [{expData.DataReferencePlugInName}] as expected.");
            Assert.True(attr3.ConfigString.Equals(expData.DataReferenceConfigString, StringComparison.OrdinalIgnoreCase),
                $"Attribute [{expData.Attribute3Name}] in Transfer [{expData.Name}] data reference ConfigString was" +
                $" [{attr3.ConfigString}], expected [{expData.DataReferenceConfigString}].");

            output.WriteLine("Check Transfer Categories.");
            int actualTransferCategoryCount = transferFound.Categories.Count;
            const int ExpectedTransferCategoryCount = 1;
            Assert.True(actualTransferCategoryCount == ExpectedTransferCategoryCount,
                $"Category Count in Transfer [{expData.Name}] was {actualTransferCategoryCount}, expected {ExpectedTransferCategoryCount}.");
            Assert.True(transferFound.Categories[expData.ElementCategoryName] != null,
                $"Category [{expData.ElementCategoryName}] not found in Transfer [{expData.Name}] as expected.");

            output.WriteLine("Check Transfer Ports.");
            int actualPortCount = transferFound.Ports.Count;
            const int ExpectedPortCount = 3;
            Assert.True(actualPortCount == ExpectedPortCount, $"Port Count in Transfer [{expData.Name}] was {actualPortCount}, expected {ExpectedPortCount}.");
            var port = transferFound.Ports[expData.PortName];
            Assert.True(port != null, $"Port [{expData.PortName}] not found in Transfer [{expData.Name}] as expected.");
            Assert.True(port.AllowedElementCategories[expData.ElementCategoryName] != null,
                $"Port [{expData.PortName}] did not contain AlloweElemCategory [{expData.ElementCategoryName}] as expected.");

            output.WriteLine("Check Element Annotations.");
            var annotations = transferFound.GetAnnotations();
            int actualAnnotationsCount = annotations.Count;
            const int ExpectedAnnotationsCount = 1;
            Assert.True(actualAnnotationsCount == ExpectedAnnotationsCount,
                $"Annotations Count in Transfer [{expData.Name}] was {actualAnnotationsCount}, expected {ExpectedAnnotationsCount}.");
            Assert.True(annotations[0].Name.Equals(expData.AnnotationName, StringComparison.OrdinalIgnoreCase),
                $"Annotations[0] Name in Transfer [{expData.Name}] was [{annotations[0].Name}], expected [{expData.AnnotationName}].");
            Assert.True(annotations[0].Value.ToString().Equals(expData.AnnotationValue, StringComparison.OrdinalIgnoreCase),
                $"Annotations[0] Value in Transfer [{expData.Name}] was [{annotations[0].Value.ToString()}], expected [{expData.AnnotationValue}].");
        }

        /// <summary>
        /// Routine to create an element template with attributes, a port, categories and annotation.
        /// </summary>
        /// <param name="db">The AF Database where the element template should be created.</param>
        /// <param name="testData">Data used to create the element template.</param>
        /// <returns>Fully created element template object is returned.</returns>
        /// <remarks>
        /// The Element Template created in this routine can be verified using the FullElementTemplateVerify() routine.
        /// </remarks>
        private AFElementTemplate FullElementTemplateCreate(AFDatabase db, ElementTemplateTestConfiguration testData)
        {
            // Add attribute category if it does not exist
            var attrCat = db.AttributeCategories[testData.AttributeCategoryName];
            if (attrCat == null) attrCat = db.AttributeCategories.Add(testData.AttributeCategoryName);

            // Add element category if it does not exist
            var elemCat = db.ElementCategories[testData.ElementCategoryName];
            if (elemCat == null) elemCat = db.ElementCategories.Add(testData.ElementCategoryName);

            var newElemTemplate = db.ElementTemplates.Add(testData.Name);
            var attTemplate = newElemTemplate.AttributeTemplates.Add(testData.AttributeTemplateName);
            attTemplate.Categories.Add(attrCat);
            attTemplate.Type = typeof(AFFile);
            newElemTemplate.Categories.Add(elemCat);
            newElemTemplate.ExtendedProperties.Add(testData.ElementTemplateExtPropKey, testData.ExtPropValue);
            var port = newElemTemplate.Ports.Add(testData.PortName);
            port.AllowedElementCategories.Add(elemCat);

            return newElemTemplate;
        }

        /// <summary>
        /// Verifies a complex element template object.
        /// </summary>
        /// <param name="db">The AF Database that contains the element template being verified.</param>
        /// <param name="elemTemplateID">ID (GUID) of the element template to be verified.</param>
        /// <param name="expData">Expected DAta used to check element template.</param>
        /// <remarks>
        /// This routine is used to verify element templates created using the FullElementTemplateCreate() routine.
        /// </remarks>
        private void FullElementTemplateVerify(AFDatabase db, Guid elemTemplateID, ElementTemplateTestConfiguration expData)
        {
            var readElemTemplate = AFElementTemplate.FindElementTemplate(db.PISystem, elemTemplateID);
            Assert.True(readElemTemplate != null, $"Unable to find Element Template [{expData.Name}] with ID [{elemTemplateID}].");
            string actElemTempName = readElemTemplate.Name;
            Assert.True(actElemTempName.Equals(expData.Name, StringComparison.OrdinalIgnoreCase),
                $"Element Template found with ID [{elemTemplateID}] had name [{actElemTempName}], expected [{expData.Name}].");

            int actualAttributeTemplateCount = readElemTemplate.AttributeTemplates.Count;
            const int ExpectedAttributeTemplateCount = 1;
            Assert.True(actualAttributeTemplateCount == ExpectedAttributeTemplateCount,
                $"Attribute Template count in Element Template [{expData.Name}] was [{actualAttributeTemplateCount}], expected {ExpectedAttributeTemplateCount}.");
            var actAttTemp = readElemTemplate.AttributeTemplates[expData.AttributeTemplateName];
            Assert.True(actAttTemp != null, $"Could not find Attribute Template [{expData.AttributeTemplateName}] in Element Template [{expData.Name}].");

            int actualCategoryCount = readElemTemplate.Categories.Count;
            const int ExpectedCategoryCount = 1;
            Assert.True(actualAttributeTemplateCount == ExpectedCategoryCount,
                $"Category count in Element Template [{expData.Name}] was {actualCategoryCount}, expected {ExpectedCategoryCount}.");
            var actualElemCat = readElemTemplate.Categories[expData.ElementCategoryName];
            Assert.True(actualElemCat != null, $"Category [{expData.ElementCategoryName}] not found in Element Template [{expData.Name}].");

            int actualExtPropCount = readElemTemplate.ExtendedProperties.Count;
            const int ExpectedExtPropCount = 1;
            Assert.True(actualExtPropCount == ExpectedExtPropCount,
                $"Extended Property count in Element Template [{expData.Name}] was {actualExtPropCount}, expected {ExpectedExtPropCount}.");
            string actualExtPropValue = readElemTemplate.ExtendedProperties[expData.ElementTemplateExtPropKey].ToString();
            Assert.True(actualExtPropValue.Equals(expData.ExtPropValue, StringComparison.OrdinalIgnoreCase),
                $"ExtendedProperty for Key [{expData.ElementTemplateExtPropKey}] in ElementTemplate [{expData.Name}]" +
                $" was [{actualExtPropValue}], expected [{expData.ExtPropValue}].");

            int actualPortCount = readElemTemplate.Ports.Count;
            const int ExpectedPortCount = 1;
            Assert.True(actualExtPropCount == ExpectedPortCount, $"Port count in Element Template [{expData.Name}] was {actualPortCount}, expected {ExpectedPortCount}.");
            var actualPort = readElemTemplate.Ports[expData.PortName];
            Assert.True(actualElemCat != null, $"Port [{expData.PortName}] not found in Element Template [{expData.Name}].");

            var actPortElementCategory = actualPort.AllowedElementCategories[expData.ElementCategoryName];
            Assert.True(actPortElementCategory != null,
                $"Did not find Element Category [{expData.ElementCategoryName}] in Allowed Element Categories for Element Template [{expData.Name}].");
        }
    }
}
