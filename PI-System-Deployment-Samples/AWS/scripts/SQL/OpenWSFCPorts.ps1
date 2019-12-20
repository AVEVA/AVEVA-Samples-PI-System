try {
    Start-Transcript -Path C:\cfn\log\OpenWSFCPorts.ps1.txt -Append

    $ErrorActionPreference = "Stop"

    netsh advfirewall firewall add rule name="SQL Server" dir=in action=allow protocol=TCP localport=1433 
    netsh advfirewall firewall add rule name="SQL Admin Connection" dir=in action=allow protocol=TCP localport=1434
    netsh advfirewall firewall add rule name="SQL Service Broker" dir=in action=allow protocol=TCP localport=4022 
    netsh advfirewall firewall add rule name="AlwaysOn TCPIP End Point" dir=in action=allow protocol=TCP localport=5022
    netsh advfirewall firewall add rule name="AlwaysOn AG Listener" dir=in action=allow protocol=TCP localport=5023
    netsh advfirewall firewall add rule name="SQL Debugger/RPC" dir=in action=allow protocol=TCP localport=135 
}
catch {
    $_ | Write-AWSQuickStartException
}