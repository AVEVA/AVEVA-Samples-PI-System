[CmdletBinding()]
param(
    [string]
    $Handle
)

Write-Verbose "Creating Handle Key with $Handle"
New-AWSQuickStartWaitHandle -Handle $Handle