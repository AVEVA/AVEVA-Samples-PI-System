[CmdletBinding()]
param(

)

try {
    Start-Transcript -Path C:\cfn\log\Install-WindowsFailoverClustering.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    Install-WindowsFeature failover-clustering -IncludeManagementTools
}
catch {
    $_ | Write-AWSQuickStartException
}