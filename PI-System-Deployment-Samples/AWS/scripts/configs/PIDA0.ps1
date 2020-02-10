[CmdletBinding()]
param(
    # Domain Net BIOS Name, e.g. 'mypi'.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainNetBiosName,

    # Username of domain admin account.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainAdminUserName,

    # Setup Kit PI Installer Product ID
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$SetupKitsS3PIProductID,

    # PI Data Archive Primary
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIDataArchivePrimary,

    # PI Data Archive Secondary
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIDataArchiveSecondary,

    # Primary domain controller targeted for service account creation.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PrimaryDomainController = 'DC0',

    # Used to determine whether PI Collective Creation scripts need executing. Cloud Formation passes a string, hence this is a string rather than a boolean.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [ValidateSet('true','false')]
    [string]$DeployHA = 'false',

    # OSIsoft Field Service Technical Standards - Management task in the PI Data Archive.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIAdministratorsADGroup = 'PIAdmins',

    # OSIsoft Field Service Technical Standards - Read access to PI Points data. This group replaces PIWorld.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIUsersADGroup = 'Domain Users',

    # OSIsoft Field Service Technical Standards - Read and write access on PI Point data. This group includes PI Buffer Subsystem and PI Buffer Server.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIBuffersADGroup = 'PIBuffers',

    # OSIsoft Field Service Technical Standards - Read access on PI Point configuration. This group includes buffered PI Interfaces. Ex: PI Interface for OPC DA.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIInterfacesADGroup = 'PIInterfaces',

    # OSIsoft Field Service Technical Standards - PI Point creation rights. This group includes users creating analysis in PI AF, which in most cases will be creating PI Points to store the results of their calculations.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIPointsAnalysisCreatorADGroup = 'PIPointsAnalysisCreator',

    # OSIsoft Field Service Technical Standards - PI Vision, PI WebAPI, and PI Web Crawler.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIWebAppsADGroup = 'PIWebApps',

    # OSIsoft Field Service Technical Standards - PI Connectors and Relays.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIConnectorRelaysADGroup = 'PIConnectorRelays',

    # OSIsoft Field Service Technical Standards - PI Data Collection Managers
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIDataCollectionManagersADGroup = 'PIDataCollectionManagers',

    # OSIsoft Field Service Technical Standards - PI Data Collection Managers
    [Parameter(Mandatory)]
    [ValidateSet("true", "false")]
    [String]$EnableAdGroupCreation = "false",

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix
)

