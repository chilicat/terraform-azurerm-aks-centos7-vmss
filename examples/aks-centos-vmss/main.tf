
module "centos7-vmss" {
  source  = "chilicat/centos7-vmss/azurerm"
  version = ">0"
  resource_group_name = var.resource_group_name
  aks_name            = var.aks_name
  name                = var.name
}

