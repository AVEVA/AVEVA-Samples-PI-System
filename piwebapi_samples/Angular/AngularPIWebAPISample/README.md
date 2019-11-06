The sample code in this folder demonstrates how to utilize the PI Web API in Angular. You must have already [configured your Angular development environment](https://angular.io/guide/quickstart) in order to run this sample application.  


Prerequisites
-------------
 - This application by default will use Port 4200
 
```
Note: This application is hosted on HTTP.  This is not secure.  You should use a certificate and HTTPS.
```

Getting Started
------------

To run the sample code:
- Clone the GitHub repository
- Open the Angular\AngularPIWebAPISample folder with your IDE
- Install the required modules by running the following command in the terminal:  ```npm ci```
- Run the application using the following command in the terminal:  ```ng serve```
- By default, you can open the Angular app by using the following URL in a browser:  ```localhost:4200```

Getting Started with Tests
------------

To run the sample tests:
- Open the test file:  ```Angular\AngularPIWebAPISample\src\app\services\piwebapi.service.spec.ts```
- Search for the text __const piWebAPIUrl__, add your PI Web API Url.  For example:  

```typescript 
const piWebAPIUrl = 'https://mydomain.com/piwebapi';
```

- Search for the text __const assetServer__, add your Asset Server Name.  For example:  

```typescript 
const assetServer = 'AssetServerName';
```

- Search for the text __const piServer__, add your PI Server Name.  For example:  

```typescript
const piWebAPIUrl = 'PIServerName';
```

- Search for the text __const userName__, add your PI Web API user name.  For example:  

```typescript
const userName = 'MyUserName';
```

- Search for the text __const userPassword__, add your PI Web API user password.  For example:  
```typescript
const userPassword = 'MyUserPassword';
```

- Search for the text __const authType__, add your PI Web API authentication method (Basic or Kerberos).  For example: 

```typescript
const authType = 'Basic';
```

- In the terminal, use the following command to run the tests:  ```ng test```
- If you run into any issues with the Jasmine tests timing out, you can search for the __jasmine.DEFAULT_TIMEOUT_INTERVAL__ setting, uncomment it, and set it to a higher value.  For example:
```typescript
jasmine.DEFAULT_TIMEOUT_INTERVAL = 10000;
``` 

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
An error occured:  Http failure response for [...]: 0 Unknown Error
```

Functionality
--------------

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

[![Build Status](https://osisoft.visualstudio.com/Engineering%20Incubation/_apis/build/status/PI_System/AngularJS_PIWebAPISample?branchName=master)](https://osisoft.visualstudio.com/Engineering%20Incubation/_build/latest?definitionId=5281&branchName=master)

For the main PI Web API page [ReadMe](../../)  
For the main landing page on master [ReadMe](https://github.com/osisoft/OSI-Samples)
