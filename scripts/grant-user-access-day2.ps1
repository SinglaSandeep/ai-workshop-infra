<#
.SYNOPSIS
    Grants Day 2 (Data) participant access for the slim PepsiCo workshop.

.DESCRIPTION
    Day 2 has four resources participants need access to. Only one of them
    is plain Azure RBAC — the rest must be granted in their respective
    portals or via T-SQL. This script:

    1. Runs user-access-day2-slim.bicep to grant Cognitive Services User on
       Sandeep's existing Azure OpenAI account.
    2. Prints copy/paste instructions for Fabric admin portal + Purview
       Studio role assignments.
    3. Optionally runs setup-sql-vector.sql against the deployed Azure SQL
       to CREATE USER FROM EXTERNAL PROVIDER for the workshop group and
       seed the demo VECTOR table.

    Run AFTER deploy-day2.ps1.

.PARAMETER ResourceGroupName
    The Day 2 RG (same as Sandeep's Day 1 RG).

.PARAMETER WorkshopGroupObjectId
    Entra Object ID of the workshop participants security group (or single
    user). This is the same object that gets the AOAI role + the SQL user +
    the Fabric capacity contributor role + the Purview Data Reader role.

.PARAMETER WorkshopGroupDisplayName
    Display name of the Entra group (used in the T-SQL CREATE USER call).
    Required if you also pass -RunSqlSetup.

.PARAMETER PrincipalType
    'Group' (default) or 'User'.

.PARAMETER SandeepAzureOpenAIName
    Resource name of Sandeep's AOAI account. Leave blank to skip the AOAI
    grant.

.PARAMETER SandeepAzureOpenAIResourceGroup
    RG of Sandeep's AOAI if it lives in a different RG. Empty = same RG.

.PARAMETER RunSqlSetup
    Also run Allfiles/lab03/setup-sql-vector.sql against the SQL server
    output by deploy-day2.ps1. Requires sqlcmd and the SQL Entra admin to
    run this script (so they can CREATE USER and GRANT).

.EXAMPLE
    ./scripts/grant-user-access-day2.ps1 `
        -ResourceGroupName rg-pepsi-shared `
        -WorkshopGroupObjectId 11111111-2222-3333-4444-555555555555 `
        -WorkshopGroupDisplayName 'pepsi-workshop-day2-attendees' `
        -SandeepAzureOpenAIName aoai-pepsi-shared `
        -RunSqlSetup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)] [string] $WorkshopGroupObjectId,
    [string] $WorkshopGroupDisplayName,
    [ValidateSet('Group','User')] [string] $PrincipalType = 'Group',
    [string] $SandeepAzureOpenAIName = '',
    [string] $SandeepAzureOpenAIResourceGroup = '',
    [switch] $RunSqlSetup
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bicep = Join-Path $projectRoot 'infra/user-access-day2-slim.bicep'
$outputsFile = Join-Path $projectRoot '.azure/main-day2-outputs.json'

if (-not (Test-Path $outputsFile)) {
    throw "Day 2 deployment outputs not found at $outputsFile. Run ./scripts/deploy-day2.ps1 first."
}

$outputs = Get-Content $outputsFile | ConvertFrom-Json

# ---------------------------------------------------------------------------
# 1) AOAI RBAC via Bicep
# ---------------------------------------------------------------------------
Write-Host "== Day 2 user access =="
if ($SandeepAzureOpenAIName) {
    Write-Host "[1/3] Granting Cognitive Services User on AOAI '$SandeepAzureOpenAIName'..."

    $deployName = "pepsi-day2-useraccess-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $usersJson = (@(
        @{ principalId = $WorkshopGroupObjectId; principalType = $PrincipalType }
    ) | ConvertTo-Json -Compress -AsArray)

    az deployment group create `
        --resource-group $ResourceGroupName `
        --name $deployName `
        --template-file $bicep `
        --parameters workshopUsers="$usersJson" `
                     sandeepAzureOpenAIName=$SandeepAzureOpenAIName `
                     sandeepAzureOpenAIResourceGroup=$SandeepAzureOpenAIResourceGroup `
        --output none
    if ($LASTEXITCODE -ne 0) { throw "AOAI RBAC deployment failed." }

    Write-Host "      Done. RBAC may take a few minutes to propagate."
} else {
    Write-Host "[1/3] Skipped AOAI grant (no -SandeepAzureOpenAIName provided)."
}

# ---------------------------------------------------------------------------
# 2) Manual portal steps
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[2/3] Manual portal grants - please complete:"
Write-Host ""
Write-Host "   --- Fabric capacity admin (Lab 01 + 02) ---"
Write-Host "   Go to https://app.fabric.microsoft.com/admin-portal/capacities"
Write-Host "   Open capacity '$($outputs.fabricCapacityName.value)' -> Capacity admins -> Add"
Write-Host "       $WorkshopGroupDisplayName  ($WorkshopGroupObjectId)"
Write-Host "   Then create a workspace and add the same group as Workspace Contributor."
Write-Host ""
Write-Host "   --- Purview Data Reader (Governance demo) ---"
Write-Host "   Go to Purview Studio for account '$($outputs.purviewAccountName.value)'"
Write-Host "   Data Map -> Collections -> Root -> Role assignments -> Data Readers -> Add"
Write-Host "       $WorkshopGroupDisplayName  ($WorkshopGroupObjectId)"
Write-Host ""

# ---------------------------------------------------------------------------
# 3) SQL CREATE USER + table setup
# ---------------------------------------------------------------------------
if ($RunSqlSetup) {
    if (-not $WorkshopGroupDisplayName) {
        throw "-RunSqlSetup requires -WorkshopGroupDisplayName so the T-SQL CREATE USER FROM EXTERNAL PROVIDER can target the right principal."
    }

    $sqlScript = Join-Path $projectRoot 'Allfiles/lab03/setup-sql-vector.sql'
    if (-not (Test-Path $sqlScript)) {
        throw "Cannot find SQL setup script at $sqlScript"
    }

    $server = $outputs.sqlServerFqdn.value
    $database = $outputs.sqlDatabaseName.value
    if (-not $server) {
        Write-Warning "[3/3] SQL was skipped at deploy time (no sqlServerFqdn output). Skipping SQL setup."
    } else {
        Write-Host "[3/3] Running SQL VECTOR setup on $server / $database..."
        $tmp = New-TemporaryFile
        try {
            (Get-Content $sqlScript -Raw) `
                -replace '\$\(WORKSHOP_GROUP_NAME\)', $WorkshopGroupDisplayName `
                | Set-Content -Path $tmp.FullName -Encoding utf8
            sqlcmd -S $server -d $database -G -I -i $tmp.FullName
            if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed with exit $LASTEXITCODE" }
        } finally {
            Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
        }
        Write-Host "      Done. The demo 'documents' VECTOR(1536) table is ready."
    }
} else {
    Write-Host "[3/3] Skipped SQL setup (pass -RunSqlSetup to run setup-sql-vector.sql)."
}

Write-Host ""
Write-Host "All Day 2 access grants complete (or queued for portal admin)."
