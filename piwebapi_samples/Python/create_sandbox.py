""" This script creates and deletes a PI Web API Asset database, AF category,
    AF Template and AF Element, creating a sandbox used by the other methods

    When creating the sandbox, the following order must be followed:
        create_database, create_category, create_template, create_element

    This python script requires some pre-requisites:
        1.  A back-end server with PI WEB API with CORS enabled.
"""

import json
import getpass
import requests

from requests.auth import HTTPBasicAuth
from requests_kerberos import HTTPKerberosAuth

OSI_AF_ATTRIBUTE_TAG = 'OSIPythonAttributeSampleTag'
OSI_AF_CATEGORY = 'OSIPythonCategory'
OSI_AF_DATABASE = 'OSIPythonDatabase'
OSI_AF_ELEMENT = 'OSIPythonElement'
OSI_AF_TEMPLATE = 'OSIPythonTemplate'
OSI_TAG = 'OSIPythonSampleTag'
OSI_TAG_SINUSOID = 'OSIPythonAttributeSinusoid'
OSI_TAG_SINUSOIDU = 'OSIPythonAttributeSinusoidU'


def call_headers(include_content_type):
    """ Create API call headers
        @includeContentType boolean:  flag determines whether or not the
        content-type header is included
    """
    if include_content_type is True:
        header = {
            'content-type': 'application/json',
            'X-Requested-With': 'XmlHttpRequest'
        }
    else:
        header = {
            'X-Requested-With': 'XmlHttpRequest'
        }

    return header


def call_security_method(security_method, user_name, user_password):
    """ Create API call security method
        @param security_method string:  security method to use:  basic or kerberos
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
    """

    if security_method.lower() == 'basic':
        security_auth = HTTPBasicAuth(user_name, user_password)
    else:
        security_auth = HTTPKerberosAuth(mutual_authentication='REQUIRED',
                                         sanitize_mutual_error_response=False)

    return security_auth


