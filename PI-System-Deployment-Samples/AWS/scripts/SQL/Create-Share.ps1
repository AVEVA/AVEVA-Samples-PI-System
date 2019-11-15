[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory=$true)]
    [string]$ShareName,

    [Parameter(Mandatory=$true)]
    [string]$Path,

    [Parameter(Mandatory=$false)]
    [string]$ServerName='localhost',

    [Parameter(Mandatory=$true)]
    [string]$FolderPath,

    [Parameter(Mandatory=$true)]
    [string]$FolderName,

    [Parameter(Mandatory=$false)]
    [string[]]$FullAccessUser='everyone',

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix

)

try {
    Start-Transcript -Path C:\cfn\log\Create-Share.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    # Get exisitng service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUser" -WithDecryption $True).Parameters[0].Value
    
    $DomainAdminFullUser = $DomainNetBIOSName + '\' + $DomainAdminUser
    $DomainAdminSecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $DomainAdminCreds = New-Object System.Management.Automation.PSCredential($DomainAdminFullUser, $DomainAdminSecurePassword)

    $CreateFolderPs={
        $ErrorActionPreference = "Stop"
        New-Item -ItemType directory -Path $Using:FolderPath -Name $Using:FolderName
    }
    Invoke-Command -Scriptblock $CreateFolderPs -ComputerName $ServerName -Credential $DomainAdminCreds -ArgumentList $FolderPath,$FolderName

    $CreateSharePs={
        $ErrorActionPreference = "Stop"
        New-SmbShare -Name $Using:ShareName -Path $Using:Path -FullAccess $Using:FullAccessUser
    }
    Invoke-Command -Scriptblock $CreateSharePs -ComputerName $ServerName -Credential $DomainAdminCreds
}
catch {
    $_ | Write-AWSQuickStartException
}
