# Scripts

Run these from the repository root in PowerShell, in order. Each maps to one
part of the workshop provisioning flow.

| Order | Script | Part | What it does |
| ----- | ------ | ---- | ------------ |
| 1 | `deploy.ps1` | A - Infra | Deploys `infra/main.bicep` into the **existing** resource group you pass with `-ResourceGroup` (never creates one), then exports outputs to `.azure/main-outputs.json`. |
| 2 | `load-data.ps1` | B - Data | Seeds Cosmos DB and builds the marketing knowledge base, and writes the workshop `.env`. |
| 3 | `grant-resource-access.ps1` | C - Resource access | Grants the service principals / apps in `resource-access.parameters.json` Contributor on the resource group. |
| 4 | `grant-user-access.ps1` | D - User access | Grants participants Contributor on the resource group. |
| - | `deploy-user-projects.ps1` | D - User access (isolation) | **Optional.** Creates multiple isolated Foundry **projects** (listed in `infra/foundry-projects.txt`) in the same account and grants one Entra group Azure AI User on every project. |
| - | `revoke-resource-access.ps1` | C - Resource access | Removes the service-principal / app grants (optional). |
| - | `revoke-user-access.ps1` | D - User access | Removes the participant grants (optional). |
| - | `destroy.ps1` | Teardown | Deletes every resource **inside** the resource group but keeps the group itself. |

See the top-level [README.md](../README.md) for full, beginner-friendly
instructions including tool installation.
