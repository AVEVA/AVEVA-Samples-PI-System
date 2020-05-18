
# PI Web API Data Analysis Sample

**Version:** 1.0.0 

[![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/PIWebAPI_Data_Analysis?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=1644&branchName=master)

The sample code in this folder demonstrates how to utilize the PI Web API to do some basic data analysis using Python Jupyter Notebook. In order to run this sample, you need to have [Python](https://www.python.org/downloads/release/python-373/) installed.

## Background and Problem
### Background
San Leandro Technical Campus (SLTC) is OSIsoft's headquarters in San Leandro, California. Like every office building, SLTC also needs temperature control systems to maintain a comfortable working environment. Now, consider a normal working day: The building starts getting occupied at around 7 AM. The building management system has to turn on the systems beforehand in order to reach a set temperature (say 70 deg F) by 7 AM. So let's say they have the control systems set to turn on at around 5 AM. 

The problem here is that these control systems are not identical. They all have different cooling rates so all of them don't take exactly 2 hours to reach the set point. Suppose one of them (Unit A) might reach the set point of 70 deg F by 6 AM. Unit A is now running for an extra hour in order to maintain the temperature of the office when there is nobody in the office. Our motivation here is to minimize this extra time so that we can save our costs and save some wasted energy as well.

### Problem Statement
Our objective here is to predict the total time taken by each of the unit in the building to reach the setpoint so that building management systems can turn on the units as close as possible to 7 AM.

In our earlier example, if we had predicted earlier (to some degree of accuracy) that the Unit A takes an hour to reach the set point, we would have turned it on by 6 AM instead of 5 AM which would have resulted us in saving that extra hour of wasted energy.

We will be utilizing the data that we have and do some basic data analysis and predictive machine learning using Jupyter Notebook in order to predict the cooling time for different units.

### Data Overview
In this sample, we are denoting these control systems as two different `VAVCO` units which are represented as AF Elements. Each of these elements have different attributes which mimic an actual cooling unit such as `% cooling` and `Set Point Offset`.

There are also eventframes of the template `VAVCO startup` which represent the start up events of the cooling unit. They have some attributes which capture the metadata on start time as well as end time. 

All this data is available as part of `Building Data.xml`. There is a helpful utility which will import this database as well as create and populate the PI Points. Find more on how to use it in the next section.

## Getting Started
- Clone the GitHub repository
- Open the `Data_Analysis` folder with your IDE (eg. Visual Studio Code)
- Install the required modules by running the following command in the terminal : `pip install -r requirements.txt`

### Setting up the AF database and the PI Data Archive
- In the `Data_Analysis` folder, populate the values of `test_config.json` with your own system configuration. 
For example:
```
	"PIWEBAPI_URL": "https://mydomain.com/piwebapi/",
	"AF_SERVER_NAME": "AssetServerName",
	"PI_SERVER_NAME": "PIServerName",
	"AF_DATABASE_NAME": "AFDatabaseNAme",
	"USER_NAME": "MyUserName",
	"USER_PASSWORD": "MyUserPassword",
	"AUTH_TYPE": "basic" # Basic or Kerberos 
```
- `Building Example.xml` assumes that the PI Server is on the same system. Edit the `Building Example.xml` to replace all occurences of `localhost`to your PI Server.
- Run `PIUploadUtility.sln` which imports the AF database from `Building Example.xml`, creates PI tags outlined in `tagdefinition.csv` and uploads the values in `pidata.csv` to PI Data Archive.
- The 
- You can open up PI System Explorer and check out the AF database you just created to further understand the data and the hierarchy.

### Running Jupyter Notebook
- Open a terminal and type in `jupyter notebook`. This will open a browser window. Navigate to the cloned repository and open up `Sandbox.ipynb`. Run the cells one by one and you can see the output in browser itself.
- The last cell in the notebook is for running unit tests so that you can test your PI Web API connection is working properly. As it tests the methods defined earlier in the notebook, you need to run the previous cells (the one which defines the GET and POST methods) of the notebook before trying to run the unit tests.

##  Documentation
The documentation for the various controllers and topics can be found at your local PI Web API help system: https://your-server/piwebapi/help

##  Authentication and minimum versions
The sample works with Basic authentication. 
This sample has been tested on `PI Web API 2018 SP1`, `PI AF Server 2018 SP2` and `PI Data Archive 2018 SP2`.

---

For the main PI Web API page [ReadMe](../)  
For the main landing page on master [ReadMe](https://github.com/osisoft/OSI-Samples)