#terraform {
#  backend "azurerm" {
#  }
#}

provider "azurerm" {
  version = "=2.0.0"
  features {}
}

variable "vm_count" {
  description = "Number of VMs to build"
}

variable "region" {
  description = "Azure region"
}

variable "vnet_name" {
  description = "new vnet name"
}

variable "subnet_name" {
  description = "new subnet name"
}

variable "vnet_address_space" {
  description = "new vnet ip address CIDR"
}

variable "subnet_address_prefix" {
  description = "subnet CIDR address for vnet"
}

variable "nsg_name" {
  description = "name for network security group"
}

variable "vmusername" {
  description = "windows server username"
}

variable "vmpassword" {
  description = "password for windows server username"
}


#------------------------------------------------------------------#
# Create random name and hex for generating unique service names   #
#------------------------------------------------------------------#

# Create random_id for use throughout the plan
resource "random_id" "random_name" {
  prefix      = "sampleenv"
  byte_length = "4"
}

#---------------------------------------------#
# Create Resource Group                       #
#---------------------------------------------#

# Create a resource group
resource "azurerm_resource_group" "production" {
  name     = lower(random_id.random_name.hex)
  location = var.region
}

#-------------------------------------#
# Create Network Components:          #
# 1. Virtual Network & Subnets        #
# 2. Network Security Groups          #
# 3. Network Interfaces               #
#-------------------------------------#

# Create a virtual network in the production resource group
resource "azurerm_virtual_network" "prodvnet" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name
}

  resource "azurerm_subnet" "dmz" {
  name                      = var.subnet_name
  resource_group_name       = azurerm_resource_group.production.name
  virtual_network_name      = azurerm_virtual_network.prodvnet.name
  address_prefix            = var.dmz_address_prefix
}

# create NSG for DMZ
resource "azurerm_network_security_group" "prodwebnsg" {
  name                = var.nsg_name
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name

  security_rule {
    name                       = "allowrdp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = var.subnet_address_prefix
  }
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "nsgprodwebtodmz" {
  subnet_id                 = azurerm_subnet.dmz.id
  network_security_group_id = azurerm_network_security_group.prodwebnsg.id
}


# Create Public IPs for VMs
resource "azurerm_public_ip" "vmpublicip" {
  count                        = var.vm_count
  name                         = "vmpip-${format("%02d", count.index+1)}"
  location                     = azurerm_resource_group.production.location
  resource_group_name          = azurerm_resource_group.production.name
  allocation_method            = "Static"
  sku                          = "Standard"
  domain_name_label            = "vmpip${lower(random_id.random_name.hex)}"
}


# Create Server(s) NICs
resource "azurerm_network_interface" "prodwebnic" {
  count               = var.vm_count
  name                = "prodwebnics-${format("%02d", count.index+1)}"
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name

  ip_configuration {
    name                                    = "dmzfe"
    subnet_id                               = azurerm_subnet.dmz.id
    private_ip_address_allocation           = "dynamic"
    public_ip_address_id                    = element(azurerm_public_ip.vmpublicip.*.id, count.index)
  }
}


#---------------------------------------------#
# Create Infrastructure Compute Components:   #
# 1. Create Availability Set                  #
# 2. Windows Virtual Machines                 #
#---------------------------------------------#

# Create an availability set for web servers
resource "azurerm_availability_set" "prodwebservers" {
  name                = "webavailabilityset"
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name
  managed             = "true"
}

# Create Web VMs
resource "azurerm_windows_virtual_machine" "webprodvm" {
  count                 = var.vm_count
  name                  = "webprodvm-${format("%02d", count.index+1)}"
  location              = azurerm_resource_group.production.location
  resource_group_name   = azurerm_resource_group.production.name
  size                  = "Standard_DS1_v2"
  admin_username        = var.vmusername
  admin_password        = var.vmpassword
  availability_set_id   = azurerm_availability_set.prodwebservers.id
  network_interface_ids = [
    element(azurerm_network_interface.prodwebnic.*.id, count.index),
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}


