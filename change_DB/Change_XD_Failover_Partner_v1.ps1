<#
   Copyright (c) Citrix Systems, Inc. All rights reserved.

.SYNOPSIS
   Reconfigure XenDesktop connection strings to include or remove an SQL mirror partner

.DESCRIPTION
   The Change_XD_Partner script uses the XenDesktop Powershell API to reconfigure
   the database connection strings in the correct sequence to update the failover
   partner.  The script will prompt for the failover partner locations for each of
   the site, monitoring and configuration logging databases.

.PARAMETER ClearPartner
   Remove the failover partner from all connection strings.
#>

param (
    [switch]    $ClearPartner,
    [switch]    $help
    )

if ($help)
{
    Get-Help($MyInvocation.MyCommand.Path) -detailed
    return
}

#requires -Version 3.0
. $PSScriptRoot\DBConnectionStringFuncs.ps1

function CreateNewConnectionString([string]$currentConnectionString, [string]$partner)
{
	$connectionBuilder = new-Object System.Data.SqlClient.SqlConnectionStringBuilder $currentConnectionString
    if ([String]::IsNullOrEmpty($partner))
    {
        $connectionBuilder["Failover Partner"] = $null
    }
    else
    {
        if ($connectionBuilder.DataSource -eq $partner)
        {
            write-host -ForegroundColor Red "You should not set the failover partner to be the same as the principal server"
            write-host -ForegroundColor Red ("Database Name:   {0}" -f $connectionBuilder.InitialCatalog)
            write-host -ForegroundColor Red ("Database Server: {0}" -f $connectionBuilder.DataSource)
            write-host -ForegroundColor Red ("Partner Server:  {0}" -f $partner)

            exit 1
        }
	    $connectionBuilder["Failover Partner"] = $partner
    }
	return $connectionBuilder.ConnectionString
}

Check-Snapins

## perhaps a catch 22, but we assume that we can actually get a list of controllers from the current ddc
$controllers = CreateControllerList
Check-Services $controllers

$siteConnectionString = Get-BrokerDBConnection -AdminAddress $controllers[0]
$configLoggingDataStoreConnectionString = Get-LogDBConnection -DataStore "Logging" -AdminAddress $controllers[0]
$monitorLoggingDataStoreConnectionString = Get-MonitorDBConnection -DataStore "Monitor" -AdminAddress $controllers[0]

$settingPartner = !$clearPartner
if ($settingPartner)
{
    Write-Host -ForegroundColor Yellow "Note that providing a blank failover partner will remove the failover partner"

    Write-Host ("Current connection String: {0}" -f $siteConnectionString)
	$sitePartner = Read-Host 'What is the FQDN of the failover partner for the site database'
	
	if ($siteConnectionString -ne $configLoggingDataStoreConnectionString)
	{
        Write-Host ("Current connection String: {0}" -f $configLoggingDataStoreConnectionString)
		$configLoggingPartner = Read-Host 'What is the FQDN of the failover partner for the Configuration Logging datastore'
	}
	else
	{
		$configLoggingPartner = $sitePartner
	}
	
	if ($siteConnectionString -ne $monitorLoggingDataStoreConnectionString)
	{
        Write-Host ("Current connection String: {0}" -f $monitorLoggingDataStoreConnectionString)
		$monitorPartner = Read-Host 'What is the FQDN of the failover partner for the Monitoring datastore'
	}
	else
	{
		$monitorPartner = $sitePartner
	}
}
else
{
	$sitePartner = $null
	$configLoggingPartner = $null
	$monitorPartner = $null
}


$siteUpdatedConnectionString = CreateNewConnectionString $siteConnectionString $sitePartner
$configLoggingUpdatedConnectionString = CreateNewConnectionString $configLoggingDataStoreConnectionString $configLoggingPartner
$monitorUpdatedConnectionString = CreateNewConnectionString $monitorLoggingDataStoreConnectionString $monitorPartner

ProcessConnectionStringUpdates $controllers $siteConnectionString $siteUpdatedConnectionString $configLoggingDataStoreConnectionString $configLoggingUpdatedConnectionString $monitorLoggingDataStoreConnectionString $monitorUpdatedConnectionString