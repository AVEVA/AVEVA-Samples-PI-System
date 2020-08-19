# Problem Description
Running the PI System Deployment Tests, if the optional tests for PI Manual Logger are enabled, in some cases the user running the tests could see a false positive; meaning they see a failure for PI Manual Logger on the test report even though PI Manual Logger is functional with no issues. This specific case of false positive is due to absence of required access permissions for running the PI System Deployment Tests. 
A set of access permissions are required for the user running the PI System Deployment Tests in order to successfully pass the preliminary checks and get to the functional tests (these requirements are listed in the Requirements document). For PI Manual Logger, however, even if the required permissions are not in place, the preliminary checks will pass. But the following functional tests won’t be executed correctly due to lack of access permissions, and the user will see a failure of the functional tests on PI Manual Logger. 

# Workaround
Prior to running the PI System Deployment Tests, verify that the user running the tests has access permissions required for running the PI Manual Logger tests. These are listed in the [Requirements](../Requirements.md) document.

# Found in Version
PI System Deployment Tests 1.0.2

# Fixed in Version
PI System Deployment Tests 1.0.3