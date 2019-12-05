# PI Web API R Sample

[![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/PIWebAPI_R?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=965&branchName=master)

The sample code in this folder demonstrates how to utilize the PI Web API in R. The sample code is dependent on:

- [Downloading R](https://cran.r-project.org/mirrors.html)
- [Installing httr](https://CRAN.R-project.org/package=httr) to work with HTTP and jsonlite for parsing and generating JSON

The steps below assume that you have [RStudio](https://www.rstudio.com/products/rstudio/download/).

## Getting Started

To run the sample code:

- Clone the GitHub repository
- Open RStudio
- Install httr if not already installed. From the Console inside RStudio `install.packages("httr")`
- Open the file: `sampleCode.R`
- Click the **Source** menu option to execute the sample code

## Getting Started with Tests

To run the sample tests:

- Install [testthat](https://cran.r-project.org/web/packages/testthat/index.html) if not already installed. From the Console inside RStudio `install.packages("testthat")`
- Open the file: `test_config.R`
- Replace the values with your system configuration.

For example:

```R
defaultName <- "MyUserName" # Or, 'domain\\userName'
defaultPassword <- "MyUserPassword"
defaultPIWebAPIUrl <- "https://mydomain.com/piwebapi"
defaultAssetServer <- "AssetServerName"
defaultPIServer <- "PIServerName"
defaultAuthorization <- "basic"
```

- Open the file: `run_tests.r`
- Search for the text path **<- "."**, change the path to the folder in which you placed the R scripts. For example:

```R
path <- "C:\\R\\"
```

- Click the **Source** menu option to execute the sample code tests

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
