using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using Newtonsoft.Json.Linq;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// The Vision3Fixture is a partial test context class to be shared in Vision3 related
    /// xUnit test classes.
    /// </summary>
    /// <remarks>
    /// xUnit.net ensures that the fixture instance will be created before any tests run and
    /// when all tests are done will clean up the fixture object with 'Dispose' call.
    /// This fixture includes helper functions isolated to PI DataArchive related calls.
    /// See Utils.cs for more general test helper functions.
    /// </remarks>
    public sealed class Vision3Fixture : IDisposable
    {
        /// <summary>
        /// DateTime format string used to create unique text in the tests.
        /// </summary>
        public const string DateTimeFormat = "yyyy-MM-dd-HHmmssfff";

        /// <summary>
        /// A string describing common issues users may encounter in PI Vision testing.
        /// </summary>
        public const string CommonVisionIssues = "Verify that IIS and the PI Vision web site are running, " +
            "PI Vision is configured correctly, and the running user is in PI Vision Admins group.";

        /// <summary>
        /// Keyword used to find the verification token in the http response.
        /// </summary>
        private const string RequestVerificationTokenKeyword = "RequestVerificationToken";

        /// <summary>
        /// Name of the folder where test displays will be saved.
        /// </summary>
        private const string TestFolderName = "OSIsoftTests_Displays";

        /// <summary>
        /// Client handler for the HttpClient object.
        /// </summary>
        private static readonly HttpClientHandler _handler = new HttpClientHandler() { UseDefaultCredentials = true };

        /// <summary>
        /// Constructor for Vision3Fixture class
        /// </summary>
        public Vision3Fixture()
        {
            CreateNewHttpClient(Settings.PIVisionServer, _handler);
        }

        /// <summary>
        /// HttpClient to hit PI Vision endpoints.
        /// </summary>
        public HttpClient Client { get; private set; }

        /// <summary>
        /// Session token required to post to endpoints.
        /// </summary>
        private string VerificationToken { get; set; }

        /// <summary>
        /// Id of the folder where test displays are saved.
        /// </summary>
        private string TestFolderId { get; set; }

        /// <summary>
        /// Dictionary of display objects by Id.
        /// </summary>
        private Dictionary<string, JObject> Displays { get; } = new Dictionary<string, JObject>();

        /// <summary>
        /// Get a unique display name incorporating the current time.
        /// </summary>
        /// <returns>Unique name string.</returns>
        public string GetUniqueDisplayName()
        {
            string uniqueText = DateTime.UtcNow.ToString(DateTimeFormat, CultureInfo.InvariantCulture);
            return $"OSIsoftTests_Vision3Display_{uniqueText}";
        }

        /// <summary>
        /// Get verification token required to post changes to the server.
        /// </summary>
        /// <returns>Task representing the asynchronous operation.</returns>
        public async System.Threading.Tasks.Task<HttpResponseMessage> GetVerificationToken()
        {
            using (var requestMessage
                    = new HttpRequestMessage(HttpMethod.Get, Client.BaseAddress))
            {
                var response = await Client.SendAsync(requestMessage).ConfigureAwait(false);
                var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                if (response.RequestMessage.RequestUri != Client.BaseAddress)
                {
                    CreateNewHttpClient(response.RequestMessage.RequestUri.ToString(), _handler);
                }

                using (var reader = new StringReader(contents))
                {
                    string currentLine = reader.ReadLine();
                    while (currentLine != null && !currentLine.Contains(RequestVerificationTokenKeyword + ':'))
                    {
                        currentLine = reader.ReadLine();
                    }

                    if (currentLine != null)
                    {
                        var split = currentLine.Split(new char[] { '=', ' ', ';', '\'' }, StringSplitOptions.RemoveEmptyEntries);
                        VerificationToken = split[1];
                    }
                }

                return response;
            }
        }

        /// <summary>
        /// Post a vision display to the server for saving.
        /// </summary>
        /// <param name="displayName">Name of the display to save.</param>
        /// <returns>Task representing the asynchronous operation.</returns>
        public async System.Threading.Tasks.Task<HttpResponseMessage> PostSaveDisplay(string displayName)
        {
            if (VerificationToken == null)
            {
                using (await GetVerificationToken().ConfigureAwait(false)) { }
            }

            if (TestFolderId == null)
            {
                using (await FindOrCreateTestFolder().ConfigureAwait(false)) { }
            }

            var displayContent = CreateDisplayJson(displayName);

            var content = new StringContent(displayContent, Encoding.UTF8, "application/json");
            using (var httpRequestMessage = new HttpRequestMessage
            {
                Method = HttpMethod.Post,
                RequestUri = new Uri(Client.BaseAddress + "Displays/SaveDisplay"),
                Headers =
                {
                    { HttpRequestHeader.Accept.ToString(), "application/json" },
                    { "X-Requested-With", "XMLHttpRequest" },
                    { RequestVerificationTokenKeyword, VerificationToken },
                },
                Content = content,
            })
            {
                var response = await Client.SendAsync(httpRequestMessage).ConfigureAwait(false);
                var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                var o = JObject.Parse(contents);
                o.GetValue("DisplayId", StringComparison.OrdinalIgnoreCase);
                o.GetValue("RequestId", StringComparison.OrdinalIgnoreCase);
                Displays.Add(displayName, o);
                return response;
            }
        }

        /// <summary>
        /// Post a vision display to the server for deletion.
        /// </summary>
        /// <param name="displayName">Name of the display to delete.</param>
        /// <returns>Task representing the asynchronous operation.</returns>
        public async System.Threading.Tasks.Task<HttpResponseMessage> PostDeleteDisplay(string displayName)
        {
            if (VerificationToken == null)
            {
                using (await GetVerificationToken().ConfigureAwait(false)) { }
            }

            var displayId = Displays[displayName].GetValue("DisplayId", StringComparison.OrdinalIgnoreCase).Value<int>();
            using (var httpRequestMessage = new HttpRequestMessage
            {
                Method = HttpMethod.Delete,
                RequestUri = new Uri(Client.BaseAddress + "Services/Displays/" + displayId),
                Headers =
                {
                    { HttpRequestHeader.Accept.ToString(), "application/json" },
                    { "X-Requested-With", "XMLHttpRequest" },
                    { RequestVerificationTokenKeyword, VerificationToken },
                },
            })
            {
                var response = await Client.SendAsync(httpRequestMessage).ConfigureAwait(false);
                if (response.StatusCode == HttpStatusCode.NoContent)
                    Displays.Remove(displayName);
                return response;
            }
        }

        /// <summary>
        /// Post a vision display folder to the server for deletion.
        /// </summary>
        /// <param name="displayName">Name of the display to delete.</param>
        /// <returns>Task representing the asynchronous operation.</returns>
        public async System.Threading.Tasks.Task<HttpResponseMessage> PostDeleteDisplayFolder()
        {
            if (TestFolderId == null)
            {
                return new HttpResponseMessage(HttpStatusCode.Continue);
            }

            if (VerificationToken == null)
            {
                using (await GetVerificationToken().ConfigureAwait(false)) { }
            }

            using (var httpRequestMessage = new HttpRequestMessage
            {
                Method = HttpMethod.Delete,
                RequestUri = new Uri(Client.BaseAddress + "Navigation/VisionFolder/" + TestFolderId),
                Headers =
                {
                    { HttpRequestHeader.Accept.ToString(), "application/json" },
                    { "X-Requested-With", "XMLHttpRequest" },
                    { RequestVerificationTokenKeyword, VerificationToken },
                },
            })
            {
                return await Client.SendAsync(httpRequestMessage).ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Get a vision display from the server for editing.
        /// </summary>
        /// <param name="displayName">Name of the display to open.</param>
        /// <returns>Task representing the asynchronous operation.</returns>
        public async System.Threading.Tasks.Task<HttpResponseMessage> OpenEditDisplay(string displayName)
        {
            var displayId = Displays[displayName].GetValue("DisplayId", StringComparison.OrdinalIgnoreCase).Value<int>();
            using (var httpRequestMessage = new HttpRequestMessage
            {
                Method = HttpMethod.Get,
                RequestUri = new Uri(Client.BaseAddress + "Displays/" + displayId + "/OpenEditDisplay"),
                Headers =
                {
                    { HttpRequestHeader.Accept.ToString(), "application/json" },
                    { "X-Requested-With", "XMLHttpRequest" },
                    { RequestVerificationTokenKeyword, VerificationToken },
                },
            })
            {
                return await Client.SendAsync(httpRequestMessage).ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Post a vision display to the server to receive data.
        /// </summary>
        /// <param name="displayName">Name of the display to get data.</param>
        /// <returns>Task representing the asynchronous operation.</returns>
        public async System.Threading.Tasks.Task<HttpResponseMessage> PostDiffForData(string displayName)
        {
            string json = @"{
                Changes: [],
                EndTime: '*',
                ForceUpdate: true,
                IncludeMetadata: false,
                StartTime: '*-8h',
                TZ: 'America/New_York'
            }";

            if (VerificationToken == null)
            {
                using (await GetVerificationToken().ConfigureAwait(false)) { }
            }

            var requestId = Displays[displayName].GetValue("RequestId", StringComparison.OrdinalIgnoreCase).Value<string>();
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            using (var httpRequestMessage = new HttpRequestMessage
            {
                Method = HttpMethod.Post,
                RequestUri = new Uri(Client.BaseAddress + "Data/" + requestId + "/DiffForData"),
                Headers =
                {
                    { HttpRequestHeader.Accept.ToString(), "application/json" },
                    { "X-Requested-With", "XMLHttpRequest" },
                    { RequestVerificationTokenKeyword, VerificationToken },
                },
                Content = content,
            })
            {
                return await Client.SendAsync(httpRequestMessage).ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Remove any displays that have been saved from the database.
        /// </summary>
        /// <returns>Task representing the asynchronous operation.</returns>
        public async System.Threading.Tasks.Task CleanUpDisplays()
        {
            var keys = (from k in Displays.Keys select k).ToList();
            foreach (string key in keys)
            {
                using (await PostDeleteDisplay(key).ConfigureAwait(false)) { }
            }
        }

        /// <summary>
        /// Dispose of the HttpClient once the tests are complete.
        /// </summary>
        public void Dispose()
        {
            var response = PostDeleteDisplayFolder().Result;
            response.Dispose();
            _handler.Dispose();
            Client.Dispose();
        }

        /// <summary>
        /// Get permissions for a folder from server.
        /// </summary>
        /// <param name="folderId">Id of the folder to get permissions.</param>
        /// <returns>Task representing the asynchronous operation.</returns>
        internal async System.Threading.Tasks.Task<HttpResponseMessage> GetFolderPermissions(string folderId)
        {
            if (VerificationToken == null)
            {
                using (await GetVerificationToken().ConfigureAwait(false)) { }
            }

            using (var httpRequestMessage = new HttpRequestMessage
            {
                Method = HttpMethod.Get,
                RequestUri = new Uri(Client.BaseAddress + "Navigation/FolderPermissions?elementId=" + folderId),
                Headers =
                {
                    { HttpRequestHeader.Accept.ToString(), "application/json" },
                    { "X-Requested-With", "XMLHttpRequest" },
                    { RequestVerificationTokenKeyword, VerificationToken },
                },
            })
            {
                return await Client.SendAsync(httpRequestMessage).ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Find Id of test folder or create it if it doesn't exist.
        /// </summary>
        /// <returns>Task representing the asynchronous operation.</returns>
        internal async System.Threading.Tasks.Task<HttpResponseMessage> FindOrCreateTestFolder()
        {
            var response = await Client.GetAsync("Services/Repository/FolderChildren").ConfigureAwait(false);
            var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
            var o = JObject.Parse(contents);
            var homeFolder = (JObject)o.GetValue("Folders", StringComparison.OrdinalIgnoreCase).First;
            if (homeFolder != null)
            {
                foreach (JObject f in homeFolder.GetValue("Children", StringComparison.OrdinalIgnoreCase))
                {
                    if (f.GetValue("Name", StringComparison.OrdinalIgnoreCase).Value<string>() == TestFolderName)
                    {
                        TestFolderId = f.GetValue("DisplayFolderId", StringComparison.OrdinalIgnoreCase).Value<string>();
                    }
                }
            }

            if (TestFolderId == null)
            {
                using (await CreateTestFolder().ConfigureAwait(false)) { }
            }

            return response;
        }

        /// <summary>
        /// Creates a new httpClient.
        /// </summary>
        /// <param name="url">Url for the base address.</param>
        /// <param name="handler">Client handler for the HttpClient object.</param>
        private void CreateNewHttpClient(string url, HttpClientHandler handler)
        {
            Client = new HttpClient(handler);
            Client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json")); // ACCEPT header

            // Remove trailing /#/ that may be on this address as an anchor point for some browser operations
            if (url.EndsWith("/#/", StringComparison.OrdinalIgnoreCase))
                url = url.Substring(0, url.Length - 3);

            Client.BaseAddress = new Uri(url.TrimEnd('/') + "/");
        }

        /// <summary>
        /// Create JSON string for a test display.
        /// </summary>
        /// <param name="displayName">Name of the created display.</param>
        /// <returns>JSON string representing a test display.</returns>
        private string CreateDisplayJson(string displayName)
        {
            string json = @"{
                'Attachments': [],
                CurrentElement: null,
                Display: {
                    EventFramePath: null,
                    Id: -1,
                    Name: '" + displayName + @"',
                    RequestId: '6751e210-4ca5-4d76-a113-466fbf58fa4b',
                    Revision: 1,
                    symbols: [{
                        Configuration: {
                            DataShape: 'Value',
                            Height: 56.5,
                            Left: 140,
                            TextAlignment: 'left',
                            Top: 212,
                        },
                        DataSources: ['af:\\\\" + Settings.AFServer + @"\\" + Settings.AFDatabase + @"\\Region 0\\Wind Farm 00\\TUR00000|Elevation'],
                        Name: 'Symbol0',
                        SymbolType: 'value',
                    },
                    {
                        Configuration: {
                            BorderColor: '#fff',
                            BorderWidth: 3,
                            DataShape: 'Gauge',
                            Height: 200,
                            IndicatorType: 'pointer',
                            LabelLocation: 'bottom',
                            Left: 89,
                            ShowLabel: true,
                            ShowUOM: true,
                            ShowValue: true,
                            Top: 80,
                            Width: 200
                        },
                        DataSources: ['af:\\\\" + Settings.AFServer + @"\\" + Settings.AFDatabase + @"\\Region 0\\Wind Farm 00\\TUR00000|Elevation'],
                        Name: 'Symbol1',
                        SymbolType: 'radialgauge',
                    },
                    {
                        Configuration: {
                            DataShape: 'Trend',
                            Height: 56.5,
                            Left: 140,
                            TextAlignment: 'left',
                            Top: 212,
                            Width: 200,
                            TrendConfig: {
	                            LegendWidth: 120,
	                            nowPosition: true,
	                            padding: 2,
	                            timeScale: {axis: true, tickMarks: true},
	                            valueScale: {axis: false, tickMarks: true, bands: true, padding: 2}
                            },
                            ValueScaleSetting: {MinType: 0, MaxType: 0}
                        },
                        DataSources: ['af:\\\\" + Settings.AFServer + @"\\" + Settings.AFDatabase + @"\\Region 0\\Wind Farm 00\\TUR00000|Elevation'],
                        Name: 'Symbol2',
                        SymbolType: 'trend',
                    }],
                },
                EndTime: '*',
                EventFramePath: null,
                FolderId: " + TestFolderId + @",
                StartTime: '*-8h',
                TZ: 'America/New_York'
            }";
            return json;
        }

        /// <summary>
        /// Create folder for test displays.
        /// </summary>
        /// <returns>Task representing the asynchronous operation.</returns>
        private async System.Threading.Tasks.Task<HttpResponseMessage> CreateTestFolder()
        {
            if (VerificationToken == null)
            {
                using (await GetVerificationToken().ConfigureAwait(false)) { }
            }

            string json = @"{ElementId: null, Name: '" + TestFolderName + @"'}";

            var content = new StringContent(json, Encoding.UTF8, "application/json");
            using (var httpRequestMessage = new HttpRequestMessage
            {
                Method = HttpMethod.Post,
                RequestUri = new Uri(Client.BaseAddress + "Navigation/NewDisplayFolder"),
                Headers =
                {
                    { HttpRequestHeader.Accept.ToString(), "application/json" },
                    { "X-Requested-With", "XMLHttpRequest" },
                    { RequestVerificationTokenKeyword, VerificationToken },
                },
                Content = content,
            })
            {
                var response = await Client.SendAsync(httpRequestMessage).ConfigureAwait(false);
                var contents = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                var o = JObject.Parse(contents);
                TestFolderId = o.GetValue("DisplayFolderId", StringComparison.OrdinalIgnoreCase).Value<string>();
                return response;
            }
        }
    }
}
