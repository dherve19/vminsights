# Variables (Set these before running)
$logAnalyticsResourceGroup = "XXXXXXX"
$logAnalyticsWorkspaceName = "XXXXXXXXXX"
$dcrId = "XXXXXXX"

# Authenticate to Azure
#Connect-AzAccount
# Authenticate
Connect-AzAccount -Subscription "XXXXXXXXXXXXX" -Tenant "XXXXXXXXXXXXXXXX"

# Get Log Analytics Workspace details
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $logAnalyticsResourceGroup -Name $logAnalyticsWorkspaceName
$workspaceId = $workspace.CustomerId
$workspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $logAnalyticsResourceGroup -Name $logAnalyticsWorkspaceName).PrimarySharedKey

# Read subscription IDs from file
#$subscriptionFilePath = ".suscriptionsids.txt"
$subscriptionFilePath = "C:\Path\To\suscriptions.txt"
$subscriptionIds = Get-Content -Path $subscriptionFilePath | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' }
#$subscriptionIds ="21c4f4fe-356f-4c05-beb2-0ca673839278"

foreach ($subscriptionId in $subscriptionIds) {
    Write-Host "`nProcessing Subscription: $subscriptionId" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $subscriptionId

    # Get running VMs
    $vms = Get-AzVM -Status | Where-Object { $_.PowerState -eq "VM running" }

    foreach ($vm in $vms) {
        Write-Host "Configuring   $($vm.StorageProfile.OsDisk.OsType) VM Insights for VM: $($vm.Name) in Resource Group: $($vm.ResourceGroupName)" -ForegroundColor Green

        # Check OS type
        $osType = $vm.StorageProfile.OsDisk.OsType

        if ($osType -eq "Windows") {
            # Enable Azure Monitor Agent for Windows
            Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName `
                              -VMName $vm.Name `
                              -Name "AzureMonitorWindowsAgent" `
                              -Publisher "Microsoft.Azure.Monitor" `
                              -ExtensionType "AzureMonitorWindowsAgent" `
                              -TypeHandlerVersion "1.0" `
                              -Settings @{ "workspaceId" = $workspaceId } `
                              -ProtectedSettings @{ "workspaceKey" = $workspaceKey } `
                              -Location $vm.Location

            # Install Dependency Agent for Windows
            Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName `
                              -VMName $vm.Name `
                              -Name "DependencyAgentWindows" `
                              -Publisher "Microsoft.Azure.Monitoring.DependencyAgent" `
                              -ExtensionType "DependencyAgentWindows" `
                              -TypeHandlerVersion "9.10" `
                              -Location $vm.Location
        }
        elseif ($osType -eq "Linux") {
            # Enable Azure Monitor Agent for Linux
            Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName `
                              -VMName $vm.Name `
                              -Name "AzureMonitorLinuxAgent" `
                              -Publisher "Microsoft.Azure.Monitor" `
                              -ExtensionType "AzureMonitorLinuxAgent" `
                              -TypeHandlerVersion "1.0" `
                              -Settings @{ "workspaceId" = $workspaceId } `
                              -ProtectedSettings @{ "workspaceKey" = $workspaceKey } `
                              -EnableAutomaticUpgrade $true`
                              -Location $vm.Location

            # Install Dependency Agent for Linux
            Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName `
                              -VMName $vm.Name `
                              -Name "DependencyAgentLinux" `
                              -Publisher "Microsoft.Azure.Monitoring.DependencyAgent" `
                              -ExtensionType "DependencyAgentLinux" `
                              -TypeHandlerVersion "9.10" `
                              -EnableAutomaticUpgrade $true`
                              -Location $vm.Location

        }
        else {
            Write-Host "Unknown OS type for VM: $($vm.Name)" -ForegroundColor Red
        }

        # Associate DCR with VM
        New-AzDataCollectionRuleAssociation -AssociationName "$($vm.Name)-DCRAssociation" `
                                            -ResourceUri $vm.Id `
                                            -DataCollectionRuleId $dcrId

        Write-Host "DCR associated with VM: $($vm.Name)" -ForegroundColor Yellow
    }
}

Write-Host "`nVM Insights configuration complete!" -ForegroundColor Yellow
