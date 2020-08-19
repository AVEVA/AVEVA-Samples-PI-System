using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics.Contracts;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using OSIsoft.AF;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using OSIsoft.AF.UnitsOfMeasure;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Test context class to be shared in PI related xUnit test classes.
    /// </summary>
    /// <remarks>
    /// xUnit.net ensures that the fixture instance will be created before any tests run and
    /// when all tests are done will clean up the fixture object with 'Dispose' call.
    /// This fixture includes helper functions isolated to PI DataArchive related calls.
    /// See Utils.cs for more general test helper functions.
    /// </remarks>
    public sealed class PIFixture : IDisposable
    {
        #region Wind Farm Database Constants

        /// <summary>
        /// All PI Points created in the OSIsoft PI System Deployment Tests share the same PI PointSource.
        /// </summary>
        public const string TestPIPointSource = "OSIsoftTests";

        /// <summary>
        /// The SineWave name mask.
        /// </summary>
        /// <remarks>
        /// In Wind Farm database, each turbine element contains one SineWave attribute with PI Point data reference
        /// at ElementTemplates[Turbine]|Analog|SineWave.
        /// </remarks>
        public const string SineWavePointNameMask = "OSIsoftTests*SineWave";

        /// <summary>
        /// The length of the sign wave in hours.
        /// </summary>
        public const int SineWaveLengthInHours = 3;
        #endregion

        /// <summary>
        /// A small tolerance used to check the equality of two double values, especially when the values are equal or close to 0.
        /// </summary>
        public const double Epsilon = 1e-9;

        private const int MaxDegreeOfParallelism = 8;
        private const int PointPageSize = 1000;

        /// <summary>
        /// Creates an instance of the PIFixture class.
        /// </summary>
        public PIFixture()
        {
            var dataArchiveName = Settings.PIDataArchive;
            var servers = PIServers.GetPIServers();
            PIServer = servers[dataArchiveName];

            if (PIServer != null)
            {
                PIServer.Connect();
            }
            else
            {
                throw new InvalidOperationException(
                    $"The specific PI Data Archive [{dataArchiveName}] does not exist or is not configured.");
            }
        }

        /// <summary>
        /// The PI Server to be tested associated with this fixture.
        /// </summary>
        /// <value>
        /// Returns the PI Server object to be used for the test.
        /// </value>
        public PIServer PIServer { get; private set; }

        /// <summary>
        /// Converts a time stamp to a float value based on its OLE Automation date.
        /// </summary>
        /// <param name="timeStamp">A time stamp to be converted.</param>
        /// <returns>Returns the float version of the specified timestamp.</returns>
        public static float ConvertTimeStampToFloat(DateTime timeStamp) =>
            (float)timeStamp.ToOADate() * 1000000;

        /// <summary>
        /// PIFixture dispose method to close down connections when ending.
        /// </summary>
        public void Dispose() => PIServer.Disconnect();

        /// <summary>
        /// Creates a number of PI Points with the default attribute values with option to turn off compression.
        /// </summary>
        /// <param name="pointNameFormat">A point naming string with the first group of consecutive '#' serving as the placeholder for digits.</param>
        /// <param name="pointCount">The number of PI Points to be created.</param>
        /// <param name="turnoffCompression">Will create PI Point with compression turned off if True (default False).</param>
        /// <returns>Returns the list of created PI Points.</returns>
        public IEnumerable<PIPoint> CreatePIPoints(string pointNameFormat, int pointCount, bool turnoffCompression = false)
        {
            var attributeValues = new Dictionary<string, object>()
            {
                { PICommonPointAttributes.PointSource, TestPIPointSource },
            };

            if (turnoffCompression)
            {
                attributeValues.Add(PICommonPointAttributes.ExceptionDeviation, 0);
                attributeValues.Add(PICommonPointAttributes.ExceptionMaximum, 0);
                attributeValues.Add(PICommonPointAttributes.Compressing, 0);
            }

            return CreatePIPoints(pointNameFormat, pointCount, attributeValues);
        }

        /// <summary>
        /// Creates a number of PI Points with the default attribute values unless specified.
        /// </summary>
        /// <param name="pointNameFormat">A PI Point naming string with the first group of consecutive '#' serving as the placeholder for digits.</param>
        /// <param name="pointCount">The number of PI Points to be created.</param>
        /// <param name="pointAttributes">List of PI Point attributes to be used when creating Points. If null, then default attribute values will be used.</param>
        /// <returns>Returns the list of created PI Points.</returns>
        public IEnumerable<PIPoint> CreatePIPoints(string pointNameFormat, int pointCount, Dictionary<string, object> pointAttributes)
        {
            // The first group of consecutive # will serve as the placeholder for digits.
            // If the maximum PI Point count is less than the specified Point count, an exception will be thrown.
            string hashSymbol = Regex.Match(pointNameFormat, @"#+").Groups[0].Value;
            int maxpointCount = (int)Math.Pow(10, hashSymbol.Length);
            if (pointCount > maxpointCount)
                throw new InvalidOperationException($"The pointNameFormat of [{pointNameFormat}] does not support {pointCount} points.");

            var pointNames = new List<string>();
            if (string.IsNullOrWhiteSpace(hashSymbol))
            {
                pointNames.Add(pointNameFormat);
            }
            else
            {
                string digitFormat = $"D{hashSymbol.Length}";
                for (int i = 0; i < pointCount; i++)
                {
                    pointNames.Add(pointNameFormat.Replace(hashSymbol, i.ToString(digitFormat, CultureInfo.InvariantCulture)));
                }
            }

            // Process PI Points in pages
            var points = new AFListResults<string, PIPoint>();
            int j = 0;
            foreach (IList<string> pointGroup in pointNames.GroupBy(name => j++ / PointPageSize).Select(g => g.ToList()))
            {
                AFListResults<string, PIPoint> results = PIServer.CreatePIPoints(pointGroup, pointAttributes);
                if (results.Errors.Count > 0)
                    throw results.Errors.First().Value;
                points.AddResults(results);
            }

            return points;
        }

        /// <summary>
        /// Deletes the PI Points matching the name filter.
        /// </summary>
        /// <param name="nameFilter">Name filter to use when deleting PI Points.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void DeletePIPoints(string nameFilter, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            var pointList = new List<PIPoint>();
            pointList.AddRange(PIPoint.FindPIPoints(PIServer, nameFilter));

            if (pointList.Count <= 0)
                output.WriteLine($"Did not find any PI Points to delete with name filter [{nameFilter}].");
            else
                output.WriteLine($"PI Points with name filter [{nameFilter}] found. Removing from [{PIServer.Name}].");

            // Process PI Points in pages
            int i = 0;
            foreach (IList<PIPoint> pointGroup in pointList.GroupBy(name => i++ / PointPageSize).Select(g => g.ToList()))
            {
                AFErrors<string> errors = PIServer.DeletePIPoints(pointGroup.Select(pt => pt.Name));
                if (errors != null)
                    throw errors.Errors.First().Value;
            }
        }

        /// <summary>
        /// Creates a PI Point with the default attribute values  with option to turn off compression.
        /// </summary>
        /// <param name="pointName">The name of the PI Point to be created.</param>
        /// <param name="turnOffCompression">Will create PI Point with compression turned off if True (default False).</param>
        /// <returns>Returns the created PI Point.</returns>
        public PIPoint CreatePIPoint(string pointName, bool turnOffCompression = false)
        {
            var attributeValues = new Dictionary<string, object>()
                {
                    { PICommonPointAttributes.PointSource, TestPIPointSource },
                };

            if (turnOffCompression)
            {
                attributeValues.Add(PICommonPointAttributes.ExceptionDeviation, 0);
                attributeValues.Add(PICommonPointAttributes.ExceptionMaximum, 0);
                attributeValues.Add(PICommonPointAttributes.Compressing, 0);
            }

            return PIServer.CreatePIPoint(pointName, attributeValues);
        }

        /// <summary>
        /// Removes the PI Point from the PI Server (Data Archive) if it exists.
        /// </summary>
        /// <param name="pointName">The name of the PI Point to remove.</param>
        /// <param name="output">The output logger used for writing messages.</param>
        public void RemovePIPointIfExists(string pointName, ITestOutputHelper output)
        {
            Contract.Requires(output != null);

            if (PIPoint.TryFindPIPoint(PIServer, pointName, out _))
            {
                output.WriteLine($"PI Point [{pointName}] found. Removing it from [{PIServer.Name}].");
                PIServer.DeletePIPoint(pointName);
            }
            else
            {
                output.WriteLine($"PI Point [{pointName}] not found. Cannot remove it from [{PIServer.Name}].");
            }
        }

        /// <summary>
        /// Sends a number of events to each PI Point in a PI Point list.
        /// </summary>
        /// <remarks>
        /// By default the events' timestamp increments by 1 second and the values are calculated from the timestamps.
        /// If the eventsToSend parameter is specified then those events are used explicitly.
        /// </remarks>
        /// <param name="startTime">Start time used for event time stamps.</param>
        /// <param name="eventCount">Number of events to write to PI Data Archive.</param>
        /// <param name="piPoints">List of PI Points to which events will be written.</param>
        /// <param name="eventsToSend">OPTIONAL events to use (instead of being generated by routine).</param>
        public void SendTimeBasedPIEvents(AFTime startTime, int eventCount, List<PIPoint> piPoints, Dictionary<DateTime, double> eventsToSend = null)
        {
            // Build PI events as needed
            if (eventsToSend == null)
            {
                DateTime st = startTime;
                eventsToSend = new Dictionary<DateTime, double>();
                for (int i = 0; i < eventCount; i++)
                {
                    DateTime ts = st.AddSeconds(i);
                    eventsToSend.Add(ts, PIFixture.ConvertTimeStampToFloat(ts));
                }
            }

            object[] vals = eventsToSend.Values.Cast<object>().ToArray();
            DateTime[] timeStamps = eventsToSend.Keys.ToArray();
            AFValueStatus[] statuses = Enumerable.Range(0, eventCount).Select(_ => AFValueStatus.Good).ToArray();
            UOM nullUOM = null;

            var newValues = new List<AFValues>();
            var pointList = new PIPointList(piPoints);
            foreach (PIPoint pt in pointList)
            {
                var newAFValues = new AFValues(vals, timeStamps, statuses, nullUOM)
                {
                    PIPoint = pt,
                };
                newValues.Add(newAFValues);
            }

            if (newValues.Count == 0)
                return;

            // Send PI events
            foreach (AFValues values in newValues)
            {
                AFErrors<AFValue> errors = PIServer.UpdateValues(values.ToList(), AFUpdateOption.NoReplace);
                if (errors != null)
                    throw errors.Errors.First().Value;
            }
        }

        /// <summary>
        /// Reads PI events from a list of PI Points with specified start time and maximum event count.
        /// </summary>
        /// <param name="pointList">List of PI Points from which to read events.</param>
        /// <param name="startTime">Start time used to read events.</param>
        /// <param name="maxEventCount">Maximum number of events to read.</param>
        /// <returns>Returns a dictionary where the key is the PI Point name and the value are the AFValues for the PI Point.</returns>
        public IDictionary<string, AFValues> ReadPIEvents(IEnumerable<PIPoint> pointList, AFTime startTime, int maxEventCount)
        {
            var results = new ConcurrentDictionary<string, AFValues>();
            Parallel.ForEach(
             pointList,
             new ParallelOptions { MaxDegreeOfParallelism = MaxDegreeOfParallelism },
             pt =>
             {
                 AFValues values = pt.RecordedValuesByCount(
                     startTime,
                     maxEventCount,
                     true,
                     AFBoundaryType.Inside,
                     null,
                     false);

                 results.TryAdd(pt.Name, values);
             });

            return results.ToDictionary(kvp => kvp.Key, kvp => kvp.Value);
        }

        /// <summary>
        /// Reads PI events from a list of PI Points with specified start time and end time.
        /// </summary>
        /// <param name="pointList">List of PI Points from which to read events.</param>
        /// <param name="startTime">Start time used to read events.</param>
        /// <param name="endTime">End time used to read events.</param>
        /// <returns>Returns a dictionary where the key is the PI Point name and the value are the AFValues for the PI Point.</returns>
        public IDictionary<string, AFValues> ReadPIEvents(IEnumerable<PIPoint> pointList, AFTime startTime, AFTime endTime)
        {
            var results = new ConcurrentDictionary<string, AFValues>();
            var timeRange = new AFTimeRange(startTime, endTime);
            Parallel.ForEach(
                pointList,
                new ParallelOptions { MaxDegreeOfParallelism = MaxDegreeOfParallelism },
                pt =>
                {
                    AFValues values = pt.RecordedValues(
                        timeRange,
                        AFBoundaryType.Inside,
                        null,
                        false);

                    results.TryAdd(pt.Name, values);
                });

            return results.ToDictionary(kvp => kvp.Key, kvp => kvp.Value);
        }

        /// <summary>
        /// Placeholder class for applying CollectionDefinitionAttribute and all the ICollectionFixture<> interfaces.
        /// </summary>
        /// <remarks>
        /// This class does not have any code and is never created.
        /// </remarks>
        [CollectionDefinition("PI collection")]
        public class PITestCollection : ICollectionFixture<PIFixture>
        {
        }
    }
}
