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

    # OSIsoft Field Service Technical Standards - PI Vision.
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
                Name      = 'RebootDotNet'
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
                @{Name = $PIWebAppsADGroup; Description = 'Identity for PI Vision'; },
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
                @{Name = 'PI Web Apps'; Description = 'Identity for PI Vision'; },
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
# MIIcVwYJKoZIhvcNAQcCoIIcSDCCHEQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAIuuxuoLo0qTlf
# vjSCMfkAY1UtYDGKVqnth04jj5Z5IKCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# aGxEMrJmoecYpJpkUe8wggVVMIIEPaADAgECAhAGVvq6kseGimsYGJGsdvpbMA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcNMjAwNjE2MDAwMDAw
# WhcNMjIwNzIyMTIwMDAwWjCBkTELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRQw
# EgYDVQQHEwtTYW4gTGVhbmRybzEVMBMGA1UEChMMT1NJc29mdCwgTExDMQwwCgYD
# VQQLEwNEZXYxFTATBgNVBAMTDE9TSXNvZnQsIExMQzEjMCEGCSqGSIb3DQEJARYU
# cGRlcmVnaWxAb3Npc29mdC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQDPSOGDHDmQTrdWSTB6jfvZ3+ngv2HwU/64ZUGKq+PbyQKcqeRI5MT2Fokj
# K9yp6JoVnipZaBZdjLRj//FuqDR/pNy3VZo1xmufKICqrSS6x2AxKb9l/6mcO/MF
# E2FgG0tND/xftCQlChB91GokCyiVNkwbLleB9uM6yn73ZZkiA0Chmjguipfal+hS
# 27vds5xYGLtcnqWcKcZR5pr838vDT+8zzrxoWQ8se3H9LHYLyCiwk+84mA1M//BW
# xaA7ERt1eJ3vLzYu3+ryH+GFiYEhJHu3FZjktEg5oZ25Vj7iwgTG+/CIMZsEDe5G
# SFvePn3jpMmEaPbOPfx8FVwh8XItAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRa
# xLl7KgqjpepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQUmzSViihexjjLsHHW6j+r7Fxw
# U/gwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRw
# MG4wNaAzoDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQt
# Y3MtZzEuY3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1h
# c3N1cmVkLWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsG
# AQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCB
# hAYIKwYBBQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2Vy
# dC5jb20wTgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8E
# AjAAMA0GCSqGSIb3DQEBCwUAA4IBAQAR/2LHTPvx/fBATBS0jBBhPEhlrpNgkWZ9
# NCo0wJC5H2V2CpokuZxA4HoK0YCsz2x68BpCnBOX3pdSWC+kQOvLyJayTQew+c/R
# sebGEVp9NNtsnpcFhjM3e7hqsQAm6rCIJWk0Q1sSyYnhnqHA/iS1DxNqZ/qZHx1k
# ise1+9bOefqB1YN+vtmPBlLkboKCklbrJmHSEn4cZNBHjq1yVYOPacuws+8kAEMh
# lDjG2NkfyqF72Jo90SFK7xgjE6euLbvmjGYRSF9h4V+aR6MaEcDkUe2aoCgCmnDX
# Q+9sIKX0AojqBVLFUNQpzelOdjGWNzdcMMSu8p0pNw4xeAbuCEHfMYIRIDCCERwC
# AQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBB
# c3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQBlb6upLHhoprGBiRrHb6WzANBglg
# hkgBZQMEAgEFAKCBnjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgM1PEjJ7MtPYP
# zi/t1bSw1X9fY2BwwS9bRFJKDPMPk10wMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAHUV
# Xm4PMp56PrEkzagQaCBjXxW3LxvbU6T0NiEbDpEAKL3tU8/hy38VBOPhkAp/hxio
# F22pkRQ/cesPLQpQyIMLLUmcZHqffo7JsQhaCW5Ex8oiVSHpzAcgDslrX3uPn8sl
# LMbvmJ4JlAvAIG84x9A6FaCcGK/QQJLzOQ4Rr3yMljZ+rZwgT7BTculpAYMGAmKi
# ufrgeMgO//sd0m7k13QxHUG+/U7ctVRReCZzaaf2ON04791BrMSTE0jzWaKmR+vS
# kEHEsEYUyJPtfNu8XBoqqgdwqASa2PvbWzscG8dzQFJK4+hyltYU7p+F39d+8xdK
# Jx/NQ9Uypyq/XUUX9Wihgg7JMIIOxQYKKwYBBAGCNwMDATGCDrUwgg6xBgkqhkiG
# 9w0BBwKggg6iMIIOngIBAzEPMA0GCWCGSAFlAwQCAQUAMHgGCyqGSIb3DQEJEAEE
# oGkEZzBlAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgtoUGry+IfMfs
# CK25IR7VmncaOwgAy7u2c6ECkTry+WICEQDhBHBxlkGVHQQ02KPE5a59GA8yMDIw
# MTExMTE3MjcyOVqgggu7MIIGgjCCBWqgAwIBAgIQBM0/hWiudsYbsP5xYMynbTAN
# BgkqhkiG9w0BAQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2Vy
# dCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTE5MTAwMTAwMDAw
# MFoXDTMwMTAxNzAwMDAwMFowTDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMSQwIgYDVQQDExtUSU1FU1RBTVAtU0hBMjU2LTIwMTktMTAtMTUw
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDpZDWc+qmYZWQb5BfcuCk2
# zGcJWIVNMODJ/+U7PBEoUK8HMeJdCRjC9omMaQgEI+B3LZ0V5bjooWqO/9Su0noW
# 7/hBtR05dcHPL6esRX6UbawDAZk8Yj5+ev1FlzG0+rfZQj6nVZvfWk9YAqgyaSIT
# vouCLcaYq2ubtMnyZREMdA2y8AiWdMToskiioRSl+PrhiXBEO43v+6T0w7m9FCzr
# DCgnJYCrEEsWEmALaSKMTs3G1bJlWSHgfCwSjXAOj4rK4NPXszl3UNBCLC56zpxn
# ejh3VED/T5UEINTryM6HFAj+HYDd0OcreOq/H3DG7kIWUzZFm1MZSWKdegKblRSj
# AgMBAAGjggM4MIIDNDAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNV
# HSUBAf8EDDAKBggrBgEFBQcDCDCCAb8GA1UdIASCAbYwggGyMIIBoQYJYIZIAYb9
# bAcBMIIBkjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQ
# UzCCAWQGCCsGAQUFBwICMIIBVh6CAVIAQQBuAHkAIAB1AHMAZQAgAG8AZgAgAHQA
# aABpAHMAIABDAGUAcgB0AGkAZgBpAGMAYQB0AGUAIABjAG8AbgBzAHQAaQB0AHUA
# dABlAHMAIABhAGMAYwBlAHAAdABhAG4AYwBlACAAbwBmACAAdABoAGUAIABEAGkA
# ZwBpAEMAZQByAHQAIABDAFAALwBDAFAAUwAgAGEAbgBkACAAdABoAGUAIABSAGUA
# bAB5AGkAbgBnACAAUABhAHIAdAB5ACAAQQBnAHIAZQBlAG0AZQBuAHQAIAB3AGgA
# aQBjAGgAIABsAGkAbQBpAHQAIABsAGkAYQBiAGkAbABpAHQAeQAgAGEAbgBkACAA
# YQByAGUAIABpAG4AYwBvAHIAcABvAHIAYQB0AGUAZAAgAGgAZQByAGUAaQBuACAA
# YgB5ACAAcgBlAGYAZQByAGUAbgBjAGUALjALBglghkgBhv1sAxUwHwYDVR0jBBgw
# FoAU9LbhIB3+Ka7S5GGlsqIlssgXNW4wHQYDVR0OBBYEFFZTD8HGB6dN19huV3KA
# UEzk7J7BMHEGA1UdHwRqMGgwMqAwoC6GLGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9zaGEyLWFzc3VyZWQtdHMuY3JsMDKgMKAuhixodHRwOi8vY3JsNC5kaWdpY2Vy
# dC5jb20vc2hhMi1hc3N1cmVkLXRzLmNybDCBhQYIKwYBBQUHAQEEeTB3MCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wTwYIKwYBBQUHMAKGQ2h0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1cmVkSURU
# aW1lc3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggEBAC6DoUQFSgTjuTJS
# +tmB8Bq7+AmNI7k92JKh5kYcSi9uejxjbjcXoxq/WCOyQ5yUg045CbAs6Mfh4szt
# y3lrzt4jAUftlVSB4IB7ErGvAoapOnNq/vifwY3RIYzkKYLDigtgAAKdH0fEn7QK
# aFN/WhCm+CLm+FOSMV/YgoMtbRNCroPBEE6kJPRHnN4PInJ3XH9P6TmYK1eSRNfv
# bpPZQ8cEM2NRN1aeRwQRw6NYVCHY4o5W10k/V/wKnyNee/SUjd2dGrvfeiqm0kWm
# VQyP9kyK8pbPiUbcMbKRkKNfMzBgVfX8azCsoe3kR04znmdqKLVNwu1bl4L4y6kI
# bFMJtPcwggUxMIIEGaADAgECAhAKoSXW1jIbfkHkBdo2l8IVMA0GCSqGSIb3DQEB
# CwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQg
# SUQgUm9vdCBDQTAeFw0xNjAxMDcxMjAwMDBaFw0zMTAxMDcxMjAwMDBaMHIxCzAJ
# BgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5k
# aWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBU
# aW1lc3RhbXBpbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC9
# 0DLuS82Pf92puoKZxTlUKFe2I0rEDgdFM1EQfdD5fU1ofue2oPSNs4jkl79jIZCY
# vxO8V9PD4X4I1moUADj3Lh477sym9jJZ/l9lP+Cb6+NGRwYaVX4LJ37AovWg4N4i
# Pw7/fpX786O6Ij4YrBHk8JkDbTuFfAnT7l3ImgtU46gJcWvgzyIQD3XPcXJOCq3f
# QDpct1HhoXkUxk0kIzBdvOw8YGqsLwfM/fDqR9mIUF79Zm5WYScpiYRR5oLnRlD9
# lCosp+R1PrqYD4R/nzEU1q3V8mTLex4F0IQZchfxFwbvPc3WTe8GQv2iUypPhR3E
# HTyvz9qsEPXdrKzpVv+TAgMBAAGjggHOMIIByjAdBgNVHQ4EFgQU9LbhIB3+Ka7S
# 5GGlsqIlssgXNW4wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wEgYD
# VR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYB
# BQUHAwgweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5k
# aWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4
# oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dEFzc3VyZWRJRFJvb3RDQS5jcmwwUAYDVR0gBEkwRzA4BgpghkgBhv1sAAIEMCow
# KAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCwYJYIZI
# AYb9bAcBMA0GCSqGSIb3DQEBCwUAA4IBAQBxlRLpUYdWac3v3dp8qmN6s3jPBjdA
# hO9LhL/KzwMC/cWnww4gQiyvd/MrHwwhWiq3BTQdaq6Z+CeiZr8JqmDfdqQ6kw/4
# stHYfBli6F6CJR7Euhx7LCHi1lssFDVDBGiy23UC4HLHmNY8ZOUfSBAYX4k4YU1i
# RiSHY4yRUiyvKYnleB/WCxSlgNcSR3CzddWThZN+tpJn+1Nhiaj1a5bA9FhpDXzI
# AbG5KHW3mWOFIoxhynmUfln8jA/jb7UBJrZspe6HUSHkWGCbugwtK22ixH67xCUr
# RwIIfEmuE7bhfEJCKMYYVs9BNLZmXbZ0e/VWMyIvIjayS6JKldj1po5SMYICTTCC
# AkkCAQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZ
# MBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hB
# MiBBc3N1cmVkIElEIFRpbWVzdGFtcGluZyBDQQIQBM0/hWiudsYbsP5xYMynbTAN
# BglghkgBZQMEAgEFAKCBmDAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJ
# KoZIhvcNAQkFMQ8XDTIwMTExMTE3MjcyOVowKwYLKoZIhvcNAQkQAgwxHDAaMBgw
# FgQUAyW9UF7aljAtwi9PoB5MKL4oNMUwLwYJKoZIhvcNAQkEMSIEIAobC46VoQpW
# 0JNhTyQuupn0OgzVhMM8iiieJVRTxJqaMA0GCSqGSIb3DQEBAQUABIIBAJz4fUjV
# M9muHPKRzQYAUD4KAd/5QX4fYiIUYXh1fAiElZi7K7wSaTajERUbJrqrRlCLz1SQ
# j7aP7FWaV3nl8A6PyvaepRMGk9MsYOR6o0zJIo1McE7mRitrJY5JUX9l8Hqd9g3x
# vQteW/2Tde/7MIn5p0AawMdIZDqAvJ9Kx5UcZNa5SmZDLtVPUkk469CzOZpc1Y5s
# FGJZmnxo4IQhBC9cwLDS79Hzq75vgEJIabEcrxdyZR9ZC4zgTzT5Q6jnDU4tUJ8i
# 6GFv0k+Hd+0gjgvydeD3oUuTXfPVNhlhOjmvCjYCXDmMZoS+ZTah3ksjFHy7zx0i
# N/4xwZ2s2Bv/+EU=
# SIG # End signature block
