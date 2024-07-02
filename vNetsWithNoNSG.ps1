Import-Module Az.Accounts
Import-Module Az.Network
Import-Module Az.Compute
Import-Module Az.Resources

try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

$subscriptions = Get-AzSubscription

$allSubnets = @()
$associatedSubnets = @()
$unassociatedSubnets = @()
$output = @()

$NSGs = @()
$vNETs = @()

ForEach ($subscription in $subscriptions) {
    Set-AzContext -SubscriptionName $subscription
    
    Get-AzResourceGroup | ForEach-Object {
        $vNETs += Get-AzVirtualNetwork -ResourceGroupName $_.ResourceGroupName
        $NSGs += Get-AzNetworkSecurityGroup -ResourceGroupName $_.ResourceGroupName
    }
}   

ForEach($virtualNetwork in $vNETs) {
    $allSubnets += $virtualNetwork.Subnets.ID
}

ForEach($NSG in $NSGs) {
    $associatedSubnets += $NSG.subnets.ID
}

ForEach($subnet in $allSubnets){
    $add = 0
    ForEach ($associatedSubnet in $associatedSubnets) {
        if ($subnet -eq $associatedSubnet) {
            $add = 1
        }
    }
    if ($add -eq 0) {
        $unassociatedSubnets += $subnet
    }
}

ForEach ($subnet in $unassociatedSubnets) {
    $split = $subnet -split "/"
    $formatted = "" | Select-Object SubnetName, VirtualNetwork, ResourceGroup
    $formatted.SubnetName = $split[-1]
    $formatted.VirtualNetwork = $split[8]
    $formatted.ResourceGroup = $split[4]
    $output += $formatted
}

[string]$table = $output | Sort-Object VirtualNetwork | Select-Object @{n='Subnet Name';e={$_.SubnetName}}, @{n='Virutal Network';e={$_.VirtualNetwork}}, @{n='Resource Group';e={$_.ResourceGroup}} | ConvertTo-HTML -Fragment
[string]$htmlbody = ("<h1>Virtual Networks with no Network Security Group</h1>{0}" -f $table)
$smtpserver = "smtp.sendgrid.net"
$smtpport = redacted
$recipients = @("redacted")
$from = "redacted"
$username = "redacted"
$pwd = "redacted"
$securepwd = ConvertTo-SecureString $pwd -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $securepwd

$subject = "Virtual Network Subnets with no Network Security Group"

Send-MailMessage -From $from -Subject $subject -To $recipients -Body $htmlbody -BodyAsHtml -Usessl -Port $smtpport -SmtpServer $smtpserver -Credential $credential