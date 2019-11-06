using System;
using System.Collections.Generic;
using OSIsoft.AF.PI;
using OSIsoft.AF.Time;
using Xunit;
using Xunit.Abstractions;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// This class tests the ability to create, update, and rename
    /// on the PI Data Archive.
    /// </summary>
    [Collection("PI collection")]
    public class PIDAPointTests : IClassFixture<PIFixture>
    {
        /// <summary>
        /// Constructor for PIDAPointTests Class.
        /// </summary>
        /// <param name="output">The output logger used for writing messages.</param>
        /// <param name="fixture">Fixture to manage PI connection information.</param>
        public PIDAPointTests(ITestOutputHelper output, PIFixture fixture)
        {
            Output = output;
            Fixture = fixture;
        }

        private PIFixture Fixture { get; }
        private ITestOutputHelper Output { get; }

        /// <summary>
        /// Exercises PI Point create and delete operations.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Create a new PI Point</para>
        /// <para>Verify that the PI Point is created, by finding it in PIServer</para>
        /// <para>Delete the PI Point</para>
        /// <para>Verify that the PI Point was deleted</para>
        /// </remarks>
        [Fact]
        public void CreateAndDeletePointTest()
        {
            // Construct a unique PI Point name same as the test name, followed by the current timestamp.
            // If the PI Point deletion doesn't go through, identifying the test that created the Point gets easy.
            string pointName = $"PointCreationAndDeletionTest{AFTime.Now}";

            try
            {
                // Create a PI Point
                Output.WriteLine($"Create PI Point [{pointName}].");
                PIPoint point = Fixture.PIServer.CreatePIPoint(pointName);

                // Assert that the PI Point creation was successful
                Assert.True(PIPoint.FindPIPoint(Fixture.PIServer, pointName) != null,
                    $"Could not find PI Point [{pointName}] on Data Archive [{Fixture.PIServer.Name}] after creation.");
            }
            finally
            {
                // Delete the PI Point to cleanup
                Fixture.DeletePIPoints(pointName, Output);

                // Assert that the PI Point deletion was successful
                Exception ex = Assert.Throws<PIPointInvalidException>(() => PIPoint.FindPIPoint(Fixture.PIServer, pointName));
                Assert.True(ex.Message.Contains("PI Point not found"),
                    $"Expected to get an exception message saying that the [PI Point not found] " +
                    $"when searching for PI Point [{pointName}] after deletion, but the actual message was [{ex.Message}].");
            }
        }

        /// <summary>
        /// Exercises PI Point rename operation.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Create a new PI Point</para>
        /// <para>Verify that the PI Point is created, by finding it in PIServer</para>
        /// <para>Rename the PI Point by changing the Point's name attribute</para>
        /// <para>Verify that the PI Point was renamed</para>
        /// </remarks>
        [Fact]
        public void RenamePointTest()
        {
            // Construct a unique PI Point name
            string pointName = $"RenamePointTest{AFTime.Now}";
            string newName = pointName + "_Renamed";

            try
            {
                // Create a PI Point
                Output.WriteLine($"Create PI Point [{pointName}].");
                PIPoint point = Fixture.PIServer.CreatePIPoint(pointName);

                // Assert that the PI Point creation was successful
                Assert.True(PIPoint.FindPIPoint(Fixture.PIServer, pointName) != null,
                    $"Could not find PI Point [{pointName}] on Data Archive [{Fixture.PIServer.Name}] after creation.");

                // Change the name of the PI Point
                IDictionary<string, object> attributesToEdit = new Dictionary<string, object>()
                {
                    { PICommonPointAttributes.Tag, newName },
                };

                Output.WriteLine($"Rename PI Point [{pointName}] to [{newName}].");
                foreach (var attribute in attributesToEdit)
                {
                    point.SetAttribute(attribute.Key, attribute.Value);
                }

                point.SaveAttributes();

                // Refresh the server
                Fixture.PIServer.Refresh();

                // Look for the PI Point with the new name
                Assert.True(PIPoint.FindPIPoint(Fixture.PIServer, newName) != null,
                    $"Could not find PI Point [{newName}] on Data Archive [{Fixture.PIServer.Name}] after rename from [{pointName}].");
            }
            finally
            {
                // Delete the PI Point to cleanup
                Fixture.DeletePIPoints($"{pointName}*", Output);
            }
        }

        /// <summary>
        /// Exercises PI Point attribute update operation.
        /// </summary>
        /// <remarks>
        /// This test requires write access to the target PI Data Archive.
        /// <para>Test Steps:</para>
        /// <para>Create a new PI Point</para>
        /// <para>Verify that the PI Point is created, by finding it in PIServer</para>
        /// <para>Change the PI Point attributes</para>
        /// <para>Verify that the new attribute values are stored</para>
        /// </remarks>
        [Fact]
        public void UpdatePointTest()
        {
            string pointName = $"UpdatePointTest{AFTime.Now}";

            IDictionary<string, object> attributes = new Dictionary<string, object>()
            {
                { PICommonPointAttributes.Tag, pointName },
                { PICommonPointAttributes.PointType, PIPointType.Float32 },
            };

            try
            {
                // Create a PI Point
                Output.WriteLine($"Create PI Point [{pointName}].");
                PIPoint point = Fixture.PIServer.CreatePIPoint(pointName, attributes);

                // Assert that the PI Point creation was successful
                Assert.True(PIPoint.FindPIPoint(Fixture.PIServer, pointName) != null,
                    $"Could not find PI Point [{pointName}] on Data Archive [{Fixture.PIServer.Name}] after creation.");

                IDictionary<string, object> attributesToEdit = new Dictionary<string, object>()
                {
                    { PICommonPointAttributes.PointType, PIPointType.String },
                };

                Output.WriteLine($"Update PI Point [{pointName}] type from Float32 to String.");
                foreach (var attribute in attributesToEdit)
                {
                    point.SetAttribute(attribute.Key, attribute.Value);
                }

                point.SaveAttributes();

                // Refresh the server
                Fixture.PIServer.Refresh();

                // Look for the PI Point
                var pipoint = PIPoint.FindPIPoint(Fixture.PIServer, pointName);

                // Assert that the attribute values have changed
                Assert.True(pipoint.GetAttribute(PICommonPointAttributes.PointType).Equals(PIPointType.String),
                    $"Expected the Point Type of the PI Point [{pointName}] to be a [string], but it was actually [{pipoint.GetAttribute(PICommonPointAttributes.PointType)}].");
            }
            finally
            {
                // Delete the PI Point to cleanup
                Fixture.DeletePIPoints(pointName, Output);
            }
        }
    }
}
