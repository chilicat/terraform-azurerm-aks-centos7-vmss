provider "azurerm" {
  features {}
}

locals {
    // Parse subnet information from ID:
    // /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/default
    parse_subnet_reg    = "(?i)^/Subscriptions/(?P<subscription_id>[^/]+)/resourceGroups/(?P<resource_group>[^/]+)/providers/.+/.+/(?P<vnet_name>[^/]+)/subnets/(?P<subnet_name>[^/]+)$"
    subnet_info         = regex(local.parse_subnet_reg, data.azurerm_kubernetes_cluster.aks.agent_pool_profile[0].vnet_subnet_id)
    
    // /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/networkSecurityGroups/<aks-nsg>
    parse_nsg_reg       = "(?i)^/Subscriptions/(?P<subscription_id>[^/]+)/resourceGroups/(?P<resource_group>[^/]+)/providers/.+/.+/(?P<name>[^/]+)$"
    nsg_info            = regex(local.parse_nsg_reg, data.azurerm_virtual_machine_scale_set.main_scale_set.network_interface[0].network_security_group_id)
    
    // Parse AKS VMSS information from ID:
    // /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Compute/virtualMachineScaleSets/<vmss>/virtualMachines/0/networkInterfaces/<vmss>/ipConfigurations/ipconfig1
    parse_vmss_reg      = "(?i)^/Subscriptions/(?P<subscription_id>[^/]+)/resourceGroups/(?P<resource_group>[^/]+)/providers/Microsoft.Compute/virtualMachineScaleSets/(?P<name>[^/]+)/.*$" 
    vmss_info        = regex(local.parse_vmss_reg, data.azurerm_lb_backend_address_pool.aksOutboundBackendPool.backend_ip_configurations[0].id)
    
    lb_address_pool_ids = [ data.azurerm_lb_backend_address_pool.aksOutboundBackendPool.id, data.azurerm_lb_backend_address_pool.kubernetes.id ]

    vnet_subnet_id = data.azurerm_kubernetes_cluster.aks.agent_pool_profile[0].vnet_subnet_id
    nsg_id = data.azurerm_virtual_machine_scale_set.main_scale_set.network_interface[0].network_security_group_id

    user_identity = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].user_assigned_identity_id

    // resourceNameSuffix of default VMSS
    // "routeTableName": "aks-agentpool-28141608-routetable",
    // aks-agentpool-{resourceNameSuffix}-routetable
    // resourceNameSuffix = data.azurerm_resources.agent_pool.resources[0].tags.resourceNameSuffix

    scale_set_name = "aks-${var.name}-centos-vmss"
    
    azure_json_tpl = templatefile("${path.module}/templates/azure.json", {
       tenantId =  data.azurerm_client_config.current.tenant_id
       subnetName = local.subnet_info.subnet_name
       securityGroupName = local.nsg_info.name
       vnetName = local.subnet_info.vnet_name
       vnetResourceGroup = local.subnet_info.resource_group
       userAssignedIdentityID = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].client_id
       subscriptionId  = data.azurerm_client_config.current.subscription_id
       resourceGroup = data.azurerm_kubernetes_cluster.aks.node_resource_group 
       location = data.azurerm_resource_group.node_rg.location
       primaryScaleSetName = local.scale_set_name
    })

    kubelet_env = templatefile("${path.module}/templates/kubelet-env.sh", {
        resource_group_name = local.subnet_info.resource_group
        agentpool = var.name
    })

    kubelet_config = templatefile("${path.module}/templates/kubelet-config.yaml", {
        dns_service_ip = data.azurerm_kubernetes_cluster.aks.network_profile[0].dns_service_ip
    })

    install_script = filebase64("${path.module}/templates/install.sh")
    cloudinit = templatefile("${path.module}/templates/cloud-init.tpl", {
        azure_json      = local.azure_json_tpl
        kubeconfig_raw  = data.azurerm_kubernetes_cluster.aks.kube_config_raw
        kubeconfig      = data.azurerm_kubernetes_cluster.aks.kube_config[0] 
        kubelet_env     = local.kubelet_env
        kubelet_config  = local.kubelet_config
        install_script  = local.install_script
    })
}

