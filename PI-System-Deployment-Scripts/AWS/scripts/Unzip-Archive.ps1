[CmdletBinding()]
param(
    [string]
    $Source,

    [string]
    $Destination
)

Write-Verbose "Loading System.IO.Compression.FileSystem Assembly"
[System.Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem')

Write-Verbose "Unpacking $Source to $Destination"
[System.IO.Compression.ZipFile]::ExtractToDirectory($Source, $Destination)