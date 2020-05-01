# Verify test install completed successfully
# This script is used by the automated test pipeline, but can be modified to verify specific deployments
$sqlservice = Get-Service -DisplayName "SQL Server (SQLExpress)"
if ($sqlservice.Status -ne "Running") {
  throw "SQL Service is not running after script completed."
}
$piarchss = Get-Service -DisplayName "PI Archive Subsystem"
if ($piarchss.Status -ne "Running") {
  throw "PI Archive Subsystem not running after script completed."
}
# Update PATH so PI PowerShell can be used
$locations = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
'HKCU:\Environment'
$locations | ForEach-Object {
  $k = Get-Item $_
  $k.GetValueNames() | ForEach-Object {
    $name = $_
    $value = $k.GetValue($_)

    if ($dryRun -eq $true) {
      Write-LogFunction $func "DryRun: Found variable '$name' with value '$value'"
    }
    elseif ($userLocation -and $name -ieq 'PATH') {
      $Env:Path += ";$value"
    }
    else {
      Set-Item -Path Env:\$name -Value $value
    }
  }

  $userLocation = $true
}
$afserver = Get-AFServer -Name $env:computername
$afdatabase = Get-AFDatabase -AFServer $afserver -Name 'TestDatabase'
if ($null -eq $afdatabase) {
  throw "AF Database not found after script completed."
}
$piprocbook = Get-Item -Path $env:PIHOME\Procbook\Procbook.exe
if (-not $piprocbook.Exists) {
  throw "PI ProcessBook executable not found after script completed."
}
