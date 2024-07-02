### import modules needed
Import-Module Az.Accounts
Import-Module Az.ConnectedMachine

try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

### smtp mailing details
$smtpserver = "smtp.sendgrid.net"
$smtpport = redacted
$username = "redacted"
$pwd = "redacted"
$securepwd = ConvertTo-SecureString $pwd -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $securepwd

$from = "redacted"
$recipients = @("redacted")
$subject = "Azure Arc Health Report"

### catching expired machines
$expiredmachines  = @()

Get-AzConnectedMachine -ResourceGroupName "redacted" | ForEach-Object -Process{
    if ($_.Status -ne "Connected"){
        $machineinfo = "" |Select-Object MachineName, LastStatusChange, Status
        $machineinfo.MachineName = $_.Name
        $machineinfo.LastStatusChange = $_.LastStatusChange
        $machineinfo.Status = $_.Status
        $expiredmachines += $machineinfo
    }
}
#grabs all connected arc mmachines --> grabs all machines where they are "expired" --> grabs machine info --> add to array
[string]$htmlexpiredmachines = $expiredmachines | Sort-Object -Property MachineName | Select-Object @{n = "MachineName"; e = {$_.MachineName}},@{n = "LastStatusChange"; e = {$_.LastStatusChange}},@{n = "Status"; e = {$_.Status}} | ConvertTo-HTML -Fragment

### catching failed extensions 
$failedextensions = @()
$machineinfo = Get-AzConnectedMachine -ResourceGroupName "redacted"
$machineinfo | ForEach-Object -Process{   
    $cmachine = $_.Name
    if ($_.Status -eq "Connected"){
        $extensions = Get-AzConnectedMachineExtension -ResourceGroupName "redacted" -MachineName $_.Name
        $extensions | ForEach-Object -Process{
            if($_.provisioningState -ne "Succeeded"){
                $extensioninfo = "" | Select-Object ExtensionName, provisioningState, MachineName                    
                $extensioninfo.ExtensionName = $_.Name
                $extensioninfo.provisioningState = $_.provisioningState
                $extensioninfo.MachineName = $cmachine
                $failedextensions += $extensioninfo
            }
        } 
    }
}
#grabs all connected arc machines --> grabs all extensions where they are failed --> grabs extension info + machine name --> add to array
[string]$htmlfailedextensions = $failedextensions | Sort-Object -Property MachineName | Select-Object @{n = "MachineName"; e = {$_.MachineName}},@{n = "ExtensionName"; e = {$_.ExtensionName}}, @{n = "ProvisioningState"; e = {$_.provisioningState}} | ConvertTo-HTML -Fragment

### creating html body with break between tables
[string]$htmlbody = ("<h1>Expired Arc Machines</h1>{0}<br /><br /> <h1>Failed Extensions</h1>{1}" -f $htmlexpiredmachines, $htmlfailedextensions)

### sending email
Send-MailMessage -From $from -Subject $subject -To $recipients -Body $htmlbody -BodyAsHtml -Usessl -Port $smtpport -SmtpServer $smtpserver -Credential $credential

### checks if schedule already exists (ie previous run) --> if it exists, delete it
Get-AzAutomationScheduledRunbook -AutomationAccountName "redacted" -ResourceGroupName "redacted" -RunbookName "GetExpiredArcMachinesTest" | ForEach-Object -Process{
    if($_.ScheduleName -eq "6DaysAfterPatchTuesday"){
        Remove-AzAutomationSchedule -AutomationAccountName "redacted" -Name "6DaysAfterPatchTuesday" -ResourceGroupName "redacted" -Force
    }
}
### checks if this run was on tuesday UTC --> sets timezone to pst --> sets next schedule to start at 6 days away --> creates and registers new schedule to the runbook
if ((get-date).DayOfWeek -eq "Tuesday"){
    $TimeZone = "Pacific Standard Time"
    $starttime = (Get-Date).AddDays(6)
    New-AzAutomationSchedule -AutomationAccountName "redacted" -Name "6DaysAfterPatchTuesday" -StartTime $starttime -OneTime -ResourceGroupName "redacted" -TimeZone $TimeZone
    Register-AzAutomationScheduledRunbook -AutomationAccountName "redacted" -RunbookName "GetExpiredArcMachinesTest" -ScheduleName "6DaysAfterPatchTuesday" -ResourceGroupName "redacted"
}