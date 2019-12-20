​ <sup>  **Version:** 1.0.1</sup>

![OSIlogo.png](./images/OSIlogo.png)

# PI System Deployment Tests

```
Warning: PI System Deployment Tests should not be run on a production environment.
```

## Overview

PI System Deployment Tests are a lightweight testing framework along with a set of test samples designed to serve as a starting point for assessing the latest versions of the PI System prior to deployment. Each customer has a unique PI System architecture. These sample tests are meant to provide examples customers can use to get started building a more holistic, testing setup that meets the needs of their PI System.

This GitHub repo contains the source code (xUnit tests), documentation, and a script that compiles and runs the tests.

It is expected for users to execute the xUnit test source code 'as is' and unmodified with the exception of the _App.config_ file.

PI System Deployment Tests have been designed and tested on English operating systems.

[![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/PI%20System%20Deployment%20Tests/PI%20System%20Deployment%20Tests%20Sprint%20Build?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=437&branchName=master)

### Directories

The PI System Deployment Tests repo contains these directories:

| Directory                         | Contents                                                                                                                                               |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **[\scripts](./scripts/)**        | Contains the _Run.ps1_ PowerShell script supporting routines.                                                                                          |
| **[\source](./source/README.md)** | Contains a C# solution with xUnit tests. Also contains the _App.config_ file, which you edit to point to your test PI System.                          |
| **[\xml](./xml/README.md)**       | Contains the _OSIsoftTests-Wind.xml_ file. This file is imported into a target PI Server to create the Wind Farm AF database and associated PI points. |

### Before you begin

Before running the script and tests, you _must_ perform the following prerequisite tasks:

1. Prepare your PI System and determine which PI System components to include in the testing. See [Requirements](Requirements.md) for detailed instructions.

2. Set up a test client machine where tests will run. Make sure to use a Windows user account that meets the required security levels defined in [Requirements](Requirements.md).

   a. Install AF Client (AF 2018 SP3 or later) on the test client machine.

   b. Install PowerShell tools for the PI System on the test client machine. Both AF Client and PowerShell tools are included in the PI Server 2018 SP3 install kit.

   c. You must have Administrator privileges to run the PowerShell script.

3. Download and extract the _PI-System-Deployment-Tests-master.zip_ file to the test client machine.

4. Edit the _App.config_ file (located in the _\source_ directory) to match your selections from step 1. This file specifies what target PI System components to test.

   **Note:** After completing these steps, you are ready to execute the _Run.ps1_ script to run the tests. See [Run the scripts and tests](./scripts/README.md) for instructions.

## Overview of the Run.ps1 script

The _Run.ps1_ script contains all the steps required to execute the test suite. This script reads the _App.config_ file from the source directory to determine which tests to run and where PI System components are located. The script imports the WindFarm AF database (_OSIsoftTests_Wind.xml_) using the AF database name, and the AF Server and PI Data Archive locations specified in the _App.config_ file. Next, it creates PI points, downloads and installs all required assemblies (.NET development pack, NuGet, and MSBuild) if required, and compiles the test suite.

The _xUnit.console_ runner is used to execute tests. Settings in the _App.config_ file determine which tests run. Tests results are placed in the _\testResults_ directory.

The _Run.ps1_ script executes the tests in two general steps:

1. The Preliminary Checks confirm if your PI System configuration meets minimum requirements. These checks verify various things such as if the required Windows services are running, if the machines configured in the _App.config_ file are online, and if the user running the tests has sufficient privileges.
2. Executes the tests for required and any optional components as configured in the _App.config_ file.

At the end of the script, you have the option of removing the AF database and PI points created earlier by the script.

### Feedback

To request a new sample or if there is a feature or capability you would like demonstrated or there is an existing sample you would like in your favorite language, please give us feedback at the [OSIsoft GitHub Feedback Channel](https://feedback.osisoft.com/forums/922279-osisoft-github).

### Support

If your support question or issue is related to an OSIsoft product (error message, problem with product configuration, etc.), please open a case with OSIsoft Tech Support through the [myOSIsoft Customer Portal](https://myosisoft.com).

If your support question or issue is related to a non-modified sample (or test) or sample documentation; please email [Samples@osisoft.com](mailto:Samples@osisoft.com).

### License

PI System Deployment Tests are licensed under the [Apache 2 license](../../LICENSE).
