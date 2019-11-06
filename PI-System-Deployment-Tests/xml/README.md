# Set up the Wind Farm database for PI System Deployment Tests

PI System Deployment Tests requires a mock AF database and the associated PI points.  For this purpose, we have developed a test AF database named Wind Farm.  

The Wind Farm database deployment package includes the following: 

- *README.md* (this file)
- *OSIsoftTests-Wind.xml* 

The creation of the Wind Farm database adds 814 PI points, 496 analyses, and 51 elements.

## The Wind Farm in PI System Deployment Tests

The PI System Deployment Tests requires that the Wind Farm database be in place along with the associated PI points.  The setup portion of the *Run.ps1* script handles the import of the AF database and also the creation of the PI points.

In addition, the setup backfills 80 analog analyses for one 24-hour period.  Most analyses run every 2 seconds, and roughly 40 PI events are generated each second.  Normally, this amount of background processing should not affect the overall performance of the PI system. You may wish to monitor hardware consumption during testing.

The Deployment Instructions below are not generally required during PI System Deployment Tests execution.  These steps occur during the setup portion of the *Run.ps1* script. 

## Deployment Instructions

I. Prerequisites with the following minimum software versions:

- PI Data Archive 2018 SP3 or later,
- PI AF Server 2018 SP3 or later
- PI Analysis Service 2018 SP3 or later
- PI AF Client 2018 SP3 or later on the test client machine

II. Set up the AF database manually. 

​	**Note:** The *Run.ps1* script deploys the OSIsoft Tests Wind Farm AF database and creates the required PI points. If you want to deploy this database manually, follow the steps below.

1. In PI System Explorer (PSE), connect to the target AF Server and create a new AF database named “OSIsoftTests-Wind” or as desired. 

2. Import *OSIsoftTests-Wind.xml* using the default import settings, make sure "Disable New Analyses and Notifications" is checked. 

3. Enter the PI Data Archive server name in the *\\\\Your-AFServer-Name\Your-AFDatabase-Name\PI Data Archive|Name* attribute. (The values used should match those that are entered in the *App.config* file.)

   **Note:** Continuing to the next step creates 814 PI points. 

4. Right-click the root element and select “Create or Update Data Reference” to generate PI Points and link them to corresponding AF attributes. 

5. Go to PSE -> Management tab, select all analyses and click "Enable selected analyses". Wait and make sure all analyses are in the running status.

6. Select 80 analyses with the names of "Demo Data - Analog Random Calcs" and "Demo Data - Analog SineWave Calcs", click "Queue backfilling or recalculation for selected analyses", queue recalculations with the option of "Permanently delete existing data and recalculate" to populate historical data for at least one day. Wait on the recalculations to finish. Note that archive files must already exist in the Data Archive on backfill dates.

Return to the main [PI System Deployment Tests landing page](../../../).

