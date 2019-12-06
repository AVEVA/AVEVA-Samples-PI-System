The sample code in the folders below demonstrate how to utilize the PI Web API in several languages/frameworks.

The samples exercise the PI Web API in exactly the same way across multiple languages/frameworks: Angular, AngularJS, jQuery, Python and R. Each in their own folder. The samples show basic functionality of the PI Web API, not every feature. These samples are meant to show a basic sample application that uses the PI Web API to read and write data to a PI Data Archive and AF. Tests are also included to verify that the code is functioning as expected.

| Languages                                | Test Status                                                                                                                                                                                                                                |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [Angular](Angular/AngularPIWebAPISample) | [![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/PIWebAPI_Angular?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=953&branchName=master)   |
| [AngularJS](AngularJS/)                  | [![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/PIWebAPI_AngularJS?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=958&branchName=master) |
| [JQuery](JQuery/)                        | [![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/PIWebAPI_JQuery?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=962&branchName=master)    |
| [Python](Python/)                        | [![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/PIWebAPI_Python?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=963&branchName=master)    |
| [R](R/)                                  | [![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/PIWebAPI_R?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=965&branchName=master)         |

## System Configuration

In order to run these samples, you must configure PI Web API with the proper security to:

- Create an AF database
- Create AF categories
- Create AF templates
- Create AF elements with attributes
- Create PI Points associated with element attributes
- Write and read element attributes
- Delete all the above AF/PI Data Archive objects

On your client machine running this code, it is assumed that you have configured the system to trust the certficate used by PI Web API.

## Common Actions

The functionality included with the samples include (recommended order of execution):

- Create an AF database
- Create a category
- Create an element template
- Create an element and associate the element's attributes with PI tags where appropriate
- Write a single value to an attribute
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

## Test Configurations

Automated tests are also available to test the above mentioned functionality. Note that the tests must be updated with the appropriate:

- Username
- Password
- PI Web API host
- AF Server
- PI Data Archive

## Feedback

If you have a need for a new sample; if there is a feature or capability that should be demonstrated; if there is an existing sample that should be in your favorite language; please reach out to us and give us feedback at https://feedback.osisoft.com under the OSIsoft GitHub Channel. [Feedback](https://feedback.osisoft.com/forums/922279-osisoft-github).

## Support

If your support question or issue is related to something with an OSIsoft product (an error message, a problem with product configuration, etc...), please open a case with OSIsoft Tech Support through myOSIsoft Customer Portal (https://my.osisoft.com).

If your support question or issue is related to a non-modified sample (or test) or documentation for the sample; please email Samples@osisoft.com.

For the main PI System Samples landing page on master [ReadMe](https://github.com/osisoft/OSI-Samples-PI-System)
For the main samples landing page on master [ReadMe](https://github.com/osisoft/OSI-Samples)
