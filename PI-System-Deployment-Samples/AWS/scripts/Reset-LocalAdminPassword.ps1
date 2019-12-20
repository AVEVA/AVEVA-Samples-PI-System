[CmdletBinding()]
param(
    [string]
    $password
)

try {
    $ErrorActionPreference = "Stop"

    Write-Verbose "Resetting local admin password"
    ([adsi]("WinNT://$env:COMPUTERNAME/administrator, user")).psbase.invoke('SetPassword', $password)
}
catch {
    $_ | Write-AWSQuickStartException
}