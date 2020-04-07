using System;
using System.Diagnostics.Contracts;
using System.Linq;
using OSIsoft.AF;
using OSIsoft.AF.Notification;
using OSIsoft.AF.Search;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Theses tests verify the basic configurations for PI Notifications, including the tests for PlugIns,
    /// notification rule, notification rule template and notification contact template.
    /// </summary>
    [Collection("AF collection")]
    public partial class NotificationTests : IClassFixture<AFFixture>, IClassFixture<NotificationsFixture>
    {
        internal const string KeySetting = "PINotificationsService";
        internal const TypeCode KeySettingTypeCode = TypeCode.String;

        /// <summary>
        /// Constructor for NotificationsConfigurationTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="afFixture">Fixture to manage AF connection and specific helper functions.</param>
        /// <param name="notificationFixture">Fixture to manage notifications objects.</param>
        public NotificationTests(ITestOutputHelper output, AFFixture afFixture, NotificationsFixture notificationsFixture)
        {
            Contract.Requires(output != null);
            Contract.Requires(afFixture != null);
            Contract.Requires(notificationsFixture != null);

            Output = output;
            AFFixture = afFixture;
            NotificationsFixture = notificationsFixture;
            notificationsFixture.InitializeWebService(afFixture, output);
        }

        private AFFixture AFFixture { get; }

        private NotificationsFixture NotificationsFixture { get; }

        private ITestOutputHelper Output { get; }

        private PISystem PISystem => AFFixture.PISystem;

        private AFPlugIn EmailPlugIn => PISystem.DeliveryChannelPlugIns[NotificationsFixture.EmailPlugInName];

        private AFPlugIn WebServicePlugIn => PISystem.DeliveryChannelPlugIns[NotificationsFixture.WebServicePlugInName];

        /// <summary>
        /// Tests to see if the current patch of PI Notifications is applied
        /// </summary>
        /// <remarks>
        /// Errors if the current patch is not applied with a message telling the user to upgrade
        /// </remarks>
        [Fact]
        public void HaveLatestPatchNotifications()
        {
            var factAttr = new GenericFactAttribute(TestCondition.NOTIFICATIONSCURRENTPATCH, true);
            Assert.NotNull(factAttr);
        }

        /// <summary>
        /// Test email and web service PlugIns are loaded properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Verify the Email PlugIn loaded properly</para>
        /// <para>Verify the Email PlugIn was loaded from the right assembly</para>
        /// <para>Verify the Web Service PlugIn loaded properly</para>
        /// <para>Verify the Web Service PlugIn was loaded from the right assembly</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void PlugInsTest()
        {
            Output.WriteLine("Verify the Email PlugIn was loaded properly.");
            Assert.True(EmailPlugIn != null, "Email PlugIn is not found.");
            Assert.True(EmailPlugIn.AssemblyFileName != null, "The assembly file name is null for email PlugIn.");
            Assert.True(
                EmailPlugIn.AssemblyFileName.Contains(NotificationsFixture.EmailPlugInAssemblyFileName),
                "The assembly file name for email PlugIn is not set properly.");

            Output.WriteLine("Verify the Web Service PlugIn was loaded properly.");
            Assert.True(WebServicePlugIn != null, "WebService PlugIn is not found.");
            Assert.True(WebServicePlugIn.AssemblyFileName != null, "The assembly file name is null for web service PlugIn.");
            Assert.True(
                WebServicePlugIn.AssemblyFileName.Contains(NotificationsFixture.WebServicePlugInAssemblyFileName),
                "The assembly file name for web service PlugIn is not set properly.");
        }

        /// <summary>
        /// Test notification rule can be added and configured properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an element with a notification rule</para>
        /// <para>Configure the properties of the created notification rule</para>
        /// <para>Verify the notification rule is added, configured and retrieved</para>
        /// <para>Delete the element</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void NotificationRuleTest()
        {
            AFDatabase db = AFFixture.AFDatabase;
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleTest)}";
            var notificationRuleName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRule1";

            AFFixture.RemoveElementIfExists(elementName, Output);

            try
            {
                Output.WriteLine($"Create element [{elementName}] with notification rule [{notificationRuleName}].");
                var element = db.Elements.Add(elementName);
                var notificationRule = element.NotificationRules.Add(notificationRuleName);
                notificationRule.Criteria = "Category:test*";
                notificationRule.ResendInterval = TimeSpan.FromMinutes(2);
                notificationRule.NonrepetitionInterval = TimeSpan.FromMinutes(15);
                var format = notificationRule.DeliveryFormats.Add("testFormat", EmailPlugIn);
                db.CheckIn();

                db = AFFixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                Output.WriteLine("Verify the properties of the created notification rule.");
                notificationRule = db.Elements[elementName].NotificationRules[notificationRuleName];
                Assert.True(notificationRule.Criteria == "Category:test*", "Criteria is not set properly.");
                Assert.True(notificationRule.ResendInterval == TimeSpan.FromMinutes(2), "Resend interval is not set properly.");
                Assert.True(notificationRule.NonrepetitionInterval == TimeSpan.FromMinutes(15), "Non-repetition interval is not set properly.");
                Assert.True(notificationRule.DeliveryFormats.Count == 1, "Expected to have one defined format.");
                Assert.True(notificationRule.DeliveryFormats[0].ID == format.ID, "Expected delivery format was not the correct one.");

                Output.WriteLine("Verify the notification rule is added and retrieved.");
                using (var ruleSearch = new AFNotificationRuleSearch(db, nameof(NotificationRuleTest), $"Name:={notificationRuleName}"))
                {
                    var rules = ruleSearch.FindObjects().Select(nr => nr.ID).ToArray();
                    Assert.True(rules.Contains(notificationRule.ID), $"The created notification rule [{notificationRuleName}] is not found.");
                }
            }
            finally
            {
                AFFixture.RemoveElementIfExists(elementName, Output);
            }
        }

        /// <summary>
        /// Test notification rule template can be added and configured properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an element template with a notification rule template</para>
        /// <para>Configure the properties of the created notification rule template</para>
        /// <para>Verify the notification rule template is added, configured and retrieved</para>
        /// <para>Delete the element template</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void NotificationRuleTemplateTest()
        {
            AFDatabase db = AFFixture.AFDatabase;
            var elementTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleTemplateTest)}";
            var notificationRuleTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRuleTemplate1";

            AFFixture.RemoveElementTemplateIfExists(elementTemplateName, Output);

            try
            {
                Output.WriteLine($"Create element template [{elementTemplateName}] with notification rule template [{notificationRuleTemplateName}].");
                var elementTemplate = db.ElementTemplates.Add(elementTemplateName);
                var notificationRuleTemplate = elementTemplate.NotificationRuleTemplates.Add(notificationRuleTemplateName);
                notificationRuleTemplate.Criteria = "Name:test*";
                notificationRuleTemplate.ResendInterval = TimeSpan.FromSeconds(30);
                notificationRuleTemplate.NonrepetitionInterval = TimeSpan.FromMinutes(15);
                var format = notificationRuleTemplate.DeliveryFormats.Add("testFormat", EmailPlugIn);
                db.CheckIn();

                db = AFFixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                Output.WriteLine("Verify the properties of the created notification rule template.");
                notificationRuleTemplate = db.ElementTemplates[elementTemplateName].NotificationRuleTemplates[notificationRuleTemplateName];
                Assert.True(notificationRuleTemplate.Criteria == "Name:test*", "Criteria is not set correctly.");
                Assert.True(notificationRuleTemplate.ResendInterval == TimeSpan.FromSeconds(30), "Resend interval is not set properly.");
                Assert.True(notificationRuleTemplate.NonrepetitionInterval == TimeSpan.FromMinutes(15), "Non-repetition interval is not set properly.");
                Assert.True(notificationRuleTemplate.DeliveryFormats.Count == 1, "Expected to have one defined format.");
                Assert.True(notificationRuleTemplate.DeliveryFormats[0].ID == format.ID, "Expected delivery format was not the correct one.");

                Output.WriteLine("Verify the notification rule template is added and retrieved.");
                using (var ruleTemplateSearch = new AFNotificationRuleTemplateSearch(db, nameof(NotificationRuleTemplateTest), string.Empty))
                {
                    var rules = ruleTemplateSearch.FindObjects().Select(nr => nr.ID).ToArray();
                    Assert.True(rules.Contains(notificationRuleTemplate.ID),
                        $"The created notification rule template [{notificationRuleTemplateName}] is not found.");
                }
            }
            finally
            {
                AFFixture.RemoveElementTemplateIfExists(elementTemplateName, Output);
            }
        }

        /// <summary>
        /// Test notification rule from an element template can be added and configured properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an element template with a notification rule template</para>
        /// <para>Configure the properties of the created notification rule template</para>
        /// <para>Create an element from the created element template</para>
        /// <para>Verify the notification rule in the element is added, configured and retrieved</para>
        /// <para>Delete the element and the element template</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void NotificationRuleFromTemplateTest()
        {
            AFDatabase db = AFFixture.AFDatabase;
            var elementTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleFromTemplateTest)}";
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleFromTemplateTest)}";
            var notificationRuleTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRuleTemplate1";

            AFFixture.RemoveElementIfExists(elementName, Output);
            AFFixture.RemoveElementTemplateIfExists(elementTemplateName, Output);

            try
            {
                Output.WriteLine($"Create element template [{elementTemplateName}] with notification rule template [{notificationRuleTemplateName}].");
                var elementTemplate = db.ElementTemplates.Add(elementTemplateName);
                var notificationRuleTemplate = elementTemplate.NotificationRuleTemplates.Add(notificationRuleTemplateName);
                notificationRuleTemplate.Criteria = "Category:test";
                notificationRuleTemplate.ResendInterval = TimeSpan.FromSeconds(30);
                notificationRuleTemplate.NonrepetitionInterval = TimeSpan.FromMinutes(15);
                var format = notificationRuleTemplate.DeliveryFormats.Add("testFormat", EmailPlugIn);

                Output.WriteLine($"Create element [{elementName}] from element template [{elementTemplateName}].");
                var element = db.Elements.Add(elementName, elementTemplate);
                db.CheckIn();

                db = AFFixture.ReconnectToDB(); // This operation clears AFSDK cache and assures retrieval from AF server
                Output.WriteLine("Verify the properties of the created notification rule template.");
                var notificationRule = db.Elements[elementName].NotificationRules[notificationRuleTemplateName];
                Assert.True(notificationRule.Criteria == "Category:test", "Criteria is not set properly.");
                Assert.True(notificationRule.ResendInterval == TimeSpan.FromSeconds(30), "Resend interval is not set properly.");
                Assert.True(notificationRule.NonrepetitionInterval == TimeSpan.FromMinutes(15), "Non-repetition interval is not set properly.");
                Assert.True(notificationRule.DeliveryFormats.Count == 0, "Expected to have zero format. Format is from the template.");

                Output.WriteLine("Verify the notification rule template is added and retrieved.");
                using (var ruleSearch = new AFNotificationRuleSearch(db, nameof(NotificationRuleFromTemplateTest), string.Empty))
                {
                    var rules = ruleSearch.FindObjects().Select(nr => nr.ID).ToArray();
                    Assert.True(rules.Contains(notificationRule.ID), $"The created notification rule [{notificationRuleTemplateName}] is not found.");
                }
            }
            finally
            {
                AFFixture.RemoveElementIfExists(elementName, Output);
                AFFixture.RemoveElementTemplateIfExists(elementTemplateName, Output);
            }
        }

        /// <summary>
        /// Test email notification contact template can be added and configured properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an email contact template</para>
        /// <para>Configure the properties of the created contact template</para>
        /// <para>Verify the contact template is added, configured and retrieved</para>
        /// <para>Delete the contact template</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void EmailNotificationContactTemplateTest()
        {
            var notificationContactTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(EmailNotificationContactTemplateTest)}";
            var contactConfigString = "ToEmail=test@example.com";

            AFFixture.RemoveNotificationContactTemplateIfExists(notificationContactTemplateName, Output);

            try
            {
                Output.WriteLine($"Create email notification contact template [{notificationContactTemplateName}].");
                var nct = new AFNotificationContactTemplate(PISystem, notificationContactTemplateName)
                {
                    DeliveryChannelPlugIn = EmailPlugIn,
                    ConfigString = contactConfigString,
                    RetryInterval = TimeSpan.FromSeconds(45),
                    MaximumRetries = 3,
                };
                nct.CheckIn();

                AFFixture.ReconnectToDB();
                var id = nct.ID;
                var nct2 = PISystem.NotificationContactTemplates[id];
                Output.WriteLine("Verify the properties of the created notification contact template.");
                Assert.True(nct2.DeliveryChannelPlugIn.Name == NotificationsFixture.EmailPlugInName,
                    "Delivery channel PlugIn is not Email delivery channel PlugIn.");
                Assert.True(nct2.ConfigString == contactConfigString, "Delivery channel configuration string is not set properly.");
                Assert.True(nct2.RetryInterval == TimeSpan.FromSeconds(45), "Retry interval is not set properly.");
                Assert.True(nct2.MaximumRetries == 3, "Maximum retries is not set properly.");

                Output.WriteLine("Verify the notification contact template is added and retrieved.");
                using (var contactTemplateEmailSearch = new AFNotificationContactTemplateSearch(PISystem, nameof(EmailNotificationContactTemplateTest), string.Empty))
                {
                    var rules = contactTemplateEmailSearch.FindObjects().Select(nr => nr.ID).ToArray();
                    Assert.True(rules.Contains(id), $"The created notification contact template [{notificationContactTemplateName}] is not found.");
                }
            }
            finally
            {
                AFFixture.RemoveNotificationContactTemplateIfExists(notificationContactTemplateName, Output);
            }
        }

        /// <summary>
        /// Test web service notification contact template can be added and configured properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create a web service contact template</para>
        /// <para>Configure the properties of the created contact template</para>
        /// <para>Verify the contact template is added, configured and retrieved</para>
        /// <para>Delete the contact template</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void WebServiceNotificationContactTemplateTest()
        {
            var notificationContactTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(WebServiceNotificationContactTemplateTest)}";

            AFFixture.RemoveNotificationContactTemplateIfExists(notificationContactTemplateName, Output);

            try
            {
                Output.WriteLine($"Create web service notification contact template [{notificationContactTemplateName}].");
                var nct = new AFNotificationContactTemplate(PISystem, notificationContactTemplateName)
                {
                    DeliveryChannelPlugIn = WebServicePlugIn,
                    ConfigString = "Style=SOAP;WebServiceName=Service;WebServiceMethod=Method;WebServiceUrl=http://localhost:9000",
                    RetryInterval = TimeSpan.FromSeconds(30),
                    MaximumRetries = 2,
                };
                nct.CheckIn();

                AFFixture.ReconnectToDB();
                var nctId = nct.ID;
                var nct2 = PISystem.NotificationContactTemplates[nctId];
                Output.WriteLine("Verify the properties of the created web service notification contact template.");
                Assert.True(nct2.DeliveryChannelPlugIn.Name == NotificationsFixture.WebServicePlugInName,
                    "Delivery channel PlugIn is not WebService delivery channel PlugIn.");

                // SOAP style is implicit but authentication option is added automatically by default
                Assert.True(
                    nct2.ConfigString == "AuthenticationOption=Windows;WebServiceMethod=Method;WebServiceName=Service;WebServiceURL=http://localhost:9000",
                    "Delivery channel configuration string is not set properly.");
                Assert.True(nct2.RetryInterval == TimeSpan.FromSeconds(30), "Retry interval is not set properly.");
                Assert.True(nct2.MaximumRetries == 2, "Maximum retries is not set properly.");

                Output.WriteLine("Verify the web service notification contact template is added, configured and retrieved.");
                using (var contactTemplateEmailSearch = new AFNotificationContactTemplateSearch(PISystem, nameof(WebServiceNotificationContactTemplateTest), string.Empty))
                {
                    var rules = contactTemplateEmailSearch.FindObjects().Select(nr => nr.ID).ToArray();
                    Assert.True(rules.Contains(nctId), $"The created notification contact template [{notificationContactTemplateName}] is not found.");
                }
            }
            finally
            {
                AFFixture.RemoveNotificationContactTemplateIfExists(notificationContactTemplateName, Output);
            }
        }
    }
}
