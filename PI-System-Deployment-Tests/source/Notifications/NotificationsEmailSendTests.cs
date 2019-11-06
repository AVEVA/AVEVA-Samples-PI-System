using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;
using OSIsoft.AF;
using OSIsoft.AF.Analysis;
using OSIsoft.AF.EventFrame;
using OSIsoft.AF.Notification;
using OSIsoft.AF.Time;
using Xunit;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// These tests verify the notification send operations to email delivery endpoint(s), including the
    /// tests for annotations, group contact delivery and escalation contact delivery.
    /// </summary>
    /// <remarks>
    /// Note: These tests will be skipped if the SMTP server configuration is not configured.
    /// </remarks>
    public partial class NotificationTests : IClassFixture<AFFixture>, IClassFixture<NotificationsFixture>
    {
        /// <summary>
        /// Test notification rule can send notification to an email delivery endpoint successfully for an detected
        /// event frame, and the annotations for the event frame is added properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create an email contact template</para>
        /// <para>Create an element with a notification rule</para>
        /// <para>Configure the notification rule criteria to Event Frame Search</para>
        /// <para>Add the contact template to the subscriber of the notification rule</para>
        /// <para>Create an event frame</para>
        /// <para>Verify the notification is sent for the event frame and the annotation is set properly</para>
        /// <para>Verify the content of the annotation is set properly</para>
        /// <para>Delete the contact template, event frame and the element</para>
        /// </remarks>
        [NotificationsFact]
        public void NotificationRuleSendEmailAnnotationTest()
        {
            AFDatabase db = AFFixture.AFDatabase;
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleSendEmailAnnotationTest)}";
            var notificationRuleName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRule1";
            var eventFrameName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_EventFrame1";

            AFFixture.RemoveElementIfExists(elementName, Output);
            Guid? eventFrameId = null;
            AFNotificationContactTemplate emailEndpoint = null;

            try
            {
                emailEndpoint = CreateEmailEndpoint(nameof(NotificationRuleSendEmailAnnotationTest));
                Output.WriteLine($"Create email notification contact template [{emailEndpoint.Name}].");
                PISystem.CheckIn();

                Output.WriteLine($"Create element [{elementName}] with notification rule [{notificationRuleName}]");
                var element = db.Elements.Add(elementName);
                var notificationRule = element.NotificationRules.Add(notificationRuleName);
                notificationRule.Criteria = $"Name:{NotificationsFixture.TestPrefix}*";
                var format = notificationRule.DeliveryFormats.Add("testFormat", EmailPlugIn);
                NotificationsFixture.SetFormatProperties(format.Properties, nameof(NotificationRuleSendEmailAnnotationTest));

                var subscriber = notificationRule.Subscribers.Add(emailEndpoint);
                subscriber.DeliveryFormat = format;

                notificationRule.SetStatus(AFStatus.Enabled);
                db.CheckIn();

                Output.WriteLine("Waiting for notification to startup.");
                Thread.Sleep(TimeSpan.FromSeconds(10));

                var eventFrame = new AFEventFrame(db, eventFrameName)
                {
                    PrimaryReferencedElement = element,
                };

                eventFrame.SetStartTime(AFTime.Now);
                eventFrame.CheckIn();
                eventFrameId = eventFrame.ID;
                Output.WriteLine($"Created event frame [{eventFrameName}].");

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
                Assert.False(string.IsNullOrWhiteSpace(annotations[0].Description), "The description of the annotation is not set properly.");
                Assert.True((string)annotations[0].Value == string.Format(CultureInfo.InvariantCulture, NotificationsFixture.SentAnnotation, 1),
                    "The value of the annotation is not set properly.");

                Output.WriteLine("Verify the content of the annotation is set properly.");
                Assert.False(string.IsNullOrWhiteSpace(annotations[0].Description), "The description of the annotation is not set properly.");
                var description = NotificationsFixture.DeserializeAnnotationDescription(annotations[0].Description);
                var subscribers = description.Subscribers;
                Assert.True(description.Notification == notificationRuleName, "The notification rule name is not set properly.");
                Assert.True(subscribers.Count == 1, $"Expected to get only one subscriber, but got {description.Subscribers.Count}.");
                Assert.True(subscribers[0].Name == emailEndpoint.Name, "The name of the subscriber is not set properly.");
                Assert.True(subscribers[0].Configuration == Settings.PINotificationsRecipientEmailAddress, "The email address of the subscriber is not set properly.");
                Assert.True(subscribers[0].Type == "Email", "The type of the subscriber is not set properly.");
            }
            finally
            {
                AFFixture.RemoveElementIfExists(elementName, Output);
                if (eventFrameId != null)
                {
                    AFFixture.RemoveEventFrameIfExists(eventFrameId.GetValueOrDefault(), Output);
                }

                if (emailEndpoint != null)
                {
                    PISystem.NotificationContactTemplates.Remove(emailEndpoint.ID);
                    PISystem.CheckIn();
                }
            }
        }

        /// <summary>
        /// Test notification rule can send notification to a group contact (with multiple email delivery
        /// endpoints added) successfully for an detected event frame, and the annotations for the event frame
        /// is added properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create multiple email contact templates and a group contact template</para>
        /// <para>Add the multiple email contacts to the group contact</para>
        /// <para>Create an element with a notification rule</para>
        /// <para>Configure the notification rule criteria to Event Frame Search</para>
        /// <para>Add the group contact to the subscriber of the notification rule</para>
        /// <para>Create an event frame</para>
        /// <para>Verify the notification is sent for the event frame and the annotation is set properly</para>
        /// <para>Verify the content of the annotation is set properly</para>
        /// <para>Verify the subscriber information of the multiple email contacts</para>
        /// <para>Delete the contact templates, event frame and the element</para>
        /// </remarks>
        [NotificationsFact]
        public void NotificationRuleSendToGroupContactTest()
        {
            AFDatabase db = AFFixture.AFDatabase;
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleSendToGroupContactTest)}";
            var notificationRuleName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRule1";
            var groupNotificationContactTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_Group1";
            var eventFrameName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_EventFrame1";
            var emailContactsCountInGroup = 3;

            AFFixture.RemoveElementIfExists(elementName, Output);
            Guid? eventFrameId = null;
            var emailEndpoints = new List<AFNotificationContactTemplate>();
            AFNotificationContactTemplate group = null;

            try
            {
                Output.WriteLine($"Create group notification contact template [{groupNotificationContactTemplateName}]" +
                    $" with [{emailContactsCountInGroup}] email notification contact templates added.");
                group = new AFNotificationContactTemplate(PISystem, groupNotificationContactTemplateName)
                {
                    ContactType = AFNotificationContactType.Group,
                };
                group.CheckIn();

                for (var i = 0; i < emailContactsCountInGroup; i++)
                {
                    var emailEndpoint = CreateEmailEndpoint($"{nameof(NotificationRuleSendToGroupContactTest)}_{i}");
                    group.NotificationContactTemplates.Add(emailEndpoint);
                    emailEndpoints.Add(emailEndpoint);
                }

                PISystem.CheckIn();

                Output.WriteLine($"Create element [{elementName}] with notification rule [{notificationRuleName}].");
                var element = db.Elements.Add(elementName);
                var notificationRule = element.NotificationRules.Add(notificationRuleName);
                notificationRule.Criteria = $"Name:{NotificationsFixture.TestPrefix}*";
                var subscriber = notificationRule.Subscribers.Add(group);
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
                Assert.True(annotations[0].Name == NotificationsFixture.AnnotationName, "The name of the annotation is not set properly.");
                Assert.True((string)annotations[0].Value == string.Format(CultureInfo.InvariantCulture, NotificationsFixture.SentAnnotation, emailContactsCountInGroup),
                    "The value of the annotation is not set properly.");

                Output.WriteLine("Verify the content of the annotation is set properly.");
                Assert.False(string.IsNullOrWhiteSpace(annotations[0].Description), "The description of the annotation is not set properly.");
                var description = NotificationsFixture.DeserializeAnnotationDescription(annotations[0].Description);
                var subscribers = description.Subscribers;
                Assert.True(description.Notification == notificationRuleName, "The notification rule name is not set properly.");
                Assert.True(subscribers.Count == emailContactsCountInGroup, $"Expected to get [{emailContactsCountInGroup}] subscribers, but got {description.Subscribers.Count}.");

                Output.WriteLine("Verify the subscriber information of the multiple email contacts.");
                for (int i = 0; i < emailContactsCountInGroup; i++)
                {
                    Assert.True(subscribers[i].Name == emailEndpoints[i].Name, $"The name of the [{i}] subscriber is not set properly.");
                    Assert.True(subscribers[i].Configuration == Settings.PINotificationsRecipientEmailAddress, $"The email address of the [{i}] subscriber is not set properly.");
                    Assert.True(subscribers[i].Type == "Email", $"The type of the [{i}] subscriber is not set properly.");
                }
            }
            finally
            {
                AFFixture.RemoveElementIfExists(elementName, Output);
                if (eventFrameId != null)
                    AFFixture.RemoveEventFrameIfExists(eventFrameId.GetValueOrDefault(), Output);

                if (group != null)
                    PISystem.NotificationContactTemplates.Remove(group.ID);

                foreach (var emailEndpoint in emailEndpoints)
                {
                    PISystem.NotificationContactTemplates.Remove(emailEndpoint.ID);
                }

                PISystem.CheckIn();
            }
        }

        /// <summary>
        /// Test notification rule can send notification to an escalation contact (with multiple email delivery
        /// endpoints added) successfully for an detected event frame, and the annotations for the event frame
        /// is added properly.
        /// </summary>
        /// <remarks>
        /// Test Steps:
        /// <para>Create multiple email contact templates and an escalation contact template</para>
        /// <para>Add the multiple email contacts to the escalation contact and configure the escalation period</para>
        /// <para>Create an element with a notification rule</para>
        /// <para>Configure the notification rule criteria to Event Frame Search</para>
        /// <para>Add the escalation contact to the subscriber of the notification rule</para>
        /// <para>Create an event frame</para>
        /// <para>Verify the notification is sent for the event frame and the annotation is set properly</para>
        /// <para>Verify the content of the annotation is set properly</para>
        /// <para>Delete the contact templates, event frame and the element</para>
        /// </remarks>
        [NotificationsFact]
        public void NotificationRuleSendToEscalationContactTest()
        {
            AFDatabase db = AFFixture.AFDatabase;
            var elementName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_{nameof(NotificationRuleSendToEscalationContactTest)}";
            var notificationRuleName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_NotificationRule1";
            var escalationNotificationContactTemplateName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_Escalation1";
            var eventFrameName = $"{NotificationsFixture.TestPrefix}_{NotificationsFixture.TestInfix}_EventFrame1";
            var emailContactsCountInEscalation = 2;
            var escalationPeriod = TimeSpan.FromSeconds(20);

            AFFixture.RemoveElementIfExists(elementName, Output);
            Guid? eventFrameId = null;
            var emailEndpoints = new List<AFNotificationContactTemplate>();
            AFNotificationContactTemplate escalation = null;

            try
            {
                Output.WriteLine($"Created group notification contact template [{escalationNotificationContactTemplateName}]" +
                    $" with [{emailContactsCountInEscalation}] email notification contact added.");
                escalation = new AFNotificationContactTemplate(PISystem, escalationNotificationContactTemplateName)
                {
                    ContactType = AFNotificationContactType.Escalation,
                    EscalationTimeout = escalationPeriod,
                };
                escalation.CheckIn();

                for (var i = 0; i < emailContactsCountInEscalation; i++)
                {
                    var emailEndpoint = CreateEmailEndpoint($"{nameof(NotificationRuleSendToEscalationContactTest)}_{i}");
                    escalation.NotificationContactTemplates.Add(emailEndpoint);
                    emailEndpoints.Add(emailEndpoint);
                }

                PISystem.CheckIn();

                Output.WriteLine($"Created element [{elementName}] with notification rule [{notificationRuleName}].");
                var element = db.Elements.Add(elementName);
                var notificationRule = element.NotificationRules.Add(notificationRuleName);
                notificationRule.Criteria = $"Name:{NotificationsFixture.TestPrefix}*";
                var subscriber = notificationRule.Subscribers.Add(escalation);
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

                Output.WriteLine("Waiting for escalation period.");
                Thread.Sleep(TimeSpan.FromSeconds(30));

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
                Assert.True(annotations.Count == emailContactsCountInEscalation, $"Expected to get [{emailContactsCountInEscalation}] annotations, but got [{annotations.Count}].");
                for (var i = 0; i < emailContactsCountInEscalation; i++)
                {
                    Assert.True(annotations[i].Name == NotificationsFixture.AnnotationName, "The name of the annotation is not set properly.");

                    Assert.False(string.IsNullOrWhiteSpace(annotations[i].Description), "The description of the annotation is not set properly.");
                    var description = NotificationsFixture.DeserializeAnnotationDescription(annotations[i].Description);
                    var subscribers = description.Subscribers;
                    Assert.True(description.Notification == notificationRuleName, "The notification rule name is not set properly.");
                    Assert.True(subscribers.Count == 1, $"Expected to get only one subscriber, but got {description.Subscribers.Count}.");
                    Assert.True(subscribers[0].Name == emailEndpoints[i].Name, $"The name of the [{i}] subscriber is not set properly.");
                    Assert.True(subscribers[0].Configuration == Settings.PINotificationsRecipientEmailAddress, $"The configuration of the [{i}] subscriber is not displayed in the annotation.");
                    Assert.True(subscribers[0].Type == "Email", $"The type of the [{i}] subscriber is not set properly.");

                    if (i == 0)
                    {
                        Assert.True((string)annotations[i].Value == string.Format(CultureInfo.InvariantCulture, NotificationsFixture.SentAnnotation, 1),
                            "The value of the annotation is not set properly.");
                    }
                    else
                    {
                        Assert.True((string)annotations[i].Value == string.Format(CultureInfo.InvariantCulture, NotificationsFixture.EscalatedAnnotation, 1),
                            "The value of the annotation is not set properly.");
                    }
                }

                for (var i = emailContactsCountInEscalation - 1; i > 0; i--)
                {
                    Assert.True(annotations[i].CreationDate - annotations[i - 1].CreationDate >= escalationPeriod, $"The escalation period is not performed properly.");
                }
            }
            finally
            {
                AFFixture.RemoveElementIfExists(elementName, Output);
                if (eventFrameId != null)
                    AFFixture.RemoveEventFrameIfExists(eventFrameId.GetValueOrDefault(), Output);

                if (escalation != null)
                    PISystem.NotificationContactTemplates.Remove(escalation.ID);

                foreach (var emailEndpoint in emailEndpoints)
                {
                    PISystem.NotificationContactTemplates.Remove(emailEndpoint.ID);
                }

                PISystem.CheckIn();
            }
        }

        private AFNotificationContactTemplate CreateEmailEndpoint(string notificationContactTemplateName)
        {
            var email = new AFNotificationContactTemplate(AFFixture.PISystem, $"{NotificationsFixture.TestPrefix}_{notificationContactTemplateName}")
            {
                DeliveryChannelPlugIn = EmailPlugIn,
                ConfigString = $"ToEmail={Settings.PINotificationsRecipientEmailAddress};FromEmail=testFromEmail@osisoft.com;UseGlobalFromEmail=false;UseHtml=false",
            };

            return email;
        }
    }
}
