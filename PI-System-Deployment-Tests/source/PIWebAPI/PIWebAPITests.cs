using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using OSIsoft.AF;
using OSIsoft.AF.Asset;
using OSIsoft.AF.EventFrame;
using OSIsoft.AF.PI;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests various features of the PI Web API Server.
    /// </summary>
    [Collection("PIWebAPI collection")]
    public class PIWebAPITests : IClassFixture<PIWebAPIFixture>
    {
        internal const string KeySetting = "PIWebAPI";
        internal const TypeCode KeySettingTypeCode = TypeCode.String;
        private const string PIPointName = "OSIsoftTests.Region 0.Wind Farm 00.TUR00000.Random";

        private string _channelMessage = null;

        /// <summary>
        /// Constructor for PIWebAPITests class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage PI Web API connection and specific helper functions.</param>
        public PIWebAPITests(ITestOutputHelper output, PIWebAPIFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private PIWebAPIFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Tests to see if the current patch of PI Web API is applied
        /// </summary>
        /// <remarks>
        /// Errors if the current patch is not applied with a message telling the user to upgrade
        /// </remarks>
        [Fact]
        public void HaveLatestPatchWebAPI()
        {
            var factAttr = new GenericFactAttribute(TestCondition.PIWEBAPICURRENTPATCH, true);
            Assert.NotNull(factAttr);
        }

        /// <summary>
        /// Verifies the PI Web API configuration element is in a good state.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Find 'System Configuration' AF Element (inside PI Web API Fixture)</para>
        /// <para>Verify System Configuration AF Element is not checked out</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void ConfigurationElementTest()
        {
            Output.WriteLine("Find 'System Configuration' AF Element (inside PI Web API Fixture).");
            Assert.True(!Equals(Fixture.ConfigElement, null),
               "Failed to find PI Web API configuration element. If configuration instance is "
               + "different from PI Web API machine name, specify the name in the setting "
               + "PIWebAPIConfigurationInstance.");

            Output.WriteLine("Verify System Configuration AF Element is not checked out.");
            Assert.True(Equals(Fixture.ConfigElement.CheckOutInfo, null),
                $"PI Web API configuration element [{Fixture.ConfigElement.GetPath()}] is checked out.");
        }

        /// <summary>
        /// Verifies PI Web API rejects unauthorized requests.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Save test fixture authentication settings</para>
        /// <para>Set test client to not authenticate</para>
        /// <para>Run GET request against PI Web API</para>
        /// <para>Verify GET request returned 401 Unauthorized</para>
        /// <para>Restore test fixture authentication settings</para>
        /// </remarks>
        [PIWebAPIFact(PIWebAPITestCondition.Authenticate)]
        public void AuthenticationTest()
        {
            var configUrl = $"{Fixture.HomePageUrl}/system/configuration";

            // Save off authentication settings
            var defaultCredentials = Fixture.Client.UseDefaultCredentials;
            var authHeader = Fixture.Client.Headers[HttpRequestHeader.Authorization];

            // Set so authentication should fail
            Output.WriteLine("Set security so authentication fails.");
            Fixture.Client.UseDefaultCredentials = false;
            Fixture.Client.Headers[HttpRequestHeader.Authorization] = string.Empty;
            var code = HttpStatusCode.OK;
            try
            {
                Output.WriteLine($"Try to connect to the configuration page at [{configUrl}].");
                var result = Fixture.Client.DownloadString(configUrl);
            }
            catch (WebException ex)
            {
                code = ((HttpWebResponse)ex.Response).StatusCode;
            }
            finally
            {
                // Restore original values for authentication
                Output.WriteLine("Set security back to original settings.");
                Fixture.Client.UseDefaultCredentials = defaultCredentials;
                Fixture.Client.Headers[HttpRequestHeader.Authorization] = authHeader;
            }

            Assert.True(code == HttpStatusCode.Unauthorized,
                $"Expected to receive an Unauthorized Http status code, got back {code.ToString()}.");
        }

        /// <summary>
        /// Verifies PI Web API CRUD operations against AF Server.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Get test AF Database from PI Web API</para>
        /// <para>Create test Element in AF Database</para>
        /// <para>Update test Element</para>
        /// <para>Read test Element</para>
        /// <para>Add attribute to test Element</para>
        /// <para>Delete test Element</para>
        /// <para>Create test Event Frame in AF Database</para>
        /// <para>Update test Event Frame</para>
        /// <para>Read test Event Frame</para>
        /// <para>Delete test Event Frame</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void AFReadWriteTest()
        {
            var elementName = "OSIsoftTestElement";
            var elementNameEdit = $"{elementName}2";

            Fixture.Client.Headers.Add(HttpRequestHeader.CacheControl, "no-cache");

            // Get Database object from PI Web API to extract its WebId
            var databaseWebIdRequestUrl = $"{Fixture.HomePageUrl}/assetdatabases?path=\\\\{Settings.AFServer}\\{Settings.AFDatabase}";
            Output.WriteLine($"Get database object for [{Settings.AFDatabase}] from Web API at Url [{databaseWebIdRequestUrl}].");
            var databaseData = JObject.Parse(Fixture.Client.DownloadString(databaseWebIdRequestUrl));
            var databaseWebId = (string)databaseData["WebId"];

            // Skip Write/Update portion of test if writes are disabled
            if (Fixture.DisableWrites)
            {
                Output.WriteLine($"Writes are disabled, skipping that portion of the test.");
                return;
            }

            // Create test Element object under test Database
            var createUrl = $"{Fixture.HomePageUrl}/assetdatabases/{databaseWebId}/elements";
            var elementJson = $"{{\"Name\": \"{elementName}\"}}";
            Output.WriteLine($"Create element [{elementName}] under [{Settings.AFDatabase}] through Web API using [{elementJson}] at Url [{createUrl}].");
            Fixture.Client.UploadString(createUrl, "POST", elementJson);

            // Check Element exists in AF
            Output.WriteLine($"Verify element object [{elementName}] exists through Web API.");
            var path = $"\\\\{Settings.AFServer}\\{Settings.AFDatabase}\\{elementName}";
            var foundElements = AFElement.FindElementsByPath(new string[] { path }, Fixture.AFFixture.PISystem);
            var element = foundElements.FirstOrDefault();
            Assert.True(element != null, $"Test Element [{elementName}] was not found in AF.");
            var elementEditJson = $"{{\"Name\": \"{elementNameEdit}\"}}";
            var location = string.Empty;
            try
            {
                // Extract new Element URL off create response headers
                location = Fixture.Client.ResponseHeaders["Location"];

                // Change Element name
                Output.WriteLine($"Rename element object [{elementName}] to [{elementNameEdit}] through Web API.");
                Fixture.Client.UploadString(location, "PATCH", elementEditJson);

                // Check Element was renamed in AF
                element.Refresh();
                Assert.True(element.Name == elementNameEdit, $"Test Element [{elementName}] was not renamed to [{elementNameEdit}] in AF.");

                // Request full Element object from PI Web API to test read, check name value
                Output.WriteLine($"Read full element object [{elementName}] from Web API.");
                var readData = JObject.Parse(Fixture.Client.DownloadString(location));
                Assert.True(string.Equals((string)readData["Name"], elementNameEdit, StringComparison.OrdinalIgnoreCase),
                    $"Test Element [{elementName}] was not renamed to [{elementNameEdit}] in read data.");

                // Create Attribute
                var createAttributeUrl = $"{location}/attributes";
                var attributeJson = $"{{\"Name\":\"Attribute\"}}";
                Output.WriteLine($"Create attribute object 'Attribute' through Web API using [{attributeJson}] at Url [{createAttributeUrl}].");
                Fixture.Client.UploadString(createAttributeUrl, "POST", attributeJson);

                // Check Attribute was added in AF
                element.Refresh();
                Assert.True(element.Attributes.Count == 1, $"Test Attribute 'Attribute' was not created in AF.");
            }
            finally
            {
                // Delete test Element
                Fixture.Client.UploadString(location, "DELETE", string.Empty);
            }

            // Create test Event Frame object under test Database
            createUrl = $"{Fixture.HomePageUrl}/assetdatabases/{databaseWebId}/eventframes";
            Output.WriteLine($"Create event frame object [{element}] through Web API using [{elementJson}] at Url [{createUrl}].");
            Fixture.Client.UploadString(createUrl, "POST", elementJson);

            // Check Event Frame exists in AF
            path = $"\\\\{Settings.AFServer}\\{Settings.AFDatabase}\\EventFrames[{elementName}]";
            var foundEvents = AFEventFrame.FindEventFramesByPath(new string[] { path }, Fixture.AFFixture.PISystem);
            var eventFrame = foundEvents.FirstOrDefault();
            Assert.True(eventFrame != null, $"Test Event Frame [{elementName}] was not found in AF.");

            try
            {
                // Extract new Event Frame URL off create response headers
                location = Fixture.Client.ResponseHeaders["Location"];

                // Change Event Frame name
                Output.WriteLine($"Rename event frame object [{elementName}] to [{elementEditJson}] through Web API.");
                Fixture.Client.UploadString(location, "PATCH", elementEditJson);

                // Check Event Frame was renamed in AF
                eventFrame.Refresh();
                Assert.True(eventFrame.Name == elementNameEdit, $"Test Event Frame [{elementName}] was not renamed to [{elementNameEdit}] in AF.");

                // Request full Event Frame object from PI Web API to test read, check name value
                Output.WriteLine($"Read full event frame object [{elementName}] from Web API.");
                var readData = JObject.Parse(Fixture.Client.DownloadString(location));
                Assert.True(string.Equals((string)readData["Name"], elementNameEdit, StringComparison.OrdinalIgnoreCase),
                    $"Test Event Frame [{elementName}] was not renamed to [{elementNameEdit}] in read data.");
            }
            finally
            {
                // Delete test Event Frame
                Fixture.Client.UploadString(location, "DELETE", string.Empty);
            }

            Fixture.Client.Headers.Remove(HttpRequestHeader.CacheControl);
        }

        /// <summary>
        /// Verifies PI Web API CRUD operations against PI Data Archive.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Get test Data Archive from PI Web API</para>
        /// <para>Create test PI Point in Data Archive</para>
        /// <para>Update test PI Point name</para>
        /// <para>Read test PI Point data</para>
        /// <para>Delete test PI Point</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void DAReadWriteTest()
        {
            PIServer piServer = Fixture.PIFixture.PIServer;
            var piPointName = "OSIsoftTestPoint";
            var piPointNameEdit = $"{piPointName}2";

            // Get Data Archive object from PI Web API to extract its WebId
            var dataArchiveUrl = $"{Fixture.HomePageUrl}/dataservers?path=\\PIServers[{Settings.PIDataArchive}]";
            Output.WriteLine($"Get Data Archive data through Web API using Url [{dataArchiveUrl}].");
            var dataArchiveData = JObject.Parse(Fixture.Client.DownloadString(dataArchiveUrl));

            // Skip Write/Update portion of test if writes are disabled
            if (Fixture.DisableWrites) return;

            // Create a test PI Point
            var createUrl = $"{Fixture.HomePageUrl}/dataservers/{(string)dataArchiveData["WebId"]}/points";
            Output.WriteLine($"Create PI Point [{piPointName}] through Web API using Url [{createUrl}]");
            Fixture.Client.UploadString(createUrl, "POST", $"{{\"Name\": \"{piPointName}\", \"PointClass\": \"classic\", \"PointType\": \"Float32\"}}");

            // Check PI Point exists in DA
            var point = PIPoint.FindPIPoint(piServer, piPointName);
            Assert.True(point != null, $"Test PI Point [{piPointName}] was not found in Data Archive.");

            var location = string.Empty;
            try
            {
                // Extract new PI Point URL off create response headers
                location = Fixture.Client.ResponseHeaders["Location"];

                // Change PI Point name
                Output.WriteLine($"Change PI Point name from [{piPointName}] to [{piPointNameEdit}].");
                Fixture.Client.UploadString(location, "PATCH", $"{{\"Name\": \"{piPointNameEdit}\"}}");

                // Check PI Point is renamed in DA
                point = PIPoint.FindPIPoint(piServer, piPointNameEdit);
                Assert.True(point != null, $"Test PI Point [{piPointNameEdit}] was not found in Data Archive.");

                // Request full PI Point object from PI Web API to test read, check name value
                var piPointData = JObject.Parse(Fixture.Client.DownloadString(location));
                Output.WriteLine($"Read PI Point through Web API using Url [{location}].");
                Assert.True(string.Equals((string)piPointData["Name"], piPointNameEdit, StringComparison.OrdinalIgnoreCase),
                    $"Test PI Point has incorrect value for Name. Expected: [{piPointNameEdit}], Actual: [{(string)piPointData["Name"]}]");
            }
            finally
            {
                // Delete test PI Point
                Fixture.Client.UploadString(location, "DELETE", string.Empty);
            }
        }

        /// <summary>
        /// Verifies Stream Updates functionality.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Get test Data Archive from PI Web API</para>
        /// <para>Get test PI Point in Data Archive</para>
        /// <para>Get marker for stream updates for PI Point</para>
        /// <para>Wait for new value to be added for stream</para>
        /// <para>Get stream updates using marker, verify new value is included</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void StreamUpdatesTest()
        {
            var testStart = DateTime.UtcNow;

            // Get Data Archive object from PI Web API to extract its WebId
            var dataArchiveUrl = $"{Fixture.HomePageUrl}/dataservers?path=\\\\PIServers[{Settings.PIDataArchive}]";
            Output.WriteLine($"Get Data Archive data through Web API using Url [{dataArchiveUrl}].");
            var dataArchiveData = JObject.Parse(Fixture.Client.DownloadString(dataArchiveUrl));

            // Verifies test PI Point is found
            var piPointUrl = $"{Fixture.HomePageUrl}/dataservers/{(string)dataArchiveData["WebId"]}/points?nameFilter={PIPointName}";
            Output.WriteLine($"Get PI Point data for [{PIPointName}] through Web API using Url [{piPointUrl}].");
            var piPointData = JObject.Parse(Fixture.Client.DownloadString(piPointUrl));
            Assert.True(piPointData["Items"].Count() > 0, $"Could not find test PI Point [{PIPointName}].");
            var webId = piPointData["Items"][0]["WebId"].ToString();

            var streamUrl = $"{Fixture.HomePageUrl}/streams/{webId}";
            var registerUrl = $"{streamUrl}/updates";
            var response = Fixture.Client.UploadString(registerUrl, "POST", string.Empty);
            var registerData = JObject.Parse(response);
            var marker = (string)registerData["LatestMarker"];

            // Wait for value to update from analysis
            var updatesUrl = $"{Fixture.HomePageUrl}/streams/updates/{marker}";

            // Request stream updates using marker every 5 seconds until new events received and verify new value found in updates
            Output.WriteLine($"Get stream updates through Web API using Url [{updatesUrl}].");
            var waitTimeInSeconds = 60;
            var pollIntervalInSeconds = 5;
            AssertEventually.True(
                () => JObject.Parse(Fixture.Client.DownloadString(updatesUrl))["Events"].ToObject<List<JObject>>().Count() > 0,
                TimeSpan.FromSeconds(waitTimeInSeconds),
                TimeSpan.FromSeconds(pollIntervalInSeconds),
                "No new events received via stream updates.");

            Output.WriteLine($"Verify new value in stream updates.");
            AssertEventually.True(
                () =>
                {
                    var updateData = JObject.Parse(Fixture.Client.DownloadString(updatesUrl));
                    var updateEvents = updateData["Events"].ToObject<List<JObject>>();

                    var updateEvent = updateEvents.Last();
                    var timeStamp = (DateTime)updateEvent["Timestamp"];
                    return timeStamp > testStart;
                },
                TimeSpan.FromSeconds(waitTimeInSeconds),
                TimeSpan.FromSeconds(pollIntervalInSeconds),
                $"Test failed to retrieve a stream updates event with a timestamp after test start time [{testStart}] within {waitTimeInSeconds} seconds. " +
                    $"This may indicate that the data ingress for {PIPointName} to PI Data Archive was delayed, or a longer CalculationWaitTimeInSeconds " +
                    $"has been set in Analysis Service Configuration.");
        }

        /// <summary>
        /// Verifies Channel functionality in PI Web API.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Find a known PI Point whose value will be updated during the test</para>
        /// <para>Open a channel via websocket to the PI Point's stream</para>
        /// <para>Check data received from channel</para>
        /// <para>Close channel to stream</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void ChannelsTest()
        {
            var testStart = DateTime.UtcNow;

            // Get Data Archive object from PI Web API to extract its WebId
            var dataArchiveUrl = $"{Fixture.HomePageUrl}/dataservers?path=\\PIServers[{Settings.PIDataArchive}]";
            Output.WriteLine($"Get Data Archive data through Web API using Url [{dataArchiveUrl}].");
            var dataArchiveData = JObject.Parse(Fixture.Client.DownloadString(dataArchiveUrl));

            // Verifies test PI Point is found
            var piPointUrl = $"{Fixture.HomePageUrl}/dataservers/{(string)dataArchiveData["WebId"]}/points?nameFilter={PIPointName}";
            Output.WriteLine($"Get PI Point data for [{PIPointName}] through Web API using Url [{piPointUrl}].");
            var piPointData = JObject.Parse(Fixture.Client.DownloadString(piPointUrl));
            Assert.True(piPointData["Items"].Count() > 0, $"Could not find test PI Point [{PIPointName}].");
            var webId = piPointData["Items"][0]["WebId"].ToString();

            Output.WriteLine($"Open channel to a stream for PI Point data for [{PIPointName}].");
            var waitTimeInSeconds = 60;
            var pollIntervalInSeconds = 5;
            AssertEventually.True(
                () =>
                {
                    using (var cancellationSource = new CancellationTokenSource())
                    {
                        var runTask = ReadChannelData(webId, cancellationSource.Token);
                        var timeOutSeconds = waitTimeInSeconds;
                        var taskCompleted = runTask.Wait(TimeSpan.FromSeconds(timeOutSeconds));
                        Assert.True(taskCompleted, $"The channel for [{PIPointName}] did not return data from its stream in the allotted time frame ({timeOutSeconds} seconds).");
                    }

                    Assert.True(_channelMessage != null, $"The channel for [{PIPointName}] did not return data from its stream.");
                    var updateEvent = JObject.Parse(_channelMessage);
                    var timeStamp = (DateTime)updateEvent["Items"][0]["Items"][0]["Timestamp"];

                    return timeStamp > testStart;
                },
                TimeSpan.FromSeconds(waitTimeInSeconds),
                TimeSpan.FromSeconds(pollIntervalInSeconds),
                $"Test failed to retrieve a channel event with a timestamp after test start time [{testStart}] within {waitTimeInSeconds} seconds. " +
                    $"This may indicate that the data ingress for {PIPointName} to PI Data Archive was delayed, or a longer CalculationWaitTimeInSeconds " +
                    $"has been set in Analysis Service Configuration.");
        }

        /// <summary>
        /// Verifies that types can be created and deleted using OMF. Skip this test if OMF is not installed.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Define json strings for a type, container, and data ingress</para>
        /// <para>Set the headers needed to create a type against the OMF endpoint</para>
        /// <para>Send the json data to the OMF endpoint to create a type, container, and data</para>
        /// <para>Verify an OperationId was returned in the response</para>
        /// <para>Verify objects were created in AF and PI</para>
        /// <para>Delete the type, container, and data that was created</para>
        /// <para>Verify the response for the delete is empty</para>
        /// <para>Verify objects were deleted in AF and PI</para>
        /// </remarks>
        [PIWebAPIFact(PIWebAPITestCondition.Omf)]
        public void OMFTest()
        {
            // Use ticks as a unique id mask to avoid naming collisions with other PI Points
            var idTicks = $"{DateTime.UtcNow.Ticks}";
            string typeId = $"TankMeasurement{idTicks}";
            string containerId = $"Tank1Measurements{idTicks}";
            PISystem omfAFServer = null;
            AFDatabase omfDatabase = null;
            PIServer omfPIServer = null;
            List<PIPoint> omfPIPoints = null;
            AFElementTemplate omfTypeAsTemplate = null;
            var jsonType = @"[
                {
                    ""id"": """ + typeId + @""",
                    ""version"": ""1.0.0.0"",
                    ""type"": ""object"",
                    ""classification"": ""dynamic"",
                    ""properties"": {
                            ""Time"": {
                                ""format"": ""date-time"",
                                    ""type"": ""string"",
                                    ""isindex"": true
                            },
                            ""Pressure"": {
                                ""type"": ""number"",
                                    ""name"": ""Tank Pressure""
                            },
                            ""Temperature"": {
                                ""type"": ""number"",
                                    ""name"": ""Tank Temperature""
                            }
                        }
                    }
                ]";

            var jsonContainer = @"[{
                ""id"": """ + containerId + @""",
                ""typeid"": """ + typeId + @""",
                ""typeVersion"": ""1.0.0.0"",
                ""indexes"": [""Pressure""]
            }]";

            var jsonData = @"[{
                    ""containerid"": """ + containerId + @""",
                    ""values"": [{
                            ""Time"": ""2017-01-11T22:24:23.430Z"",
                            ""Pressure"": 11.5,
                            ""Temperature"": 101
                    }]
            }]";

            var coll = new NameValueCollection
            {
                { "messagetype", "type" },
                { "messageformat", "json" },
                { "omfversion", "1.1" },
                { "action", "create" },
            };

            try
            {
                // Create the type object
                var omfUrl = $"{Fixture.HomePageUrl}/omf";
                Fixture.Client.Headers.Add(coll);
                Output.WriteLine($"Create OMF type through Web API using Url [{omfUrl}] and JSON [{jsonType}].");
                var createTypeResponse = JObject.Parse(Fixture.Client.UploadString(omfUrl, "POST", jsonType));
                Assert.True(createTypeResponse["OperationId"] != null, $"OperationId not returned in OMF response.");

                // Create a container for the created type
                Fixture.Client.Headers["messagetype"] = "container";
                Output.WriteLine($"Create OMF container through Web API using Url [{omfUrl}] and JSON [{jsonContainer}].");
                var createContainerResponse = JObject.Parse(Fixture.Client.UploadString(omfUrl, "POST", jsonContainer));
                Assert.True(createContainerResponse["OperationId"] != null, "OperationId not returned in OMF response.");

                // Add data to the container
                Fixture.Client.Headers["messagetype"] = "data";
                Output.WriteLine($"Add data to the OMF container through Web API using Url [{omfUrl}] and JSON [{jsonData}].");
                var createDataResponse = JObject.Parse(Fixture.Client.UploadString(omfUrl, "POST", jsonData));
                Assert.True(createDataResponse["OperationId"] != null, "OperationId not returned in OMF response.");

                // Verify objects were created correctly in AF and PI
                var instanceConfigUrl = $"{Fixture.HomePageUrl}/system/instanceconfiguration";
                var config = JObject.Parse(Fixture.Client.DownloadString(instanceConfigUrl));
                Output.WriteLine($"Verify OMF objects were create in AF and PI through Web API using Url [{instanceConfigUrl}].");
                omfAFServer = new PISystems()[(string)config["OmfAssetServerName"]];
                omfDatabase = omfAFServer.Databases[(string)config["OmfAssetDatabaseName"]];
                omfPIServer = PIServers.GetPIServers()[(string)config["OmfDataArchiveName"]];
                if (omfPIServer.ConnectionInfo == null)
                    omfPIServer.Connect();

                var typeInAF = omfDatabase.ElementTemplates[typeId];
                Assert.True(typeInAF != null, $"The OMF Type [{typeId}] should exist as an ElementTemplate in [{omfDatabase}] on [{omfAFServer}].");

                var pointFound = PIPoint.TryFindPIPoint(omfPIServer, $"{containerId}.Pressure", out var piPointPressure);
                Assert.True(pointFound, $"PI Point [{containerId}.Pressure] not found in [{omfPIServer.Name}].");
                Assert.True(piPointPressure.CurrentValue().ValueAsSingle() == 11.5,
                    $"Value for PI Point [{containerId}.Pressure] incorrect. Expected: [11.5], Actual: [{piPointPressure.CurrentValue().ValueAsSingle()}].");
                pointFound = PIPoint.TryFindPIPoint(omfPIServer, $"{containerId}.Temperature", out var piPointTemperature);
                Assert.True(pointFound, $"PI Point [{containerId}.Temperature] not found in [{omfPIServer.Name}].");
                Assert.True(piPointTemperature.CurrentValue().ValueAsInt32() == 101,
                    $"Value for PI Point [{containerId}.Temperature] incorrect. Expected: [101], Actual: [{piPointTemperature.CurrentValue().ValueAsInt32()}].");

                // Delete the data
                Output.WriteLine("Delete OMF data.");
                Fixture.Client.Headers["action"] = "delete";
                var deleteDataResponse = JObject.Parse(Fixture.Client.UploadString(omfUrl, "POST", jsonData));
                Assert.True(deleteDataResponse["OperationId"] != null, "OperationId not returned in OMF response.");

                // Delete the container
                Fixture.Client.Headers["messagetype"] = "container";
                var deleteContainerResponse = JObject.Parse(Fixture.Client.UploadString(omfUrl, "POST", jsonContainer));
                Assert.True(deleteContainerResponse["OperationId"] != null, "OperationId not returned in OMF response.");

                // Delete the type
                Fixture.Client.Headers["messagetype"] = "type";
                var deleteTypeResponse = JObject.Parse(Fixture.Client.UploadString(omfUrl, "POST", jsonType));
                Assert.True(deleteTypeResponse["OperationId"] != null, "OperationId not returned in OMF response.");

                // Verify objects were deleted. Remove objects that were not deleted before Assert to ensure cleanup
                omfPIPoints = PIPoint.FindPIPoints(omfPIServer, $"{containerId}*", null, null).ToList();
                omfDatabase.ElementTemplates.Refresh();
                omfTypeAsTemplate = omfDatabase.ElementTemplates[typeId];

                Assert.True(omfPIPoints.Count == 0, "PIPoints were not deleted by the DELETE CONTAINER request to OMF.");
                Assert.True(omfTypeAsTemplate == null, $"The OMF Type [{typeId}] was not deleted by the DELETE TYPE request to OMF.");
            }
            catch (WebException ex)
            {
                var httpResponse = (HttpWebResponse)ex.Response;
                var statusCode = string.Empty;
                if (httpResponse.StatusCode != HttpStatusCode.OK &&
                    httpResponse.StatusCode != HttpStatusCode.Accepted &&
                    httpResponse.StatusCode != HttpStatusCode.NoContent)
                {
                    statusCode = $"{httpResponse.StatusCode}: {httpResponse.StatusDescription}";
                }

                // For troubleshooting error response codes returned by PI Web API
                using (var reader = new StreamReader(ex.Response.GetResponseStream()))
                {
                    var response = JObject.Parse(reader.ReadToEnd())["Messages"]?[0]["Events"]?[0]["Message"]?.ToString();
                    if (!string.IsNullOrEmpty(response))
                        Assert.True(false, $"Error returned from OMF: {response}. {statusCode}.");
                    else
                        throw;
                }
            }
            finally
            {
                // Clean up any existing OMF objects if not deleted by OMF
                if (omfPIServer != null)
                {
                    if (omfPIServer.ConnectionInfo == null)
                        omfPIServer.Connect();
                    omfPIPoints = PIPoint.FindPIPoints(omfPIServer, $"{containerId}*", null, null).ToList();
                    bool pointsDeleted = omfPIPoints.Count == 0;
                    if (!pointsDeleted)
                    {
                        omfPIServer.DeletePIPoints(omfPIPoints.Select(p => p.Name).ToList());
                    }
                }

                if (omfAFServer != null && omfDatabase != null)
                {
                    omfTypeAsTemplate = omfDatabase.ElementTemplates[typeId];
                    bool typeDeleted = omfTypeAsTemplate == null;
                    if (!typeDeleted)
                    {
                        AFElementTemplate.DeleteElementTemplates(omfAFServer, new List<Guid> { omfTypeAsTemplate.ID });
                    }
                }
            }
        }

        /// <summary>
        /// Verifies that the Indexed Search Crawler service is running.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Determine whether to check PI Web API machine or specific crawler machine</para>
        /// <para>Call utility service to verify that the crawler service is running</para>
        /// </remarks>
        [PIWebAPIFact(PIWebAPITestCondition.IndexedSearch)]
        public void IndexedSearchTest()
        {
            string machine = Settings.PIWebAPICrawler;
            if (string.IsNullOrEmpty(machine))
            {
                // No crawler machine specified, use PI Web API setting and strip off any domain name
                machine = Settings.PIWebAPI.Split('.')[0];
            }

            Output.WriteLine($"Check if the PI Crawler service is running on [{machine}].");
            Utils.CheckServiceRunning(machine, "picrawler", Output);
        }

        /// <summary>
        /// Open a websocket connection to a stream's channel in PI Web API.
        /// </summary>
        /// <param name="webId">WebId of the stream.</param>
        /// <param name="cancellationToken">CancellationToken for websocket.</param>
        /// <returns>True if the task completes in the allotted time given, false otherwise.</returns>
        private async Task ReadChannelData(string webId, CancellationToken cancellationToken)
        {
            var channelUri = new Uri($"wss://{Settings.PIWebAPI}/piwebapi/streams/{webId}/channel");
            WebSocketReceiveResult receiveResult;
            var receiveBuffer = new byte[65535];
            var receivedSegment = new ArraySegment<byte>(receiveBuffer);
            string message = null;

            using (var webSocket = new ClientWebSocket())
            {
                // Open the websocket connection as the user running the test
                webSocket.Options.UseDefaultCredentials = Fixture.Client.UseDefaultCredentials;
                
                if (!Fixture.Client.UseDefaultCredentials)
                {
                    webSocket.Options.Credentials = new NetworkCredential(Settings.PIWebAPIUser, Settings.PIWebAPIPassword);
                }

                await webSocket.ConnectAsync(channelUri, cancellationToken).ConfigureAwait(false);

                // Reads data from channel via websocket. Verifies result is the correct type and length
                while (message == null)
                {
                    try
                    {
                        receiveResult = await webSocket.ReceiveAsync(receivedSegment, cancellationToken).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }

                    if (receiveResult.MessageType != WebSocketMessageType.Text)
                    {
                        await webSocket.CloseAsync(WebSocketCloseStatus.InvalidMessageType, "Message type is not text", CancellationToken.None).ConfigureAwait(false);
                        return;
                    }
                    else if (receiveResult.Count > receiveBuffer.Length)
                    {
                        await webSocket.CloseAsync(WebSocketCloseStatus.InvalidPayloadData, "Message is too long", CancellationToken.None).ConfigureAwait(false);
                        return;
                    }

                    message = Encoding.UTF8.GetString(receiveBuffer, 0, receiveResult.Count);
                }

                await webSocket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "Closing connection", CancellationToken.None).ConfigureAwait(false);
                _channelMessage = message;
                return;
            }
        }
    }
}
