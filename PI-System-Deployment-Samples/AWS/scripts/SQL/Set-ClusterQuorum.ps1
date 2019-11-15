[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode2NetBIOSName,

    [Parameter(Mandatory=$false)]
    [string]$FileServerNetBIOSName,

    [Parameter(Mandatory=$false)]
    [bool]$Witness=$true,

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix

)
try {
    Start-Transcript -Path C:\cfn\log\Set-ClusterQuorum.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    # Get exisitng service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUser" -WithDecryption $True).Parameters[0].Value
    
    $DomainAdminFullUser = $DomainNetBIOSName + '\' + $DomainAdminUser
    $DomainAdminSecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $DomainAdminCreds = New-Object System.Management.Automation.PSCredential($DomainAdminFullUser, $DomainAdminSecurePassword)

    $SetClusterQuorum={
        $ErrorActionPreference = "Stop"
        if ($Using:Witness) {
            $ShareName = "\\" + $Using:FileServerNetBIOSName + "\witness"
            Set-ClusterQuorum -NodeAndFileShareMajority $ShareName
        } else {
            Set-ClusterQuorum -NodeMajority
        }
    }

    Invoke-Command -Scriptblock $SetClusterQuorum -ComputerName $WSFCNode2NetBIOSName -Credential $DomainAdminCreds

}
catch {
    $_ | Write-AWSQuickStartException
}
