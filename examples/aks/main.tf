
terraform {
  required_providers {
    azurerm = {
      version = "2.78"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_virtual_network" "network" {
  name                = "${lower(var.name)}-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space = [var.network_cidr]
}

resource "azurerm_subnet" "subnet" {
  name                = "default"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = [var.kube_sub_network_cidr]
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_user_assigned_identity" "userid" {
  name                = "kubernetes-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_version  = var.kubernetes_version
  dns_prefix = var.name
  
  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = var.default_node_pool_vm_size
    vnet_subnet_id = azurerm_subnet.subnet.id
    orchestrator_version  = var.kubernetes_version
  }

  network_profile {
    # We support only 'azure' as network_plugin at the moment
    network_plugin      = "azure"
    load_balancer_sku   = var.load_balancer_sku
  }
  
  linux_profile {
    admin_username = var.admin_username
    ssh_key {
      key_data = file(var.ssh_key_file)
    }
  }
  
  role_based_access_control {
    enabled = true
  }
  
  identity {
    type = "UserAssigned"
    user_assigned_identity_id = azurerm_user_assigned_identity.userid.id
  }
}