def create_sandbox(piwebapi_url, asset_server, pi_server, user_name, user_password,
                   piwebapi_security_method):
    """ Create the sandbox.  Calls methods to create the structure needed by the other calls.
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param pi_server string:  Name of the PI Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    create_database(piwebapi_url, asset_server, user_name,
                    user_password, piwebapi_security_method)
    create_category(piwebapi_url, asset_server, user_name,
                    user_password, piwebapi_security_method)
    create_template(piwebapi_url, asset_server, pi_server,
                    user_name, user_password, piwebapi_security_method)
    create_element(piwebapi_url, asset_server, user_name,
                   user_password, piwebapi_security_method)
    delete_element(piwebapi_url, asset_server, user_name,
                  user_password, piwebapi_security_method)
    delete_template(piwebapi_url, asset_server, user_name,
                   user_password, piwebapi_security_method)
    delete_category(piwebapi_url, asset_server, user_name,
                   user_password, piwebapi_security_method)
    delete_database(piwebapi_url, asset_server, user_name,
                   user_password, piwebapi_security_method)


def create_database(piwebapi_url, asset_server, user_name, user_password, piwebapi_security_method):
    """ Create Python Web API Sample database
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('Create Database')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get AF Server
    response = requests.get(piwebapi_url + '/assetservers?path=\\\\' + asset_server,
                            auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Create the body for the request
        request_body = {
            'Name': OSI_AF_DATABASE,
            'Description': 'Database for Python Web API',
            'ExtendedProperties': {}
        }

        #  Create a header
        header = call_headers(True)

        #  Create the database
        response = requests.post(data['Links']['Self'] + '/assetdatabases',
                                 auth=security_method, verify=False,
                                 json=request_body, headers=header)
        if response.status_code == 201:
            print('Database {} created'.format(OSI_AF_DATABASE))
        else:
            print(response.status_code, response.reason, response.text)

    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code


def create_category(piwebapi_url, asset_server, user_name, user_password, piwebapi_security_method):
    """ Create an AF Category
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('Create Category')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the database
    request_url = '{}/assetdatabases?path=\\\\{}\\{}'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Create the body for the request
        request_body = {
            'Name': OSI_AF_CATEGORY,
            'Description': '{} category'.format(OSI_AF_CATEGORY)
        }

        #  Create a header
        header = call_headers(True)

        #  Create the element category
        response = requests.post(data['Links']['Self'] + '/elementcategories',
                                 auth=security_method, verify=False, json=request_body, headers=header)
        if response.status_code == 201:
            print('Category {} created'.format(OSI_AF_CATEGORY))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code


def create_template(piwebapi_url, asset_server, pi_server, user_name, user_password,
                    piwebapi_security_method):
    """ Create an AF template
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param pi_server string:  Name of the PI Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('Create Template')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the database
    request_url = '{}/assetdatabases?path=\\\\{}\\{}'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Create the body for the request
        request_body = {
            'Name': OSI_AF_TEMPLATE,
            'Description': '{} Template'.format(OSI_AF_TEMPLATE),
            'CategoryNames': [OSI_AF_CATEGORY],
            'AllowElementToExtend': True
        }
        #  Create a header
        header = call_headers(True)

        #  Create the element template
        response = requests.post(data['Links']['Self'] + '/elementtemplates', auth=security_method,
                                 verify=False, json=request_body, headers=header)

        #  If the template was created, add attributes
        if response.status_code == 201:
            print('Template {} created'.format(OSI_AF_TEMPLATE))

            # Get the newly created machine template
            request_url = '{}/elementtemplates?path=\\\\{}\\{}\\ElementTemplates[{}]'.format(
                piwebapi_url, asset_server, OSI_AF_DATABASE, OSI_AF_TEMPLATE)
            response = requests.get(
                request_url, auth=security_method, verify=False)
            data = json.loads(response.text)

            # Add templte attributes
            response = requests.post(data['Links']['Self'] + '/attributetemplates',
                                     auth=security_method, verify=False,
                                     json={'Name': 'Active', 'Description': '',
                                           'IsConfigurationItem': True, 'Type': 'Boolean'},
                                     headers=header)
            response = requests.post(data['Links']['Self'] + '/attributetemplates',
                                     auth=security_method, verify=False,
                                     json={'Name': 'OS', 'Description': 'Operating System',
                                           'IsConfigurationItem': True, 'Type': 'String'},
                                     headers=header)
            response = requests.post(data['Links']['Self'] + '/attributetemplates',
                                     auth=security_method, verify=False,
                                     json={'Name': 'OSVersion',
                                           'Description': 'Operating System Version',
                                           'IsConfigurationItem': True, 'Type': 'String'},
                                     headers=header)
            response = requests.post(data['Links']['Self'] + '/attributetemplates',
                                     auth=security_method, verify=False,
                                     json={'Name': 'IPAddresses',
                                           'Description': 'A list of IP Addresses for all NIC',
                                           'IsConfigurationItem': True, 'Type': 'String'},
                                     headers=header)

            # Add Sinusoid U
            response = requests.post(data['Links']['Self'] + '/attributetemplates',
                                     auth=security_method, verify=False,
                                     json={'Name': OSI_TAG_SINUSOID,
                                           'Description': '', 'IsConfigurationItem': False,
                                           'Type': 'Double', 'DataReferencePlugIn': 'PI Point',
                                           'ConfigString': '\\\\' + pi_server + '\\SinusoidU'},
                                     headers=header)

            # Add Sinusoid
            response = requests.post(data['Links']['Self'] + '/attributetemplates',
                                     auth=security_method, verify=False,
                                     json={'Name': OSI_TAG_SINUSOIDU, 'Description': '',
                                           'IsConfigurationItem': False, 'Type': 'Double',
                                           'DataReferencePlugIn': 'PI Point',
                                           'ConfigString': '\\\\' + pi_server + '\\Sinusoid'},
                                     headers=header)

            # Add the sampleTag attribute
            response = requests.post(data['Links']['Self'] + '/attributetemplates',
                                     auth=security_method, verify=False,
                                     json={'Name': OSI_AF_ATTRIBUTE_TAG, 'Description': '',
                                           'IsConfigurationItem': False, 'Type': 'Double',
                                           'DataReferencePlugIn': 'PI Point',
                                           'ConfigString': '\\\\' + pi_server +
                                           '\\%Element%_{};ReadOnly=False;'.format(OSI_TAG) +
                                           'ptclassname=classic;pointtype=Float64;' +
                                           'pointsource=webapi'},
                                     headers=header)

            if response.status_code == 201:
                print('Template {} created'.format(OSI_AF_TEMPLATE))
            else:
                print(response.status_code, response.reason, response.text)
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code


def create_element(piwebapi_url, asset_server, user_name, user_password, piwebapi_security_method):
    """ Create an AF element
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('Create Element')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the sample database
    request_url = '{}/assetdatabases?path=\\\\{}\\{}'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  create a body for the request
        request_body = {
            'Name': OSI_AF_ELEMENT,
            'Description': '{} element'.format(OSI_AF_ELEMENT),
            'TemplateName': OSI_AF_TEMPLATE,
            'ExtendedProperties': {}
        }

        #  Create a header that passes in json
        header = call_headers(True)

        #  Create the element
        response = requests.post(data['Links']['Self'] + '//elements', auth=security_method,
                                 verify=False, json=request_body, headers=header)
        if response.status_code == 201:
            print('Equipment {} created'.format(OSI_AF_ELEMENT))

            # Get the newly created element
            request_url = '{}/elements?path=\\\\{}\\{}\\{}'.format(
                piwebapi_url, asset_server, OSI_AF_DATABASE, OSI_AF_ELEMENT)
            response = requests.get(
                request_url, auth=security_method, verify=False)
            data = json.loads(response.text)

            #  Create the tags based on the template configuration
            response = requests.post(piwebapi_url + '/elements/' + data['WebId'] + '/config',
                                     auth=security_method, verify=False,
                                     json={'includeChildElements': True}, headers=header)

            print(json.dumps(json.loads(response.text), indent=4, sort_keys=True))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code


def delete_element(piwebapi_url, asset_server, user_name, user_password, piwebapi_security_method):
    """ Delete an AF element
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('Delete Element')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the element
    request_url = '{}/elements?path=\\\\{}\\{}\\{}'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE, OSI_AF_ELEMENT)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Create a header
        header = call_headers(False)

        #  Delete the element
        response = requests.delete(data['Links']['Self'], auth=security_method,
                                   verify=False, headers=header)
        if response.status_code == 204:
            print('Element {} Deleted'.format(OSI_AF_ELEMENT))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code


