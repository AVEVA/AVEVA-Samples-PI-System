# Welcome to the testing guide!


For OSI Samples testing we are concerned with testing the samples to ensure that each sample works completely and as expected with no errors.  We check final and intermittant results in the samples to ensure the results are as expected.  The goal for the tests is to ensure a level of confidence of operation in each sample.  We test to make sure that the sample is working and running as expected on a clean system, so that a user of a sample knows they have a good starting base to learn from.  

The way the tests are run can be found by looking at the Continuous Integration pipeline as defined by these 2 files [azure-pipelines](azure-pipelines.yml)and [azure-pipelines-on-prem](azure-pipelines-on-prem.yml).  They are split up for clarity that some tests use OSIsoft hosted test agents.  The main reason we are using our own hosted agents is to simplify security by having the test agent inside our domain.  Note: using proper security for you computer and PI Web API can make it safe to open to the internet.  To see what is deployed on the OSIsoft hosted test agents see the [on prem testing](miscellaneous/on_prem_testing.md) document.

Test against OCS (including OMF tests to OCS) are run Monday, Wednesday, Friday and on every PR.

Tests can also be run manually.  Steps for running a test manually locally is noted in the specific sample readme, but also can be found by inspecting the .yml files.

Unless otherwise noted in the sample readme.md, all tests have these basic assumptions:

All:
* All noted expections and requirements in the sample readme are followed
* The azure-pipelines tests use Microsoft hosted agents to run the tests
* The azure-pipelines-on-prem tests use OSIsoft hosted agents to run the tests
