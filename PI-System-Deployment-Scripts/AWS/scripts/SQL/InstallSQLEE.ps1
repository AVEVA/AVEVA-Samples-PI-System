[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]
    $NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]
    $DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]
    $SQLServiceAccount,

    [Parameter(Mandatory=$true)]
    [string]
    $DomainAdminUser,

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix

)

try {
    Start-Transcript -Path C:\cfn\log\InstallSQLEE.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    # Get exisitng service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUser" -WithDecryption $True).Parameters[0].Value
    $SQLServiceAccountPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$SQLServiceAccount" -WithDecryption $True).Parameters[0].Value
    
    $DomainAdminFullUser = $DomainNetBIOSName + '\' + $DomainAdminUser
    $DomainAdminSecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $DomainAdminCreds = New-Object System.Management.Automation.PSCredential($DomainAdminFullUser, $DomainAdminSecurePassword)

    $InstallSqlPs={
        $ErrorActionPreference = "Stop"
        $fname= "C:\sqlinstall\" + (dir -File -Path "C:\sqlinstall\" *.iso)
        $driveLetter = Get-Volume | ?{$_.DriveType -eq 'CD-ROM'} | select -ExpandProperty DriveLetter
        if ($driveLetter.Count -lt 1) {
            Mount-DiskImage -ImagePath $fname
            $driveLetter = Get-Volume | ?{$_.DriveType -eq 'CD-ROM'} | select -ExpandProperty DriveLetter
        }
        # Install SSMS on SQL Server 2016 or higher
        if ((Get-Volume -DriveLetter $($driveLetter)).FileSystemLabel -in @("SqlSetup_x64_ENU", "SQL2016_x64_ENU")) {
            $ssms = "C:\sqlinstall\SSMS-Setup-ENU.exe"
            $ssmsargs = "/quiet /norestart"
            Start-Process $ssms $ssmsargs -Wait -ErrorAction Stop -RedirectStandardOutput "C:\cfn\log\SSMSInstallerOutput.txt" -RedirectStandardError "C:\cfn\log\SSMSInstallerErrors.txt"
        }
        # Install SQL Server
        if ((Get-Volume -DriveLetter $($driveLetter)).FileSystemLabel -eq "SqlSetup_x64_ENU") {
            $features = 'SQLEngine,Replication,FullText,Conn'
        } elseif ((Get-Volume -DriveLetter $($driveLetter)).FileSystemLabel -eq "SQL2016_x64_ENU") {
            $features = 'SQLEngine,Replication,FullText,Conn,BOL'
        } else {
            $features = 'SQLEngine,Replication,FullText,Conn,BOL,ADV_SSMS'
        }
        $installer = "$($driveLetter):\SETUP.EXE"
        $arguments =  '/Q /Action=Install /UpdateEnabled=False /Features=' + $features + ' /INSTANCENAME=MSSQLSERVER /SQLSVCACCOUNT="' + $Using:DomainNetBIOSName + '\' + $Using:SQLServiceAccount + '" /SQLSVCPASSWORD="' + $Using:SQLServiceAccountPassword + '" /AGTSVCACCOUNT="' + $Using:DomainNetBIOSName + '\' + $Using:SQLServiceAccount + '" /AGTSVCPASSWORD="' + $Using:SQLServiceAccountPassword + '" /SQLSYSADMINACCOUNTS="' + $Using:DomainNetBIOSName + '\' + $Using:DomainAdminUser + '" /SQLUSERDBDIR="D:\MSSQL\DATA" /SQLUSERDBLOGDIR="E:\MSSQL\LOG" /SQLBACKUPDIR="F:\MSSQL\Backup" /SQLTEMPDBDIR="F:\MSSQL\TempDB" /SQLTEMPDBLOGDIR="F:\MSSQL\TempDB" /IACCEPTSQLSERVERLICENSETERMS'
        $installResult = Start-Process $installer $arguments -Wait -ErrorAction Stop -PassThru -RedirectStandardOutput "C:\cfn\log\SQLInstallerOutput.txt" -RedirectStandardError "C:\cfn\log\SQLInstallerErrors.txt"
        $exitcode=$installResult.ExitCode
        if ($exitcode -ne 0 -and $exitcode -ne 3010) {
            throw "SQL Server install failed with exit code $exitcode, check the installer logs for more details."
        }
    }

    $Retries = 0
    $Installed = $false
    while (($Retries -lt 8) -and (!$Installed)) {
        try {
            Invoke-Command -Authentication Credssp -Scriptblock $InstallSqlPs -ComputerName $NetBIOSName -Credential $DomainAdminCreds
            $Installed = $true
        }
        catch {
            $Exception = $_
            $Retries++
            if ($Retries -lt 8) {
                # powershell.exe -ExecutionPolicy RemoteSigned -Command C:\cfn\scripts\Enable-CredSSP.ps1
                Start-Sleep (([math]::pow($Retries, 2)) * 60)
            }
        }
    }
    if (!$Installed) {
        throw $Exception
    }
}
catch {
    $_ | Write-AWSQuickStartException
}
