# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.28"
    }
  }
}

# Identify the provider
provider "azurerm" {
  features {}
}

variable "vm" {
	type = map(string)
	default = {
		admin 					= "tdsan"
		rg 						= "it-az-rg"
		location 				= "eastus"
		vnet                    = "itots-vnet"
		subnet 					= "itots-subnet"
		cidr 					= "10.10.0.0/16"
		sap 					= "45.37.66.254"
	}
}

# Create admin password for vm
variable "admin_password" {
	type = string
	description = "Enter Admin password for VM"
}

# Create admin password for vm
variable "admin_username" {
	type = string
	default = "tdsan"
	description = "Enter Admin username for VM"
}

# Create Computer name
variable "vm_name" {
	type							= string
	description 					= "Enter Virtual Machine Name"
}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
	name							= var.vm.rg
	location						= var.vm.location
}

# Create Virtual Network
resource "azurerm_virtual_network" "vnet" {
	name 							= "${var.vm.rg}-vnet"
	address_space 					= [var.vm.cidr]
	location 						= azurerm_resource_group.rg.location
	resource_group_name 			= azurerm_resource_group.rg.name
	vm_protection_enabled			= true
}

# Create Subnet from vNet
resource "azurerm_subnet" "subnet" {
	name 							= "${var.vm.rg}-subnet"
	resource_group_name 			= azurerm_resource_group.rg.name
	virtual_network_name 			= azurerm_virtual_network.vnet.name
	address_prefixes 				= [cidrsubnet(var.vm.cidr, 8, 1)]
	enforce_private_link_endpoint_network_policies = true
	enforce_private_link_service_network_policies = true
}

# Create Public IP
resource "azurerm_public_ip" "publicip" {
	name 							= "${var.vm_name}-pip"
	location 						= azurerm_resource_group.rg.location
	resource_group_name 			= azurerm_resource_group.rg.name
	allocation_method 				= "Dynamic"
	ip_version 						= "IPv4"
}

locals {
	ports = {
		"SSH"	= { pri = 995, dst = 22, sap = var.vm.sap },
		"SSH2"	= { pri = 996, dst = 2222, sap = var.vm.sap },
		"RDP"	= { pri = 997, dst = 3389, sap = var.vm.sap },
		"HTTP"	= { pri = 998, dst = 80, sap = "*" },
		"HTTPS"	= { pri = 999, dst = 443, sap = "*" }
		"Appl"	= { pri = 1000, dst = 8080, sap = "*" }
	}
}

# Create Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name								= "${azurerm_resource_group.rg.name}-nsg"
  location							= azurerm_resource_group.rg.location
  resource_group_name				= azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "ports" {
	for_each						= local.ports
      name     						= each.key
      priority 						= each.value.pri
	  direction						= "Inbound"
	  access						= "Allow"
	  protocol						= "Tcp"
	  source_port_range				= "*"
	  destination_port_range		= each.value.dst
	  source_address_prefix			= each.value.sap
	  destination_address_prefix	= "*"
	  resource_group_name			= azurerm_resource_group.rg.name
	  network_security_group_name	= azurerm_network_security_group.nsg.name
	}

resource "azurerm_network_interface" "nic" {
	name = "${var.vm_name}-nic"
	location = azurerm_resource_group.rg.location
	resource_group_name = azurerm_resource_group.rg.name

	ip_configuration {
		name 							= "${var.vm_name}-ipcfg"
		subnet_id 						= azurerm_subnet.subnet.id
		private_ip_address_allocation 	= "Dynamic"
		public_ip_address_id 			= azurerm_public_ip.publicip.id
	}
}

resource "azurerm_virtual_machine" "vm" {
	name								= var.vm_name
	location							= azurerm_resource_group.rg.location
	resource_group_name					= azurerm_resource_group.rg.name
	network_interface_ids				= [azurerm_network_interface.nic.id]
	vm_size								= "Standard_B2s"
	delete_os_disk_on_termination 		= true
	delete_data_disks_on_termination 	= true
	
	storage_os_disk {
		name							= "${var.vm_name}-osdisk"
		caching							= "ReadWrite"
		create_option					= "FromImage"
		managed_disk_type				= "StandardSSD_LRS"
		disk_size_gb					= 30
		write_accelerator_enabled 		= false # Must be set to false
	}

	storage_image_reference {
		publisher  						= "OpenLogic"
		offer 							= "CentOS"
		sku								= "8_2-gen2"
		version							= "latest"
	}

	os_profile {
		computer_name 					= var.vm_name
		admin_username					= var.admin_username
		admin_password					= var.admin_password
	}

	os_profile_linux_config {
		disable_password_authentication = false
	}
}

resource "azurerm_network_interface_security_group_association" "assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}