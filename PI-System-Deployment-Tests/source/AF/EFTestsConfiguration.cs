#pragma warning disable SA1649 // SA1649FileNameMustMatchTypeName
namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Test configuration data for the event frame tests.
    /// </summary>
    public class EventFrameTestConfiguration
    {
        /// <summary>
        /// Constructor for EventFrameTestConfiguration class.
        /// </summary>
        /// <param name="name">Initial value for the Name property.</param>
        public EventFrameTestConfiguration(string name) => Name = name;

        #region Fields used for Creation or Verification
#pragma warning disable SA1600 // Elements should be documented
        public string Name { get; set; }
        public string AttributeCategoryName => AFFixture.AttributeCategoryNameStatus;
        public string ElementCategoryName => AFFixture.ElemementCategoryNameEquipment;
        public string EventFrameElementName => "OSIsoftTests_EFElement";
        public string ExtPropKey => "OSIsoftTests_XPropKey";
        public string ExtPropValue => "OSIsoftTests_XPropValue";
        public string Attribute1Name => "OSIsoftTests_Attribute#1";
        public string Attribute2Name => "OSIsoftTests_Attribute#2";
        public double Attribute2Value => 1234.5678;
        public string Attribute3Name => "OSIsoftTests_Attribute#3";
        public string DataReferencePlugInName => "Formula";
        public string DataReferenceConfigString => "[8765.4321]";
        public string AnnotationName => "OSIsoftTests_Annotation#1";
        public string AnnotationValue => "OSIsoftTests Annotation #1";
        public string ChildEventFrame => "OSIsoftTests_ChildEventFrame";
#pragma warning restore SA1600 // Elements should be documented
        #endregion
    }
}
