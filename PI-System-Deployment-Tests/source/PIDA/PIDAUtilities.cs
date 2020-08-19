using System;
using System.Diagnostics.Contracts;
using System.Globalization;
using System.IO;
using System.Net;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// PIDAUtilities Class.
    /// </summary>
    /// <remarks>
    /// This class encapsulates PIDA utilities for the PI System Deployment Tests.
    /// </remarks>
    public static class PIDAUtilities
    {
        private static string _piServerPath = string.Empty;
        private static string _piHomePath = string.Empty;
        private static string _piHome64Path = string.Empty;

        /// <summary>
        /// Returns a PI timestamp string in the format dd-MMM-yyyy HH:mm:ss.
        /// </summary>
        /// <param name="dateTime">The date/time to convert.</param>
        /// <param name="displaySubseconds">Flag indicating of sub-seconds should be included in the result.</param>
        /// <returns>The time as a string in PI absolute format.</returns>
        public static string ToPiTimeString(DateTime dateTime, bool displaySubseconds = false)
            => dateTime.ToString(displaySubseconds ? "dd-MMM-yyyy HH:mm:ss.fffff" : "dd-MMM-yyyy HH:mm:ss", CultureInfo.InvariantCulture);

        /// <summary>
        /// Find if PI messages with a particular ID are logged in the time window.
        /// </summary>
        /// <param name="fixture">The testing fixture.</param>
        /// <param name="startTime">The start time.</param>
        /// <param name="endTime">The end time.</param>
        /// <param name="id">The message id.</param>
        /// <param name="msgText">The message text that to be found in the log.</param>
        /// <returns>Return true if msgs with id and msgText are found in the log; otherwise false.</returns>
        public static bool FindMessagesInLog(PIFixture fixture, string startTime, string endTime, int id, string msgText)
        {
            Contract.Requires(fixture != null);
            Contract.Requires(startTime != null);
            Contract.Requires(endTime != null);
            Contract.Requires(msgText != null);

            string filename = GetPIGETMSGFullFileName();
            startTime = DoubleQuoteIfNeeded(startTime);
            endTime = DoubleQuoteIfNeeded(endTime);
            msgText = DoubleQuoteIfNeeded(msgText);

            string arguments = GenerateRemotePIToolArgumentsAsNeeded(fixture.PIServer.ConnectionInfo.Host) + $"-id {id} -st {startTime} -et {endTime} -msg {msgText} -sum";

            // Note: pigetmsg returns exit code 1 even though the command worked.
            // Ignore the exit code and just check the results.
            PIDAExternalToolHelper.RunProgram(filename, arguments, out string results, out _);

            if (!string.IsNullOrEmpty(results))
            {
                string searchText = "Total Messages: ";
                string resultLine = GetFirstLineThatStartsWith(results, searchText);
                if (!string.IsNullOrEmpty(resultLine))
                {
                    string countText = resultLine.Substring(resultLine.IndexOf(searchText, StringComparison.OrdinalIgnoreCase) + resultLine.Length - 1);
                    return Convert.ToInt32(countText, CultureInfo.InvariantCulture) > 0;
                }
            }

            return false;
        }

        /// <summary>
        /// Generate the PI tool parameters for remote access.
        /// </summary>
        /// <remarks>
        /// These will only be generated if you are not running directly on the target PI server.
        /// Note that these are the only tools that support remoting: pigetmsg
        /// </remarks>
        /// <returns>The arguments to be included in the command line for the PI tools.</returns>
        private static string GenerateRemotePIToolArgumentsAsNeeded(string hostName)
        {
            if (Utils.IsRunningOnTargetServer(Settings.PIDataArchive))
                return string.Empty;

            /*
            // Old-style comment structure required for stylecop build.
            // Here is the link to the OSIsoft Live Library entry that explains which PI core tools support remoting and the format of the parameters.
            // https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v9/GUID-BBFB9FD5-5DCB-4330-B73D-1ACAF51ABFFA#addHistory=true&filename=GUID-A411AAB1-A84E-4AD6-BEB1-EC3A0F686FFE.xml&docid=GUID-EABC9DBA-D400-4478-95F8-575202950F08&inner_id=&tid=&query=&scope=&resource=&toc=false&eventType=lcContent.loadDocGUID-EABC9DBA-D400-4478-95F8-575202950F08
            // You can use the -node option to remotely invoke the following PI Data Archive utilities:
            // pigetmsg

            // There are Windows, Trust and Explicit options.
            // For now this code only supports the Windows Active Directory option.
            // To support other options we can add additional information to the App.config and add the logic in here.
            // For the remoting to work with the Windows option you will need to create a Mapping on the target PI Server.
            // Map the domain user that is logged into the client computer and is running the tests to any PI Identity.
            */
            string results = $" -node {hostName} -windows "; // pre and post spaces included for simplicity of usage
            return results;
        }

        /// <summary>
        /// Get the PISERVER environment variable.
        /// </summary>
        /// <returns>The results.</returns>
        private static string GetPISERVERPath()
        {
            if (!string.IsNullOrEmpty(_piServerPath))
            {
                return _piServerPath;
            }
            else
            {
                _piServerPath = System.Environment.GetEnvironmentVariable("PISERVER");
                return _piServerPath;
            }
        }

        /// <summary>
        /// Get the PIHOME environment variable.
        /// </summary>
        /// <returns>The results.</returns>
        private static string GetPIHOMEPath()
        {
            if (!string.IsNullOrEmpty(_piHomePath))
            {
                return _piHomePath;
            }
            else
            {
                _piHomePath = System.Environment.GetEnvironmentVariable("PIHOME");
                return _piHomePath;
            }
        }

        /// <summary>
        /// Get the PIHOME environment variable for 64-bit.
        /// </summary>
        /// <returns>The results.</returns>
        private static string GetPIHOME64Path()
        {
            if (!string.IsNullOrEmpty(_piHome64Path))
            {
                return _piHome64Path;
            }
            else
            {
                _piHome64Path = System.Environment.GetEnvironmentVariable("PIHOME64");
                return _piHome64Path;
            }
        }

        /// <summary>
        /// Get the full file name of the PIGETMSG tool.
        /// </summary>
        /// <returns>The results.</returns>
        private static string GetPIGETMSGFullFileName()
        {
            string piGetMsgPath = string.Empty;

            if (!string.IsNullOrEmpty(GetPISERVERPath()))
            {
                piGetMsgPath = GetPISERVERPath();
            }
            else if (!string.IsNullOrEmpty(GetPIHOMEPath()))
            {
                piGetMsgPath = GetPIHOMEPath();
            }
            else if (!string.IsNullOrEmpty(GetPIHOME64Path()))
            {
                piGetMsgPath = GetPIHOME64Path();
            }

            return DoubleQuoteIfNeeded(Path.Combine(piGetMsgPath, "adm", "pigetmsg.exe"));
        }

        /// <summary>
        /// Double quote a string if needed. Duplicate double quotes are not added.
        /// </summary>
        /// <returns>The results.</returns>
        private static string DoubleQuoteIfNeeded(string data)
        {
            if (data.StartsWith("\"", StringComparison.OrdinalIgnoreCase))
                return data;

            return "\"" + data + "\"";
        }

        /// <summary>
        /// Get the first line in a set of lines that starts with a particular string.
        /// </summary>
        /// <param name="dataWithNewLines">The data. Will usually include new-line characters.</param>
        /// <param name="searchText">The search text.</param>
        /// <param name="ignoreCase">The ignore case flag.</param>
        /// <returns>True if at least one line starts with the search text; False otherwise.</returns>
        private static string GetFirstLineThatStartsWith(string dataWithNewLines, string searchText, bool ignoreCase = false)
        {
            using (var stringReader = new StringReader(dataWithNewLines))
            {
                string line;
                while ((line = stringReader.ReadLine()) != null)
                {
                    string trimmedLine = line.TrimStart();
                    if (trimmedLine.StartsWith(searchText, ignoreCase, CultureInfo.InvariantCulture))
                        return line;
                }
            }

            return string.Empty;
        }
    }
}
