# Style Guide

This readme serves as a guide to help explain organization in this repo and questions about the code

## Organization

* For each different technology (for instance OCS, OMF) there is a main landing page. 
* Each sample is represented on the main landing page for the technology with an appropriate short task name, description including a link to a greater description, links to the individual samples marked by languages, and test status.
* A task level description should include information that is common to all language specific examples below it, including common steps.  This should also include links back to the main page, to all languages and highlight test status of these languages.
* A language specific readme should include information that is unique to this language.  This can include stepping over line examples from the sample with reference back to the general steps.  This readme should also include links back to the main technology page, to the general task readme, and the specific test status.


## Code expectations

* Samples highlight a specific generic task a person can accomplish.  It can include multiple related tasks.
* The sample should be self contained, setting up and cleaning up after itself as much as possible.  Anything that is needed in setup of the system needs to be well documented in readme, as warranted, there should be how to do the needed setup or a link to directions on how to do it.  
* The code follows OSIsoft and industry best practices in design and code style.
* Automated tests are included that check to ensure the sample runs as expected on a clean system, including making sure intermediate results in the sample are as expected.  Any expectations of the test or sample itself is included in the sample readme.  There are more details about testing in the [testing guide](test_guide.md).
* Comments are included in the code to help developers understand any interaction that isn't otherwise documented in the code or intellisense help of functions.
* Samples are repeated in various programming languages as appropriate.
* The library samples include functions that are reused across samples. 
* If the task level description includes common steps for the various language samples, each language sample explicitly marks where the steps are in the code.
* Samples are versioned and a [history](miscellaneous/versionHistory.md) of the code samples is viewable.

Note: Samples (including the sample libraries) do not necessarily go over every possible setting and every endpoint of a service (documentation is there to show all of the details).  Samples are created to highlight specifc tasks and show how things could be made and organized.

## Assumptions
 The samples will assume you have an OSI system setup and properly running.  

* This means either a PI Server installed and running or, in the case of OCS, a tenant is provisioned.  
* For OCS samples it is typically assumed you have client credentials configured and a namespace created.  Some samples may use different types of authentication and this is noted in the sample readme, but even in those it is assumed that this already created.  
* For the OMF examples it is assumed you have the OMF endpoint configured and running.
* For PI Web API samples it assumed that your PI System, including PI Web API, is running and configured.  It is also assumed that your client machine trusts the certificate used by PI Web API.   



