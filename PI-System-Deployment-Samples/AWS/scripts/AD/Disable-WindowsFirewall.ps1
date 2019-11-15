try {
    $ErrorActionPreference = "Stop"
    Start-Transcript -Path C:\cfn\log\$($MyInvocation.MyCommand.Name).log -Append

    Get-NetFirewallProfile | Set-NetFirewallProfile -Enabled False
}
catch {
    $_ | Write-AWSQuickStartException
}