def delete_template(piwebapi_url, asset_server, user_name, user_password, piwebapi_security_method):
    """ Delete an AF template
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('Delete Template')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the element template
    request_url = '{}/elementtemplates?path=\\\\{}\\{}\\ElementTemplates[{}]'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE, OSI_AF_TEMPLATE)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Create a header
        header = call_headers(True)

        #  Delete the element template
        request_url = '{}/elementtemplates/{}'.format(
            piwebapi_url, data['WebId'])
        response = requests.delete(
            request_url, auth=security_method, verify=False, headers=header)
        if response.status_code == 204:
            print('Template {} Deleted'.format(OSI_AF_TEMPLATE))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code


def delete_category(piwebapi_url, asset_server, user_name, user_password, piwebapi_security_method):
    """ Delete an AF Category
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('Delete Category')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the element category
    request_url = '{}/elementcategories?path=\\\\{}\\{}\\CategoriesElement[{}]'.format(piwebapi_url, asset_server, OSI_AF_DATABASE, OSI_AF_CATEGORY)
    response = requests.get(request_url, auth=security_method, verify=False)
    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Create a header
        header = call_headers(False)

        #  Delete the element category
        response = requests.delete(data['Links']['Self'], auth=security_method,
                                   verify=False, headers=header)
        if response.status_code == 204:
            print('Category {} deleted.'.format(OSI_AF_CATEGORY))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code


def delete_database(piwebapi_url, asset_server, user_name, user_password, piwebapi_security_method):
    """ Delete Python Web API Sample database
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('Delete Database')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get AF Server
    request_url = '{}/assetdatabases?path=\\\\{}\\{}'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Create the header
        header = call_headers(True)

        #  Delete the sample database
        response = requests.delete(piwebapi_url + '/assetdatabases/' + data['WebId'],
                                   auth=security_method, verify=False, headers=header)
        if response.status_code == 204:
            print('Database {} deleted.'.format(OSI_AF_DATABASE))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code

#    Main method


def main():
    """ Main method.  Receive user input and call the do_batch_call method """
    piwebapi_url = str(input('Enter the PI Web API url: '))
    af_server_name = str(input('Enter the Asset Server Name: '))
    pi_server_name = str(input('Enter the PI Server Name: '))
    piwebapi_user = str(input('Enter the user name: '))
    piwebapi_password = str(getpass.getpass('Enter the password: '))
    piwebapi_security_method = str(input('Enter the security method,  Basic or Kerberos:'))
    piwebapi_security_method = piwebapi_security_method.lower()

    create_sandbox(piwebapi_url, af_server_name, pi_server_name, piwebapi_user, piwebapi_password,
                   piwebapi_security_method)


if __name__ == '__main__':
    main()
