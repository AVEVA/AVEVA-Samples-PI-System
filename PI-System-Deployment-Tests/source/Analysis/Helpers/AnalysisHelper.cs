using System.Collections.Generic;
using System.Diagnostics.Contracts;
using System.Linq;
using OSIsoft.AF.Analysis;
using OSIsoft.AF.Asset;
using OSIsoft.AF.Data;
using OSIsoft.AF.Time;
using Xunit;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Analysis Helper Methods.
    /// </summary>
    public static class AnalysisHelper
    {
        /// <summary>
        /// Assert results of an analysis output.
        /// </summary>
        public static void AssertResults(AFAttribute output, AFTimeRange timeRange, IList<AFValue> expectedValues)
        {
            Contract.Requires(expectedValues != null);

            var actualValues = output.GetRecordedValues(timeRange);
            Assert.Equal(actualValues.Count, expectedValues.Count);
            for (int i = 0; i < actualValues.Count; i++)
            {
                Assert.Equal(actualValues[i], expectedValues[i]);
            }
        }

        /// <summary>
        /// Get the list of input attributes for an analysis.
        /// </summary>
        public static IList<AFAttribute> GetInputs(this AFAnalysis analysis)
            => analysis?.AnalysisRule.GetConfiguration().GetInputs().OfType<AFAttribute>().ToList();

        /// <summary>
        /// Get the list of output attributes for an analysis.
        /// </summary>
        public static IList<AFAttribute> GetOutputs(this AFAnalysis analysis)
            => analysis?.AnalysisRule.GetConfiguration().GetOutputs().OfType<AFAttribute>().ToList();

        /// <summary>
        /// Returns recorded values using boundary mode=inside.
        /// </summary>
        public static AFValues GetRecordedValues(this AFAttribute attribute, AFTimeRange timeRange)
            => attribute?.Data.RecordedValues(timeRange, AFBoundaryType.Inside, null, null, true);
    }
}
