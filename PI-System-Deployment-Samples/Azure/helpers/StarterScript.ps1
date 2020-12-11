#  Root directory where you downloaded/unzipped from GitHub
$DirectoryRoot = '<Location of the Deployment folder>'  # for example, C:\DeploymentFolder

#  Helpers folder within the root - where the scripts live
$PSScriptRoot = Join-Path $DirectoryRoot 'helpers'

#  Parameters used by the Master Bootstrapper script.  Modify these to match the current environment
#  SubscriptionName, Location, and ResourceGroupName must match the Azure environment
#  The deployHA flag (true/false) dictates whether or not High Availability will be used
#  The LocalArtifactFilePath must be set to match the current directory structure
$param = @{
	'SubscriptionName' = '<Your Subscription name>'
	'Location' = '<Location of your Resource Group>'
	'ResourceGroupName' = '<Your Resource Group name>'
	'deployHA' = 'true'
	'EnableOSIsoftTelemetry'   = '<Please specify "true" to enable OSIsoft to collect telemetry information or "false" to not allow OSIsoft to collect telemetry information>'
	'EnableMicrosoftTelemetry' = '<Please specify "true" to enable Microsoft to collect telemetry information or "false" to not allow Microsoft to collect telemetry information>'
}

#  Call the Master BootStrapper script and start the deployment using the parameters above
if (Get-Module -ListAvailable -Name "AzureRM.Automation") {
	& (Join-Path $PSScriptRoot 'MasterBootstrapperScript.ps1') @param 
}
else {
	& (Join-Path $PSScriptRoot 'MasterBootstrapperScript_az.ps1') @param 
}
