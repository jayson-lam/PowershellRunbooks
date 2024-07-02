#import all required modules
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

#get all succeeded reservations and all subscriptions
$today = Get-Date

$tenants = Get-AzContext
$allReservations = @()

ForEach ($tenant in $tenants){
    Set-AzContext -Tenant $tenant.Tenant
    $allReservations += Get-AzReservation
    $subscriptions += Get-AzSubscription
}
#initialize array
$resourceGroups = @()
$oArray = @()

#get all resource groups in for each subscription
ForEach ($subscription in $subscriptions){
    Set-AzContext -SubscriptionName $subscription
    $resourceGroups += Get-AzResourceGroup
}

#for each reservation in all reservations, get a quote for a single resource group, in westus2, given quantity, type, sku, and term
#azure only lets reservation owner view the monthly cost so we use the same information and generate a quote based off the parameters
#values should be equivalent to the cost calculator
ForEach ($reservation in $allReservations){
        if ($reservation.ExpiryDateTime -ge $today){
        Write-Output $reservation.ExpiryDate
        $quote = Get-AzReservationQuote -AppliedScopeType 'Single' -AppliedScopePropertyResourceGroupId "redacted" -BillingPlan 'Monthly' -billingScopeId "redacted" -DisplayName 'temp' -Location 'westus2' -Quantity $reservation.quantity -ReservedResourceType $reservation.ReservedResourceType -Sku $reservation.SkuName -Term $reservation.term -InstanceFlexibility "On"

        $rg = $reservation.AppliedScopePropertyDisplayName
        $expiration = ($reservation.ExpiryDate)
        $name = $reservation.DisplayName 

        #if the term is 3 years, divide by 36 (3 * 12 months), else divide by 12 to get monthly cost
        if ($reservation.Term -eq "P3Y"){
            $price = ([float]($quote.BillingCurrencyTotal.Amount))/36
        }else{
            $price = ([float]($quote.BillingCurrencyTotal.Amount))/12
        }

        #for the resource group scope, grab the cost recovery and department tags
        ForEach ($resourceGroup in $resourceGroups){
            if ($resourceGroup.ResourceGroupName -eq $rg){
                $costRecovery = $resourceGroup.tags.foreach({ $_.CostRecovery})
                $Dept = $resourceGroup.tags.foreach({$_.Dept})
            }
        }
        
        #create the object and set its properties equal to the respective values
        $currReservation = "" | Select-Object Name, ResourceGroup, Expiration, CostRecovery, Price, Dept
        $currReservation.Name = $name
        $currReservation.ResourceGroup = $rg
        $currReservation.Expiration = $expiration
        $currReservation.CostRecovery = $costRecovery[0]
        $currReservation.Price = $price
        $currReservation.Dept = $Dept

        #add the current reservations to the output array
        $oArray += $currReservation 
    }
}
#create the attachment file (blank csv)
$attachment3 = New-Item reservations-data.csv -ItemType file

#format the output file and sort by expiration date
$reservationscsv = $oArray | Sort-Object -Property Expiration |  Select-Object @{n='Reservation Name';e={$_.Name}},@{n='Recovery?';e={$_.CostRecovery}},@{n='Department';e={$_.Dept}}, @{n='Cost per Month';e={('{0:N2}' -f $_.Price)}},@{n='Expiration Date';e={($_.Expiration).ToString('MM-yyyy')}}, @{n='Resource Group';e={$_.ResourceGroup}} | Export-Csv $attachment3 -notypeinformation

#everything below delete to place into AzureBilling.ps1
$smtpserver = "smtp.sendgrid.net"
$smtpport = redacted
$recipients = @("redacted")
$from = "redacted"
$username = "apikey"
$pwd = "redacted"
$securepwd = ConvertTo-SecureString $pwd -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $securepwd

$subject = "Azure Reservations CSV"
$body = ""

Send-MailMessage -Attachments $attachment3 -From $from -Subject $subject -To $recipients -Body $body -BodyAsHtml -Usessl -Port $smtpport -SmtpServer $smtpserver -Credential $credential