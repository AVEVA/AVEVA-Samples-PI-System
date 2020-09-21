"""This script creates and executes a batch call using the PI Web API
   This python script requires some pre-requisites:
   1.  A back-end server with PI WEB API with CORS enabled.
"""

import json
import getpass
import random
import requests

from requests.auth import HTTPBasicAuth
from requests_kerberos import HTTPKerberosAuth

OSI_AF_DATABASE = 'OSIPythonDatabase'
OSI_AF_ELEMENT = 'OSIPythonElement'
OSI_AF_ATTRIBUTE_TAG = 'OSIPythonAttributeSampleTag'


def call_headers(include_content_type):
    """ Create the header and return a string.
    Parameters:
        include_content_type is a flag that determines whether or not the
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
    """ Create the security method and return a HTTP authorization for basic or kerberos.
    Parameters:
        security_method:  security method to use:  basic or kerberos
        user_name:  User's credentials name
        user_password:  User's credentials password
    """

    if security_method.lower() == 'basic':
        security_auth = HTTPBasicAuth(user_name, user_password)
    else:
        security_auth = HTTPKerberosAuth(mutual_authentication='REQUIRED',
                                         sanitize_mutual_error_response=False)

    return security_auth


def do_batch_call(piwebapiurl, asset_server, user_name, user_password, piwebapi_security_method):
    """ Create and execute a PI Web API batch call
    Parameters:
        piwebapiurl: the URL of the PI Web API
        assetServer:  the AF server name
        user_name:  User's credentials name
        user_password:  User's credentials password
        piwebapi_security_method:  Security method:  basic or kerberos
    """
    print('doBatchCall')

    #  create security method - basic or kerberos
    security_method = call_security_method(
        piwebapi_security_method, user_name, user_password)

    #  Get the sample tag
    request_url = '{}/attributes?path=\\\\{}\\{}\\{}|{}'.format(
        piwebapiurl, asset_server, OSI_AF_DATABASE, OSI_AF_ELEMENT, OSI_AF_ATTRIBUTE_TAG)
    response = requests.get(request_url, auth=security_method, verify=False)

    #  Only continue if the first request was successful
    if response.status_code == 200:
        #  Deserialize the JSON Response
        data = json.loads(response.text)

        #  Create the header
        header = call_headers(False)

        #  Create random value to write to a tag.
        attributeValue = '{:.4f}'.format(random.random() * 10)

        #  Create the data for this call
        batch_request = {
            '1': {
                'Method': 'GET',
                'Resource': request_url,
                'Content': '{}'
            },
            '2': {
                'Method': 'GET',
                'Resource': piwebapiurl + '/streams/{0}/value',
                'Content': '{}',
                'Parameters': ['$.1.Content.WebId'],
                'ParentIds': ['1']
            },
            '3': {
                'Method': 'GET',
                'Resource': piwebapiurl + '/streams/{0}/recorded?maxCount=10',
                'Content': '{}',
                'Parameters': ['$.1.Content.WebId'],
                'ParentIds': ['1']
            },
            '4': {
                'Method': 'PUT',
                'Resource': piwebapiurl + '/attributes/{0}/value',
                'Content': '{\'Value\':' + attributeValue + '}',
                'Parameters': ['$.1.Content.WebId'],
                'ParentIds': ['1']
            },
            '5': {
                'Method': 'POST',
                'Resource': piwebapiurl + '/streams/{0}/recorded',
                'Content': '[{\'Value\': \'111\'}, {\'Value\': \'222\'}, {\'Value\': \'333\'}]',
                'Parameters': ['$.1.Content.WebId'],
                'ParentIds': ['1']
            },
            '6': {
                'Method': 'GET',
                'Resource': piwebapiurl + '/streams/{0}/recorded?maxCount=10&selectedFields=Items.Timestamp;Items.Value',
                'Content': '{}',
                'Parameters': ['$.1.Content.WebId'],
                'ParentIds': ['1']
            }
        }

        #  Now that we have the attribute, we need to read the stream value
        response = requests.post(piwebapiurl + '/batch', auth=security_method, verify=False,
                                 json=batch_request, headers=header)

        if response.status_code == 207:
            print('Batch Status: ' + str(response.status_code))

            #  Deserialize the JSON Response
            data = json.loads(response.text)

            #  Print the results for each call and format it so it is legible JSON
            print('1: Get the sample tag')
            print(json.dumps(data['1'], indent=4, sort_keys=True))

            print('2: Get the sample tag\'s snapshot value')
            print(json.dumps(data['2'], indent=4, sort_keys=True))

            print('3: Get the sample tag\'s last 10 recorded values')
            print(json.dumps(data['3'], indent=4, sort_keys=True))

            print('4: Write a snapshot value to the sample tag')
            print(json.dumps(data['4'], indent=4, sort_keys=True))

            print('5: Write a set of recorded values to the sample tag')
            print(json.dumps(data['5'], indent=4, sort_keys=True))

            print(
                '6: Get the sample tag\'s last 10 recorded values, only returning the value and timestamp')
            print(json.dumps(data['6'], indent=4, sort_keys=True))

        else:
            print(response.status_code, response.reason, response.text)
    else:
        print(response.status_code, response.reason, response.text)

    return response.status_code


def main():
    """ Main method.  Receive user input and call the do_batch_call method """
    piwebapi_url = str(input('Enter the PI Web API url: '))
    af_server_name = str(input('Enter the Asset Server Name: '))
    piwebapi_user = str(input('Enter the user name: '))
    piwebapi_password = str(getpass.getpass('Enter the password: '))
    piwebapi_security_method = str(
        input('Enter the security method,  Basic or Kerberos:'))
    piwebapi_security_method = piwebapi_security_method.lower()

    do_batch_call(piwebapi_url, af_server_name, piwebapi_user, piwebapi_password,
                  piwebapi_security_method)


if __name__ == '__main__':
    main()
