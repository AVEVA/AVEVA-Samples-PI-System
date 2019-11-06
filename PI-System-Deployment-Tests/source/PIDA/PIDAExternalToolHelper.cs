using System;
using System.Diagnostics;
using System.Text;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// PIDAExternalToolHelper Class.
    /// </summary>
    /// <remarks>
    /// This class encapsulates helper functions for the PI System Deployment Tests.
    /// </remarks>
    public static class PIDAExternalToolHelper
    {
        /// <summary>
        /// Runs an external program with arguments and get the results and exit code.
        /// </summary>
        /// <param name="filename">The program to run.</param>
        /// <param name="arguments">The arguments.</param>
        /// <param name="results">The results.</param>
        /// <param name="exitCode">The exit code.</param>
        /// <param name="waitTimeInSeconds">The wait time in seconds.</param>
        public static void RunProgram(string filename, string arguments, out string results, out int exitCode, int waitTimeInSeconds = 60)
        {
            using (var process = new Process())
            {
                process.StartInfo.FileName = filename;
                if (!string.IsNullOrEmpty(arguments))
                    process.StartInfo.Arguments = arguments;

                process.StartInfo.CreateNoWindow = true;
                process.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
                process.StartInfo.UseShellExecute = false;
                process.StartInfo.RedirectStandardOutput = true;
                process.StartInfo.RedirectStandardError = true;
                process.StartInfo.RedirectStandardInput = false;

                var stdOutputAndError = new StringBuilder();
                process.OutputDataReceived += (sender, args) => stdOutputAndError.AppendLine(args.Data);
                process.ErrorDataReceived += (sender, args) => stdOutputAndError.AppendLine(args.Data);

                process.Start();

                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                process.WaitForExit((int)TimeSpan.FromSeconds(waitTimeInSeconds * 1000).TotalSeconds);

                results = stdOutputAndError.ToString();
                exitCode = process.ExitCode;
            }
        }
    }
}
