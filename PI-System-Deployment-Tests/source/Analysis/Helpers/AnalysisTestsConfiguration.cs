#pragma warning disable SA1649 // SA1649FileNameMustMatchTypeName
namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Test configuration data for the analysis tests.
    /// </summary>
    public class AnalysisTestConfiguration
    {
        /// <summary>
        /// Constructor for AnalysisTestConfiguration class.
        /// </summary>
        /// <param name="name">Initial value for the Name property.</param>
        public AnalysisTestConfiguration(string name) => Name = name;

        #region Fields used for Creation or Verification
#pragma warning disable SA1600 // Elements should be documented
        public string Name { get; set; }
        public string AnalysisCategoryName => "OSIsoftTests_AF_AnalysisTest_AnalysisCat1";
        public string AnalysisRulePlugIn => "PerformanceEquation";
        public string AnalysisTimeRulePlugIn => "Periodic";
        public string AnalysisExtPropKey => "OSIsoftTests_AF_AnalysisTest_ExpPropKey";
        public string AnalysisExtPropValue => "OSIsoftTests_AF_AnalysisTest_ExpPropKey";
#pragma warning restore SA1600 // Elements should be documented
        #endregion
    }
}
