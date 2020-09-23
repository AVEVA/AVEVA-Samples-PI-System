""" This script read values through the PI Web API.

    This python script requires some pre-requisites:
        1.  A back-end server with PI WEB API with CORS enabled.
"""

import json
import getpass
import requests

OSI_AF_ATTRIBUTE_TAG = 'OSIPythonAttributeSampleTag'
OSI_AF_DATABASE = 'OSIPythonDatabase'
OSI_AF_ELEMENT = 'OSIPythonElement'


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
    from requests.auth import HTTPBasicAuth
    from requests_kerberos import HTTPKerberosAuth

    if security_method.lower() == 'basic':
        security_auth = HTTPBasicAuth(user_name, user_password)
    else:
        security_auth = HTTPKerberosAuth(mutual_authentication='REQUIRED',
                                         sanitize_mutual_error_response=False)

    return security_auth


def read_attribute_snapshot(piwebapi_url, asset_server, user_name, user_password,
                            piwebapi_security_method):
    """ Read a single value
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('readAttributeSnapshot')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the sample tag
    request_url = '{}/attributes?path=\\\\{}\\{}\\{}|{}'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE, OSI_AF_ELEMENT, OSI_AF_ATTRIBUTE_TAG)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        print(response.text)
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Read the single stream value
        response = requests.get(piwebapi_url + '/streams/' + data['WebId'] + '/value',
                                auth=security_method, verify=False)

        if response.status_code == 200:
            print('{} Snapshot Value'.format(OSI_AF_ATTRIBUTE_TAG))
            print(json.dumps(json.loads(response.text), indent=4, sort_keys=True))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)
    return response.status_code


def read_attribute_stream(piwebapi_url, asset_server, user_name, user_password,
                          piwebapi_security_method):
    """ Read a set of values
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('readAttributeStream')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the sample tag
    request_url = '{}/attributes?path=\\\\{}\\{}\\{}|{}'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE, OSI_AF_ELEMENT, OSI_AF_ATTRIBUTE_TAG)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Read the set of values
        response = requests.get(piwebapi_url + '/streams/' + data['WebId'] +
                                '/recorded?startTime=*-2d', auth=security_method, verify=False)

        if response.status_code == 200:
            print('{} Values'.format(OSI_AF_ATTRIBUTE_TAG))
            print(json.dumps(json.loads(response.text), indent=4, sort_keys=True))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)
    return response.status_code


def read_attribute_selected_fields(piwebapi_url, asset_server, user_name, user_password,
                                   piwebapi_security_method):
    """ Read sampleTag values with selected fields to reduce payload size
        @param piwebapi_url string: the URL of the PI Web API
        @param asset_server string:  Name of the Asset Server
        @param user_name string: The user's credentials name
        @param user_password string: The user's credentials password
        @param piwebapi_security_method string:  Security method:  basic or kerberos
    """
    print('readAttributeSelectedFields')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the sample tag
    request_url = '{}/attributes?path=\\\\{}\\{}\\{}|{}'.format(
        piwebapi_url, asset_server, OSI_AF_DATABASE, OSI_AF_ELEMENT, OSI_AF_ATTRIBUTE_TAG)
    response = requests.get(request_url,
                            auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Read a set of values and return only the specified columns
        response = requests.get(piwebapi_url + '/streams/' + data['WebId'] +
                                '/recorded?startTime=*-2d&selectedFields=Items.Timestamp;Items.Value',
                                auth=security_method, verify=False)
        if response.status_code == 200:
            print('SampleTag Values with Selected Fields')
            print(json.dumps(json.loads(response.text), indent=4, sort_keys=True))
        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)
    return response.status_code


def main():
    """ Main method.  Receive user input and call the write value methods """
    piwebapi_url = str(input('Enter the PI Web API url: '))
    af_server_name = str(input('Enter the Asset Server Name: '))
    piwebapi_user = str(input('Enter the user name: '))
    piwebapi_password = str(getpass.getpass('Enter the password: '))
    piwebapi_security_method = str(input('Enter the security method,  Basic or Kerberos:'))
    piwebapi_security_method = piwebapi_security_method.lower()

    read_attribute_snapshot(piwebapi_url, af_server_name, piwebapi_user, piwebapi_password,
                            piwebapi_security_method)
    read_attribute_stream(piwebapi_url, af_server_name, piwebapi_user, piwebapi_password,
                          piwebapi_security_method)
    read_attribute_selected_fields(piwebapi_url, af_server_name, piwebapi_user, piwebapi_password,
                                   piwebapi_security_method)


if __name__ == '__main__':
    main()
