using System;
using Newtonsoft.Json.Linq;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests the ability to create, open, save, and delete displays in PI Vision.
    /// </summary>
    public class Vision3Tests : IClassFixture<Vision3Fixture>
    {
        internal const string KeySetting = "PIVisionServer";
        internal const TypeCode KeySettingTypeCode = TypeCode.String;

        /// <summary>
        /// Constructor for Vision3Tests class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage PI Vision 3 connection and specific helper functions.</param>
        public Vision3Tests(ITestOutputHelper output, Vision3Fixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private Vision3Fixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Tests to see if the current PI Vision patch is applied
        /// </summary>
        /// <remarks>
        /// Errors if the current patch is not applied with a message telling the user to upgrade
        /// </remarks>
        [Fact]
        public void HaveLatestPatchVision3()
        {
            var factAttr = new GenericFactAttribute(TestCondition.PIVISIONCURRENTPATCH, true);
            Assert.NotNull(factAttr);
        }

        /// <summary>
        /// Creates a test Display Folder in PI Vision if missing.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Check if PI Vision Server is set in the App.Config</para>
        /// <para>If config is not set, skip check</para>
        /// <para>If config is set, create new Vision fixture</para>
        /// <para>With the fixture, attempt to create display folder in PI Vision</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public async void CreatePIVisionDisplayFolderTest()
        {
            Output.WriteLine("Create a new display folder into the database.");
            using (var response = await Fixture.FindOrCreateTestFolder().ConfigureAwait(false))
            {
                Assert.True(response.IsSuccessStatusCode, "PI Vision cannot save a display folder. " +
                Vision3Fixture.CommonVisionIssues);
            }
        }

        /// <summary>
        /// Verifies that test can connect to PI Vision server.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Make base call to server</para>
        /// <para>Verify response indicates successful call</para>
        /// <para>Check that new display contents were returned</para>
        /// </remarks>
        /// <returns>A <see cref="System.Threading.Tasks.Task"/> representing the asynchronous unit test.</returns>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public async System.Threading.Tasks.Task ConnectToServerTestAsync()
        {
            Output.WriteLine("Begin new connect to server test.");
            using (var response = await Fixture.GetVerificationToken().ConfigureAwait(false))
            {
                Output.WriteLine("Check that call to server returned successfully.");
                Assert.True(response.IsSuccessStatusCode, "Cannot connect to PI Vision. Check to make sure the app config " +
                    "contains the full path to your PI Vision server (i.e. https://MyServer/Vision). " + Vision3Fixture.CommonVisionIssues);

                Output.WriteLine("Check that new display contents were returned.");
                var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                Assert.True(contents != null, "Contents have not been returned.");
            }
        }

        /// <summary>
        /// Verifies that new PI Vision displays can be created.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Call New Display Endpoint</para>
        /// <para>Verify response indicates successful call</para>
        /// <para>Check that new display contents were returned</para>
        /// </remarks>
        /// <returns>A <see cref="System.Threading.Tasks.Task"/> representing the asynchronous unit test.</returns>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public async System.Threading.Tasks.Task NewDisplayTestAsync()
        {
            Output.WriteLine("Begin new display test.");
            Output.WriteLine("Get a new display.");
            using (var response = await Fixture.Client.GetAsync("Displays/NewDisplay").ConfigureAwait(false))
            {
                Output.WriteLine("Check that call to server returned successfully.");
                Assert.True(response.IsSuccessStatusCode, "PI Vision cannot create new displays. " +
                    Vision3Fixture.CommonVisionIssues);

                Output.WriteLine("Check that new display contents were returned.");
                var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                Assert.True(contents != null, "Contents have not been returned.");
            }
        }

        /// <summary>
        /// Verifies that PI Vision displays can be saved.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Call Save Display Endpoint</para>
        /// <para>Verify response indicates successful call</para>
        /// <para>Check that a new display object was returned</para>
        /// <para>Remove display from database</para>
        /// </remarks>
        /// <returns>A <see cref="System.Threading.Tasks.Task"/> representing the asynchronous unit test.</returns>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public async System.Threading.Tasks.Task SaveDisplayTestAsync()
        {
            try
            {
                Output.WriteLine("Begin save display test.");
                var displayName = Fixture.GetUniqueDisplayName();

                Output.WriteLine($"Insert display [{displayName}] into the database.");
                using (var response = await Fixture.PostSaveDisplay(displayName).ConfigureAwait(false))
                {
                    Output.WriteLine("Check that call to server returned successfully.");
                    Assert.True(response.IsSuccessStatusCode, "PI Vision cannot save displays. " +
                        Vision3Fixture.CommonVisionIssues);

                    Output.WriteLine("Check that a saved display object was returned.");
                    var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    Assert.True(contents != null, "Contents have not been returned.");
                    var o = JObject.Parse(contents);
                    var d = o.GetValue("LinkName", StringComparison.OrdinalIgnoreCase).Value<string>();
                    Assert.True(o.GetValue("LinkName", StringComparison.OrdinalIgnoreCase).Value<string>() == displayName, "Display saved incorrectly.");
                }
            }
            finally
            {
                Output.WriteLine("Remove display from database.");
                await Fixture.CleanUpDisplays().ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Verifies that PI Vision displays can be loaded.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Insert displays into the database</para>
        /// <para>Call Open Display Endpoint</para>
        /// <para>Verify response indicates successful call</para>
        /// <para>Check that a display object was returned</para>
        /// <para>Remove display from database</para>
        /// </remarks>
        /// <returns>A <see cref="System.Threading.Tasks.Task"/> representing the asynchronous unit test.</returns>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public async System.Threading.Tasks.Task OpenDisplayTestAsync()
        {
            try
            {
                Output.WriteLine("Begin open display test.");
                var displayName = Fixture.GetUniqueDisplayName();

                Output.WriteLine($"Insert display [{displayName}] into the database.");
                using (var response = await Fixture.PostSaveDisplay(displayName).ConfigureAwait(false))
                {
                    Output.WriteLine("Check that call to server returned successfully.");
                    Assert.True(response.IsSuccessStatusCode, "PI Vision cannot save displays. " +
                        Vision3Fixture.CommonVisionIssues);
                }

                Output.WriteLine("Open a display that was previously saved.");
                using (var response = await Fixture.OpenEditDisplay(displayName).ConfigureAwait(false))
                {
                    Output.WriteLine("Check that call to server returned successfully.");
                    Assert.True(response.IsSuccessStatusCode, "PI Vision cannot open displays. " +
                        Vision3Fixture.CommonVisionIssues);

                    Output.WriteLine("Check that a display object was returned.");
                    var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    Assert.True(contents != null, "Contents have not been returned.");
                    var o = JObject.Parse(contents);
                    Assert.True(o.GetValue("Name", StringComparison.OrdinalIgnoreCase).Value<string>() == displayName, "Display was not retrieved correctly.");
                }
            }
            finally
            {
                Output.WriteLine("Remove display from database.");
                await Fixture.CleanUpDisplays().ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Verifies that PI Vision display data can be retrieved.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Insert displays into the database</para>
        /// <para>Call Diff For Data Endpoint</para>
        /// <para>Verify response indicates successful call</para>
        /// <para>Check that data was returned</para>
        /// <para>Remove display from database</para>
        /// </remarks>
        /// <returns>A <see cref="System.Threading.Tasks.Task"/> representing the asynchronous unit test.</returns>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public async System.Threading.Tasks.Task DiffForDataTestAsync()
        {
            try
            {
                Output.WriteLine("Begin get display data test.");
                var displayName = Fixture.GetUniqueDisplayName();

                Output.WriteLine($"Insert display [{displayName}] into the database.");
                using (var response = await Fixture.PostSaveDisplay(displayName).ConfigureAwait(false))
                {
                    Output.WriteLine("Check that call to server returned successfully.");
                    Assert.True(response.IsSuccessStatusCode, "PI Vision cannot save displays. " +
                        Vision3Fixture.CommonVisionIssues);
                }

                Output.WriteLine("Request display data.");
                using (var response = await Fixture.PostDiffForData(displayName).ConfigureAwait(false))
                {
                    Output.WriteLine("Check that call to server returned successfully.");
                    Assert.True(response.IsSuccessStatusCode, "PI Vision cannot retrieve display data. " +
                        Vision3Fixture.CommonVisionIssues);

                    Output.WriteLine("Check that data was returned.");
                    var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    Assert.True(contents != null, "Contents have not been returned.");
                    var j = JArray.Parse(contents);
                    Assert.True(j[0].Value<JObject>().GetValue("Value", StringComparison.OrdinalIgnoreCase).Value<string>() != "No Data", "No Data returned. Verify that AF Server is running," +
                        " the AF Server is setup on the PI Vision server, and that the current user has permissions to read data.");
                }
            }
            finally
            {
                Output.WriteLine("Remove display from database.");
                await Fixture.CleanUpDisplays().ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Verifies that PI Vision displays can be deleted.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Insert displays into the database</para>
        /// <para>Call Delete Display Endpoint</para>
        /// <para>Verify response indicates successful call</para>
        /// </remarks>
        /// <returns>A <see cref="System.Threading.Tasks.Task"/> representing the asynchronous unit test.</returns>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public async System.Threading.Tasks.Task DeleteDisplayTestAsync()
        {
            Output.WriteLine("Begin delete display test.");
            var displayName = Fixture.GetUniqueDisplayName();

            Output.WriteLine($"Insert display [{displayName}] into the database.");
            using (var response = await Fixture.PostSaveDisplay(displayName).ConfigureAwait(false))
            {
                Output.WriteLine("Check that call to server returned successfully.");
                Assert.True(response.IsSuccessStatusCode, "PI Vision cannot save displays. " +
                    Vision3Fixture.CommonVisionIssues);
            }

            Output.WriteLine("Delete a display from the database.");
            using (var response = await Fixture.PostDeleteDisplay(displayName).ConfigureAwait(false))
            {
                Output.WriteLine("Check that call to server returned successfully.");
                Assert.True(response.IsSuccessStatusCode, "PI Vision cannot delete display. " +
                    Vision3Fixture.CommonVisionIssues);
            }
        }
    }
}
