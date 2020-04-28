# Verify test install completed successfully
$sqlservice = Get-Service -DisplayName "SQL Server ($SqlInstance)"
if ($sqlservice.Status -ne "Running") {
  throw "SQL Service is not running after script completed."
}
$piarchss = Get-Service -DisplayName "PI Archive Subsystem"
if ($piarchss.Status -ne "Running") {
  throw "PI Archive Subsystem not running after script completed."
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
