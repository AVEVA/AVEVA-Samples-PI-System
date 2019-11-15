[CmdletBinding()]
param(

)

try {
    Start-Transcript -Path C:\cfn\log\Install-NetFrameworkCore.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    $retries = 0
    $installed = $false
    do {
        try {
            Install-WindowsFeature NET-Framework-Core
            $installed = $true
        }
        catch {
            $exception = $_
            $retries++
            if ($retries -lt 6) {
                Write-Host $exception
                $linearBackoff = $retries * 60
                Write-Host "Installation failed. Retrying in $linearBackoff seconds."
                Start-Sleep -Seconds $linearBackoff
            }
        }
    } while (($retries -lt 6) -and (-not $installed))
    if (-not $installed) {
          throw $exception
    }
}
catch {
    $_ | Write-AWSQuickStartException
}
