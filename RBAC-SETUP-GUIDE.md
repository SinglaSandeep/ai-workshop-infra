# Day 2 Data Platform - RBAC Setup Guide

## Overview

This guide explains how to grant 100+ workshop participants access to Day 2 Data Platform resources using Azure RBAC with Entra Security Groups.

## Architecture

```
Single Azure Deployment (Shared Resources)
├── Azure OpenAI          → 100 users via RBAC
├── Azure ML Workspace    → 100 users via RBAC
├── Storage (ADLS Gen2)   → 100 users via RBAC
├── Key Vault             → 100 users via RBAC
└── PostgreSQL (optional) → 100 users via RBAC

Each participant creates their own FREE Fabric workspace
```

## Prerequisites

1. **Azure Resources Deployed**
   ```bash
   azd up
   ```
   This creates all Day 2 infrastructure.

2. **Entra Security Group Created**
   - Go to Azure Portal → Entra ID → Groups
   - Create new Security Group: `PepsiCo-Workshop-Participants`
   - Copy the **Object ID** (e.g., `aaaa-bbbb-cccc-dddd`)

3. **Add Participants to Group**
   - Add all 100+ participant email addresses to the security group
   - OR invite them as guests first, then add to group

## Quick Setup (3 Steps)

### Step 1: Update Parameters File

Edit `infra/user-access-day2.parameters.json`:

```json
{
  "workshopUsers": {
    "value": [
      {
        "principalId": "aaaa-bbbb-cccc-dddd",  // Your security group Object ID
        "principalType": "Group"
      }
    ]
  },
  "userAccess": {
    "value": {
      "enableAzureOpenAI": true,
      "enableAzureML": true,
      "enableStorage": true,
      "enableKeyVault": true,
      "enablePostgreSQL": false  // Set true if using PostgreSQL
    }
  }
}
```

**Important:**
- Replace `aaaa-bbbb-cccc-dddd` with your actual security group Object ID
- Use `"principalType": "Group"` for groups, `"User"` for individual users
- You can add multiple groups or users to the array

### Step 2: Grant Permissions

Run the grant script:

```powershell
.\scripts\grant-user-access-day2.ps1
```

This grants all group members:
- **Azure OpenAI**: Cognitive Services User (inference only, no deployments)
- **Azure ML**: AzureML Data Scientist (run experiments, submit jobs)
- **Storage**: Storage Blob Data Contributor (read/write Lakehouse data)
- **Key Vault**: Key Vault Secrets User (read connection strings)
- **PostgreSQL**: Reader role (data plane access via SQL GRANT)

### Step 3: Verify

Check role assignments in Azure Portal:
```
Resource → Access control (IAM) → Role assignments
```

You should see your security group with the assigned roles.

## Permissions Breakdown

| Resource | Role | What Participants Can Do | What They CANNOT Do |
|----------|------|--------------------------|---------------------|
| Azure OpenAI | Cognitive Services User | Run chat completions, embeddings | Deploy models, change config |
| Azure ML | AzureML Data Scientist | Submit jobs, train models, read datasets | Delete workspace, change compute |
| Storage | Storage Blob Data Contributor | Upload/download Lakehouse data | Delete storage account, change config |
| Key Vault | Key Vault Secrets User | Read connection strings, API keys | Create/delete secrets, change policies |
| PostgreSQL | Reader | Connect to database (via SQL GRANT) | Change server config, create databases |

## Advanced Usage

### Add Individual Users (Testing)

For testing, you can add individual users instead of a group:

```json
{
  "workshopUsers": {
    "value": [
      {
        "principalId": "user1-object-id",
        "principalType": "User"
      },
      {
        "principalId": "user2-object-id",
        "principalType": "User"
      }
    ]
  }
}
```

### Multiple Security Groups

You can grant access to multiple groups:

```json
{
  "workshopUsers": {
    "value": [
      {
        "principalId": "group1-object-id",
        "principalType": "Group"
      },
      {
        "principalId": "group2-object-id",
        "principalType": "Group"
      }
    ]
  }
}
```

### Selective Permissions

Disable specific resources if not used in your labs:

```json
{
  "userAccess": {
    "value": {
      "enableAzureOpenAI": true,
      "enableAzureML": false,        // Disable if not using LAB 04
      "enableStorage": true,
      "enableKeyVault": false,       // Disable if not needed
      "enablePostgreSQL": false      // Use Cosmos DB instead
    }
  }
}
```

## PostgreSQL Special Setup

PostgreSQL requires additional data plane configuration:

1. **Connect as admin** to the PostgreSQL database
2. **Grant database permissions** via SQL:

```sql
-- For each participant or group
GRANT CONNECT ON DATABASE vectordb TO "user@domain.com";
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO "user@domain.com";
GRANT USAGE ON SCHEMA public TO "user@domain.com";
```

Or use Entra group name:
```sql
GRANT CONNECT ON DATABASE vectordb TO "PepsiCo-Workshop-Participants";
```

## Revoke Access (Post-Workshop)

To remove all Day 2 permissions after the workshop:

```powershell
.\scripts\revoke-user-access-day2.ps1
```

This removes all RBAC role assignments but keeps the resources running.

To delete everything (resources + permissions):

```bash
azd down --purge
```

## Troubleshooting

### Error: "principalId not found"

**Problem**: The Object ID doesn't exist in Entra ID

**Solution**:
1. Verify the Object ID in Azure Portal → Entra ID → Groups
2. Make sure it's the **Object ID**, not the Group Name
3. Ensure the group is in the same tenant as the Azure subscription

### Participants Can't Access Resources

**Problem**: Users added to group after RBAC was granted

**Solution**: RBAC updates automatically when group membership changes. Wait 5-10 minutes for propagation.

### PostgreSQL Connection Fails

**Problem**: Reader role doesn't grant database access automatically

**Solution**: Run SQL GRANT commands (see PostgreSQL Special Setup above)

## Cost Optimization

**Shared Resources Model:**
- 1 deployment serves 100 participants
- Total cost: $20-40 for 3-day workshop
- vs. $20,000+ for 100 separate deployments

**After Workshop:**
```bash
azd down --purge  # Delete everything
```

## Security Best Practices

1. ✅ **Use Security Groups** instead of individual users (easier management)
2. ✅ **Least Privilege**: Only enable resources participants actually need
3. ✅ **Time-Limited**: Revoke access immediately after workshop
4. ✅ **Audit Logs**: Monitor access via Azure Monitor
5. ✅ **No Admin Rights**: Participants can use but not delete/modify resources

## Day 1 + Day 2 Combined RBAC

If you deployed both Day 1 (AI Foundry) and Day 2 (Data Platform):

```powershell
# Grant Day 1 permissions (AI Foundry, AI Search, Cosmos DB)
.\scripts\grant-user-access.ps1

# Grant Day 2 permissions (Azure OpenAI, AML, Storage)
.\scripts\grant-user-access-day2.ps1
```

Participants get access to **all resources** from a single security group.

## Next Steps

After granting RBAC:
1. Share resource endpoints with participants (from `.azure/main-outputs.json`)
2. Participants follow [PARTICIPANT-SETUP-GUIDE.md](PARTICIPANT-SETUP-GUIDE.md) to create Fabric workspaces
3. Start workshop labs!

## Support

For issues or questions:
- Check Azure Portal → Resource → Activity Log for RBAC errors
- Verify security group membership propagated (wait 5-10 minutes)
- Ensure participants use correct Entra account (not personal Microsoft account)
