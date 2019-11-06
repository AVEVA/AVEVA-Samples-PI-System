using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.ServiceModel;
using System.Threading;
using Xunit.Sdk;

namespace OSIsoft.PISystemDeploymentTests
{
    [ServiceBehavior(InstanceContextMode = InstanceContextMode.Single, ConcurrencyMode = ConcurrencyMode.Single)]
    internal class TestWebService : IWebService
    {
        private readonly ConcurrentQueue<Message> _queue;
        private int _messageId;

        public TestWebService()
        {
            _queue = new ConcurrentQueue<Message>();
        }

        public void Test(Guid ruleId, string content)
        {
            var messageId = Interlocked.Increment(ref _messageId);
            var msg = new Message()
            {
                MessageId = messageId,
                NotificationRuleId = ruleId,
                Content = content,
            };

            _queue.Enqueue(msg);
        }

        public Message WaitForMessage(TimeSpan timeout)
        {
            if (!TryWaitForMessage(timeout, out var message))
            {
                throw new XunitException($"Waiting for message operation timed out. Timeout: {timeout}.");
            }

            return message;
        }

        public bool TryWaitForMessage(TimeSpan timeout, out Message message)
        {
            var stopwatch = Stopwatch.StartNew();
            var interval = (int)(timeout.TotalMilliseconds / 100);
            while (true)
            {
                if (_queue.TryDequeue(out message))
                    return true;

                if (stopwatch.Elapsed < timeout)
                    Thread.Sleep(interval);

                if (stopwatch.Elapsed >= timeout)
                    return false;
            }
        }

        internal class Message
        {
            public int MessageId { get; set; }

            public Guid NotificationRuleId { get; set; }

            public string Content { get; set; }
        }
    }
}
