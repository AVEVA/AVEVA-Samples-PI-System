using System;
using System.Globalization;
using System.Threading;
using OSIsoft.AF;
using OSIsoft.AF.Analysis;
using OSIsoft.AF.EventFrame;
using OSIsoft.AF.Notification;
using OSIsoft.AF.Time;
using Xunit;
using static OSIsoft.PISystemDeploymentTests.TestWebService;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// These tests verify the notification send operation to a web service delivery endpoint, including the
    /// tests for annotations, resend configuration, event frame notify options and acknowledgment.
    /// </summary>
    public partial class NotificationTests : IClassFixture<AFFixture>, IClassFixture<NotificationsFixture>
    {
        /// <summary>
        /// Test notification rule can send notification to a web service delivery endpoint successfully for an
        /// detected event frame, and the annotations for the event frame is added properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an element with a notification rule</para>
        /// <para>Configure the notification rule criteria to Event Frame Search</para>
        /// <para>Add the created web service contact template to the subscriber of the notification rule</para>
        /// <para>Create an event frame</para>
        /// <para>Verify the notification is sent for the event frame and the annotation is set properly</para>
        /// <para>Verify the content of the annotation is set properly</para>
        /// <para>Delete the event frame and the element</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void NotificationRuleSendWebServiceAnnotationTest()
        {
            Assert.True(NotificationsFixture.SoapWebServiceHost != null, "The Web Service host couldn't be started.");

            AFDatabase db = AFFixture.AFDatabase;
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleSendWebServiceAnnotationTest)}";
            var notificationRuleName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRule1";
            var eventFrameName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_EventFrame1";

            AFFixture.RemoveElementIfExists(elementName, Output);
            Guid? eventFrameId = null;

            try
            {
                Output.WriteLine($"Created element [{elementName}] with notification rule [{notificationRuleName}].");
                var element = db.Elements.Add(elementName);
                var notificationRule = element.NotificationRules.Add(notificationRuleName);
                notificationRule.Criteria = $"Name:{NotificationsFixture.TestPrefix}*";
                var format = notificationRule.DeliveryFormats.Add("testFormat", WebServicePlugIn);
                NotificationsFixture.SetFormatProperties(format.Properties, nameof(NotificationRuleSendWebServiceAnnotationTest));

                var webServiceEndpoint = NotificationsFixture.GetSoapWebServiceEndpoint();
                var subscriber = notificationRule.Subscribers.Add(webServiceEndpoint);
                subscriber.DeliveryFormat = format;
                notificationRule.SetStatus(AFStatus.Enabled);
                db.CheckIn();

                Output.WriteLine("Waiting for notification to startup.");
                Thread.Sleep(TimeSpan.FromSeconds(10));

                var eventFrame = new AFEventFrame(db, eventFrameName)
                {
                    PrimaryReferencedElement = element,
                };

                Output.WriteLine($"Created event frame [{eventFrameName}].");
                eventFrame.SetStartTime(AFTime.Now);
                eventFrame.CheckIn();
                eventFrameId = eventFrame.ID;

                var msg = NotificationsFixture.Service.WaitForMessage(TimeSpan.FromMinutes(1));
                Assert.True(notificationRule.ID == msg.NotificationRuleId, "Notification rule is not set properly.");
                Assert.True(msg.Content == nameof(NotificationRuleSendWebServiceAnnotationTest), "The message content is not set properly.");

                // Verify annotations are gotten correctly
                var annotations = eventFrame.GetAnnotations();
                if (annotations.Count == 0)
                {
                    AssertEventually.True(
                        () => eventFrame.GetAnnotations().Count != 0,
                        TimeSpan.FromSeconds(60),
                        TimeSpan.FromSeconds(5),
                        "Did not find any annotations.");
                    annotations = eventFrame.GetAnnotations();
                }

                Output.WriteLine("Verify the notification is sent for the event frame and the annotation is set properly.");
                Assert.True(annotations.Count == 1, $"Expected to get only one annotation, but got {annotations.Count}.");
                Assert.True(annotations[0].Owner.ID == eventFrameId, "The owner of the annotation is not set properly.");
                Assert.True(annotations[0].Name == NotificationsFixture.AnnotationName, "The name of the annotation is not set properly.");
                Assert.True((string)annotations[0].Value == string.Format(CultureInfo.InvariantCulture, NotificationsFixture.SentAnnotation, 1),
                    "The value of the annotation is not set properly.");

                Output.WriteLine("Verify the content of the annotation is set properly.");
                Assert.False(string.IsNullOrWhiteSpace(annotations[0].Description), "The description of the annotation is not set properly.");
                var description = NotificationsFixture.DeserializeAnnotationDescription(annotations[0].Description);
                var subscribers = description.Subscribers;
                Assert.True(description.Notification == notificationRuleName, "The notification rule name is not set properly.");
                Assert.True(subscribers.Count == 1, $"Expected to get only one subscriber, but got {description.Subscribers.Count}.");
                Assert.True(subscribers[0].Name == webServiceEndpoint.Name, "The name of the subscriber is not set properly.");
                Assert.True(subscribers[0].Type == "WebService", "The type of the subscriber is not set properly.");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(elementName, Output);
                if (eventFrameId != null)
                {
                    AFFixture.RemoveEventFrameIfExists(eventFrameId.GetValueOrDefault(), Output);
                }
            }
        }

        /// <summary>
        /// Test notification rule can resend notification to a web service successfully for an detected
        /// event frame if ResendInterval is configured.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an element with a notification rule</para>
        /// <para>Configure the notification rule criteria to Event Frame Search</para>
        /// <para>Configure the resend interval of the notification rule</para>
        /// <para>Add the created web service contact template to the subscriber of the notification rule</para>
        /// <para>Create an event frame</para>
        /// <para>Verify the notification is resent</para>
        /// <para>Delete the event frame and the element</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void NotificationRuleResendWebServiceTest()
        {
            Assert.True(NotificationsFixture.SoapWebServiceHost != null, "The Web Service host couldn't be started.");

            AFDatabase db = AFFixture.AFDatabase;
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleResendWebServiceTest)}";
            var notificationRuleName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRule1";
            var eventFrameName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_EventFrame1";
            var resendInterval = TimeSpan.FromMinutes(1);

            AFFixture.RemoveElementIfExists(elementName, Output);
            Guid? eventFrameId = null;

            try
            {
                Output.WriteLine($"Create element [{elementName}] with notification rule [{notificationRuleName}].");
                var element = db.Elements.Add(elementName);
                var notificationRule = element.NotificationRules.Add(notificationRuleName);
                notificationRule.Criteria = $"Name:{NotificationsFixture.TestPrefix}*";
                notificationRule.ResendInterval = resendInterval;
                var format = notificationRule.DeliveryFormats.Add("testFormat", WebServicePlugIn);
                NotificationsFixture.SetFormatProperties(format.Properties, nameof(NotificationRuleResendWebServiceTest));

                var webServiceEndpoint = NotificationsFixture.GetSoapWebServiceEndpoint();
                var subscriber = notificationRule.Subscribers.Add(webServiceEndpoint);
                subscriber.DeliveryFormat = format;
                notificationRule.SetStatus(AFStatus.Enabled);
                db.CheckIn();

                Output.WriteLine("Waiting for notification to startup.");
                Thread.Sleep(TimeSpan.FromSeconds(10));

                var eventFrame = new AFEventFrame(db, eventFrameName)
                {
                    PrimaryReferencedElement = element,
                };

                Output.WriteLine($"Create event frame [{eventFrameName}].");
                eventFrame.SetStartTime(AFTime.Now);
                eventFrame.CheckIn();
                eventFrameId = eventFrame.ID;

                var msg = NotificationsFixture.Service.WaitForMessage(resendInterval);
                Assert.True(notificationRule.ID == msg.NotificationRuleId, "Notification rule is not set properly.");
                Assert.True(msg.Content == nameof(NotificationRuleResendWebServiceTest), "The message content is not set properly.");

                // Waiting for resend
                Output.WriteLine("Verify notification is resent.");
                Thread.Sleep(resendInterval);
                msg = NotificationsFixture.Service.WaitForMessage(resendInterval);
                Assert.True(notificationRule.ID == msg.NotificationRuleId, "Notification rule is not set properly.");
                Assert.True(msg.Content == nameof(NotificationRuleResendWebServiceTest), "The message content is not set properly.");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(elementName, Output);
                if (eventFrameId != null)
                {
                    AFFixture.RemoveEventFrameIfExists(eventFrameId.GetValueOrDefault(), Output);
                }
            }
        }

        /// <summary>
        /// Test notification rule can send notifications to a web service successfully for an detected
        /// event frame when the event frame notify option is set to 'Event start', 'Event end' and
        /// 'Event start and end'.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an element with a notification rule</para>
        /// <para>Configure the notification rule criteria to Event Frame Search</para>
        /// <para>Configure notify option of the notification rule to 'Event start', 'Event end' and 'Event start and end'</para>
        /// <para>Add the created web service contact template to the subscriber of the notification rule</para>
        /// <para>Create an event frame</para>
        /// <para>Verify the notification is sent properly based on the configured notify option</para>
        /// <para>Delete the event frame and the element</para>
        /// </remarks>
        [OptionalTheory(KeySetting, KeySettingTypeCode)]
        [InlineData(AFNotifyOption.EventStart, true, false)]
        [InlineData(AFNotifyOption.EventEnd, false, true)]
        [InlineData(AFNotifyOption.EventStartAndEnd, true, true)]
        public void NotificationRuleSendWebServiceEventFrameNotifyOptionTest(AFNotifyOption afNotifyOption, bool eventFrameStartSent, bool eventFrameEndSent)
        {
            Assert.True(NotificationsFixture.SoapWebServiceHost != null, "The Web Service host couldn't be started.");

            AFDatabase db = AFFixture.AFDatabase;
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleSendWebServiceEventFrameNotifyOptionTest)}_{afNotifyOption.ToString()}";
            var notificationRuleName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRule1";
            var eventFrameName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_EventFrame1";

            AFFixture.RemoveElementIfExists(elementName, Output);
            Guid? eventFrameId = null;

            try
            {
                Output.WriteLine($"Run test {nameof(NotificationRuleSendWebServiceEventFrameNotifyOptionTest)} with notify option [{afNotifyOption.ToString()}].");
                Output.WriteLine($"Create element [{elementName}] with notification rule [{notificationRuleName}].");
                var element = db.Elements.Add(elementName);
                var notificationRule = element.NotificationRules.Add(notificationRuleName);
                notificationRule.Criteria = $"Name:{NotificationsFixture.TestPrefix}*";
                notificationRule.NonrepetitionInterval = TimeSpan.FromMinutes(1);
                var format = notificationRule.DeliveryFormats.Add("testFormat", WebServicePlugIn);
                NotificationsFixture.SetFormatProperties(format.Properties, nameof(NotificationRuleSendWebServiceEventFrameNotifyOptionTest));

                var webServiceEndpoint = NotificationsFixture.GetSoapWebServiceEndpoint();
                var subscriber = notificationRule.Subscribers.Add(webServiceEndpoint);
                subscriber.DeliveryFormat = format;
                subscriber.NotifyOption = afNotifyOption;
                notificationRule.SetStatus(AFStatus.Enabled);
                db.CheckIn();

                Output.WriteLine("Waiting for notification to startup.");
                Thread.Sleep(TimeSpan.FromSeconds(10));

                var eventFrame = new AFEventFrame(db, eventFrameName)
                {
                    PrimaryReferencedElement = element,
                };

                Output.WriteLine($"Created event frame [{eventFrameName}].");
                eventFrame.SetStartTime(AFTime.Now);
                eventFrame.CheckIn();
                eventFrameId = eventFrame.ID;

                Output.WriteLine("Event frame start send.");
                Message msg;
                if (eventFrameStartSent)
                {
                    msg = NotificationsFixture.Service.WaitForMessage(TimeSpan.FromMinutes(1));
                    Assert.True(notificationRule.ID == msg.NotificationRuleId, "Notification rule is not set properly.");
                    Assert.True(msg.Content == nameof(NotificationRuleSendWebServiceEventFrameNotifyOptionTest), "The message content is not set properly.");
                }
                else
                {
                    var foundMessage = NotificationsFixture.Service.TryWaitForMessage(TimeSpan.FromMinutes(1), out msg);
                    Assert.False(foundMessage, $"Notification rule should not send any notification, but found message for notification rule Id: [{msg?.NotificationRuleId}].");
                }

                // Waiting for event frame close send
                eventFrame.SetEndTime(AFTime.Now);
                eventFrame.CheckIn();

                if (eventFrameEndSent)
                {
                    msg = NotificationsFixture.Service.WaitForMessage(TimeSpan.FromMinutes(1));
                    Assert.True(notificationRule.ID == msg.NotificationRuleId, "Notification rule is not set properly.");
                    Assert.True(msg.Content == nameof(NotificationRuleSendWebServiceEventFrameNotifyOptionTest), "The message content is not set properly.");
                }
                else
                {
                    var foundMessage = NotificationsFixture.Service.TryWaitForMessage(TimeSpan.FromMinutes(1), out msg);
                    Assert.False(foundMessage, $"Notification rule should not send any notification, but found message for notification rule Id: [{msg?.NotificationRuleId}].");
                }
            }
            finally
            {
                AFFixture.RemoveElementIfExists(elementName, Output);
                if (eventFrameId != null)
                {
                    AFFixture.RemoveEventFrameIfExists(eventFrameId.GetValueOrDefault(), Output);
                }
            }
        }

        /// <summary>
        /// Test notification rule can send notification to a web service successfully for an detected
        /// event frame, and won't resend the notification if acknowledged.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an element with a notification rule</para>
        /// <para>Create an event frame template</para>
        /// <para>Configure the notification rule criteria to Event Frame Search</para>
        /// <para>Add the created web service contact template to the subscriber of the notification rule</para>
        /// <para>Create an event frame from the event frame template</para>
        /// <para>Verify the notification is sent properly for the event frame</para>
        /// <para>Acknowledge the event frame</para>
        /// <para>Verify the notification stops sending when the event frame is acknowledged</para>
        /// <para>Delete the event frame and the element</para>
        /// </remarks>
        [OptionalFact(KeySetting, KeySettingTypeCode)]
        public void NotificationRuleResendWebServiceStopsOnAcknowledgmentTest()
        {
            Assert.True(NotificationsFixture.SoapWebServiceHost != null, "The Web Service host couldn't be started.");

            AFDatabase db = AFFixture.AFDatabase;
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleResendWebServiceStopsOnAcknowledgmentTest)}";
            var eventFrameTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_EventFrameTemplate1";
            var notificationRuleName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRule1";
            var eventFrameName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_EventFrame1";

            AFFixture.RemoveElementIfExists(elementName, Output);
            AFFixture.RemoveElementTemplateIfExists(eventFrameTemplateName, Output);
            Guid? eventFrameId = null;

            try
            {
                Output.WriteLine($"Create event frame template [{eventFrameTemplateName}] and element [{elementName}] with notification rule [{notificationRuleName}].");
                var efTemplate = db.ElementTemplates.Add(eventFrameTemplateName);
                efTemplate.InstanceType = typeof(AFEventFrame);
                efTemplate.CanBeAcknowledged = true;

                var element = db.Elements.Add(elementName);
                var notificationRule = element.NotificationRules.Add(notificationRuleName);
                notificationRule.Criteria = $"Template:{eventFrameTemplateName}";
                notificationRule.ResendInterval = TimeSpan.FromSeconds(30);
                var format = notificationRule.DeliveryFormats.Add("testFormat", WebServicePlugIn);
                NotificationsFixture.SetFormatProperties(format.Properties, nameof(NotificationRuleResendWebServiceStopsOnAcknowledgmentTest));

                var webServiceEndpoint = NotificationsFixture.GetSoapWebServiceEndpoint();
                var subscriber = notificationRule.Subscribers.Add(webServiceEndpoint);
                subscriber.DeliveryFormat = format;
                subscriber.NotifyOption = AFNotifyOption.EventStartAndEnd;
                notificationRule.SetStatus(AFStatus.Enabled);
                db.CheckIn();

                Output.WriteLine("Waiting for notification to startup.");
                Thread.Sleep(TimeSpan.FromSeconds(10));

                var eventFrame = new AFEventFrame(db, eventFrameName, efTemplate)
                {
                    PrimaryReferencedElement = element,
                };

                Output.WriteLine($"Create event frame [{eventFrameName}].");
                eventFrame.SetStartTime(AFTime.Now);
                eventFrame.CheckIn();
                eventFrameId = eventFrame.ID;

                Output.WriteLine("Event frame start send.");
                var msg = NotificationsFixture.Service.WaitForMessage(TimeSpan.FromMinutes(1));
                Assert.True(notificationRule.ID == msg.NotificationRuleId, "Notification rule is not set properly.");
                Assert.True(msg.Content == nameof(NotificationRuleResendWebServiceStopsOnAcknowledgmentTest), "The message content is not set properly.");

                Output.WriteLine($"Acknowledge the event frame with the Id: {eventFrameId}");
                eventFrame.Acknowledge();
                eventFrame.CheckIn();

                var foundMessage = NotificationsFixture.Service.TryWaitForMessage(TimeSpan.FromMinutes(1), out msg);
                Assert.False(foundMessage, $"Notification rule should not resend if acknowledged, but found message for notification rule with the Id: [{msg?.NotificationRuleId}].");
            }
            finally
            {
                AFFixture.RemoveElementTemplateIfExists(eventFrameTemplateName, Output);
                AFFixture.RemoveElementIfExists(elementName, Output);
                if (eventFrameId != null)
                {
                    AFFixture.RemoveEventFrameIfExists(eventFrameId.GetValueOrDefault(), Output);
                }
            }
        }
    }
}
