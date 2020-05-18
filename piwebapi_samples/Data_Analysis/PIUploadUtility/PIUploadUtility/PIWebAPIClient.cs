using System;
using System.Threading.Tasks;
using System.Net.Http;
using System.Net.Http.Headers;
using Newtonsoft.Json.Linq;
using System.Text;

namespace PIUploadUtility
{
    class PIWebAPIClient
    {
        private HttpClient client;

        public PIWebAPIClient()
        {
            client = new HttpClient(new HttpClientHandler() { UseDefaultCredentials = true });
            client.DefaultRequestHeaders.Add("X-Requested-With", "xhr");
        }

        public PIWebAPIClient(string baseAddress, string username, string password)
        {
            client = new HttpClient();

            //Base address must end with a '/'
            if (baseAddress[baseAddress.Length - 1] != '/')
            {
                baseAddress += "/";
            }

            client.BaseAddress = new Uri(baseAddress);
            string creds = Convert.ToBase64String(
                System.Text.Encoding.ASCII.GetBytes(String.Format("{0}:{1}", username, password)));
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", creds);
            client.DefaultRequestHeaders.Add("X-Requested-With", "xhr");
        }

        public async Task<JObject> GetAsync(string uri)
        {
            HttpResponseMessage response = await client.GetAsync(uri);

            Console.WriteLine("GET response code ", response.StatusCode);
            string content = await response.Content.ReadAsStringAsync();

            if(!response.IsSuccessStatusCode)
            {
                var responseMessage = "Response status code does not indicate success: " + (int)response.StatusCode + " (" + response.StatusCode + " ). ";
                throw new HttpRequestException(responseMessage + Environment.NewLine + content);
            }
            return JObject.Parse(content);
        }

        public async Task PostAsync(string uri, string data)
        {
            HttpResponseMessage response = await client.PostAsync(
                uri, new StringContent(data, Encoding.UTF8, "application/json"));

            Console.WriteLine("POST response code ", response.StatusCode);
            string content = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                var responseMessage = "Response status code does not indicate success: " + (int)response.StatusCode + " (" + response.StatusCode + " ). ";
                throw new HttpRequestException(responseMessage + Environment.NewLine + content);
            }
        }

        public async Task PostXmlAsync(string uri, string data)
        {
            HttpResponseMessage response = await client.PostAsync(
                uri, new StringContent(data, Encoding.UTF8, "text/xml"));

            Console.WriteLine("GET response code ", response.StatusCode);
            string content = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                var responseMessage = "Response status code does not indicate success: " + (int)response.StatusCode + " (" + response.StatusCode + " ). ";
                throw new HttpRequestException(responseMessage + Environment.NewLine + content);
            }
        }

        public JObject GetRequest(string url)
        {
            Task<JObject> t = this.GetAsync(url);
            t.Wait();
            return t.Result;
        }

        public void PostRequest(string url, string data, bool isXML=false)
        {
            if (isXML)
            {
                Task t = this.PostXmlAsync(url, data);
                t.Wait();
            }
            else
            {
                Task t = this.PostAsync(url, data);
                t.Wait();
            }
        }

        public void Dispose()
        {
            client.Dispose();
        }
    }
}
