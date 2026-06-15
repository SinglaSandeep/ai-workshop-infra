param(
    [switch]$Force = $true,
    [switch]$Purge = $true
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
    $arguments = @('down')
    if ($Force) {
        $arguments += '--force'
    }
    if ($Purge) {
        $arguments += '--purge'
    }

    azd @arguments
}
finally {
    Pop-Location
}