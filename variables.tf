variable "name" {
    description = "Base name for VMSS"
}

variable "resource_group_name" {
    description = "Resource group name where the AKS instances is deployed"
}

variable "aks_name" {
    description = "Name of the existing AKS instance"
}

variable "ssh_key_file" {
    description = "Admin user public ssh key"
    default = "~/.ssh/id_rsa.pub"
}

variable "admin_username" {
    description = "Admin user name"
    default = "adminuser"
}

variable "centos_vm_size" {
    description = "VM Size for Centos VMs"
    default = "Standard_B2s"
}

variable "instances" {
    description = "Count of instances"
    default = 1
}

variable "image_publisher" {
    default = "OpenLogic"
}

variable "image_offer" {
    default = "CentOS"
}

variable "image_sku" {
    default = "7_9-gen2"
}

variable "image_version" {
    default = "latest"
}

variable "zones" {
    default = [ 1, 2, 3 ]
}