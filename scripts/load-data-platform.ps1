<#
.SYNOPSIS
    Part B-Data - Load the Lab 03 vector data into Azure SQL and seed secrets into Key Vault.

.DESCRIPTION
    Uses deployment outputs from Part A to:
      1. Grant the operator temporary SQL admin + AOAI Cognitive Services User access.
      2. Run embed_and_load.py to populate the vector table in Azure SQL.
      3. Store endpoints/keys in Key Vault for participant consumption.

    Run AFTER scripts/deploy.ps1. Requires the pepsico-msft-workshop repo cloned.

.PARAMETER WorkshopPath
    Path to a local clone of the pepsico-msft-workshop repository.

.EXAMPLE
    ./scripts/load-data-platform.ps1 -WorkshopPath C:\dev\pepsico-msft-workshop
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkshopPath,

    [Parameter(Mandatory = $false)]
    [string]$OperatorObjectId,

    [Parameter(Mandatory = $false)]
    [string]$MainOutputsFile = '.azure/main-outputs.json',

    [switch]$SkipVectorLoad,
    [switch]$SkipKeyVault
)

$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-AzdEnvValues {
    $values = @{}
    $lines = azd env get-values 2>$null
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $values[$matches[1]] = $matches[2].Trim('"')
        }
    }
    return $values
}

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot
try {
    if (-not (Test-Path $WorkshopPath)) {
        throw "WorkshopPath '$WorkshopPath' does not exist."
    }
    if (-not (Test-Path $MainOutputsFile)) {
        throw "Deployment outputs '$MainOutputsFile' not found. Run ./scripts/deploy.ps1 first."
    }

    $outputs = Get-Content $MainOutputsFile -Raw | ConvertFrom-Json -Depth 50
    $names = $outputs.resourceNames.value
    $endpoints = $outputs.endpoints.value

    $envValues = Get-AzdEnvValues
    $resourceGroup = $envValues['AZURE_RESOURCE_GROUP']
    $subscriptionId = (az account show --query id -o tsv)

    if ([string]::IsNullOrWhiteSpace($OperatorObjectId)) {
        $OperatorObjectId = az ad signed-in-user show --query id -o tsv 2>$null
    }
    if ([string]::IsNullOrWhiteSpace($OperatorObjectId)) {
        throw 'Could not resolve an operator object id. Pass -OperatorObjectId explicitly.'
    }

    # --- Step 1: Operator data-plane grants --------------------------------
    Write-Host '== Granting operator data-load roles for the data platform =='

    # Cognitive Services User on the OpenAI account (to call embeddings API)
    if ($names.openAi) {
        $aoaiScope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$($names.openAi)"
        az role assignment create --assignee-object-id $OperatorObjectId --assignee-principal-type User `
            --role 'a97b65f3-24c7-4388-baec-2e87135dc908' --scope $aoaiScope --only-show-errors | Out-Null
        Write-Host "  Cognitive Services User -> $($names.openAi)"
    }

    Write-Host 'Waiting 30s for role assignments to propagate...'
    Start-Sleep -Seconds 30

    # --- Step 2: Create vector table and load embeddings -------------------
    if (-not $SkipVectorLoad) {
        Write-Host '== Creating vector table and loading embeddings into Azure SQL =='

        $lab03Path = Join-Path $WorkshopPath 'Allfiles/lab03'
        if (-not (Test-Path $lab03Path)) {
            throw "Lab 03 files not found at '$lab03Path'. Is WorkshopPath correct?"
        }

        Push-Location $lab03Path
        try {
            # Set environment variables for the embed script
            $env:AOAI_ENDPOINT = $endpoints.openAiEndpoint
            $env:AOAI_EMBED_DEPLOYMENT = 'text-embedding-3-small'
            $env:SQL_SERVER = $endpoints.sqlServerFqdn
            $env:SQL_DATABASE = $names.sqlDatabase

            Write-Host "  AOAI_ENDPOINT = $($env:AOAI_ENDPOINT)"
            Write-Host "  SQL_SERVER    = $($env:SQL_SERVER)"
            Write-Host "  SQL_DATABASE  = $($env:SQL_DATABASE)"

            # Create the vector table first (via sqlcmd or az sql query)
            $createTableSql = @"
IF OBJECT_ID('dbo.product_docs', 'U') IS NOT NULL DROP TABLE dbo.product_docs;
CREATE TABLE dbo.product_docs (
    doc_id      INT IDENTITY PRIMARY KEY,
    product_id  NVARCHAR(50)     NOT NULL,
    title       NVARCHAR(200)    NOT NULL,
    content     NVARCHAR(MAX)    NOT NULL,
    embedding   VECTOR(1536)     NOT NULL,
    created_at  DATETIME2        DEFAULT SYSUTCDATETIME()
);
"@
            Write-Host '  Creating dbo.product_docs table...'
            az sql db execute --resource-group $resourceGroup --server-name $names.sqlServer `
                --database-name $names.sqlDatabase --query-text $createTableSql --only-show-errors | Out-Null

            # Install Python deps and run the embedder
            if (-not (Test-Path '.venv')) {
                python -m venv .venv
            }
            & .\.venv\Scripts\Activate.ps1
            pip install -r requirements.txt --quiet

            python embed_and_load.py product_descriptions.json
        }
        finally {
            Pop-Location
        }
    }

    # --- Step 3: Seed Key Vault secrets ------------------------------------
    if (-not $SkipKeyVault -and $names.keyVault) {
        Write-Host '== Seeding Key Vault secrets =='
        $kvName = $names.keyVault

        az keyvault secret set --vault-name $kvName --name 'aoai-endpoint' --value $endpoints.openAiEndpoint --only-show-errors | Out-Null
        az keyvault secret set --vault-name $kvName --name 'aoai-embed-deployment' --value 'text-embedding-3-small' --only-show-errors | Out-Null
        az keyvault secret set --vault-name $kvName --name 'sql-server-fqdn' --value $endpoints.sqlServerFqdn --only-show-errors | Out-Null
        az keyvault secret set --vault-name $kvName --name 'sql-database' --value $names.sqlDatabase --only-show-errors | Out-Null

        Write-Host "  Secrets written to Key Vault: $kvName"
    }

    Write-Host ''
    Write-Host 'Data platform load complete.'
    Write-Host 'Next steps:'
    Write-Host '  Part C - resource access:  ./scripts/grant-resource-access.ps1'
    Write-Host '  Part D - user access:      ./scripts/grant-user-access.ps1'
}
finally {
    Pop-Location
}
