using System.Collections.Generic;

namespace OSIsoft.PISystemDeploymentTests
{
    internal sealed class AnnotationDescription
    {
        public string Notification { get; set; }

        public List<Subscribers> Subscribers { get; set; }
    }
}
