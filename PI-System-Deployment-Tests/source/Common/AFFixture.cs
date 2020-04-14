using System;
using System.Diagnostics.Contracts;
using System.Globalization;
using System.Linq;
using System.Text;
using OSIsoft.AF;
using OSIsoft.AF.Analysis;
using OSIsoft.AF.Asset;
using OSIsoft.AF.EventFrame;
using OSIsoft.AF.Search;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Test context class to be shared in AF related xUnit test classes.
    /// </summary>
    /// <remarks>
    /// xUnit.net ensures that the fixture instance will be created before any tests run and
    /// when all tests are done will clean up the fixture object with 'Dispose' call.
    /// This fixture includes helper functions isolated to AF related calls.
    /// See Utils.cs for more general test helper functions.
    /// </remarks>
    public sealed class AFFixture : IDisposable
    {
        #region Wind Farm Database Constants
#pragma warning disable SA1600 // Elements should be documented
        public const int TotalTurbineCount = 40;
        public const int TotalWindFarmCount = 8;
        public const int TotalRegionCount = 2;
        public const int TotalElementCount = TotalTurbineCount + TotalWindFarmCount + TotalRegionCount + 1;

        public const string TurbineTemplateName = "Turbine";
        public const string WindFarmTemplateName = "Farm";
        public const string RegionTemplateName = "Region";

        public const string ElemementCategoryNameEquipment = "Equipment";
        public const string AttributeCategoryNameAnemometer = "Anemometer";
        public const string AttributeCategoryNameDate = "Date";
        public const string AttributeCategoryNameLocation = "Location";
        public const string AttributeCategoryNamePotentialProduction = "Potential Production";
        public const string AttributeCategoryNamePower = "Power";
        public const string AttributeCategoryNameProduct = "Product";
        public const string AttributeCategoryNameProduction = "Production";
        public const string AttributeCategoryNameProductLost = "Production Lost";
        public const string AttributeCategoryNameRevenue = "Revenue";
        public const string AttributeCategoryNameSite = "Site";
        public const string AttributeCategoryNameStatus = "Status";
#pragma warning restore SA1600 // Elements should be documented
        #endregion

        /// <summary>
        /// DateTime format string used to create unique text in the tests.
        /// </summary>
        public const string DateTimeFormat = "yyyy-MM-dd HH:mm:ss.fff";

        /// <summary>
        /// Creates an instance of the AFFixture class.
        /// </summary>
        public AFFixture()
        {
            var systems = new PISystems();
            if (systems.Contains(Settings.AFServer))
            {
                PISystem = systems[Settings.AFServer];
                PISystem.Connect();
            }
            else
            {
                throw new InvalidOperationException(
                    $"The specific AF Server [{Settings.AFServer}] does not exist or is not configured.");
            }

            if (PISystem.Databases.Contains(Settings.AFDatabase))
                AFDatabase = PISystem.Databases[Settings.AFDatabase];
        }

        /// <summary>
        /// The PISystem to be tested associated with this fixture.
        /// </summary>
        public PISystem PISystem { get; private set; }

        /// <summary>
        /// The AFDatabase to be used by this test fixture.
        /// </summary>
        public AFDatabase AFDatabase { get; private set; }

        /// <summary>
        /// Displays the Value based upon the AFvalue's value Type with the option to add the value's UOM abbreviation.
        /// </summary>
        /// <param name="value">The AF value to display.</param>
        /// <param name="displayDigits">Displays the AFValue's value based upon the specified number of display digits.</param>
        /// <param name="addUOMAbbreviation">If true, the value's UOM abbreviation is added to the returned display value the value's UOM is defined.</param>
        /// <returns>
        /// Returns the string representation of the Value as specified by the rules for displayDigits, the value's Type. Optionally, the value's UOM abbreviation is added.
        /// </returns>
        /// <remarks>
        /// When using this method in a formatted string, "[]" is not needed outside as it is used within the method.
        /// </remarks>
        public static string DisplayAFValue(AFValue value, int displayDigits = 6, bool addUOMAbbreviation = true)
        {
            if (value == null)
                return "[null]";
            string displayString = value.DisplayValue(displayDigits, null, addUOMAbbreviation);
            if (displayString == null)
                displayString = "<null>";
            if (displayString == string.Empty)
                displayString = "<empty>";
            displayString = $"[{displayString}]";
            displayString += $" at [{value.Timestamp}]";
            return displayString;
        }

        /// <summary>
        /// Disconnects from the PISystem when disposing of the fixture.
        /// </summary>
        public void Dispose() => PISystem.Disconnect();

        /// <summary>
        /// Gets an instanced PISystem.
        /// </summary>
        /// <returns>Returns a new PISystem from a new PISystems instance.</returns>
        /// <remarks>
        /// This operation gets an instanced PISystem object. It is used to prevent the main PISystem 
        /// from using any cached data from a system check.
        /// </remarks>
        public PISystem GetInstancedSystem()
        {
            var systems = new PISystems(true);
            if (systems.Contains(Settings.AFServer))
            {
                var system = systems[Settings.AFServer];

                if (system is null)
                {
                    throw new InvalidOperationException(
                        $"The specific AF Server [{Settings.AFServer}] does not exist or is not configured.");
                }

                return system;
            }
            else
            {
                throw new InvalidOperationException(
                    $"The specific AF Server [{Settings.AFServer}] does not exist or is not configured.");
            }
        }

        /// <summary>
        /// Disconnects and reconnects to AFDatabase.
        /// </summary>
        /// <returns>Returns the new database after reconnecting.</returns>
        /// <remarks>
        /// This operation clears the AFSDK cache and confirms object persistence on AF the server. It is used
        /// to confirm that test changes are persisted (and are available to calls made with a new connection).
        /// </remarks>
        public AFDatabase ReconnectToDB()
        {
            PISystem.Disconnect();
            PISystem.Connect();

            AFDatabase = PISystem.Databases[Settings.AFDatabase];
            return AFDatabase;
        }

        /// <summary>
        /// Removes the analysis from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of the analysis to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveAnalysisIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            AFAnalysis preCheckAnalysis;
            using (var search = new AFAnalysisSearch(AFDatabase, string.Empty, $"Name:'{name}'"))
            {
                var coll = new AFNamedCollectionList<AFAnalysis>(search.FindObjects());
                preCheckAnalysis = coll[name];
            }

            if (preCheckAnalysis != null)
            {
                output.WriteLine($"Analysis [{preCheckAnalysis}] exists, delete it.");
                preCheckAnalysis.Delete();
                preCheckAnalysis.CheckIn();
            }
            else
            {
                output.WriteLine($"Analysis [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the analysis template from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of the analysis template to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveAnalysisTemplateIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckAnalysisTemplate = AFDatabase.AnalysisTemplates[name];
            if (preCheckAnalysisTemplate != null)
            {
                output.WriteLine($"Analysis Template [{preCheckAnalysisTemplate}] exists, delete it.");
                AFDatabase.AnalysisTemplates.Remove(preCheckAnalysisTemplate);
                AFDatabase.CheckIn();
            }
            else
            {
                output.WriteLine($"Analysis Template [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the attribute category from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of the attribute category to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveAttributeCategoryIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckCategory = AFDatabase.AttributeCategories[name];
            if (preCheckCategory != null)
            {
                output.WriteLine($"Attribute Category [{preCheckCategory}] exists, delete it.");
                AFDatabase.AttributeCategories.Remove(preCheckCategory);
                AFDatabase.CheckIn();
            }
            else
            {
                output.WriteLine($"Attribute Category [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the root-level element from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of the root-level element to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveElementIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckElement = AFDatabase.Elements[name];
            if (preCheckElement != null)
            {
                output.WriteLine($"Element [{preCheckElement}] exists, delete it.");
                AFDatabase.Elements.Remove(preCheckElement);
                AFDatabase.CheckIn();
            }
            else
            {
                output.WriteLine($"Element [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the element template from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of the element template to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveElementTemplateIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckElementTemplate = AFDatabase.ElementTemplates[name];
            if (preCheckElementTemplate != null)
            {
                output.WriteLine($"Element Template [{preCheckElementTemplate}] exists, delete it.");
                AFDatabase.ElementTemplates.Remove(preCheckElementTemplate);
                AFDatabase.CheckIn();
            }
            else
            {
                output.WriteLine($"Element Template [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the enumeration set from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of the enumeration set to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveEnumerationSetIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckEnumSet = AFDatabase.EnumerationSets[name];
            if (preCheckEnumSet != null)
            {
                output.WriteLine($"Enumeration Set [{preCheckEnumSet}] exists, delete it.");
                AFDatabase.EnumerationSets.Remove(preCheckEnumSet);
                AFDatabase.CheckIn();
            }
            else
            {
                output.WriteLine($"Enumeration Set [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Remove the event frame by id if it exists.
        /// </summary>
        /// <param name="id">The Id of the event frame to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveEventFrameIfExists(Guid id, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckEventFrame = AFEventFrame.FindEventFrame(PISystem, id);
            if (preCheckEventFrame != null)
            {
                output.WriteLine($"Event Frame [{preCheckEventFrame}] exists, delete it.");
                preCheckEventFrame.Delete();
                preCheckEventFrame.CheckIn();
            }
            else
            {
                output.WriteLine($"Event Frame with GUID [{id}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Remove the event frame by name if it exists.
        /// </summary>
        /// <param name="name">The name of the event frame to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveEventFrameIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            AFEventFrame preCheckEventFrame = null;
            using (var search = new AFEventFrameSearch(AFDatabase, string.Empty, $"Name:'{name}'"))
            {
                var searchResults = new AFNamedCollectionList<AFEventFrame>(search.FindObjects());
                if (searchResults.Count > 0)
                    preCheckEventFrame = searchResults.First();
            }

            if (preCheckEventFrame?.Name.Equals(name, StringComparison.OrdinalIgnoreCase) ?? false)
            {
                output.WriteLine($"Event Frame [{preCheckEventFrame}] exists, delete it.");
                preCheckEventFrame.Delete();
                preCheckEventFrame.CheckIn();
            }
            else
            {
                output.WriteLine($"Event Frame [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the named notification contact template if it exists.
        /// </summary>
        /// <param name="name">The name of the notification contact template to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveNotificationContactTemplateIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckNCT = PISystem.NotificationContactTemplates[name];
            if (preCheckNCT != null)
            {
                output.WriteLine($"Notification Contact Template [{preCheckNCT}] exists, delete it.");
                PISystem.NotificationContactTemplates.Remove(preCheckNCT);
                PISystem.CheckIn();
            }
            else
            {
                output.WriteLine($"Notification Contact Template [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the table from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of the table to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveTableIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckTable = AFDatabase.Tables[name];
            if (preCheckTable != null)
            {
                output.WriteLine($"Table [{preCheckTable}] exists, delete it.");
                AFDatabase.Tables.Remove(preCheckTable);
                AFDatabase.PISystem.CheckIn();
            }
            else
            {
                output.WriteLine($"Table [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the transfer from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of the transfer to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveTransferIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            AFTransfer preCheckTransfer = null;
            using (var search = new AFTransferSearch(AFDatabase, string.Empty, $"Name:'{name}'"))
            {
                var searchResults = new AFNamedCollectionList<AFTransfer>(search.FindObjects());
                if (searchResults.Count > 0)
                    preCheckTransfer = searchResults.First();
            }

            if (preCheckTransfer?.Name.Equals(name, StringComparison.OrdinalIgnoreCase) ?? false)
            {
                output.WriteLine($"Transfer [{preCheckTransfer}] exists, delete it.");
                AFDatabase.RemoveTransfer(preCheckTransfer);
                AFDatabase.CheckIn();
            }
            else
            {
                output.WriteLine($"Transfer [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Removes the UOM Class from the AF Database if it exists.
        /// </summary>
        /// <param name="name">The name of UOM Class to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemoveUOMClassIfExists(string name, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var preCheckUOMClass = PISystem.UOMDatabase.UOMClasses[name];
            if (preCheckUOMClass != null)
            {
                output.WriteLine($"UOM Class [{preCheckUOMClass}] exists, delete it.");
                PISystem.UOMDatabase.UOMClasses.Remove(preCheckUOMClass);
                PISystem.CheckIn();
            }
            else
            {
                output.WriteLine($"UOM Class [{name}] does not exist, can not be deleted.");
            }
        }

        /// <summary>
        /// Checks to make sure the actual AFValues matches the expected AFValues.
        /// </summary>
        /// <param name="actualValues">Actual AFValues.</param>
        /// <param name="expectedValues">Expected AFValues.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void CheckAFValues(AFValues actualValues, AFValues expectedValues, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            Assert.False(actualValues == null, "Actual value is null.");
            Assert.False(expectedValues == null, "Expected value is null.");
            if (actualValues == null || expectedValues == null) // Needed for the Coverity scan
                return;

            var actualValuesArray = actualValues.ToArray();
            var expectedValuesArray = expectedValues.ToArray();

            output.WriteLine("Actual values array:");
            foreach (var value in actualValuesArray)
            {
                output.WriteLine($"  Attribute: [{value.Attribute}]");
                output.WriteLine($"    Status: [{value.Status}]");
                output.WriteLine($"    Timestamp: [{value.Timestamp}]");
                output.WriteLine($"    UOM: [{value.UOM}]");
                output.WriteLine($"    Value: [{value.Value}]");
            }

            output.WriteLine("Expected values array:");
            foreach (var value in expectedValuesArray)
            {
                output.WriteLine($"  Attribute: [{value.Attribute}]");
                output.WriteLine($"    Status: [{value.Status}]");
                output.WriteLine($"    Timestamp: [{value.Timestamp}]");
                output.WriteLine($"    UOM: [{value.UOM}]");
                output.WriteLine($"    Value: [{value.Value}]");
            }

            if (actualValuesArray.Length != expectedValuesArray.Length)
                Assert.True(false, $"Count is incorrect. Expected: {expectedValuesArray.Length}, Actual: {actualValuesArray.Length}");

            for (int i = 0; i < actualValuesArray.Length; i++)
            {
                CheckAFValue(actualValuesArray[i], expectedValuesArray[i]);
            }
        }

        /// <summary>
        /// Checks to make sure the actual AFValue matches the expected AFValue.
        /// </summary>
        /// <param name="actualVal">Actual AFValue.</param>
        /// <param name="expectedVal">Expected AFValue.</param>
        public void CheckAFValue(AFValue actualVal, AFValue expectedVal)
        {
            Contract.Requires(actualVal != null);
            Contract.Requires(expectedVal != null);

            Assert.False(actualVal == null, "Actual value is null.");
            Assert.False(expectedVal == null, "Expected value is null.");

            CheckValue(actualVal.Attribute, expectedVal.Attribute, "Attribute is incorrect.");
            CheckValue(actualVal.Status, expectedVal.Status, $"Status is incorrect for [{actualVal.Attribute}].");
            CheckValue(actualVal.Timestamp, expectedVal.Timestamp, $"Timestamp is incorrect for [{actualVal.Attribute}].");
            CheckValue(actualVal.UOM, expectedVal.UOM, $"UOM is incorrect for [{actualVal.Attribute}].");
            CheckValue(actualVal.Value, expectedVal.Value, $"Value is incorrect for [{actualVal.Attribute}].");
        }

        internal static PISystem GetPISystemFromConfig()
        {
            PISystem pisys;

            var systems = new PISystems();
            if (systems.Contains(Settings.AFServer))
            {
                pisys = systems[Settings.AFServer];
                pisys.Connect();
            }
            else
            {
                throw new InvalidOperationException(
                    $"The specific AF Server [{Settings.AFServer}] does not exist or is not configured.");
            }

            return pisys;
        }

        /// <summary>
        /// Checks to make sure the actual value matches the expected value.
        /// </summary>
        /// <param name="actual">Actual value.</param>
        /// <param name="expected">Expected value.</param>
        /// <param name="title">Error message title.</param>
        private bool CheckValue<T>(T actual, T expected, string title)
        {
            object tmpActual = actual;
            object tmpExpected = expected;

            if (actual is double && expected is double)
            {
                tmpActual = Math.Round(Convert.ToDouble(actual, CultureInfo.InvariantCulture), 5);
                tmpExpected = Math.Round(Convert.ToDouble(expected, CultureInfo.InvariantCulture), 5);
            }

            if (!object.Equals(tmpActual, tmpExpected))
            {
                var msg = new StringBuilder(title);
                msg.AppendLine();

                if (actual is AFAttribute)
                {
                    msg.AppendFormat(CultureInfo.CurrentCulture, "  Expect: '{1}|{2}'{0}  Actual: '{3}|{4}'", Environment.NewLine,
                        (tmpExpected as AFAttribute)?.Element, tmpExpected, (tmpActual as AFAttribute)?.Element, tmpActual);
                }
                else
                {
                    msg.AppendFormat(CultureInfo.CurrentCulture, "  Expect: '{1}'{0}  Actual: '{2}'", Environment.NewLine, tmpExpected, tmpActual);
                }

                msg.AppendLine();
                Assert.True(false, msg.ToString());
            }

            return true;
        }

        /// <summary>
        /// Placeholder class for applying CollectionDefinitionAttribute and all the ICollectionFixture<> interfaces.
        /// </summary>
        /// <remarks>
        /// This class does not have any code and is never created.
        /// </remarks>
        [CollectionDefinition("AF collection")]
        public class AFTestCollection : ICollectionFixture<AFFixture>
        {
        }
    }
}
