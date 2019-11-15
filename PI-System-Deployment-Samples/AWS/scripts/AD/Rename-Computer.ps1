[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$NewName,

    [Parameter(Mandatory=$false)]
    [switch]$Restart
)

try {
    $ErrorActionPreference = "Stop"
    Start-Transcript -Path C:\cfn\log\$($MyInvocation.MyCommand.Name).log -Append

    $renameComputerParams = @{
        NewName = $NewName
    }

    Rename-Computer @renameComputerParams

    if ($Restart) {
        # Execute restart after script exit and allow time for external services
        $shutdown = Start-Process -FilePath "shutdown.exe" -ArgumentList @("/r", "/t 10") -Wait -NoNewWindow -PassThru
        if ($shutdown.ExitCode -ne 0) {
            throw "[ERROR] shutdown.exe exit code was not 0. It was actually $($shutdown.ExitCode)."
        }
    }
}
catch {
    $_ | Write-AWSQuickStartException
}