# On-Premise PI Server Install PowerShell Sample

**Version:** 1.0.0

[![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/Deployment_OnPrem?branchName=master)](https://dev.azure.com/osieng/engineering/_build/latest?definitionId=1640&branchName=master)

This sample uses PowerShell to install Microsoft SQL Server Express, the PI Server including PI Data Archive and PI AF Server, and/or a generic self-extracting PI install kit. The script only installs the packages that are specified by flags, so it can be used to run all three installs or only one.

Developed using PowerShell 5.1

## Requirements

- Powershell 5+
- Install kits for products to be installed
  - For `-sql`, Microsoft SQL Server Express kit may need to be expanded, should use `SETUP.EXE`
  - For `-piserver`, PI Server install kit with `pilicense.dat` in same directory
  - For `-pibundle`, a self-extracting PI install kit with prepared `silent.ini` (or script will use defaults)
- The `-piserver` install flag requires that a local copy of Microsoft SQL Server Express is running in order to install the PI Server
  - The script can install Microsoft SQL Server Express using the `-sql` flag and the kit available from Microsoft [here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
  - The script can install if a local copy of Microsoft SQL Express is already running
  - The script could be modified to install PI AF Server against a remote server or local SQL instance other than SQLExpress
- The `-pibundle` install flag requires that [7-zip](https://www.7-zip.org/) is installed on the local machine

## Running the Sample

### Dry Run Mode

This sample script includes an optional parameter, `-dryRun`, that will output logs but will not perform any install steps. This can be useful prior to running the script the first time to check for any potential problems. In this mode, system checks and validation of the passed in parameters will still occur, so it can be used to ensure the passed in parameters are correct before actually running the installation.

```PowerShell
.\Install-PIServer.ps1 -dryRun
```

### Install Mode

#### Microsoft SQL Server Express

To install Microsoft SQL Server Express, include the `-sql` flag to the script, and use it to pass in the path to the `SETUP.EXE`. Note that this installation can take several minutes to complete.

#### PI Server

To install the PI Server, include the `-piserver` flag to the script, and use it to pass in the path to the PI Server install kit, like `PI-Server_2018-SP3-Patch-1_.exe`. It is also required to either include the `-sql` flag or ensure Microsoft SQL Server Express is already running locally.

The PI Server installation will use the `TYPICAL` flag, which will install the PI Data Archive, PI AF Server, and supporting products. To see the full list of products installed using the `TYPICAL` flag, start the install kit normally, and at the "Feature Selection" step, click the "Select Typical" button. The "Summary" panel will list the products to be installed, or the "Individual Features" tab can also be used to inspect the list of checked features.

#### Self-extracting PI Install Kit

The `-pibundle` flag can be used to install most other PI installation kits. This flag will extract the bundle to a local directory, and then silently run the `Setup.exe` inside that folder. To override the default silent installation, use the `-silentini` flag to the script to specify a file to use.

### Logs

The script will log detailed information to a local timestamped log file, which will be listed in the output of the script. If the PI Server is installed, additional (non-timestamped) logs will be created by that install kit.

---

For the PI System Deployment Samples landing page [ReadMe](../)  
For the main PI System page [ReadMe](../../)  
For the main OSIsoft Samples page [ReadMe](https://github.com/osisoft/OSI-Samples)
