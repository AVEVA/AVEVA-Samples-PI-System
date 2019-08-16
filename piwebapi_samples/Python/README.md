The sample code in this folder demonstrates how to utilize the PI Web API using Python. You must have already [installed Python](https://www.python.org/downloads/release/python-373/) in order to run this sample application.  

Getting Started
------------

To run the sample code:
- Clone the GitHub repository
- Open the Python folder with your IDE
- Install the required modules by running the following command in the terminal:  ```pip install -r requirements.txt```
- Run the application using the following command in the terminal:  ```python .\program.py``` where ```program.py``` is the program you want to run.  e.g ```python .\create_sandbox.py```

Getting Started with Tests
------------

To run the sample tests:
- Each test file (prefixed as "test_..."), can be run independently or all the tests can be run in a single instance via the ```run_all_tests.py``` file.
- To run a single file:
  - Open the test file you wish to run: e.g. ```.\test_batch.py```
  - Note the global constants at the top file, and replace with your desired values.
- To run all tests via ```run_all_tests.py```:
  - Open __each__ test file.
  - Note the global constants at the top of each file, and replace with your desired values.
  
- All of these global constants are not necessary for each file, therefore you may only see one or two per file.
- Search for the text __PIWEBAPI_URL__, add your PI Web API Url.  For example:  

```python
PIWEBAPI_URL = 'https://mydomain.com/piwebapi';
```

- Search for the text __AF_SERVER_NAME__, add your Asset Server Name.  For example:  

```python
AF_SERVER_NAME = 'AssetServerName';
```

- Search for the text __PI_SERVER_NAME__, add your PI Server Name.  For example:  

```python
PI_SERVER_NAME = 'PIServerName';
```

- Search for the text __OSI_AF_DATABASE__, add your PI Web API database name.  For example:  

```python
OSI_AF_DATABASE = 'DatabaseName';
```

- Search for the text __OSI_AF_ELEMENT__, add your PI Web API element name.  For example:  

```python
OSI_AF_ELEMENT = 'Pump1';
```

- Search for the text __OSI_AF_ATTRIBUTE_TAG__, add your PI Web API attribute tag.  For example:  

```python
OSI_AF_ATTRIBUTE_TAG = 'PumpStatus';
```


- In the terminal, navigate to the test files and use the following command to run all the tests:   ```python .\run_all_tests.py```  or to run a test individually: ```python .\test_batch_call.py```

Note:  The tests are only configured for kerberos.

Note:  The single tests may have expected configurations of PIWebAPI, this will cause the test to fail with a 404 Error if the expected configuration isn't available.  See run_all_tests for the order to run the tests in. 


System Configuration
----------------------------

In order to run this sample, you must configure PI Web API with the proper security to:
- Create an AF database
- Create AF categories
- Create AF templates
- Create AF elements with attributes
- Create PI Points associated with element attributes
- Write and read element attributes
- Delete all the above AF/PI Data Archive objects  

In addition, PI Web API must be configured to allow CORS as follows:  

Attribute|Value|Type
------|------------|---
CorsExposedHeaders|Allow,Content-Encoding,Content-Length,Date,Location|String
CorsHeaders|*|String
CorsMethods|*|String
CorsOrigins|*|String
CorsSupportsCredentials|True|Boolean
DisableWrites|False|Boolean

Functionality
------------

This sample shows basic functionality of the PI Web API, not every feature. The sample is meant to show a basic sample application that uses the PI Web API to read and write data to a PI Data Archive and AF. Tests are also included to verify that the code is functioning as expected.

The functionality included with this sample includes(recommended order of execution):
- Create an AF database
- Create a category
- Create an element template
- Create an element and associate the element's attributes with PI tags where appropriate
- Write a single value to the attribute
- Write 100 values to an attribute
- Perform a Batch (6 steps in 1 call) operation which includes:  
  - Get the sample tag  
  - Read the sample tag's snapshot value  
  - Read the sample tag's last 10 recorded values  
  - Write a value to the sample tag  
  - Write 3 values to the sample tag  
  - Read the last 10 recorded values from the sample tag only returning the value and timestamp
- Return all the values over the last 2 days
- Return timestamp and values over the last 2 days  
- Delete the element
- Delete the element template
- Delete the sample database

[![Build Status](https://osisoft.visualstudio.com/NOC/_apis/build/status/PI%20Web%20API%20(Python)?branchName=dev)](https://osisoft.visualstudio.com/NOC/_build/latest?definitionId=4625&branchName=dev)

For the main PI Web API page [ReadMe](../)  
For the main landing page on master [ReadMe](https://github.com/osisoft/OSI-Samples)