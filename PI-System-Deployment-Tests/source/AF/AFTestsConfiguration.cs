#pragma warning disable SA1649 // SA1649FileNameMustMatchTypeName
#pragma warning disable SA1402 // File may only contain a single class
namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Test configuration data for the element template tests.
    /// </summary>
    public class ElementTemplateTestConfiguration
    {
        /// <summary>
        /// Constructor for ElementTemplateTestConfiguration class.
        /// </summary>
        /// <param name="name">Initial value for the Name property.</param>
        public ElementTemplateTestConfiguration(string name) => Name = name;

        #region Fields used for Creation or Verification
#pragma warning disable SA1600 // Elements should be documented
        public string Name { get; set; }
        public string AttributeCategoryName => AFFixture.AttributeCategoryNameStatus;
        public string ElementCategoryName => AFFixture.ElemementCategoryNameEquipment;
        public string AttributeTemplateName => "OSIsoftTests_AF_ElementTemplatesTest_AttrTemp#1";
        public string ElementTemplateExtPropKey => "OSIsoftTests_AF_ElementTemplatesTest_ExpPropKey";
        public string ExtPropValue => "OSIsoftTests_AF_ElementTemplatesTest_ExpPropKey";
        public string PortName => "OSIsoftTests_Port";
#pragma warning restore SA1600 // Elements should be documented
        #endregion
    }

    /// <summary>
    /// Test configuration data for the element tests.
    /// </summary>
    public class ElementTestConfiguration
    {
        /// <summary>
        /// Constructor for ElementTestConfiguration class.
        /// </summary>
        /// <param name="name">Initial value for the Name property.</param>
        public ElementTestConfiguration(string name) => Name = name;

        #region Fields used for Creation or Verification
#pragma warning disable SA1600 // Elements should be documented
        public string Name { get; set; }
        public string ChildElementName => "OSIsoftTests_ChildElement";
        public string ExtPropKey => "OSIsoftTests_XPropKey";
        public string ExtPropValue => "OSIsoftTests_XPropValue";
        public string ElementCategoryName => AFFixture.ElemementCategoryNameEquipment;
        public string AttributeCategoryName => AFFixture.AttributeCategoryNameStatus;
        public string Attribute1Name => "OSIsoftTests_Attribute#1";
        public string Attribute2Name => "OSIsoftTests_Attribute#2";
        public double Attribute2Value => 1234.5678;
        public string Attribute3Name => "OSIsoftTests_Attribute#3";
        public string DataReferencePlugInName => "Formula";
        public string DataReferenceConfigString => "[8765.4321]";
        public string AnnotationName => "OSIsoftTests_Annotation#1";
        public string AnnotationValue => "OSIsoftTests Annotation #1";
        public string PortName => "OSIsoftTests_Port";
#pragma warning restore SA1600 // Elements should be documented
        #endregion
    }

    /// <summary>
    /// Test configuration data for the transfer tests.
    /// </summary>
    public class TransferTestConfiguration
    {
        /// <summary>
        /// Constructor for TransferTestConfiguration class.
        /// </summary>
        /// <param name="name">Initial value for the Name property.</param>
        public TransferTestConfiguration(string name) => Name = name;

        #region Fields used for Creation or Verification
#pragma warning disable SA1600 // Elements should be documented
        public string Name { get; set; }
        public string ElementCategoryName => AFFixture.ElemementCategoryNameEquipment;
        public string AttributeCategoryName => AFFixture.AttributeCategoryNameStatus;
        public string Attribute1Name => "OSIsoftTests_Attribute#1";
        public string Attribute2Name => "OSIsoftTests_Attribute#2";
        public double Attribute2Value => 1234.5678;
        public string Attribute3Name => "OSIsoftTests_Attribute#3";
        public string DataReferencePlugInName => "Formula";
        public string DataReferenceConfigString => "[8765.4321]";
        public string AnnotationName => "OSIsoftTests_Annotation#1";
        public string AnnotationValue => "OSIsoftTests Annotation #1";
        public string PortName => "OSIsoftTests_Port";
#pragma warning restore SA1600 // Elements should be documented
        #endregion
    }
}