data "azurerm_client_config" "current" {
  # Requiered to get current subscription and tenant data
}

# Terraform has no default way to fail if some configuration is unexpected or precondition has not meet.
# Let's use this little trick to fail if the configuration of AKS is not as expected.
# https://github.com/hashicorp/terraform/issues/15469#issuecomment-814789329
resource "null_resource" "is_aks_network_plugin_correct" {
  count = data.azurerm_kubernetes_cluster.aks.network_profile[0].network_plugin == "azure" ? 0 : "The Centos AKS Node Poll supports only AKS cluster using the 'azure' network at the moment"
}

data "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  resource_group_name = var.resource_group_name
}

data "azurerm_resource_group" "node_rg" {
  name = data.azurerm_kubernetes_cluster.aks.node_resource_group 
}

data "azurerm_subnet" "subnet" {
  name                 = local.subnet_info.subnet_name
  virtual_network_name = local.subnet_info.vnet_name
  resource_group_name  = local.subnet_info.resource_group
}

// AKS creates by default a "kubernetes" load balancer.
// We use this resource to extract further information.
data "azurerm_lb" "lb" {
  name                = "kubernetes"
  resource_group_name = data.azurerm_kubernetes_cluster.aks.node_resource_group 
}

data "azurerm_lb_backend_address_pool" "aksOutboundBackendPool" {
  name            = "aksOutboundBackendPool"
  loadbalancer_id = data.azurerm_lb.lb.id
}

data "azurerm_lb_backend_address_pool" "kubernetes" {
  name            = "kubernetes"
  loadbalancer_id = data.azurerm_lb.lb.id
}

// The main scale set is the default scale set of the AKS instance
// We use this instance to get some basic data requiered to 
// setup the centos VMSS
data "azurerm_virtual_machine_scale_set" "main_scale_set" {
  name                = local.vmss_info.name
  resource_group_name = data.azurerm_kubernetes_cluster.aks.node_resource_group 
}

// ------------------------------

// cloud-init template to bootstrap cloudux vms
data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content      = local.cloudinit
  }
}

resource "azurerm_linux_virtual_machine_scale_set" "centos_vmss" {
  // Let's make sure AKS is configured as expected.
  depends_on = [
    null_resource.is_aks_network_plugin_correct
  ]

  name                = local.scale_set_name
  resource_group_name = data.azurerm_kubernetes_cluster.aks.node_resource_group 
  location            = data.azurerm_resource_group.node_rg.location
  sku                 = var.centos_vm_size
  instances           = var.instances
  admin_username      = var.admin_username
  admin_ssh_key {
    public_key = file(var.ssh_key_file)
    username = var.admin_username
  }
  
  source_image_reference {
    publisher                   = var.image_publisher
    offer                       = var.image_offer
    sku                         = var.image_sku
    version                     = var.image_version
  }

  custom_data   = data.template_cloudinit_config.config.rendered
  zones         = var.zones
  overprovision = false 
    
  tags = {
      poolName = var.name
  }
  
  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  identity  {
      type = "UserAssigned"
      identity_ids = [
          local.user_identity
      ]
  }
  network_interface {
    name    = "${local.scale_set_name}-net"
    primary = true
    network_security_group_id = local.nsg_id
    
    ip_configuration {
      name      = "ipconfig1"
      primary   = true
      subnet_id = local.vnet_subnet_id
      load_balancer_backend_address_pool_ids  = local.lb_address_pool_ids
    }

    // Azure network plugin requires that we define ip addresses for the pods.
    // The pod count for a Node is limited by provided ip_configuration's
    dynamic "ip_configuration" {
      for_each = range(2, 31)
      content {
        name      = "ipconfig${ip_configuration.value}"
        primary   = false
        subnet_id = local.vnet_subnet_id
      }
    }
  }
}