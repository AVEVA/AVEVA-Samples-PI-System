[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$ADServer1PrivateIP,

    [Parameter(Mandatory=$true)]
    [string]$ADServer2PrivateIP
)

try {
    $ErrorActionPreference = "Stop"
    Start-Transcript -Path C:\cfn\log\$($MyInvocation.MyCommand.Name).log -Append

    Get-NetAdapter | Set-DnsClientServerAddress -ServerAddresses $ADServer1PrivateIP,$ADServer2PrivateIP
}
catch {
    $_ | Write-AWSQuickStartException
}