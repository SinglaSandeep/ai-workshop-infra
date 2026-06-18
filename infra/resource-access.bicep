targetScope = 'resourceGroup'

// ===========================================================================
// Part C — Resource (service / app) access.
//
// Grants the workshop's service principals or apps access at the resource
// group scope (default Contributor) so they can use every resource in the
// workshop RG. Services authenticate to each other with keys / connection
// settings (no managed identities), so no per-resource role assignments are
// needed.
// ===========================================================================

@description('Service principals / apps that receive resource-group access. Object IDs must already exist in Entra ID.')
param servicePrincipals array

@description('Configurable resource-group access level (default Contributor). See resource-access.parameters.json.')
param resourceAccess object

var resourceGroupRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', resourceAccess.roleDefinitionId)

// One resource-group role assignment per service principal / app.
resource servicePrincipalAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for sp in servicePrincipals: {
  name: guid(resourceGroup().id, sp.objectId, 'resource-access-rg-role')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: resourceGroupRoleId
    principalId: sp.objectId
    principalType: sp.principalType
  }
}]

output summary object = {
  principalsGranted: length(servicePrincipals)
  resourceGroupRoleName: resourceAccess.roleName
}
