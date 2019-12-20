try {
    $ErrorActionPreference = "Stop"
    Start-Transcript -Path C:\cfn\log\$($MyInvocation.MyCommand.Name).log -Append
    Install-WindowsFeature AD-Domain-Services, rsat-adds -IncludeAllSubFeature

}
catch {
    $_ | Write-AWSQuickStartException
}