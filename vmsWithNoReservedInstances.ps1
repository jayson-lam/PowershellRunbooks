Import-Module Az.Reservations -Force
Import-Module Az.Accounts

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
$subject = "Azure Virtual Machines with No Reservation"

#grab all reservations that are succeeded (not expired)
$tenants = Get-AzContext
$allReservations = @()

ForEach ($tenant in $tenants){
    Set-AzContext -Tenant $tenant.Tenant
    $allReservations += Get-AzReservation 
    $subscriptions = Get-AzSubscription
}

$allResourceGroups = @()
ForEach ($subscription in $subscriptions){
    Set-AzContext -SubscriptionName $subscription
    $allResourceGroups += Get-AzResourceGroup
}

#set today variable and define arrays
$today = Get-Date
$vmWithReservation = @()
$expiringVM = @()
$allVM = @()
$vmWithoutReservation = @()

#for each reservation, grab the reservation id and split it
#using the get-azconsumptionreservationdetail cmdlet and respective reservation order and reservation id, get the instance ID containing where the reservation points to (VM Name)
#split the instance ID to grab VM name and add to array
ForEach ($reservation in $allReservations){
    $reservationIDSplit = @()
    $reservationIDSplit = ($reservation.id -split "/")
    $currReservation = Get-AzConsumptionReservationDetail -ReservationOrderId $reservationIDSplit[4] -ReservationID $reservationIDSplit[-1] -StartDate $today.AddDays(-1)  -EndDate $today
    $currReservation|ForEach-Object -Process{
        $vmIDSplit = $_.InstanceId -split "/"
        $vmWithReservation += $vmIDSplit[-1]
    }
}

#for each reservation in all the reservations, set variable equal to the expiration date of the current reservation 
#if the expiration date is within 3 months, use same concept as above and add to separate array
#additionally, using get-azVM cmdlet to get the resource group and get-azresourcegroup cmdlet to get the Dept tag for that resource group
#add all respective information to array
ForEach ($reservation in $allReservations){
    if ($reservation.ExpiryDateTime -ge $today){
        $expiryDate = $reservation.ExpiryDateTime
        $rgName = $reservation.AppliedScopePropertyDisplayName
        ForEach($resourceGroup in $allResourceGroups){
            if ($resourceGroup.ResourceGroupName -eq $rgName){
                $finaltag = $resourceGroup.tags.foreach({$_.Dept})
            }
        }
        if ($today.AddMonths(3) -gt $expiryDate){
            $reservationIDSplit = ($reservation.id -split "/")
            $currReservation = Get-AzConsumptionReservationDetail -ReservationOrderId $reservationIDSplit[4] -ReservationID $reservationIDSplit[-1] -StartDate $today.AddDays(-1)  -EndDate $today
            $currReservation|ForEach-Object -Process{


                $vmIDSplit = $_.InstanceId -split "/"
                $Name = $vmIDSplit[-1]
                $app = 0
                $i = 0

                while ($i -ne $expiringVM.length){
                    if ($Name -eq $expiringVM[$i].Name){
                        $app = 1
                    }
                $i++
                }

                if ($app -eq 0){
                    $currentVM = "" | Select-Object Name, Expiration, ResourceGroup, Dept, ReservationName
                    $currentVM.Name = $Name
                    $currentVM.Expiration = $expiryDate
                    $currentVM.ResourceGroup = $rgName
                    $currentVM.Dept = $finaltag
                    $currentVM.ReservationName = $reservation.DisplayName
                    $expiringVM += $currentVM
                    
                }
            }
        }
    }
}       

#for every enabled subscription, find all VMs and add their name resource group and subscription to the array
ForEach ($subscription in $subscriptions){
    if ($subscription.state -eq "Enabled"){
        $currsubscription = $subscription.Name
        Set-AzContext -SubscriptionName $currsubscription

        Get-AzVM -Status | ForEach-Object -Process{
            $cmachine = "" | Select-Object Name, ResourceGroup, Subscription
            $cmachine.Name = $_.Name
            $cmachine.ResourceGroup = $_.ResourceGroupName
            $cmachine.Subscription = $currsubscription
            $allVM += $cmachine
        }
    }
}

#for each vm in all the vms
# cross reference all the VMs that have reservations, if they are not on both lists add the machine to the vmWithoutReservation array
ForEach ($vm in $allVM){
    $add = 0
    ForEach ($resVM in $vmWithReservation){
        if ($vm.Name -eq $resVM){
            $add = 1
        }
    }
    if ($add -eq 0){
        $vmWithoutReservation += $vm
    }
}

#html formatting for the two tables
[string]$htmlvmWithoutReservation = $vmWithoutReservation | Sort-Object -Property Name | Select-Object @{n = "Name"; e = {$_.Name}},@{n = "Subscription"; e = {$_.Subscription}}, @{n = "Resource Group"; e = {$_.ResourceGroup}} | ConvertTo-HTML -Fragment
[string]$htmlExpiringVM = $expiringVM | Sort-Object -Property Expiration| Select-Object @{n="Name"; e = {$_.Name}}, @{n="Expiration"; e = {$_.Expiration}}, @{n="Resource Group"; e = {$_.ResourceGroup}}, @{n="Dept"; e = {$_.Dept}}, @{n="Reservation Name"; e = {$_.ReservationName}}  | ConvertTo-HTML -Fragment
[string]$htmlbody = ("<h1>Azure Virtual Machines without Reservations</h1>{0} <br><h1>Expiring Reservations</h1>{1}</br>" -f $htmlvmWithoutReservation, $htmlExpiringVM)
Send-MailMessage -From $from -Subject $subject -To $recipients -Body $htmlbody -BodyAsHtml -Usessl -Port $smtpport -SmtpServer $smtpserver -Credential $credential

#Write-Output "Below this is all VMs"
#Write-Output ""
#ForEach ($vm in $allVM){
#    Write-Output $vm.Name
#}

#Write-Output "Below this is all VMs with Reservations"
#Write-Output ""
#$vmWithReservation

#Write-Output "Below this is all VMs without reservations"
#Write-Output ""
#ForEach ($vm in $vmWithoutReservation){
#    Write-Output $vm.Name
#} #used for testing 