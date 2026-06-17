<#
.SYNOPSIS
    Deploys Day 2 (Data) slim infrastructure into the customer's Azure
    subscription / resource group.

.DESCRIPTION
    Runs `az deployment group create` against infra/main-day2.bicep, then
    writes a workshop .env file with the resource endpoints labs 01-03 need.

    Day 1 (Sandeep — Agentic AI: Foundry, Cosmos, AI Search, ContainerApps,
    ACR, AOAI) is deployed separately. This script targets the SAME RG that
    holds Sandeep's resources.

.PARAMETER ResourceGroupName
    Existing resource group (Sandeep's Day 1 RG). The script will not
    create it.

.PARAMETER Location
    Azure region. Must support Fabric, Azure SQL VECTOR, and Purview.
    Defaults to the resource group's location if not provided.

.PARAMETER FabricAdminObjectId
    Entra Object ID of the user/group to be Fabric capacity admin. Get it
    with: az ad signed-in-user show --query id -o tsv

.PARAMETER SqlAadAdminLogin
    UPN of the Entra admin for Azure SQL (Entra-only auth).

.PARAMETER SqlAadAdminObjectId
    Entra Object ID matching SqlAadAdminLogin.

.PARAMETER SkipFabric
    Skip Fabric capacity provisioning (use if a shared capacity already exists).

.PARAMETER SkipSql
    Skip Azure SQL provisioning.

.PARAMETER SkipPurview
    Skip Purview provisioning.

.EXAMPLE
    ./scripts/deploy-day2.ps1 -ResourceGroupName rg-pepsi-shared -Location eastus2 `
        -FabricAdminObjectId 4c517221-2844-4edd-84e1-8a3f5f4bb55f `
        -SqlAadAdminLogin admin@contoso.com `
        -SqlAadAdminObjectId 4c517221-2844-4edd-84e1-8a3f5f4bb55f
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ResourceGroupName,
    [string] $Location,
    [string] $SqlLocation,
    [Parameter(Mandatory = $true)] [string] $FabricAdminObjectId,
    [Parameter(Mandatory = $true)] [string] $SqlAadAdminLogin,
    [Parameter(Mandatory = $true)] [string] $SqlAadAdminObjectId,
    [string] $WorkshopName = 'pepsiws',
    [string] $EnvironmentName = 'day2',
    [ValidateSet('F2','F4','F8','F16','F32','F64')] [string] $FabricSku = 'F2',
    [string] $SqlDatabaseName = 'vectordb',
    [switch] $SkipFabric,
    [switch] $SkipSql,
    [switch] $SkipPurview
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bicep = Join-Path $projectRoot 'infra/main-day2.bicep'

if (-not (Test-Path $bicep)) {
    throw "Cannot find $bicep. Run from the data-workshop-infra repo root."
}

# Confirm RG exists
$rgExists = az group exists --name $ResourceGroupName 2>$null
if ($rgExists -ne 'true') {
    throw "Resource group '$ResourceGroupName' does not exist. Have your customer create it (or run Sandeep's Day 1 deploy) first."
}

if (-not $Location) {
    $Location = az group show --name $ResourceGroupName --query location -o tsv
    Write-Host "Using resource group location: $Location"
}
if (-not $SqlLocation) {
    $SqlLocation = $Location
}

$deployName = "pepsi-day2-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "== Deploying Day 2 slim infra =="
Write-Host "  Resource group : $ResourceGroupName"
Write-Host "  Location       : $Location"
Write-Host "  SQL Location   : $SqlLocation"
Write-Host "  Fabric admin   : $FabricAdminObjectId"
Write-Host "  SQL Entra admin: $SqlAadAdminLogin ($SqlAadAdminObjectId)"
Write-Host "  Skip flags     : Fabric=$($SkipFabric.IsPresent) SQL=$($SkipSql.IsPresent) Purview=$($SkipPurview.IsPresent)"
Write-Host ""

az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deployName `
    --template-file $bicep `
    --parameters `
        workshopName=$WorkshopName `
        environmentName=$EnvironmentName `
        location=$Location `
        sqlLocation=$SqlLocation `
        enableFabricCapacity=$([bool](-not $SkipFabric.IsPresent)) `
        fabricSkuName=$FabricSku `
        fabricAdminObjectId=$FabricAdminObjectId `
        enableSqlVector=$([bool](-not $SkipSql.IsPresent)) `
        sqlAadAdminLogin=$SqlAadAdminLogin `
        sqlAadAdminObjectId=$SqlAadAdminObjectId `
        sqlDatabaseName=$SqlDatabaseName `
        enablePurview=$([bool](-not $SkipPurview.IsPresent)) `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw "Deployment failed with exit $LASTEXITCODE."
}

# Capture outputs
$outputsJson = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $deployName `
    --query properties.outputs `
    -o json
$outputs = $outputsJson | ConvertFrom-Json

# Write outputs to .azure/main-day2-outputs.json for downstream scripts
$outDir = Join-Path $projectRoot '.azure'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outputsJson | Set-Content -Path (Join-Path $outDir 'main-day2-outputs.json') -Encoding utf8

# Write a workshop .env helper
$envFile = Join-Path $outDir 'workshop-day2.env'
@"
# PepsiCo MSFT Workshop — Day 2 (Data) endpoints
# Generated $(Get-Date -Format 'u') from deployment '$deployName'
AZURE_RESOURCE_GROUP=$ResourceGroupName
AZURE_LOCATION=$Location
FABRIC_CAPACITY_NAME=$($outputs.fabricCapacityName.value)
SQL_SERVER_FQDN=$($outputs.sqlServerFqdn.value)
SQL_DATABASE_NAME=$($outputs.sqlDatabaseName.value)
PURVIEW_ACCOUNT_NAME=$($outputs.purviewAccountName.value)
PURVIEW_ATLAS_ENDPOINT=$($outputs.purviewAtlasEndpoint.value)
"@ | Set-Content -Path $envFile -Encoding utf8

Write-Host ""
Write-Host "Day 2 infrastructure ready."
Write-Host "  Outputs : $outDir/main-day2-outputs.json"
Write-Host "  Env file: $envFile"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1) Run the SQL VECTOR setup:    sqlcmd -S $($outputs.sqlServerFqdn.value) -d $($outputs.sqlDatabaseName.value) -G -i Allfiles/lab03/setup-sql-vector.sql"
Write-Host "  2) Grant participant access:    ./scripts/grant-user-access-day2.ps1 -ResourceGroupName $ResourceGroupName"
Write-Host "  3) Add the Fabric capacity to a workspace and assign attendees as Workspace Contributors (Fabric portal)."
