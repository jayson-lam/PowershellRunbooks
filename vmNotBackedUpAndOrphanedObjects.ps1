### import modules needed
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

### smtp mailing details
$smtpserver = "smtp.sendgrid.net"
$smtpport = redacted
$username = "redacted"
$pwd = "redacted"
$securepwd = ConvertTo-SecureString $pwd -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $securepwd

$from = "redacted"
$recipients = @("redacted")
$subject = "Azure Objects Health Report"

### get all Recovery Service Vaults and Subscriptions 
$subscriptions = Get-AzSubscription

#define arrays 
$backedUpVMobjects = @()
$notBackedUpVM = @()
$allVM = @()

$NICs = @()
$vNGWs = @()
$nats = @()
$pips = @() 
$disks = @()
$loadb = @()

$orphanedDisks = @()
$orphanedNICs = @()
$orphanedPIPs = @()

###for each subscription, grab all VMs and associated name, resource group, and subscription --> add to the allVM array
ForEach ($subscription in $subscriptions){ 
    if($subscription.State -eq "Enabled"){
        Set-AzContext -SubscriptionName $subscription
        Get-AzRecoveryServicesVault | ForEach-Object -Process {$backedUpVMobjects += Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -VaultId $_.ID}

        $NICs += Get-AzNetworkInterface
        $disks += Get-AzDisk
        $pips += Get-AzPublicIpAddress
        $nats += Get-AzNatGateway
        
        Get-AzResourceGroup | ForEach-Object -Process {
            $vNGWs += Get-AzVirtualNetworkGateway -ResourceGroupName $_.ResourceGroupName
            $loadB += Get-AzLoadBalancer -ResourceGroupName $_.ResourceGroupName
        }

        Get-AzVM -Status | ForEach-Object -Process{
            $cmachine = "" | Select-Object Name, ResourceGroup, Subscription
            $cmachine.Name = $_.Name
            $cmachine.ResourceGroup = $_.ResourceGroupName
            $cmachine.Subscription = $subscription.Name
            $allVM += $cmachine   
        
            
        }
    } 
}

### for each vm across the management group, check if they match any of the VMs that are being backed up 
### yes: change arbitrary variable to 1 
### no: do nothing 
### once whole backup array has been iterated through, check the arbitrary variable; if it is still 0, no backup exists
### if it is 1, a backup exists
ForEach ($vm in $allVM){
    $add = 0
    ForEach ($backedUpVMobject in $backedUpVMobjects){
        if ($vm.Name -eq $backedUpVMobject.FriendlyName){
            $add = 1
        }
    }
    if ($add -eq 0){
        $notBackedUpVM += $vm
    }
}

ForEach ($NIC in $NICs) {
    if ($NIC.ProvisioningState -eq "Succeeded"){
        if ($null -eq $NIC.VirtualMachine){
            if($null -eq $NIC.NetworkSecurityGroup){
                if($null -eq $NIC.PrivateEndpoint){
                    $orphanedNICs += $NIC
                }
            }
        }
    }    
}

ForEach($disk in $disks){
    if($disk.DiskState -eq "Unattached"){
        $orphanedDisks += $disk
    }
}

ForEach ($pip in $pips){
    $app = 0
    ForEach ($NIC in $NICs){
        $cid = $NIC.IpConfigurations.PublicIpAddress.Id
        if ($cid -eq $pip.Id){
            $app = 1
        }        
    }

    ForEach ($nat in $nats){
        $pia = $nat.PublicIpAddresses.Id
        if ($pia -eq $pip.Id){
            $app = 1
        }
    }

    ForEach ($vNGW in $vNGWs){
        $pipID = $vNGW.IpConfigurations.PublicIpAddress.ID
        if ($pipID -eq $pip.Id){
            $app = 1
        }
    }

    ForEach($lb in $loadB){
        $pipID = $lb.frontendIPConfigurations.PublicIpAddress.ID
        if ($pipID -eq $pip.Id){
            $app = 1
        }
    }
    
    if ($app -eq 0){
        $orphanedPIPs += $pip
    }
}

#takes the VMs not being backed up and makes it into an HTML table that is sorted by Subscription 
[string]$htmlnotBackedUpVM = $notBackedUpVM | Sort-Object -Property Subscription | Select-Object @{n = "Name"; e = {$_.Name}},@{n = "Subscription"; e = {$_.Subscription}} | ConvertTo-HTML -Fragment
[string]$htmlnotAttachedDisks = $orphanedDisks | Sort-Object -Property Name | Select-Object @{n = "Name"; e = {$_.Name}},@{n = "Resource Group"; e = {$_.ResourceGroupName}} | ConvertTo-HTML -Fragment
[string]$htmlnotAttachedNICs = $orphanedNICs | Sort-Object -Property Name | Select-Object @{n = "Name"; e = {$_.Name}},@{n = "Resource Group"; e = {$_.ResourceGroupName}} | ConvertTo-HTML -Fragment
[string]$htmlnotAttachedPIPs = $orphanedPIPs | Sort-Object -Property Name | Select-Object @{n = "Name"; e = {$_.Name}},@{n = "Resource Group"; e = {$_.ResourceGroupName}} | ConvertTo-HTML -Fragment

[string]$htmlbody = ("<h1>Azure Virtual Machines Not Backed Up</h1>{0} <br><h1>Disks not Attached</h1>{1}</br><br><h1>Not attached NICs</h1>{2}</br><br><h1>Not attached PIPs</h1>{3}</br>" -f $htmlnotBackedUpVM, $htmlnotAttachedDisks, $htmlnotAttachedNICs, $htmlnotAttachedPIPs)

### sending email
Send-MailMessage -From $from -Subject $subject -To $recipients -Body $htmlbody -BodyAsHtml -Usessl -Port $smtpport -SmtpServer $smtpserver -Credential $credential