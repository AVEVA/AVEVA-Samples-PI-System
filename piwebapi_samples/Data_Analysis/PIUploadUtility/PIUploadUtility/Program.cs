using System;
using System.Xml;
using System.IO;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace PIUploadUtility
{
    class Program
    {
        static readonly string defaultConfigFile = @"..\..\..\..\test_config.json";
        static readonly string defaultDatabaseFileFile = @"..\..\Building Example.xml";
        static readonly string defaultTagDefinitionFile = @"..\..\tagdefinition.csv";
        static readonly string defaultPIDataFile = @"..\..\pidata.csv";

        static JObject config;
        static PIWebAPIClient client;

        static string GetWebIDByPath(string path, string resource)
        {
            string query = resource + "?path=" + path;

            try
            {
                JObject response = client.GetRequest(query);
                return response["WebId"].ToString();
            }
            catch (Exception e)
            {
                Console.WriteLine(e.InnerException.Message);
            }

            return null;
        }

        static void CreateDatabase(XmlDocument doc, string assetserver)
        {
            string serverPath = "\\\\" + assetserver;
            string assetserverWebID = GetWebIDByPath(serverPath, "assetservers");

            string createDBQuery = "assetservers/" + assetserverWebID + "/assetdatabases";

            string databaseName = config["AF_DATABASE_NAME"].ToString();

            Object payload = new 
            {
                 Name = databaseName,
                 Description = "Example for Building Data"  
            };

            string request_body = JsonConvert.SerializeObject(payload);
            
            try
            {
                client.PostRequest(createDBQuery, request_body);
            }
            catch (Exception e)
            {
                Console.WriteLine(e.InnerException.Message);
            }
            
            string databasePath = serverPath + "\\" + databaseName;
            string databaseWebID = GetWebIDByPath(databasePath, "assetdatabases");
            string importQuery = "assetdatabases/" + databaseWebID + "/import";

            try
            {
                client.PostRequest(importQuery, doc.InnerXml.ToString(), true);
            }
            catch (Exception e)
            {
                Console.WriteLine(e.InnerException.Message);
            }
        }

        static void CreatePIPoint(string dataserver, string tagDefinitionLocation)
        {
            string path = "\\\\PIServers[" + dataserver + "]";
            string dataserverWebID = GetWebIDByPath(path, "dataservers");
            string createPIPointQuery = "dataservers/" + dataserverWebID + "/points";
            
            var tagDefinitions = File.ReadLines(tagDefinitionLocation);
            string name, pointType, pointClass;

            foreach (string tagDefinition in tagDefinitions)
            {
                string[] split = tagDefinition.Split(',');
                name = split[0];
                pointType = split[1];
                pointClass = split[2];

                Object payload = new
                {
                    Name = name,
                    PointType = pointType,
                    PointClass = pointClass
                };

                string request_body = JsonConvert.SerializeObject(payload);

                try
                {
                    client.PostRequest(createPIPointQuery, request_body);
                }
                catch (Exception e)
                {
                    Console.WriteLine(e.InnerException.Message);
                }
            }
        }

        static bool DoesTagExist(string dataserver)
        {
            string tagname = "VAVCO 2-09.Predicted Cooling Time";
           
            string path = "\\\\" + dataserver + "\\" + tagname;
            string getPointQuery = "points?path=" + path;

            try
            {
                JObject result = client.GetRequest(getPointQuery);
            }
            catch (Exception e)
            {
                if (e.InnerException.Message.Contains("404"))
                {
                    return false;
                }
                else
                {
                    Console.WriteLine(e.InnerException.Message);
                }
            }
            
            return true;
        }
        static void UpdateValues(string dataserver, string tagDefinitionLocation, string PIDataLocation)
        {
            var tags = File.ReadLines(tagDefinitionLocation);

            foreach (string tag in tags)
            {
                string[] split = tag.Split(',');
                string tagname = split[0];
                List<string[]> entries = new List<string[]>();

                var values = File.ReadLines(PIDataLocation);
                foreach (string value in values)
                {
                    if (value.Contains(tagname))
                    {
                        entries.Add(value.Split(','));
                    }
                }

                string path = "\\\\" + dataserver + "\\" + tagname;
                string webid = GetWebIDByPath(path, "points");
                string updateValueQuery = "streamsets/recorded";

                List<Object> items = new List<Object>();
                foreach (string[] line in entries)
                {                    
                    Object item = new
                    {
                        Timestamp = line[3],
                        Value = line[1]
                    };
                    items.Add(item);
                }

                Object payload = new
                {
                    Items = items.ToArray(),
                    WebId = webid
                };

                string request_body = "[" + JsonConvert.SerializeObject(payload) + "]";

                try
                {
                    client.PostRequest(updateValueQuery, request_body);
                }
                catch (Exception e)
                {
                    Console.WriteLine(e.InnerException.Message);
                }
            }
        }
       
        static void Main(string[] args)
        {
            /*Use the default values provided at the beginning of this class (which work when running from Visual Studio) 
                or use the values provided by command line arguments*/

            string configFile = defaultConfigFile;
            string databaseFile = defaultDatabaseFileFile;
            string tagDefinitionFile = defaultTagDefinitionFile;
            string piDataFile = defaultPIDataFile;

            if (args.Length >= 1)
            {
                databaseFile = args[0];
            }

            if (args.Length >= 2)
            {
                tagDefinitionFile = args[1];
            }

            if (args.Length >= 3)
            {
                piDataFile = args[2];
            }

            if (args.Length >= 4)
            {
                configFile = args[3];
            }

            config = JObject.Parse(File.ReadAllText(configFile));
            client = new PIWebAPIClient(
                config["PIWEBAPI_URL"].ToString(),
                config["USER_NAME"].ToString(),
                config["USER_PASSWORD"].ToString());

            string dataserver = config["PI_SERVER_NAME"].ToString();
            string assetserver = config["AF_SERVER_NAME"].ToString();

            //Create and Import Database from Building Example file
            XmlDocument doc = new XmlDocument();
            doc.Load(databaseFile);
            CreateDatabase(doc, assetserver);

            //Check for and create tags
            if (!DoesTagExist(dataserver))
            {
                CreatePIPoint(dataserver, tagDefinitionFile);
            }

            //Update values from existing csv file
            UpdateValues(dataserver, tagDefinitionFile, piDataFile);
        }
    }
}
