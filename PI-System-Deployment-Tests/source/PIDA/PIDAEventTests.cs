using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Threading;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests the ability to read, write, update, and delete
    /// on the PI Data Archive.
    /// </summary>
    [Collection("PI collection")]
    public class PIDAEventTests : IClassFixture<PIFixture>
    {
        /// <summary>
        /// Constructor for PIDAEventTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage PI connection information.</param>
        public PIDAEventTests(ITestOutputHelper output, PIFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private PIFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Exercises PI Point creation and writing events operations.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Create a new PI Point, Verify that the PI Point is created, by finding it in PIServer</para>
        /// <para>Write the events</para>
        /// <para>Read the events to ensure that the write was successful</para>
        /// <para>Delete the PI Point and cleanup</para>
        /// </remarks>
        [Fact]
        public void CreatePointSendEventsAndVerify()
        {
            string pointName = $"CreatePointSendEventsAndVerify{AFTime.Now}";

            IDictionary<string, object> attributes = new Dictionary<string, object>()
            {
                { PICommonPointAttributes.Tag, pointName },
                { PICommonPointAttributes.PointType, PIPointType.Int32 },
                { PICommonPointAttributes.Compressing, 0 },
            };

            // Create a PI Point
            Output.WriteLine($"Create PI Point [{pointName}].");
            PIPoint point = Fixture.PIServer.CreatePIPoint(pointName, attributes);

            // Assert that the PI Point creation was successful
            Assert.True(PIPoint.FindPIPoint(Fixture.PIServer, pointName) != null,
                $"Could not find PI Point [{pointName}] on Data Archive [{Fixture.PIServer.Name}].");

            try
            {
                // Prepare the events to be written
                var eventsToWrite = new AFValues();
                var start = AFTime.Now.ToPIPrecision();
                int eventsCount = 10;
                var randomData = new byte[eventsCount];
                using (var random = RandomNumberGenerator.Create())
                {
                    random.GetBytes(randomData);
                }

                for (int i = 0; i < eventsCount; i++)
                {
                    var evnt = new AFValue(Convert.ToInt32(randomData[i]), start + TimeSpan.FromSeconds(i));
                    eventsToWrite.Add(evnt);
                }

                // Send the events to be written
                Output.WriteLine($"Write events to PI Point [{pointName}].");
                point.UpdateValues(eventsToWrite, AFUpdateOption.InsertNoCompression);

                // Read the events to verify that it was written successfully
                var eventsRead = new AFValues();
                Output.WriteLine($"Read events from PI Point [{pointName}].");

                AssertEventually.Equal(
                    eventsToWrite.Count,
                    () => point.RecordedValuesByCount(start, eventsCount, true, AFBoundaryType.Inside, null, false).Count,
                    TimeSpan.FromSeconds(2),
                    TimeSpan.FromSeconds(0.2));

                eventsRead = point.RecordedValuesByCount(start, eventsCount, true, AFBoundaryType.Inside, null, false);

                for (int j = 0; j < eventsCount; j++)
                {
                    Assert.True(eventsToWrite[j].Value.Equals(eventsRead[j].Value), 
                        $"Expected the value of the written event {AFFixture.DisplayAFValue(eventsToWrite[j])} " +
                        $"and the read event {AFFixture.DisplayAFValue(eventsRead[j])} to be equal.");
                }
            }
            finally
            {
                // Delete the PI Point to cleanup
                Fixture.DeletePIPoints(pointName, Output);
            }
        }

        /// <summary>
        /// Exercises PI Point value update operation.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Create a new PI Point, Verify that the PI Point is created, by finding it in PIServer</para>
        /// <para>Write the events</para>
        /// <para>Read the events to ensure that the write was successful</para>
        /// <para>Update the values of the events by replacing them</para>
        /// <para>Read the events and ensure that the values have been updated</para>
        /// <para>Delete the PI Point and cleanup</para>
        /// </remarks>
        [Fact]
        public void UpdateEventValuesTest()
        {
            string pointName = $"UpdateEventValuesTest{AFTime.Now}";

            IDictionary<string, object> attributes = new Dictionary<string, object>()
            {
                { PICommonPointAttributes.Tag, pointName },
                { PICommonPointAttributes.PointType, PIPointType.Int32 },
                { PICommonPointAttributes.Compressing, 0 },
            };

            // Create a PI Point
            Output.WriteLine($"Create PI Point [{pointName}].");
            PIPoint point = Fixture.PIServer.CreatePIPoint(pointName, attributes);

            // Assert that the PI Point creation was successful
            Assert.True(PIPoint.FindPIPoint(Fixture.PIServer, pointName) != null,
                $"Could not find PI Point [{pointName}] on Data Archive [{Fixture.PIServer.Name}].");

            try
            {
                // Prepare the events to be written
                var eventsToWrite = new AFValues();
                var start = AFTime.Now.ToPIPrecision();
                int eventsCount = 10;
                var randomData = new byte[eventsCount];
                var valuesToWrite = new List<int>();
                var timeStamps = new List<AFTime>();

                using (var random = RandomNumberGenerator.Create())
                {
                    random.GetBytes(randomData);
                    for (int i = 0; i < eventsCount; i++)
                    {
                        int value = Convert.ToInt32(randomData[i]);
                        var timestamp = start + TimeSpan.FromMinutes(i);
                        var evnt = new AFValue(value, timestamp);
                        eventsToWrite.Add(evnt);
                        valuesToWrite.Add(value);
                        timeStamps.Add(timestamp);
                    }
                }

                // Send the events to be written
                Output.WriteLine($"Write {eventsCount} events to PI Point [{pointName}].");
                point.UpdateValues(eventsToWrite, AFUpdateOption.InsertNoCompression);
                Thread.Sleep(TimeSpan.FromSeconds(1));

                // Read the events to verify that it was written successfully
                var eventsRead = new AFValues();

                Output.WriteLine($"Read events from point [{pointName}].");
                AssertEventually.True(() =>
                {
                    eventsRead = point.RecordedValuesByCount(start, eventsCount, true, AFBoundaryType.Inside, null, false);
                    if (eventsToWrite.Count != eventsRead.Count)
                    {
                        Output.WriteLine($"The read event count {eventsRead.Count} does not match the written event count {eventsToWrite.Count}.");
                        return false;
                    }

                    for (int j = 0; j < eventsCount; j++)
                    {
                        if (!eventsToWrite[j].Value.Equals(eventsRead[j].Value))
                        {
                            Output.WriteLine($"Written event value {AFFixture.DisplayAFValue(eventsToWrite[j])} " +
                                $"did not match read event value {AFFixture.DisplayAFValue(eventsRead[j])}.");
                            return false;
                        }
                    }

                    return true;
                },
                TimeSpan.FromSeconds(30),
                TimeSpan.FromSeconds(5),
                $"The events read back do not match the events written on the PI Data Archive [{Fixture.PIServer.Name}].");

                // Update/edit the values and send again
                var updatedNewValues = new List<int>();
                var eventsUpdated = new AFValues();
                randomData = new byte[eventsCount];

                using (var random = RandomNumberGenerator.Create())
                {
                    random.GetBytes(randomData);
                    for (int i = 0; i < eventsCount; i++)
                    {
                        // Ensure that the updated values are different than the written values.
                        int value = Convert.ToInt32(randomData[i]) + 256;
                        var evnt = new AFValue(value, timeStamps[i]);
                        eventsUpdated.Add(evnt);
                        updatedNewValues.Add(value);
                    }
                }

                // Send the updated events to be written
                Output.WriteLine($"Write updated events to PI Point [{pointName}].");
                point.UpdateValues(eventsUpdated, AFUpdateOption.Replace);

                // Read the events to verify that it was updated successfully
                eventsRead = new AFValues();

                Output.WriteLine($"Read events from PI Point [{pointName}].");
                AssertEventually.True(() =>
                {
                    eventsRead = point.RecordedValuesByCount(start, eventsCount, true, AFBoundaryType.Inside, null, false);
                    if (eventsUpdated.Count != eventsRead.Count)
                    {
                        Output.WriteLine($"The read event count {eventsRead.Count} does not match the updated event count {eventsUpdated.Count}.");
                        return false;
                    }

                    for (int j = 0; j < eventsCount; j++)
                    {
                        if (!eventsUpdated[j].Value.Equals(eventsRead[j].Value))
                        {
                            Output.WriteLine($"Updated event value {AFFixture.DisplayAFValue(eventsUpdated[j])} " +
                                $"did not match read event value {AFFixture.DisplayAFValue(eventsRead[j])}.");
                            return false;
                        }

                        if (eventsToWrite[j].Value.Equals(eventsRead[j].Value))
                        {
                            Output.WriteLine($"Written event value {AFFixture.DisplayAFValue(eventsToWrite[j])} " +
                                $"did match read event value {AFFixture.DisplayAFValue(eventsRead[j])}. The values should not be equal.");
                            return false;
                        }
                    }

                    return true;
                },
                $"The events read back do not match the events written or updated on the PI Data Archive [{Fixture.PIServer.Name}].");
            }
            finally
            {
                // Delete the PI Point to cleanup
                Fixture.DeletePIPoints(pointName, Output);
            }
        }

        /// <summary>
        /// Exercises PI Point value delete operation.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Create a new PI Point, Verify that the PI Point is created, by finding it in PIServer</para>
        /// <para>Write the events</para>
        /// <para>Read the events to ensure that the write was successful</para>
        /// <para>Delete the values of the events by removing them</para>
        /// <para>Read the events and ensure that the values have been deleted</para>
        /// <para>Delete the PI Point and cleanup</para>
        /// </remarks>
        [Fact]
        public void DeleteValuesTest()
        {
            string pointName = $"DeleteValuesTest{AFTime.Now}";

            IDictionary<string, object> attributes = new Dictionary<string, object>()
            {
                { PICommonPointAttributes.Tag, pointName },
                { PICommonPointAttributes.PointType, PIPointType.Int32 },
                { PICommonPointAttributes.Compressing, 0 },
            };

            // Create a PI Point
            Output.WriteLine($"Create PI Point [{pointName}].");
            PIPoint point = Fixture.PIServer.CreatePIPoint(pointName, attributes);

            // Assert that the PI Point creation was successful
            Assert.True(PIPoint.FindPIPoint(Fixture.PIServer, pointName) != null,
                $"Could not find PI Point [{pointName}] on Data Archive [{Fixture.PIServer.Name}].");

            try
            {
                // Prepare the events to be written
                var eventsToWrite = new AFValues();
                var start = AFTime.Now.ToPIPrecision();
                int eventsCount = 10;
                var randomData = new byte[eventsCount];

                using (var random = RandomNumberGenerator.Create())
                {
                    random.GetBytes(randomData);
                    for (int i = 0; i < eventsCount; i++)
                    {
                        var evnt = new AFValue(Convert.ToInt32(randomData[i]), start + TimeSpan.FromSeconds(i));
                        eventsToWrite.Add(evnt);
                    }
                }

                // Send the events to be written
                Output.WriteLine($"Write events to PI Point [{pointName}].");
                point.UpdateValues(eventsToWrite, AFUpdateOption.InsertNoCompression);

                // Read the events to verify that the events write was successful
                var eventsRead = new AFValues();

                Output.WriteLine($"Read events from PI Point [{pointName}].");
                AssertEventually.True(() =>
                {
                    eventsRead = point.RecordedValuesByCount(start, eventsCount, true, AFBoundaryType.Inside, null, false);

                    if (eventsToWrite.Count != eventsRead.Count)
                    {
                        Output.WriteLine($"The read event count {eventsRead.Count} does not match the written event count {eventsToWrite.Count}.");
                        return false;
                    }
                    else
                    {
                        for (int j = 0; j < eventsCount; j++)
                        {
                            if (!eventsToWrite[j].Value.Equals(eventsRead[j].Value))
                            {
                                Output.WriteLine($"Written event value {AFFixture.DisplayAFValue(eventsToWrite[j])} " +
                                    $"did not match read event value {AFFixture.DisplayAFValue(eventsRead[j])}.");
                                return false;
                            }
                        }
                    }

                    return true;
                },
                $"The events read back do not match the events written to PI Data Archive [{Fixture.PIServer.Name}].");

                // Delete the events
                Output.WriteLine($"Delete events from PI Point [{pointName}].");
                eventsRead.Clear();
                point.UpdateValues(eventsToWrite, AFUpdateOption.Remove);

                AssertEventually.True(() =>
                {
                    eventsRead = point.RecordedValuesByCount(start, eventsCount, true, AFBoundaryType.Inside, null, false);
                    return eventsRead.Count == 0;
                },
                $"The return event count should be 0 after deleting the events, but it was actually {eventsRead.Count}.");
            }
            finally
            {
                // Delete the PI Point to cleanup
                Fixture.DeletePIPoints(pointName, Output);
            }
        }
    }
}
