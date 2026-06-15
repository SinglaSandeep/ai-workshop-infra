param workshopConfig object

var defaults = {
  Project: workshopConfig.workshopName
  Environment: workshopConfig.environmentName
  ManagedBy: 'azd'
}

output tags object = union(defaults, workshopConfig.tags)
