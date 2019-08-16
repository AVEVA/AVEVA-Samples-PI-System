The sample code in this folder demonstrates how to utilize the PI Web API in jQuery. You must have already [downloaded jQuery](https://jquery.com/download/) in order to run this sample application.


Getting Started
------------

To run the sample code:
- The sample code was developed to run in the Chrome browser
- Clone the GitHub repository
- Open Visual Studio Code  
- Open the folder in which you placed the code
- Open the file: ```launch.json```
- Search for the text "__url__":, change this to the path to ```index.html```. For example: 

```json
"url": "file:///C:/PI Web API/JQuery/index.html",
```

- Install Debugger for Chrome extension
- Click "Start Debugging" on the Debug menu


Getting Started with Tests
------------

To run the sample tests:
- You must have [Karma](https://karma-runner.github.io/latest/index.html) installed in order to run automated tests.
    - You can install this in \JQuery\KarmaUnitTests with ```npm install karma –-save-dev```
- Open the file: ```samplePIWebAPI.js```
- Search for the text "__var configDefaults__"
- Change the text for __PIWebAPIUrl__, add your PI Web API Url.  For example:

```javascript
'PIWebAPIUrl': 'https://mydomain.com/piwebapi',
```

- Change the text for __AssetServer__, add your Asset Server Name.  For example:  

```javascript
'AssetServer': 'AssetServerName',
```

- Change the text for __PIServer__, add your PI Server Name.  For example:  

```javascript
'PIServer': 'PIServerName'
```

- Change the text for __Name__, add your PI Web API user name.  For example:  

```javascript
'Name': 'MyUserName',
```

- Change the text for __Password__, add your PI Web API user password.  For example:  

```javascript
'Password': 'MyUserPassword'
```

- Change the text for __AuthType__, add your PI Web API authentication method (Basic or Kerberos).  For example:  

```javascript
'AuthType': 'Basic',
```

- Open the file: ```launch.json```
- Search for the text "url":, change this to the path to SpecRunner.html. For example: 

```json
"url": "file:///C:/PI Web API/JQuery/JasmineUnitTests/SpecRunner.html",
```

- From \Query\KarmaUnitTests run tests with ```karma start```

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


On your client machine running this code, it is assumed that you have configured the system to trust the certficate used by PI Web API.

If you don't you will see an error similar to this in the Result box on the webpage:

```
Error finding server: undefined
```


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

[![Build Status](https://osisoft.visualstudio.com/NOC/_apis/build/status/PI%20Web%20API%20(JQuery)?branchName=dev)](https://osisoft.visualstudio.com/NOC/_build/latest?definitionId=4624&branchName=dev)   

For the main PI Web API page [ReadMe](../)<br />
For the main landing page on master [ReadMe](https://github.com/osisoft/OSI-Samples)
