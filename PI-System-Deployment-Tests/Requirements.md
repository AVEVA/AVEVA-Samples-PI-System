# Requirements

You must complete the following tasks before running PI System Deployment Tests:

* Prepare your target PI System with required and optional PI System components.

* Set up the test client machine.

* Set access privileges for the user(s) running the tests.

* Edit the *App.config* file.

  **Note:** PI high availability (HA) setups and features are not supported by PI System Deployment Tests.

## Prepare your target PI System

The tables below list the required and optional PI System components for the target PI System.

**Note:** PI Data Link and PI SQL Client must be installed on the test client machine if you want to run
tests for either of these optional PI System components.

![Prepare your target PI System.](./images/TargetPISystem.png)




### Required PI System components

At a minimum, the target PI System must have PI AF Server, PI Data Archive, and PI Analysis Service installed.  Make sure all PI System components meet minimum version requirements.

| PI System component    | Minimum version requirement  | App.config settings                                          | Associated test groups                                       |
| ---------------------- | ---------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| PI AF Server           | PI AF Server 2018 SP3        | Indicate the PI AF Server in the "**AFServer**" key (alias is allowed). AFDatabase key is set to "**OSIsoftTests-Wind**." This key can be modified if desired, but it is not recommended. | AFDataTests, AFPITests, AFPluginTests, AF Tests, EFTests     |
| PI Data Archive        | PI Data Archive 2018 SP3     | Indicate the Data Archive in the "**PIDataArchive**" key (alias is allowed). | PIDAConnectionsTests, PIDAEventTests, PIDAPointTests, PIDATests, PIDAUpdatesTests |
| PI Analysis Service    | PI Analysis Service 2018 SP3 | Indicate the machine where PI Analysis Service is installed in the "**PIAnalysisService**" key. | AnalysisTests                                                |



### Optional PI System components

If you want the test associated with an optional PI System component to run, indicate its location by assigning a value to it in the *App.config* file.  Currently, the PI System components listed below are the only components for which tests are available.

| PI System component     | Minimum version requirement                             | Value to edit in the App.config file                         | Associated test groups              |
| ----------------------- | ------------------------------------------------------- | ------------------------------------------------------------ | ----------------------------------- |
| PI Notification Service | PI Notification Service 2018 SP2                        | "**PINotificationsService**" key: Name of the machine where Notifications Service is installed. | NotificationTests                   |
| PI Web API              | PI Web API 2019                                         | "**PIWebAPI**" key: Name of the target PI web API Server.<br />"**PIWebAPICrawler**" key: Name of the target PI Web API Crawler machine if different from PI Web API server.<br />"**PIWebAPIUser**" and "**PIWebAPIPassword**" keys: Username and password if using basic authentication.<br /> "**PIWebAPIConfigurationInstance**" key: Name of PI Web API configuration instance in AF server if different from machine name.<br /> "**SkipCertificateValidation**" key: Enter "**True**" to allow clients to bypass certificate validation for testing. | PIWebAPITests                       |
| PI Vision               | PI Vision 2019                                          | "**PIVisionServer**" key: URL of target PI Vision Server.<br />"**SkipCertificateValidation**" key: Enter "**True**" to allow clients to bypass certificate validation for testing. | Vision3Tests                        |
| PI Manual Logger        | PI Manual Logger PC 2014 & PI Manual Logger Web 2017 R2 | "**PIManualLogger**" key: Name of target PI Manual Logger's Server.<br /> "**SkipCertificateValidation**" key: Enter "**True**" to allow clients to bypass certificate validation for testing. | ManualLoggerTests                   |
| PI Data Link            | PI Data Link 2019 SP1                                   | "**PIDataLinkTests**" key: Enter "**True**" to run tests; enter "**False**" to not run tests. PI Data Link is required to be installed on the test client machine. | DataLinkAFTests,  DataLinkPIDATests |
| PI SQL Client           | PI SQL Client 2018 R2                                   | "**PIsqlClientTests**" key: Enter "**True**" to run tests; enter "**False**" to not run tests. PI SQL Client is expected to be installed on the test client machine. | PIsqlClientTests                    |

**Note:** If the value for a key is left blank ("") in the *App.config* file, the tests associated with this PI System component will not run.

### Set up the test client machine

Before running PI System Deployment Tests, you need to set up the test client machine.  Install PI AF Client 2018 SP3 or greater on the client machine where tests will be executed. Also, make sure the PowerShell tools for PI System 2018 SP3 are installed. 

The test client machine must have Internet access and access to the PI System components.



## Set access privileges

Grant administrator privileges to users who will run the Windows PowerShell test script. The user running the tests needs full access to PI System resources and must be mapped to the piadmins identity and PI AF Administrators identity. Note: If a local account is used to run tests against a local AF server, a dedicated mapping from the local account to the PI AF Administrators identity may need to be created in AF security despite the default BUILTIN\Administrators to PI AF Administrators mapping. 



## Edit the App.Config file

The *App.config* file is where you set values for your target PI System.

**Warning:** Do not edit any of the "**key**" names in the *App.config* file. Only make changes to the "**value**" entries.

1.  After unzipping the *PISystemDeploymentTests.zip* file, navigate to the  _PISystemDeploymentTests\source_ directory.
2. Open the *App.config* file and then make changes as defined above to all the PI System components on your target PI System.

   ![screen_AppConfig](./images/screen_AppConfig.png)

    **Note:** Some values are required. At a minimum, you must fill in the values of PIDataArchive, AFServer, AF Database, and PIAnalysisService.

3.  Save your changes.

Return to the main [PI System Deployment Tests landing page](../../)

