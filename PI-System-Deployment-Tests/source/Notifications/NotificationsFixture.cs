using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.ServiceModel;
using System.Text;
using Newtonsoft.Json;
using OSIsoft.AF.Notification;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Test context class to be shared in notifications related xUnit test classes.
    /// </summary>
    /// <remarks>
    /// xUnit.net ensures that the fixture instance will be created before any tests run and
    /// when all tests are done will clean up the fixture object with 'Dispose' call.
    /// This fixture includes helper functions isolated to notifications related calls.
    /// See Utils.cs for more general test helper functions.
    /// </remarks>
    public sealed class NotificationsFixture : IDisposable
    {
        /// <summary>
        /// The prefix string for the notifications related tests.
        /// </summary>
        public const string TestPrefix = "OSIsoftTests";

        /// <summary>
        /// The infix string for the notifications related tests.
        /// </summary>
        public const string TestInfix = "Notifications";

        /// <summary>
        /// The value string for an annotation of a sent notification.
        /// </summary>
        public const string SentAnnotation = "Notification sent to {0} subscriber(s).";

        /// <summary>
        /// The value string for an annotation of an escalated notification.
        /// </summary>
        public const string EscalatedAnnotation = "Notification escalated to {0} subscriber(s).";

        /// <summary>
        /// The name string for notifications annotation.
        /// </summary>
        public const string AnnotationName = "Notification Subscribers";

        /// <summary>
        /// The name for email plug-in.
        /// </summary>
        public const string EmailPlugInName = "Email";

        /// <summary>
        /// The name for web service plug-in.
        /// </summary>
        public const string WebServicePlugInName = "WebService";

        /// <summary>
        /// The assembly file name for email plug-in.
        /// </summary>
        public const string EmailPlugInAssemblyFileName = "OSIsoft.AF.Notification.DeliveryChannel.Email";

        /// <summary>
        /// The assembly file name for web service plug-in.
        /// </summary>
        public const string WebServicePlugInAssemblyFileName = "OSIsoft.AF.Notification.DeliveryChannel.WebService";

        private static readonly char[] _defaultAlphabet = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray();
        private readonly List<Guid> _notificationContactTemplateIds = new List<Guid>();
        private Guid _soapWebServiceId = Guid.Empty;

        /// <summary>
        /// Creates an instance of the NotificationsFixture.
        /// </summary>
        public NotificationsFixture()
        {
            UriSuffix = GetRandomString(8);
        }

        internal AFFixture AFFixture { get; private set; }

        internal TestWebService Service { get; private set; }

        internal BasicWebServiceHost SoapWebServiceHost { get; private set; }

        internal string ServiceName { get; set; } = "NotificationTest";

        internal string ServiceUriPrefix { get; set; } = $"http://{Environment.MachineName}:9001/notificationtest";

        internal string UriSuffix { get; set; }

        internal string ServiceUri => $"{ServiceUriPrefix}/{UriSuffix}";

        /// <summary>
        /// Implement IDisposable to release unmanaged resources.
        /// </summary>
        public void Dispose()
        {
            if (AFFixture == null)
                return;

            SoapWebServiceHost?.Close();

            foreach (var id in _notificationContactTemplateIds)
            {
                try
                {
                    AFFixture.PISystem.NotificationContactTemplates.Remove(id);
                }
                catch
                {
                    // Ignore all errors
                }
            }

            var system = AFFixture.PISystem;
            AFFixture = null;
            system.CheckIn();
        }

        internal AnnotationDescription DeserializeAnnotationDescription(string description)
            => JsonConvert.DeserializeObject<AnnotationDescription>(description);

        internal AFNotificationContactTemplate GetSoapWebServiceEndpoint()
            => AFNotificationContactTemplate.FindNotificationContactTemplate(AFFixture.PISystem, _soapWebServiceId);

        internal void InitializeWebService(AFFixture afFixture, ITestOutputHelper output)
        {
            if (AFFixture != null)
                return;

            // Initialize a web service notification contact template
            AFFixture = afFixture;
            Service = new TestWebService();
            SoapWebServiceHost = new BasicWebServiceHost(Service, typeof(IWebService));

            try
            {
                SoapWebServiceHost.Start(ServiceName, ServiceUri);
            }
            catch (AddressAccessDeniedException)
            {
                SoapWebServiceHost = null;
                Service = null;

                output.WriteLine($"Warning: The Web Service endpoint [{ServiceUri}] could not be opened.");
                output.WriteLine("There are two ways how to fix the problem:");
                output.WriteLine("1. Use netsh add urlacl to add the current user for the service prefix http://+:9001/notificationtest");
                output.WriteLine("2. Run tests as administrator.");

                return;
            }

            var webServiceSoap = new AFNotificationContactTemplate(afFixture.PISystem, $"{TestPrefix}_{TestInfix}_WebServiceSoap*")
            {
                DeliveryChannelPlugIn = afFixture.PISystem.DeliveryChannelPlugIns[WebServicePlugInName],
                ConfigString = $"Style=SOAP;WebServiceName={ServiceName};WebServiceMethod={nameof(IWebService.Test)};WebServiceUrl={ServiceUri}",
            };

            _soapWebServiceId = webServiceSoap.ID;
            _notificationContactTemplateIds.Add(webServiceSoap.ID);

            AFFixture.PISystem.CheckIn();
            output.WriteLine($"Created web service notification contact template [{webServiceSoap.Name}].");
        }

        internal void SetFormatProperties(IDictionary<string, string> properties, string content)
        {
            var notificationRuleIdContent = new WebServiceContentEvaluationInfo()
            {
                ValueType = WebServiceContentValueType.Content,
                ContentInfo = new ContentEvaluationInfo()
                {
                    Id = Guid.Parse("{418DF2DB-58ED-4c27-97DE-0A909BD8B2FE}"),
                    PropertyId = 1,
                },
            };

            properties["parameter:ruleId"] = JsonConvert.SerializeObject(notificationRuleIdContent);

            var rawContent = new WebServiceContentEvaluationInfo()
            {
                ValueType = WebServiceContentValueType.Value,
                ContentInfo = new ContentEvaluationInfo()
                {
                    Name = content,
                },
            };

            properties["parameter:content"] = JsonConvert.SerializeObject(rawContent);
        }

        private static string GetRandomString(int length)
        {
            var builder = new StringBuilder(length);

            using (var random = RandomNumberGenerator.Create())
            {
                for (var i = 0; i < length; i++)
                {
                    byte[] oneByte = new byte[1];
                    random.GetBytes(oneByte);
                    char character = Convert.ToChar(oneByte[0]);
                    if (_defaultAlphabet.Contains(character))
                    {
                        builder.Append(character);
                    }
                }
            }

            return builder.ToString();
        }
    }
}
