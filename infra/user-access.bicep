targetScope = 'resourceGroup'

@description('Workshop users (people or Entra groups) that receive participant access. Principal IDs must already exist in Entra ID.')
param workshopUsers array

@description('Configurable participant access level (resource group role). See user-access.parameters.json.')
param userAccess object

// ---------------------------------------------------------------------------
// Built-in role definition (configurable in user-access.parameters.json).
//  - resourceGroup: control-plane role granted at the resource group scope so
//    participants can use every resource in the workshop RG (default
//    Contributor). With key-based auth enabled, Contributor lets participants
//    read the resource keys / connection settings they need.
// ---------------------------------------------------------------------------
var resourceGroupRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', userAccess.resourceGroup.roleDefinitionId)

// ---------------------------------------------------------------------------
// Assignments — one per workshop user/group: resource group Contributor.
// ---------------------------------------------------------------------------
resource userResourceGroupAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for user in workshopUsers: {
  name: guid(resourceGroup().id, user.objectId, 'workshop-user-rg-contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: resourceGroupRoleId
    principalId: user.objectId
    principalType: user.principalType
  }
}]

output summary object = {
  usersGranted: length(workshopUsers)
  resourceGroupRoleName: userAccess.resourceGroup.roleName
}
