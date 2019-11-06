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

            UseExactMatchForLocalhost = true;
        }

        /// <summary>
        /// Allows localhost to be an exact match which does not require admin to register the endpoint,
        /// however it will only expose the endpoint locally.
        /// </summary>
        public bool UseExactMatchForLocalhost { get; set; }

        public void Start(string serviceName, string serviceUri)
        {
            if (_host != null)
            {
                throw new InvalidOperationException("Host has already been started.");
            }

            var uri = new Uri(serviceUri);
            Binding binding;
            if (uri.Scheme == Uri.UriSchemeHttp)
            {
                BasicHttpBinding httpBinding;

                httpBinding = new BasicHttpBinding();

                if (uri.IsLoopback && UseExactMatchForLocalhost)
                {
                    // This allows us to open without any special admin permission for localhost.
                    httpBinding.HostNameComparisonMode = HostNameComparisonMode.Exact;
                }

                binding = httpBinding;
            }
            else
            {
                throw new ArgumentException($"Scheme '{uri.Scheme}' is not supported.", nameof(serviceUri));
            }

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
