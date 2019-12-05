# PI Web API Python Sample

[![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/PIWebAPI_Python?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=963&branchName=master)

The sample code in this folder demonstrates how to utilize the PI Web API using Python. You must have already [installed Python](https://www.python.org/downloads/release/python-373/) in order to run this sample application.

## Getting Started

To run the sample code:

- Clone the GitHub repository
- Open the Python folder with your IDE
- Install the required modules by running the following command in the terminal: `pip install -r requirements.txt`
- Run the application using the following command in the terminal: `python .\program.py` where `program.py` is the program you want to run. e.g `python .\create_sandbox.py`

## Getting Started with Tests

To run the sample tests:

- Open the test config file: `Python\test_config.py`
- Replace the values with your system configuration.

For example:

```python
PIWEBAPI_URL = 'https://mydomain.com/piwebapi'
AF_SERVER_NAME = 'AssetServerName'
PI_SERVER_NAME = 'PIServerName'
USER_NAME = 'MyUserName' # Or, 'domain\\userName'
USER_PASSWORD = 'MyUserPassword'
AUTH_TYPE = 'basic' # Basic or Kerberos
```

- Each test file (prefixed as "test\_..."), can be run independently or all the tests can be run in a single instance via the `run_all_tests.py` file.
- To run a single file, open the test file you wish to run: e.g. `.\test_batch.py`

- In the terminal, navigate to the test files and use the following command to run all the tests: `python .\run_all_tests.py` or to run a test individually: `python .\test_batch_call.py`

Note: The single tests may have expected configurations of PIWebAPI, this will cause the test to fail with a 404 Error if the expected configuration isn't available. See run_all_tests for the order to run the tests in.

## System Configuration

In order to run this sample, you must configure PI Web API with the proper security to:

- Create an AF database
- Create AF categories
- Create AF templates
- Create AF elements with attributes
- Create PI Points associated with element attributes
- Write and read element attributes
- Delete all the above AF/PI Data Archive objects

In addition, PI Web API must be configured to allow CORS as follows:

| Attribute               | Value                                               | Type    |
| ----------------------- | --------------------------------------------------- | ------- |
| CorsExposedHeaders      | Allow,Content-Encoding,Content-Length,Date,Location | String  |
| CorsHeaders             | \*                                                  | String  |
| CorsMethods             | \*                                                  | String  |
| CorsOrigins             | \*                                                  | String  |
| CorsSupportsCredentials | True                                                | Boolean |
| DisableWrites           | False                                               | Boolean |

## Functionality

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

---

For the main PI Web API page [ReadMe](../)  
For the main landing page on master [ReadMe](https://github.com/osisoft/OSI-Samples)
