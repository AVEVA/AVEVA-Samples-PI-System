using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace UploadUtility
{
    public class PIWebAPIClient
    {
        private readonly HttpClient _client;

        public PIWebAPIClient()
        {
            using var handler = new HttpClientHandler() { UseDefaultCredentials = true };
            _client = new HttpClient(handler);
            _client.DefaultRequestHeaders.Add("X-Requested-With", "xhr");
        }

        public PIWebAPIClient(string baseAddress, string username, string password)
        {
            _client = new HttpClient();

            // Base address must end with a '/'
            if (baseAddress[^1] != '/')
            {
                baseAddress += "/";
            }

            _client.BaseAddress = new Uri(baseAddress);
            string creds = Convert.ToBase64String(
                Encoding.ASCII.GetBytes(string.Format("{0}:{1}", username, password)));
            _client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", creds);
            _client.DefaultRequestHeaders.Add("X-Requested-With", "xhr");
        }

        public async Task<JObject> GetAsync(string uri)
        {
            HttpResponseMessage response = await _client.GetAsync(uri);

            Console.WriteLine("GET response code " + response.StatusCode);
            string content = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                var responseMessage = "Response status code does not indicate success: " + (int)response.StatusCode + " (" + response.StatusCode + " ). ";
                throw new HttpRequestException(responseMessage + Environment.NewLine + content);
            }

            return JObject.Parse(content);
        }

        public async Task PostAsync(string uri, string data)
        {
            HttpResponseMessage response = await _client.PostAsync(
                uri, new StringContent(data, Encoding.UTF8, "application/json"));

            Console.WriteLine("POST response code " + response.StatusCode);
            string content = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                var responseMessage = "Response status code does not indicate success: " + (int)response.StatusCode + " (" + response.StatusCode + " ). ";
                throw new HttpRequestException(responseMessage + Environment.NewLine + content);
            }
        }

        public async Task PostXmlAsync(string uri, string data)
        {
            HttpResponseMessage response = await _client.PostAsync(
                uri, new StringContent(data, Encoding.UTF8, "text/xml"));

            Console.WriteLine("GET response code " + response.StatusCode);
            string content = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                var responseMessage = "Response status code does not indicate success: " + (int)response.StatusCode + " (" + response.StatusCode + " ). ";
                throw new HttpRequestException(responseMessage + Environment.NewLine + content);
            }
        }

        public async Task DeleteAsync(string uri)
        {
            HttpResponseMessage response = await _client.DeleteAsync(uri);
            Console.WriteLine("DELETE response code " + response.StatusCode);
            string content = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                var responseMessage = "Response status code does not indicate success: " + (int)response.StatusCode + " (" + response.StatusCode + " ). ";
                throw new HttpRequestException(responseMessage + Environment.NewLine + content);
            }
        }

        public JObject GetRequest(string url)
        {
            Task<JObject> t = GetAsync(url);
            t.Wait();
            return t.Result;
        }

        public void PostRequest(string url, string data, bool isXML = false)
        {
            if (isXML)
            {
                Task t = PostXmlAsync(url, data);
                t.Wait();
            }
            else
            {
                Task t = PostAsync(url, data);
                t.Wait();
            }
        }

        public void DeleteRequest(string url)
        {
            Task t = DeleteAsync(url);
            t.Wait();
        }

        public void Dispose()
        {
            _client.Dispose();
        }
    }
}
