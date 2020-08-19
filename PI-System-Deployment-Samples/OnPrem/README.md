# On-Premise PI Server Install PowerShell Sample

**Version:** 1.0.0

[![Build Status](https://dev.azure.com/osieng/engineering/_apis/build/status/product-readiness/PI-System/Deployment_OnPrem?branchName=master)](https://dev.azure.com/osieng/engineering/_build?definitionId=1640&branchName=master)

This sample uses PowerShell to install Microsoft SQL Server Express, the PI Server including PI Data Archive and PI AF Server, and/or a generic self-extracting PI install kit. The script only installs the packages that are specified by flags, so it can be used to run all three installs or only one.

Developed using PowerShell 5.1, Microsoft SQL Server 2017 Express, PI Server 2018 SP3 Patch 1, and PI ProcessBook 2015 R3 Patch 1.

## Requirements

- Powershell 5+
- Install kits for products to be installed

### Microsoft SQL Server Express Requirements

Use the `-sql` flag to specify the path to `SETUP.EXE`.

- The Microsoft SQL Server Express kit may need to be expanded first

### PI Server Requirements

Use the `-piserver` flag to specify the path to the PI Server install kit.

- The PI Data Archive `pilicense.dat` should be in the same directory, otherwise, use the `-pilicdir` flag to specify the path to a directory containing the `pilicense.dat` file
- The required .NET Framework version must be installed before running this command
  - PI Server 2018 SP3 and PI Server 2018 SP3 Patch 1 require [.NET Framework 4.8](https://dotnet.microsoft.com/download/dotnet-framework/net48)
  - .NET Framework installation usually requires a restart and is not included in this script
- Microsoft SQL Server Express must be running locally in order to install the PI Server
  - The script can install Microsoft SQL Server Express using the `-sql` flag and the kit available from Microsoft [here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
  - The script can install the PI Server if a local copy of Microsoft SQL Express is already running
  - The script could also be modified to install PI AF Server against a remote server or local SQL instance other than SQLExpress

### Self-Extracting PI Install Kit Requirements

Use the `-pibundle` flag to specify the path to a self-extracting PI install kit.

- [7-zip](https://www.7-zip.org/) must be installed on the local machine
- This flag can be used in combination with the `-silentini` to perform a custom silent installation, by specifying a valid `silent.ini` file for the product to be installed
  - To build a `silent.ini` file, either consult documentation, or extract the installation kit and review the default `silent.ini` file in the output directory
- If the `-silentini` flag is not specified, the script will install using the default `silent.ini` file that is extracted from the install kit

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

#### Self-Extracting PI Install Kit

The `-pibundle` flag can be used to install most other PI installation kits. This flag will extract the bundle to a local directory, and then silently run the `Setup.exe` inside that folder. To override the default silent installation, use the `-silentini` flag to the script to specify a file to use.

### Logs

The script will log detailed information to a local timestamped log file, which will be listed in the output of the script. If the PI Server is installed, additional (non-timestamped) logs will be created by that install kit.

### Verify Script

The test pipeline uses the script `.\Verify-PIServer.ps1` to verify installations have succeeded. The test pipeline uses remote PowerShell to run the script with the parameters:

```PowerShell
.\Install-PIServer.ps1 -sql .\SQL\SETUP.EXE -piserver .\PIServer.exe -pilicdir C:\Test -afdatabase TestDatabase -pibundle .\PIProcessBook.exe -remote
```

This installs Microsoft SQL Server Express, PI Server, and PI ProcessBook, and also creates an AF Database named 'TestDatabase.' The test script then checks:

- SQL Server Express (instance SQLExpress) is running
- PI Archive Subsystem is running
- PI AF Database 'TestDatabase' was created
- PI ProcessBook executable is found in `%PIHOME%`

The test script is intended for use in the automated test pipeline, but can also be modified to verify the desired deployment.

---

For the PI System Deployment Samples landing page [ReadMe](../)  
For the main PI System page [ReadMe](../../)  
For the main OSIsoft Samples page [ReadMe](https://github.com/osisoft/OSI-Samples)
