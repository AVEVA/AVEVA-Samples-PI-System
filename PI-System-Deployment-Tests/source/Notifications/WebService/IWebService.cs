using System;
using System.ServiceModel;

namespace OSIsoft.PISystemDeploymentTests
{
    /// <summary>
    /// Service contract for web service.
    /// </summary>
    [ServiceContract]
    internal interface IWebService
    {
        /// <summary>
        /// Operation contract for test send of web service.
        /// </summary>
        /// <param name="ruleId">Send rule Id.</param>
        /// <param name="content">Send content.</param>
        [OperationContract]
        void Test(Guid ruleId, string content);
    }
}