try {
    # Set to enable catch to Write-AWSQuickStartException
    $ErrorActionPreference = "Stop"

    Import-Module C:\cfn\scripts\IPHelper.psm1

    # Set Local Configuration Manager
    Configuration LCMConfig {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode  = 'ApplyOnly'
            CertificateID      = (Get-ChildItem Cert:\LocalMachine\My)[0].Thumbprint
        }
    }

    LCMConfig
    Set-DscLocalConfigurationManager -Path .\LCMConfig


    # Set Configuration Data. Certificate used for credential encryption.
    $ConfigurationData = @{
        AllNodes = @(
            @{
                NodeName             = $env:COMPUTERNAME
                CertificateFile      = 'C:\dsc.cer'
                PSDscAllowDomainUser = $true
            }
        )
    }

    # Get exisitng service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUserName" -WithDecryption $True).Parameters[0].Value

    # Generate credential for domain security group creation.
    $securePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $domainCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$DomainAdminUserName", $securePassword)

    # Create Security groups used for FSTS Mappings
    [boolean]$EnableAdGroupCreation = if ($EnableAdGroupCreation -eq 'true') {$true} else{$false}

    # EC2 Configuration
    Configuration PIDA0Config {

        param(
            # PI Data Archive Install settings
            [string]$afServer = 'PIAF0',
            [string]$piServer = 'PIDA0',
            [string]$archiveFilesSize = '256',
            [string]$PIHOME = 'F:\Program Files (x86)\PIPC',
            [string]$PIHOME64 = 'F:\Program Files\PIPC',
            [string]$PI_INSTALLDIR = 'F:\PI',
            [string]$PI_EVENTQUEUEDIR = 'H:\PI\queue',
            [string]$PI_ARCHIVEDATDIR = 'G:\PI\arc',
            [string]$PI_FUTUREARCHIVEDATDIR = 'G:\PI\arc\future',
            [string]$PI_ARCHIVESIZE = '256' #in MB
        )

        Import-DscResource -ModuleName PSDesiredStateConfiguration
        Import-DscResource -ModuleName xStorage -ModuleVersion 3.4.0.0
        Import-DscResource -ModuleName xNetworking -ModuleVersion 5.7.0.0
        Import-DscResource -ModuleName xPendingReboot -ModuleVersion 0.4.0.0
        Import-DscResource -ModuleName PSDSSupportPIDA
        Import-DscResource -ModuleName xActiveDirectory -ModuleVersion 3.0.0.0
        Import-DscResource -ModuleName xWindowsUpdate


        Node $env:COMPUTERNAME {

            #region ### 1. VM PREPARATION ### 
            # 1A. Check for new volumes. The uninitialized disk number may vary depending on EC2 type (i.e. temp disk or no temp disk). This logic will test to find the disk number of an uninitialized disk.
            $disks = Get-Disk | Where-Object 'partitionstyle' -eq 'raw' | Sort-Object number
            if ($disks) {
                # Elastic Block Storage for Binary Files
                xWaitforDisk Volume_F {
                    DiskID           = $disks[0].number
                    retryIntervalSec = 30
                    retryCount       = 20
                }
                xDisk Volume_F {
                    DiskID      = $disks[0].number
                    DriveLetter = 'F'
                    FSFormat    = 'NTFS'
                    FSLabel     = 'Apps'
                    DependsOn   = '[xWaitforDisk]Volume_F'
                }

                # Elastic Block Storage for Archive Files
                xWaitforDisk Volume_G {
                    DiskID           = $disks[1].number
                    retryIntervalSec = 30
                    retryCount       = 20
                }
                xDisk Volume_G {
                    DiskID      = $disks[1].number
                    DriveLetter = 'G'
                    FSFormat    = 'NTFS'
                    FSLabel     = 'Archives'
                    DependsOn   = '[xWaitforDisk]Volume_G'
                }

                # Elastic Block Storage for Queue Files
                xWaitforDisk Volume_H {
                    DiskID           = $disks[2].number
                    retryIntervalSec = 30
                    retryCount       = 20
                }
                xDisk Volume_H {
                    DiskID      = $disks[2].number
                    DriveLetter = 'H'
                    FSFormat    = 'NTFS'
                    FSLabel     = 'Events'
                    DependsOn   = '[xWaitforDisk]Volume_H'
                }

                # Elastic Block Storage for Backup Files
                xWaitforDisk Volume_I {
                    DiskID           = $disks[3].number
                    retryIntervalSec = 30
                    retryCount       = 20
                }
                xDisk Volume_I {
                    DiskID      = $disks[3].number
                    DriveLetter = 'I'
                    FSFormat    = 'NTFS'
                    FSLabel     = 'Backups'
                    DependsOn   = '[xWaitforDisk]Volume_I'
                }
            }

            # 1B. Create Rule to open PI Net Manager Port
            xFirewall PINetManagerFirewallRule {
                Direction   = 'Inbound'
                Name        = 'PI-System-PI-Net-Manager-TCP-In'
                DisplayName = 'PI System PI Net Manager (TCP-In)'
                Description = 'Inbound rule for PI Data Archive to allow TCP traffic for access to the PI Server'
                Group       = 'PI Systems'
                Enabled     = 'True'
                Action      = 'Allow'
                Protocol    = 'TCP'
                LocalPort   = '5450'
                Ensure      = 'Present'
            }

            # 1C. Enable rules to allow Connection to Secondary when executing the CollectiveManager.ps1 script to form PI Data Archvie Collective.
            # The absence of this rule on the Secondary results in exception thrown during the use of get-WmiObject within CollectiveManager.ps1 script.
            # File Share SMB rule is for allowing archive and data file transer from Primary to Secondary.
            # For increased security, disable after Collective formation..
            xFirewall WindowsManagementInstrumentationDCOMIn {
                Name    = 'WMI-RPCSS-In-TCP'
                Enabled = 'True'
                Action  = 'Allow'
                Ensure  = 'Present'
            }

            xFirewall WindowsManagementInstrumentationWMIIn {
                Name    = 'WMI-WINMGMT-In-TCP'
                Enabled = 'True'
                Action  = 'Allow'
                Ensure  = 'Present'
            }

            xFirewall FileAndPrinterSharingSMBIn {
                Name    = 'FPS-SMB-In-TCP'
                Enabled = 'True'
                Action  = 'Allow'
                Ensure  = 'Present'
            }
            #endregion ### 1. VM PREPARATION ###

            #region ### 2. INSTALL AND SETUP ###

            #2A. Install .NET Framework 4.8
            xHotFix NETFramework {
                Path = 'C:\media\NETFramework\windows10.0-kb4486129.msu'
                Id = 'KB4486129'
                Ensure = 'Present'
            }
            
            # 2B. Initiate any outstanding reboots.
            xPendingReboot RebootNETFramework {
                Name      = 'PostPIInstall'
                DependsOn = '[xHotFix]NETFramework'
            }

            #2C. Install PI Data Archive with Client Tools
            Package PISystem {
                Name                 = 'PI Server 2018 Installer'
                Path                 = 'C:\media\PIServer\PIServerInstaller.exe'
                ProductId            = $SetupKitsS3PIProductID
                Arguments            = "/silent ADDLOCAL=PIDataArchive,PITotal,FD_AFExplorer,FD_AFDocs,PiPowerShell,pismt3 PIHOME=""$PIHOME"" PIHOME64=""$PIHOME64"" SENDTELEMETRY=""0"" AFACKNOWLEDGEBACKUP=""1"" PI_INSTALLDIR=""$PI_INSTALLDIR"" PI_EVENTQUEUEDIR=""$PI_EVENTQUEUEDIR"" PI_ARCHIVEDATDIR=""$PI_ARCHIVEDATDIR"" PI_FUTUREARCHIVEDATDIR=""$PI_FUTUREARCHIVEDATDIR"" PI_ARCHIVESIZE=""$PI_ARCHIVESIZE"""
                Ensure               = 'Present'
                LogPath              = "$env:ProgramData\PIServer_install.log"
                PsDscRunAsCredential = $domainCredential # Admin creds due to limitations extracting install under SYSTEM account.
                ReturnCode           = 0, 3010, 1641
                DependsOn           = '[xHotFix]NETFramework', '[xPendingReboot]RebootNETFramework'
            }

            
            # 2D. Initiate any outstanding reboots.
            xPendingReboot RebootPISystem {
                Name      = 'PostPIInstall'
                DependsOn = '[Package]PISystem'
            }
            #endregion ### 2. INSTALL AND SETUP ###


            #region ### 3. IMPLEMENT OSISOFT FIELD SERVICE TECHNICAL STANDARDS ###

            #3. i - OPTIONAL - Create Corresponding AD Groups for the Basic Windows Integrated Security Roles. Relevant Service Accounts to map through these groups.
            # Aggregate Security Group parameters in to a single array.

            # Used for PI Data Archive Security setting of AD users and group.
            WindowsFeature ADPS {
                Name   = 'RSAT-AD-PowerShell'
                Ensure = 'Present'
            }

            $PISecurityGroups = @(
                @{Name = $PIBuffersADGroup; Description = 'Identity for PI Buffer Subsystem and PI Buffer Server'; },
                @{Name = $PIInterfacesADGroup; Description = 'Identity for PI Interfaces'; },
                @{Name = $PIUsersADGroup; Description = 'Identity for the Read-only users'; },
                @{Name = $PIPointsAnalysisCreatorADGroup; Description = 'Identity for PIACEService, PIAFService and users that can create and edit PI Points'; }
                @{Name = $PIWebAppsADGroup; Description = 'Identity for PI Vision, PI WebAPI, and PI WebAPI Crawler'; },
                @{Name = $PIConnectorRelaysADGroup; Description = 'Identity for PI Connector Relays'; },
                @{Name = $PIDataCollectionManagersADGroup; Description = 'Identity for PI Data Collection Managers'; }
            )
            # If $EnableAdGroupCreation set to $true, enumerate the PISecurityGroups array and create PI Security Groups in AD.
            if ($EnableAdGroupCreation) {
                ForEach ($Group in $PISecurityGroups) {
                    xADGroup "CreatePIAdGroup_$($Group.Name)" {
                        GroupName        = $Group.Name
                        GroupScope       = 'Global'
                        Category         = 'Security'
                        Ensure           = 'Present'
                        Description      = $Group.Description
                        DomainController = $PrimaryDomainController
                        Credential       = $domainCredential
                        DependsOn        = '[Package]PISystem', '[WindowsFeature]ADPS'
                    }
                }

                ## OPTIONAL: To simplify remote access for DeploySample scenario, mapping 'Domain Admins' security group as PIAdmins. (NOT recommended for production.)
                xADGroup AddDomainAdminsToPIAdmins {
                    GroupName        = $PIAdministratorsADGroup
                    GroupScope       = 'Global'
                    Category         = 'Security'
                    Ensure           = 'Present'
                    Description      = "Members have PI Administrators rights to PI Data Archive $PIDataArchivePrimary"
                    DomainController = $PrimaryDomainController
                    Credential       = $domainCredential
                    MembersToInclude = 'Domain Admins'
                    DependsOn        = '[Package]PISystem', '[WindowsFeature]ADPS'
                }
            }

            # 3A. Create identities for basic WIS roles
            $BasicWISRoles = @(
                @{Name = 'PI Buffers'; Description = 'Identity for PI Buffer Subsystem and PI Buffer Server'; },
                @{Name = 'PI Interfaces'; Description = 'Identity for PI Interfaces'; },
                @{Name = 'PI Users'; Description = 'Identity for the Read-only users'; },
                @{Name = 'PI Points&Analysis Creator'; Description = 'Identity for PIACEService, PIAFService and users that can create and edit PI Points'; }
                @{Name = 'PI Web Apps'; Description = 'Identity for PI Vision, PI WebAPI, and PI WebAPI Crawler'; },
                @{Name = 'PI Connector Relays'; Description = 'Identity for PI Connector Relays'; },
                @{Name = 'PI Data Collection Managers'; Description = 'Identity for PI Data Collection Managers'; }
            )
            Foreach ($BasicWISRole in $BasicWISRoles) {
                PIIdentity "SetBasicWISRole_$($BasicWISRole.Name)" {
                    Name               = $BasicWISRole.Name
                    Description        = $BasicWISRole.Description
                    IsEnabled          = $true
                    CanDelete          = $false
                    AllowUseInMappings = $true
                    AllowUseInTrusts   = $true
                    Ensure             = "Present"
                    PIDataArchive      = $env:COMPUTERNAME
                    DependsOn          = '[Package]PISystem'
                    PsDscRunAsCredential = $domainCredential
                }
            }

            # 3B. i - Remove default identities
            $DefaultPIIdentities = @(
                'PIOperators',
                'PISupervisors',
                'PIEngineers',
                'pidemo'
            )
            Foreach ($DefaultPIIdentity in $DefaultPIIdentities) {
                PIIdentity "DisableDefaultIdentity_$DefaultPIIdentity" {
                    Name          = $DefaultPIIdentity
                    Ensure        = "Absent"
                    PIDataArchive = $env:COMPUTERNAME
                    DependsOn     = '[Package]PISystem'
                    PsDscRunAsCredential = $domainCredential
                }
            }

            # 3B ii - Disable default identities
            $DefaultPIIdentities = @(
                'PIWorld',
                'piusers'
            )
            Foreach ($DefaultPIIdentity in $DefaultPIIdentities) {
                PIIdentity "DisableDefaultIdentity_$DefaultPIIdentity" {
                    Name             = $DefaultPIIdentity
                    IsEnabled        = $false
                    AllowUseInTrusts = $false
                    Ensure           = "Present"
                    PIDataArchive    = $env:COMPUTERNAME
                    DependsOn        = '[Package]PISystem'
                    PsDscRunAsCredential = $domainCredential
                }
            }

            # 3C. Set PI Mappings
            $DesiredMappings = @(
                @{Name = 'BUILTIN\Administrators'; Identity = 'piadmins'}, ## OPTIONAL - Stronger security posture would exclude this mapping. Added here to simplify access for demo purposes. 
                @{Name = $($DomainNetBiosName + '\' + $PIAdministratorsADGroup); Identity = 'piadmins'},
                @{Name = $($DomainNetBiosName + '\' + $PIBuffersADGroup); Identity = 'PI Buffers'},
                @{Name = $($DomainNetBiosName + '\' + $PIInterfacesADGroup); Identity = 'PI Interfaces'},
                @{Name = $($DomainNetBiosName + '\' + $PIPointsAnalysisCreatorADGroup); Identity = 'PI Points&Analysis Creator'},
                @{Name = $($DomainNetBiosName + '\' + $PIUsersADGroup); Identity = 'PI Users'},
                @{Name = $($DomainNetBiosName + '\' + $PIWebAppsADGroup); Identity = 'PI Web Apps'},
                @{Name = $($DomainNetBiosName + '\' + $PIConnectorRelaysADGroup); Identity = 'PI Connector Relays'},
                @{Name = $($DomainNetBiosName + '\' + $PIDataCollectionManagersADGroup); Identity = 'PI Data Collection Managers'}
            )
            Foreach ($DesiredMapping in $DesiredMappings) {
                if ($null -ne $DesiredMapping.Name -and '' -ne $DesiredMapping.Name) {
                    PIMapping "SetMapping_$($DesiredMapping.Name)" {
                        Name          = $DesiredMapping.Name
                        PrincipalName = $DesiredMapping.Name
                        Identity      = $DesiredMapping.Identity
                        Enabled       = $true
                        Ensure        = "Present"
                        PIDataArchive = $env:COMPUTERNAME
                        DependsOn     = '[Package]PISystem'
                        PsDscRunAsCredential = $domainCredential
                    }
                }
            }

            # 3D. Set PI Database Security Rules
            $DatabaseSecurityRules = @(
                # PIAFLINK can only be updated if the PIAFLINK service has been configured and running.
                # @{Name = 'PIAFLINK';            Security = 'piadmins: A(r,w)'},
                @{Name = 'PIARCADMIN'; Security = 'piadmins: A(r,w)'},
                @{Name = 'PIARCDATA'; Security = 'piadmins: A(r,w)'},
                @{Name = 'PIAUDIT'; Security = 'piadmins: A(r,w)'},
                @{Name = 'PIBACKUP'; Security = 'piadmins: A(r,w)'},
                @{Name = 'PIBatch'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Users: A(r)'},
                # PIBACTHLEGACY applies to the old batch subsystem which predates the PI Batch Database.Unless the pibatch service is running, and there is a need to keep it running, this entry can be safely ignored.
                # @{Name='PIBATCHLEGACY';       Security='piadmins: A(r,w) | PIWorld: A(r) | PI Users: A(r)'},
                @{Name = 'PICampaign'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Users: A(r)'},
                @{Name = 'PIDBSEC'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Data Collection Managers: A(r) | PI Users: A(r) | PI Web Apps: A(r)'},
                @{Name = 'PIDS'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Connector Relays: A(r,w) | PI Data Collection Managers: A(r) | PI Users: A(r) | PI Points&Analysis Creator: A(r,w)'},
                @{Name = 'PIHeadingSets'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Users: A(r)'},
                @{Name = 'PIMAPPING'; Security = 'piadmins: A(r,w) | PI Web Apps: A(r)'},
                @{Name = 'PIModules'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Users: A(r)'},
                @{Name = 'PIMSGSS'; Security = 'piadmins: A(r,w) | PIWorld: A(r,w) | PI Users: A(r,w)'},
                @{Name = 'PIPOINT'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Connector Relays: A(r,w) | PI Data Collection Managers: A(r) | PI Users: A(r) | PI Interfaces: A(r) | PI Buffers: A(r,w) | PI Points&Analysis Creator: A(r,w) | PI Web Apps: A(r)'},
                @{Name = 'PIReplication'; Security = 'piadmins: A(r,w) | PI Data Collection Managers: A(r)'},
                @{Name = 'PITransferRecords'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Users: A(r)'},
                @{Name = 'PITRUST'; Security = 'piadmins: A(r,w)'},
                @{Name = 'PITUNING'; Security = 'piadmins: A(r,w)'},
                @{Name = 'PIUSER'; Security = 'piadmins: A(r,w) | PIWorld: A(r) | PI Connector Relays: A(r) | PI Data Collection Managers: A(r) | PI Users: A(r) | PI Web Apps: A(r)'}
            )
            Foreach ($DatabaseSecurityRule in $DatabaseSecurityRules) {
                PIDatabaseSecurity "SetDatabaseSecurity_$($DatabaseSecurityRule.Name)" {
                    Name          = $DatabaseSecurityRule.Name
                    Security      = $DatabaseSecurityRule.Security
                    Ensure        = "Present"
                    PIDataArchive = $env:COMPUTERNAME
                    DependsOn     = '[Package]PISystem'
                }
            }

            # 3E. Restrict use of the piadmin superuser. IMPORTANT NOTE - This change must occur last. Initial connection is via loop back trust. This gets disabled when this change occurs.
            PIIdentity Restrict_piadmin {
                Name                 = "piadmin"
                AllowUseInTrusts     = $true  ## NOTE - This is so local services (random and rampsoak specifically) can still operate. This is used by the loopback trust.
                AllowUseInMappings   = $false
                Ensure               = "Present"
                PIDataArchive        = $env:COMPUTERNAME
                PsDscRunAsCredential = $domainCredential
                DependsOn            = '[Package]PISystem'
            }#
            #endregion ### 3. IMPLEMENT OSISOFT FIELD SERVICE TECHNICAL STANDARDS ###


            #region ### 4. BACKUP CONFIGURATION ###
            # 4-A. Setup PI Server local backup scheduled task.
            Script PIBackupTask {
                GetScript            = {
                    $task = (Get-ScheduledTask).TaskName | Where-Object {$_ -eq 'PI Server Backup'}
                    Result = "$task"
                }

                TestScript           = {
                    $task = (Get-ScheduledTask).TaskName | Where-Object {$_ -eq 'PI Server Backup'}
                    if ($task) {
                        Write-Verbose -Message "'PI Server Backup' scheduled task already present. Skipping task install."
                        return $true
                    }
                    else {
                        Write-Verbose -Message "'PI Server Backup' scheduled task not found."
                        return $false
                    }
                }

                SetScript            = {
                    Write-Verbose -Message "Creating 'PI Server Backup' scheduled task. Check C:\PIBackupTaskErrors.txt and C:\PIBackupTaskOutput.txt for details."
                    $result = Start-Process -NoNewWindow -FilePath "$env:PISERVER\adm\pibackuptask.bat" -WorkingDirectory "$env:PISERVER\adm"  -ArgumentList "I:\PIBackups -install" -Wait -PassThru -RedirectStandardError 'C:\PIBackupTaskErrors.txt' -RedirectStandardOutput 'C:\PIBackupTaskOutput.txt'
                    $exitCode = $result.ExitCode.ToString()
                    Write-Verbose -Message "Exit code: $exitCode"
                }
                PsDscRunAsCredential = $domainCredential
                DependsOn            = '[Package]PISystem'
            }
            #endregion ### 4. BACKUP CONFIGURATION ###

            #region ### 4B. Set firewall rules ###
			Script SetNetFirewallRule {
                GetScript = {
                    return @{
                        Value = 'SetNetFirewallRule'
                    }
                }

                # Forces SetScript execution everytime
                TestScript = {
                    return $false
                }

                SetScript = {
                    Try {
						# Enable remote service management for COTS
						Set-NetFirewallRule -DisplayGroup "Remote Service Management" -Enabled True
						Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -Enabled True
                    }
                    Catch {
                        $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus -ErrorAction SilentlyContinue
                        if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}  # Check for source to avoid throwing exception if already present.

                        Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
                    }
                }
				PsDscRunAsCredential = $domainCredential
                DependsOn  = '[Package]PISystem'
            }
            #endregion ### 4B. Set firewall rules ###

            #region ### 5. CREATE PI DATA ARCHIVE COLLECTIVE ###
            if($DeployHA -eq 'true'){
                Script CreatePICollective {

                    GetScript            = {@(Value = 'CreatePIDataArchiveCollective')}
                    TestScript           = {
                        Write-Verbose -Message "Checking whether PI Data Archive ""$using:PIDataArchivePrimary"" is a Collective." -Verbose

                        # Generate credential used to connect to PI Data Archive.
                        $securePassword = ConvertTo-SecureString $using:DomainAdminPassword -AsPlainText -Force
                        $DomainPIAdminCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$using:DomainNetBiosName\$using:DomainAdminUserName", $securePassword)
                        $connection = Connect-PIDataArchive -PIDataArchiveMachineName $using:PIDataArchivePrimary -WindowsCredential $DomainPIAdminCredential -Port 5450 -AuthenticationMethod Windows -Verbose
                        $pidaType = $connection.CurrentRole.Type.ToString()


                        Write-Verbose -Message "PIDA Primary: $($env:COMPUTERNAME -eq $using:PIDataArchivePrimary)" -Verbose
                        Write-Verbose -Message "PIDA Type   : $pidaType" -Verbose

                        if (($env:COMPUTERNAME -eq $using:PIDataArchivePrimary) -and ($pidaType -eq 'Unspecified')) {
                            Write-Verbose -Message "PI Data Archive ""$using:PIDataArchivePrimary"" is not Collective. Will run CollectiveManager script." -Verbose
                            return $false  # Machine is Primary DA and not a Collective
                        }
                        else {

                            Write-Verbose -Message "PI Data Archive ""$using:PIDataArchivePrimary"" is either a Collective or not the primary. Skipping CollectiveManager script." -Verbose
                            return $true   # Any other case fails logic, and therefore returns true to our test and does not xecute a SetScript.
                        }
                    }
                    SetScript            = {

                        Try {
                            # Invoke CollectiveManger.ps1 script using PI Administrator credential.
                            $params = ".\CollectiveManager.ps1 -Create -PICollectiveName ""$using:PIDataArchivePrimary"" -PIPrimaryName ""$using:PIDataArchivePrimary"" -PISecondaryNames ""$using:PIDataArchiveSecondary"" -NumberOfArchivesToBackup 10 -BackupLocationOnPrimary 'I:\PIBackups'"

                            # Generate credential used to connect to PI Data Archive.
                            $securePassword = ConvertTo-SecureString $using:DomainAdminPassword -AsPlainText -Force
                            $DomainPIAdminCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$using:DomainNetBiosName\$using:DomainAdminUserName", $securePassword)

                            Write-Verbose -Message "Starting PI Data Archive Collection creation script..." -Verbose
                            $result = Start-Process -FilePath powershell.exe -Credential $DomainPIAdminCredential -WorkingDirectory C:\media\PIDA\ -Wait -PassThru -ArgumentList $params -Verbose -ErrorAction Stop -RedirectStandardOutput "C:\media\PIDA\CreatePIDACollective.log" -RedirectStandardError "C:\media\PIDA\CreatePIDACollectiveErrors.log"
                            $exitCode = $result.ExitCode.ToString()
                            Write-Verbose -Message "PI Data Archive Collection creation complete." -Verbose
                            Write-Verbose -Message "Script exit code: $exitCode." -Verbose
                        }

                        Catch {
                            Write-Error $_
                            throw 'Unable to create PI Data Archive Collective. See error for details.'
                        }
                    }
                    PsDscRunAsCredential = $domainCredential
                }
            }
            #endregion ### 5. CREATE PI DATA ARCHIVE COLLECTIVE  ###


            #region ### 6. SIGNAL WAITCONDITION ###
            # Writes output to the AWS CloudFormation Init Wait Handle (Indicating script completed)
            # To ensure it triggers only at the end of the script, set DependsOn to include all resources.
            Script Write-AWSQuickStartStatus {
                GetScript  = {@( Value = 'WriteAWSQuickStartStatus' )}
                TestScript = {$false}
                SetScript  = {

                    # Ping WaitHandle to increment Count and indicate DSC has completed.
                    # Note: Manually passing a unique ID (used DSC Configuation ane 'pida0config') to register as a unique signal. See Ref for details.
                    # Ref: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-signal.html
                    Write-Verbose "Getting Handle" -Verbose
                    $handle = Get-AWSQuickStartWaitHandle -ErrorAction SilentlyContinue
                    Invoke-Expression "cfn-signal.exe -e 0 -i 'pida0config' '$handle'"

                    # Write to Application Log to record status update.
                    $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus -ErrorAction SilentlyContinue
                    if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}  # Check for source to avoid throwing exception if already present.
                    Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message "Write-AWSQuickStartStatus function was triggered."
                }
                DependsOn  = '[Package]PISystem', '[xPendingReboot]RebootPISystem', '[Script]PIBackupTask'
            }
            #endregion ### 6. SIGNAL WAITCONDITION ###
        }
    }

    # Compile and Execute Configuration
    PIDA0Config -ConfigurationData $ConfigurationData
    Start-DscConfiguration -Path .\PIDA0Config -Wait -Verbose -Force -ErrorVariable ev
}

catch {
    # If any expectations are thrown, output to CloudFormation Init.
    $_ | Write-AWSQuickStartException
}
# SIG # Begin signature block
# MIIbywYJKoZIhvcNAQcCoIIbvDCCG7gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDKCnb+P1fdoLXC
# U/3O5yFLhr0FqAZMrIhHCmT9c+crTqCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
# ZnVTQ7VvlVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBa
# Fw0yODEwMjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lD
# ZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/l
# qJ3bMtdx6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fT
# eyOU5JEjlpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqH
# CN8M9eJNYBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+
# bMt+dDk2DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLo
# LFH3c7y9hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIB
# yTASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHow
# eDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwA
# AgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAK
# BghghkgBhv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0j
# BBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7s
# DVoks/Mi0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGS
# dQ9RtG6ljlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6
# r7VRwo0kriTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo
# +MUSaJ/PQMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qz
# sIzV6Q3d9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHq
# aGxEMrJmoecYpJpkUe8wggVWMIIEPqADAgECAhAFTTVZN0yftPMcszD508Q/MA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcNMTkwNjE3MDAwMDAw
# WhcNMjAwNzAxMTIwMDAwWjCBkjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRQw
# EgYDVQQHEwtTYW4gTGVhbmRybzEVMBMGA1UEChMMT1NJc29mdCwgTExDMQwwCgYD
# VQQLEwNEZXYxFTATBgNVBAMTDE9TSXNvZnQsIExMQzEkMCIGCSqGSIb3DQEJARYV
# c21hbmFnZXJzQG9zaXNvZnQuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
# CgKCAQEAqbP+VTz8qtsq4SWhF7LsXqeDGyUwtDpf0vlSg+aQh2fOqJhW2uiPa1GO
# M5+xbr+RhTTWzJX2vEwqSIzN43ktTdgcVT9Bf5W2md+RCYE1D17jGlj5sCFTS4eX
# Htm+lFoQF0donavbA+7+ggd577FdgOnjuYxEpZe2lbUyWcKOHrLQr6Mk/bKjcYSY
# B/ipNK4hvXKTLEsN7k5kyzRkq77PaqbVAQRgnQiv/Lav5xWXuOn7M94TNX4+1Mk8
# 74nuny62KLcMRtjPCc2aWBpHmhD3wPcUVvTW+lGwEaT0DrCwcZDuG/Igkhqj/8Rf
# HYfnZQtWMnBFAHcuA4jJgmZ7xYMPoQIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAU
# WsS5eyoKo6XqcQPAYPkt9mV1DlgwHQYDVR0OBBYEFNcTKM3o/Fjj9J3iOakcmKx6
# CPetMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8E
# cDBuMDWgM6Axhi9odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVk
# LWNzLWcxLmNybDA1oDOgMYYvaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTIt
# YXNzdXJlZC1jcy1nMS5jcmwwTAYDVR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggr
# BgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEw
# gYQGCCsGAQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/
# BAIwADANBgkqhkiG9w0BAQsFAAOCAQEAigLIcsGUWzXlZuVQY8s1UOxYgch5qO1Y
# YEDFF8abzJQ4RiB8rcdoRWjsfpWxtGOS0wkA2CfyuWhjO/XqgmYJ8AUHIKKCy6QE
# 31/I6izI6iDCg8X5lSR6nKsB2BCZCOnGJOEi3r+WDS18PMuW24kaBo1ezx6KQOx4
# N0qSrMJqJRXfPHpl3WpcLs3VA1Gew9ATOQ9IXbt8QCvyMICRJxq4heHXPLE3EpK8
# 2wlBKwX3P4phapmEUOWxB45QOcRJqgahe9qIALbLS+i5lxV+eX/87YuEiyDtGfH+
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEJMwghCP
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggZ4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPRD6tJCvNo9
# 4sODfl/QQi8odaBWnUIh3CI09txBNEdMMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQAV
# 8tf27ZaStNqo384SUJuIiOY/VtdJH6IG7ajL+bUAkP6sIHQVh1wTKjo8JUSo7NBH
# 5Rf6x3pKnxRhkWjIaG4/M2wcP9nuUbQYj+IibBUNIn0BKUikeg56uNef2wV8Ogh3
# G9b9XVKYWhlNPrCXXWx4u1pOCijIy7WiVwMN1YZGQ/naylVqkZJZy5itPLMTuLU5
# KMBmA6TJCgEYeBOlsQcxmz4VGfMH1YLF2Stj2zu7oTsVWR0BRnyzqEF7RepU/j29
# ukWrkD2T2IVOFr3jPN5SAY/ScUxoRuLaWLCIBws6QyyQBDPAyS1+YHpIw/o7t7ml
# foz5YCUo7sP36bUDy87CoYIOPDCCDjgGCisGAQQBgjcDAwExgg4oMIIOJAYJKoZI
# hvcNAQcCoIIOFTCCDhECAQMxDTALBglghkgBZQMEAgEwggEOBgsqhkiG9w0BCRAB
# BKCB/gSB+zCB+AIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgZv4v
# vuZTBvd0DjbpNefzEmR9lkzjlmCK1fogHvucEPICFH5KvZS7ZA0GSiTZnMNn+bry
# 2QlhGA8yMDIwMDEyMzIwMjAyM1owAwIBHqCBhqSBgzCBgDELMAkGA1UEBhMCVVMx
# HTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRl
# YyBUcnVzdCBOZXR3b3JrMTEwLwYDVQQDEyhTeW1hbnRlYyBTSEEyNTYgVGltZVN0
# YW1waW5nIFNpZ25lciAtIEczoIIKizCCBTgwggQgoAMCAQICEHsFsdRJaFFE98mJ
# 0pwZnRIwDQYJKoZIhvcNAQELBQAwgb0xCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5W
# ZXJpU2lnbiwgSW5jLjEfMB0GA1UECxMWVmVyaVNpZ24gVHJ1c3QgTmV0d29yazE6
# MDgGA1UECxMxKGMpIDIwMDggVmVyaVNpZ24sIEluYy4gLSBGb3IgYXV0aG9yaXpl
# ZCB1c2Ugb25seTE4MDYGA1UEAxMvVmVyaVNpZ24gVW5pdmVyc2FsIFJvb3QgQ2Vy
# dGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTYwMTEyMDAwMDAwWhcNMzEwMTExMjM1
# OTU5WjB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRp
# b24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxKDAmBgNVBAMTH1N5
# bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQC7WZ1ZVU+djHJdGoGi61XzsAGtPHGsMo8Fa4aaJwAyl2pN
# yWQUSym7wtkpuS7sY7Phzz8LVpD4Yht+66YH4t5/Xm1AONSRBudBfHkcy8utG7/Y
# lZHz8O5s+K2WOS5/wSe4eDnFhKXt7a+Hjs6Nx23q0pi1Oh8eOZ3D9Jqo9IThxNF8
# ccYGKbQ/5IMNJsN7CD5N+Qq3M0n/yjvU9bKbS+GImRr1wOkzFNbfx4Dbke7+vJJX
# cnf0zajM/gn1kze+lYhqxdz0sUvUzugJkV+1hHk1inisGTKPI8EyQRtZDqk+scz5
# 1ivvt9jk1R1tETqS9pPJnONI7rtTDtQ2l4Z4xaE3AgMBAAGjggF3MIIBczAOBgNV
# HQ8BAf8EBAMCAQYwEgYDVR0TAQH/BAgwBgEB/wIBADBmBgNVHSAEXzBdMFsGC2CG
# SAGG+EUBBxcDMEwwIwYIKwYBBQUHAgEWF2h0dHBzOi8vZC5zeW1jYi5jb20vY3Bz
# MCUGCCsGAQUFBwICMBkaF2h0dHBzOi8vZC5zeW1jYi5jb20vcnBhMC4GCCsGAQUF
# BwEBBCIwIDAeBggrBgEFBQcwAYYSaHR0cDovL3Muc3ltY2QuY29tMDYGA1UdHwQv
# MC0wK6ApoCeGJWh0dHA6Ly9zLnN5bWNiLmNvbS91bml2ZXJzYWwtcm9vdC5jcmww
# EwYDVR0lBAwwCgYIKwYBBQUHAwgwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRp
# bWVTdGFtcC0yMDQ4LTMwHQYDVR0OBBYEFK9j1sqjToVy4Ke8QfMpojh/gHViMB8G
# A1UdIwQYMBaAFLZ3+mlIR59TEtXC6gcydgfRlwcZMA0GCSqGSIb3DQEBCwUAA4IB
# AQB16rAt1TQZXDJF/g7h1E+meMFv1+rd3E/zociBiPenjxXmQCmt5l30otlWZIRx
# MCrdHmEXZiBWBpgZjV1x8viXvAn9HJFHyeLojQP7zJAv1gpsTjPs1rSTyEyQY0g5
# QCHE3dZuiZg8tZiX6KkGtwnJj1NXQZAv4R5NTtzKEHhsQm7wtsX4YVxS9U72a433
# Snq+8839A9fZ9gOoD+NT9wp17MZ1LqpmhQSZt/gGV+HGDvbor9rsmxgfqrnjOgC/
# zoqUywHbnsc4uw9Sq9HjlANgCk2g/idtFDL8P5dA4b+ZidvkORS92uTTw+orWrOV
# WFUEfcea7CMDjYUq0v+uqWGBMIIFSzCCBDOgAwIBAgIQe9Tlr7rMBz+hASMEIkFN
# EjANBgkqhkiG9w0BAQsFADB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50
# ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsx
# KDAmBgNVBAMTH1N5bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMTcx
# MjIzMDAwMDAwWhcNMjkwMzIyMjM1OTU5WjCBgDELMAkGA1UEBhMCVVMxHTAbBgNV
# BAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVz
# dCBOZXR3b3JrMTEwLwYDVQQDEyhTeW1hbnRlYyBTSEEyNTYgVGltZVN0YW1waW5n
# IFNpZ25lciAtIEczMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArw6K
# qvjcv2l7VBdxRwm9jTyB+HQVd2eQnP3eTgKeS3b25TY+ZdUkIG0w+d0dg+k/J0oz
# Tm0WiuSNQI0iqr6nCxvSB7Y8tRokKPgbclE9yAmIJgg6+fpDI3VHcAyzX1uPCB1y
# SFdlTa8CPED39N0yOJM/5Sym81kjy4DeE035EMmqChhsVWFX0fECLMS1q/JsI9Kf
# DQ8ZbK2FYmn9ToXBilIxq1vYyXRS41dsIr9Vf2/KBqs/SrcidmXs7DbylpWBJiz9
# u5iqATjTryVAmwlT8ClXhVhe6oVIQSGH5d600yaye0BTWHmOUjEGTZQDRcTOPAPs
# twDyOiLFtG/l77CKmwIDAQABo4IBxzCCAcMwDAYDVR0TAQH/BAIwADBmBgNVHSAE
# XzBdMFsGC2CGSAGG+EUBBxcDMEwwIwYIKwYBBQUHAgEWF2h0dHBzOi8vZC5zeW1j
# Yi5jb20vY3BzMCUGCCsGAQUFBwICMBkaF2h0dHBzOi8vZC5zeW1jYi5jb20vcnBh
# MEAGA1UdHwQ5MDcwNaAzoDGGL2h0dHA6Ly90cy1jcmwud3Muc3ltYW50ZWMuY29t
# L3NoYTI1Ni10c3MtY2EuY3JsMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1Ud
# DwEB/wQEAwIHgDB3BggrBgEFBQcBAQRrMGkwKgYIKwYBBQUHMAGGHmh0dHA6Ly90
# cy1vY3NwLndzLnN5bWFudGVjLmNvbTA7BggrBgEFBQcwAoYvaHR0cDovL3RzLWFp
# YS53cy5zeW1hbnRlYy5jb20vc2hhMjU2LXRzcy1jYS5jZXIwKAYDVR0RBCEwH6Qd
# MBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0yMDQ4LTYwHQYDVR0OBBYEFKUTAamfhcwb
# bhYeXzsxqnk2AHsdMB8GA1UdIwQYMBaAFK9j1sqjToVy4Ke8QfMpojh/gHViMA0G
# CSqGSIb3DQEBCwUAA4IBAQBGnq/wuKJfoplIz6gnSyHNsrmmcnBjL+NVKXs5Rk7n
# fmUGWIu8V4qSDQjYELo2JPoKe/s702K/SpQV5oLbilRt/yj+Z89xP+YzCdmiWRD0
# Hkr+Zcze1GvjUil1AEorpczLm+ipTfe0F1mSQcO3P4bm9sB/RDxGXBda46Q71Wkm
# 1SF94YBnfmKst04uFZrlnCOvWxHqcalB+Q15OKmhDc+0sdo+mnrHIsV0zd9HCYbE
# /JElshuW6YUI6N3qdGBuYKVWeg3IRFjc5vlIFJ7lv94AvXexmBRyFCTfxxEsHwA/
# w0sUxmcczB4Go5BfXFSLPuMzW4IPxbeGAk5xn+lmRT92MYICWjCCAlYCAQEwgYsw
# dzELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8w
# HQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3JrMSgwJgYDVQQDEx9TeW1hbnRl
# YyBTSEEyNTYgVGltZVN0YW1waW5nIENBAhB71OWvuswHP6EBIwQiQU0SMAsGCWCG
# SAFlAwQCAaCBpDAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcN
# AQkFMQ8XDTIwMDEyMzIwMjAyM1owLwYJKoZIhvcNAQkEMSIEIP4yJ9VcMXDXqBkC
# E/RS1xIPc8iUiE2Jp+opOZrIDipuMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMR0
# znYAfQI5Tg2l5N58FMaA+eKCATz+9lPvXbcf32H4MAsGCSqGSIb3DQEBAQSCAQBf
# 6/kpZF4ykq8u1EcW/fGvjnlms2B0xT0UIwHurGIpDrC0Alsm2ZYtDub2N2a7rDbO
# m1aCRsqJU52Cvqzksuqq2JTgBf/4NiF9rXBmzX5xhg9SFcADhxYKA57jqru/yNJA
# S4UXqxrXqIgCW5dEM31LFenrjGPG1j8Ca5ZuPDrgy5zGLySM8mMUxl9aAQV7xq4x
# VKsE12jtVw95Y45h7LftjP+hgSX/xMXMK/zO4g7SuPN4S+9ptamAt88w+nO3dKzY
# TkdPU80oaYDw6YdyE2Kai7uRHeKohS05KCrm2XLXbU65Pv8FiXjM3XAX4jOiIqz9
# X+edjMb+hypKTHDqPXL1
# SIG # End signature block
