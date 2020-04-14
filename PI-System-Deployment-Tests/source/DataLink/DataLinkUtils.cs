using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using Xunit;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// General test helper functions for Data Link tests.
    /// </summary>
    public static class DataLinkUtils
    {
        /// <summary>
        /// The path to Data Link's AFData.dll.
        /// </summary>
        public const string AFDataDLLPath = @"\Excel\OSIsoft.PIDataLink.AFData.dll";

        /// <summary>
        /// The AFLibrary class in the AFData.dll.
        /// </summary>
        public const string AFLibraryType = "OSIsoft.PIDataLink.AFData.AFLibrary";

        /// <summary>
        /// Get the PIHOME environment variable value.
        /// </summary>
        /// <param name="dirstring">The string reference the value will be stored in.</param>
        public static void GetPIHOME(ref string dirstring, int flag = -1)
        {
            // For 32-bit Office, get the PIHOME path from the pipc.ini file.
            // For 64-bit Office, get PIHOME from the registry.
            if ((Environment.Is64BitProcess || flag == 1) && flag != 0)
            {
                var piHomeKey = Microsoft.Win32.Registry.LocalMachine.OpenSubKey("Software\\PISystem");
                if (!(piHomeKey is null))
                {
                    dirstring = piHomeKey.GetValue("PIHOME").ToString();

                    // Check for and remove the trailing '\' from dirstring.
                    if (dirstring.EndsWith("\\", StringComparison.OrdinalIgnoreCase))
                        dirstring = dirstring.Substring(0, dirstring.Length - 1);
                }
                else
                {
                    Assert.True(false, "Could not locate the registry key Software\\PISystem");
                }
            }
            else
            {
                int lenstring = 255;
                var pihomepath = new StringBuilder(lenstring + 1);   // String to hold PIHOME in [PIPC]

                // Get the PIHOME from the pipc.ini file
                var trash = GetPrivateProfileString("PIPC", "PIHOME", "C:\\PIPC", pihomepath, lenstring, "PIPC.INI");
                dirstring = pihomepath.ToString().Trim();
            }
        }

        /// <summary>
        /// Checks if Data Link is installed on the test system.
        /// </summary>
        /// <returns>True if Data Link is installed, False if not.</returns>
        public static bool DataLinkIsInstalled()
        {
            // Get the PIPC directory
            string piHomeDir = string.Empty;
            DataLinkUtils.GetPIHOME(ref piHomeDir);

            // Get DataLink's AFData.dll and AFLibrary class
            var assembly = Assembly.LoadFrom(piHomeDir + AFDataDLLPath);
            var classType = assembly.GetType(AFLibraryType);

            // Create AFLibrary class instance
            dynamic classInst = Activator.CreateInstance(classType);
            return (classInst == null) ? false : true;
        }

        /// <summary>
        /// Retrieves a string from the specified section in an initialization file.
        /// </summary>
        /// <param name="lpappname">
        /// The name of the section containing the key name. If this parameter is NULL, the GetPrivateProfileString
        /// function copies all section names in the file to the supplied buffer.
        /// </param>
        /// <param name="lpkeyname">
        /// The name of the key whose associated string is to be retrieved. If this parameter is NULL, all key names
        /// in the section specified by the lpAppName parameter are copied to the buffer specified by the
        /// lpReturnedString parameter.
        /// </param>
        /// <param name="lpdefault">
        /// A default string. If the lpKeyName key cannot be found in the initialization file, GetPrivateProfileString
        /// copies the default string to the lpReturnedString buffer. If this parameter is NULL, the default is an
        /// empty string. Avoid specifying a default string with trailing blank characters.The function inserts a null
        /// character in the lpReturnedString buffer to strip any trailing blanks.
        /// </param>
        /// <param name="lpreturnedstring">
        /// A pointer to the buffer that receives the retrieved string.
        /// </param>
        /// <param name="nsize">
        /// The size of the buffer pointed to by the lpReturnedString parameter, in characters.
        /// </param>
        /// <param name="lpfilename">
        /// The name of the initialization file. If this parameter does not contain a full path to the file,
        /// the system searches for the file in the Windows directory.
        /// </param>
        /// <returns>
        /// The return value is the number of characters copied to the buffer, not including the terminating null character.
        /// If neither lpAppName nor lpKeyName is NULL and the supplied destination buffer is too small to hold the requested
        /// string, the string is truncated and followed by a null character, and the return value is equal to nSize minus one.
        /// If either lpAppName or lpKeyName is NULL and the supplied destination buffer is too small to hold all the strings,
        /// the last string is truncated and followed by two null characters.In this case, the return value is equal to nSize
        /// minus two. In the event the initialization file specified by lpFileName is not found, or contains invalid values,
        /// this function will set errorno with a value of '0x2' (File Not Found). To retrieve extended error information,
        /// call GetLastError.
        /// </returns>
        [DllImport("KERNEL32.DLL", CharSet = CharSet.Unicode, EntryPoint = "GetPrivateProfileString")]
        private static extern int GetPrivateProfileString(string lpappname, string lpkeyname, string lpdefault,
            StringBuilder lpreturnedstring, int nsize, string lpfilename);
    }
}
