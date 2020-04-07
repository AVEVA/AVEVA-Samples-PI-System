using System;
using System.ServiceModel;
using System.ServiceModel.Channels;
using System.ServiceModel.Description;

namespace OSIsoft.PISystemDeploymentTests
{
    internal sealed class BasicWebServiceHost : IDisposable
    {
        private readonly object _serviceObject;
        private readonly Type _serviceInterface;
        private ServiceHost _host;

        public BasicWebServiceHost(object serviceObject, Type serviceInterface)
        {
            _serviceObject = serviceObject ?? throw new ArgumentNullException(nameof(serviceObject));
            _serviceInterface = serviceInterface ?? throw new ArgumentNullException(nameof(serviceInterface));
        }

        public void Start(string serviceName, string serviceUri)
        {
            if (_host != null)
            {
                throw new InvalidOperationException("Host has already been started.");
            }

            var uri = new Uri(serviceUri);

            var binding = uri.Scheme == Uri.UriSchemeHttp
                ? new BasicHttpBinding()
                : throw new ArgumentException($"Scheme '{uri.Scheme}' is not supported.", nameof(serviceUri));

            _host = new ServiceHost(_serviceObject);
            _host.AddServiceEndpoint(_serviceInterface, binding, uri);

            var smb = new ServiceMetadataBehavior() { HttpGetEnabled = true, HttpGetUrl = uri };
            _host.Description.Behaviors.Add(smb);
            _host.Description.Name = serviceName;
            _host.Open();
        }

        public void Close()
        {
            if (_host != null)
            {
                if (_host.State == CommunicationState.Opened)
                    _host.Close();
                ((IDisposable)_host).Dispose();
                _host = null;
            }
        }

        public void Dispose()
        {
            Close();
        }
    }
}
