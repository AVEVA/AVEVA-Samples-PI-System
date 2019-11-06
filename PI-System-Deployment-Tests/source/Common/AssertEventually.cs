using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Threading;
using Xunit;
using Xunit.Sdk;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// An extension to Assert calls the utilizes polling.
    /// </summary>
    /// <remarks>
    /// Methods will retry the assert action until it returns true or the execution time exceeds the specified timeout.
    /// </remarks>
    public static class AssertEventually
    {
        // Default timeout and polling interval
        private static TimeSpan _defaultTimeOut = TimeSpan.FromSeconds(30);
        private static TimeSpan _defaultPollInterval = TimeSpan.FromSeconds(1);

        /// <summary>
        /// Verifies that two objects are equal, using a default comparer, by retrying the comparison.
        /// </summary>
        /// <param name="expectedValue">The expected value returned from the action function.</param>
        /// <param name="action">The action function to execute that should return the expected value if successful.</param>
        /// <param name="timeout">The maximum time to wait for the action function to return the expected value.</param>
        /// <param name="pollInterval">How often to call the action function. This should be less than the timeout.</param>
        public static void Equal<T>(T expectedValue, Func<T> action, TimeSpan timeout, TimeSpan pollInterval)
        {
            var comparer = EqualityComparer<T>.Default;
            void AssertAction() => Assert.Equal<T>(expectedValue, action());
            PollWhileFalseThenAssert<XunitException>(AssertAction, timeout, pollInterval);
        }

        /// <summary>
        /// Verifies that an expression is true, by retrying the comparison, using default polling interval and timeout.
        /// </summary>
        /// <remarks>
        /// If expression is not true, the given message is returned from assertion.
        /// </remarks>
        /// <param name="action">The action function to execute that should return true if successful.</param>
        /// <param name="message">The error message to display if the action is not successful.</param>
        /// <param name="args">The list of arguments used to create the message if the action is not successful.</param>
        public static void True(Func<bool> action, string message, params object[] args)
            => True(action, _defaultTimeOut, _defaultPollInterval, message, args);

        /// <summary>
        /// Verifies that an expression is true, by retrying the comparison.
        /// </summary>
        /// <remarks>
        /// If expression is not true, the given message is returned from assertion.
        /// </remarks>
        /// <param name="action">The action function to execute that should return true if successful.</param>
        /// <param name="timeout">The maximum time to wait for the action function to return the expected value of true.</param>
        /// <param name="pollInterval">How often to call the action function. This should be less than the timeout.</param>
        /// <param name="message">The error message to display if the action is not successful.</param>
        /// <param name="args">The list of arguments used to create the message if the action is not successful.</param>
        public static void True(Func<bool> action, TimeSpan timeout, TimeSpan pollInterval, string message, params object[] args)
        {
            void AssertAction() => Assert.True(action(), CreateMessage(timeout, message, args));
            PollWhileFalseThenAssert<XunitException>(AssertAction, timeout, pollInterval);
        }

        private static void PollWhileFalseThenAssert<T>(Action assertAction, TimeSpan timeout, TimeSpan pollInterval)
            where T : Exception
        {
            var stopwatch = Stopwatch.StartNew();
            bool success = true;
            string errMsg = string.Empty;

            while (!(success = PredicateTryCatchWrapper<T>(assertAction, out errMsg)) && stopwatch.Elapsed < timeout)
            {
                Thread.Sleep(pollInterval);
            }

            if (!success)
            {
                errMsg = Environment.MachineName.ToUpperInvariant() + ": " + (string.IsNullOrEmpty(errMsg) ? "No Message" : errMsg);
                throw new XunitException(errMsg);
            }
        }

        private static bool PredicateTryCatchWrapper<T>(Action assertAction, out string errMsg) where T : Exception
        {
            bool flag = true;
            try
            {
                assertAction();
                errMsg = string.Empty;
            }
            catch (T ex)
            {
                errMsg = ex.ToString();
                flag = false;
            }

            return flag;
        }

        private static string CreateMessage(TimeSpan timeout, string message, params object[] args)
            => string.Format(CultureInfo.CurrentCulture, $"Waited for {timeout}. {message}", args);
    }
}
