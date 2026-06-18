<#
.SYNOPSIS
    Teardown - delete the workshop resources INSIDE the resource group.

.DESCRIPTION
    Deletes every resource inside the selected resource group but leaves the
    resource group itself in place (you own / selected it). Azure AI Foundry
    (Cognitive Services) accounts support SOFT DELETE, so after the resources
    are removed this script also purges any soft-deleted Foundry accounts that
    belonged to the group, keeping redeploys reliable.

    Role assignments are NOT removed here — run revoke-resource-access.ps1 and
    revoke-user-access.ps1 first if you want to revoke access too.

.PARAMETER ResourceGroup
    Target resource group. Defaults to the one recorded by deploy.ps1.

.EXAMPLE
    ./scripts/destroy.ps1 -ResourceGroup rg-zava-sandbox
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [int]$MaxPasses = 6
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

# Delete every resource in the group without deleting the group itself. Several
# passes resolve dependency ordering (e.g. a child resource that must go before
# its parent).
function Remove-ResourceGroupContents {
    param(
        [string]$ResourceGroup,
        [int]$MaxPasses = 6
    )

    for ($pass = 1; $pass -le $MaxPasses; $pass++) {
        $ids = @(az resource list --resource-group $ResourceGroup --query '[].id' -o tsv |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($ids.Count -eq 0) {
            Write-Host "  Resource group '$ResourceGroup' is empty."
            return
        }
        Write-Host "  Pass ${pass}: deleting $($ids.Count) resource(s)..."
        az resource delete --ids @ids --only-show-errors 2>$null | Out-Null
    }

    $remaining = @(az resource list --resource-group $ResourceGroup --query '[].id' -o tsv |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($remaining.Count -gt 0) {
        Write-Warning "Some resources could not be deleted automatically:`n  $($remaining -join "`n  ")"
        Write-Warning 'Re-run ./scripts/destroy.ps1, or delete them manually in the Azure portal.'
    }
}

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot
try {
    $ResourceGroup = Resolve-ResourceGroup -ResourceGroup $ResourceGroup

    $exists = (az group exists --name $ResourceGroup -o tsv)
    if ($exists -ne 'true') {
        Write-Host "Resource group '$ResourceGroup' does not exist; nothing to delete."
        return
    }

    Write-Host "== Deleting workshop resources in resource group '$ResourceGroup' =="
    Remove-ResourceGroupContents -ResourceGroup $ResourceGroup -MaxPasses $MaxPasses

    # Belt-and-suspenders: ensure no soft-deleted Foundry account lingers.
    Clear-SoftDeletedFoundryAccounts -ResourceGroup $ResourceGroup

    # The recorded outputs are now stale (the resources are gone).
    $outputsFile = Join-Path $projectRoot '.azure/main-outputs.json'
    if (Test-Path $outputsFile) {
        Remove-Item $outputsFile -Force
    }

    Write-Host ''
    Write-Host "Done. Resource group '$ResourceGroup' was kept; its resources were deleted."
}
finally {
    Pop-Location
}