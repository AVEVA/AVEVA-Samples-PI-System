# What tests run?

```
Warning: PI System Deployment Tests should not be run on a production environment.
```

The PI System Deployment Tests PowerShell script runs Preliminary Checks first and then a suite of tests:

1.  Preliminary Checks: Check that the minimum items are in place for the components you are testing before running the test suite.  For example, it checks that PI Data Archive services are running and performs connectivity checks. The PowerShell script will not run the suite of tests until all the Preliminary Checks pass.

2.  Suite of tests: These tests run after the Preliminary Checks pass. These tests run serially; no tests run in parallel.  See the table below for a full list of tests.

## Description of test groups

### Required

Test group | Description 
----------|------------
 AFTests, AFDataTests, AFPITests, AFPluginTests | Performs create, read, update, search, and delete operations on all AF objects.
AnalysisTests   | Performs create, read, update, search, and delete operations on analyses.
 EFTests                                                      | Performs create, read, update, search, delete, and hierarchy tests on event frames. 
 PIDAEventTests, PIDATests, PIDAConnectionsTests, PIDAUpdateTests, PIDAPointTests | Verifies the user connects to PI Data Archive with the a PI Identity. Sends data to a set of new PI points, verifies all events are archived, and then removes the PI points. Reads data from a set of sinusoid PI points and verifies the periodic pattern. Retrieves PI events for multiple use cases from ClassData.  Verifies the PI point count for a given point mask is expected. 

### Optional

| Test group        | Description                                                  |
| ----------------- | ------------------------------------------------------------ |
| DataLinkAFTests   | Simulates the calls that the 'PIDataLink add-in to Excel' makes to exercise AF objects through AFData.dll. |
| DataLinkPIDATests | Simulates the calls that the 'PI DataLink add-in to Excel' makes to exercise PIDA objects through AFData.dll. |
| ManualLoggerTests | Exercises features of the PI Manual Logger product.          |
| NotificationTests | Performs tests on notification templates and rules.          |
| PISqlClientTests  | Exercise features of the PI SQL Client and PI SQL Data Access Server (RTQP Engine). |
| PIWebAPITests     | Exercises features of the PI Web API Server product.         |
| Vision3Tests      | Tests the ability to create, open, save, and delete displays in PI Vision server. |

Return to the main [PI System Deployment Tests landing page](../../../).

