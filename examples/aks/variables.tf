variable "name" {
    description = "Name of AKS instance"
    default = "aks"
}

variable "resource_group_name" {
    description = "Resource group for AKS instance"
}

variable "location" {
    description = "Location of AKS instance"
    default = "westeurope"
}

variable "kubernetes_version" {
    description = "Kubernetes version"
    default = "1.20.9"
}

variable "default_node_pool_vm_size" {
    description = "VM size of VMs in AKS default node pool"
    default = "Standard_B2s"
}

variable "ssh_key_file" {
    description = "SSK public key file"
    default = "~/.ssh/id_rsa.pub"
}

variable "admin_username" {
    description = "Admin user name for AKS VM instances"
    default = "adminuser"
}

variable "load_balancer_sku" {
    description = "AKS load balancer SKU"
    default = "Standard"
}

// ============
// Network
// ============
variable "network_cidr" {
    description = "AKS network CIDR"
    default = "10.0.0.0/8"
}

variable "kube_sub_network_cidr" {
    description = "AKS subnetwork CIDR"
    default = "10.240.0.0/16"
}