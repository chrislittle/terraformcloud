provider "azurerm" {
  version = "=2.0.0"
  features {}
}

variable "environment_name" {
  description = "name of the environment to create"
}

variable "webvm_count" {
  description = "Number of Web VMs to build"
}

variable "sqlvm_count" {
  description = "Number of SQL VMs to build"
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

variable "webavailability_set_name" {
  description = "availability set name for web servers"
}

variable "sqlavailability_set_name" {
  description = "availability set name for sql servers"
}

variable "vmusername" {
  description = "windows server username"
}

variable "vmpassword" {
  description = "password for windows server username"
}

variable "webvm_prefix"{
  description = "prefix for web server VMs"
}

variable "sqlvm_prefix" {
  description = "prefix for sql server VM"
}

variable "backup_policy_name" {
  description = "name of the backup policy"
}

#------------------------------------------------------------------#
# Create random name and hex for generating unique service names   #
#------------------------------------------------------------------#

# Create random_id for use throughout the plan
resource random_id "random_name" {
  prefix      = var.environment_name
  byte_length = "4"
}

#---------------------------------------------#
# Create Resource Group                       #
#---------------------------------------------#

# Create a resource group
resource azurerm_resource_group "rg" {
  name     = lower(random_id.random_name.hex)
  location = var.region
}

#-------------------------------------#
# Create Network Components:          #
# 1. Virtual Network & Subnets        #
# 2. Network Security Groups          #
# 3. Network Interfaces               #
#-------------------------------------#

# Create a virtual network in the resource group
resource azurerm_virtual_network "vnet" {
  name                = var.vnet_name
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

  resource azurerm_subnet "subnet" {
  name                      = var.subnet_name
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet.name
  address_prefix            = var.subnet_address_prefix
}

# create NSG for subnet
resource azurerm_network_security_group "nsg" {
  name                = var.nsg_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

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
resource azurerm_subnet_network_security_group_association "nsg-assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}


# Create Public IPs for Web VMs
resource azurerm_public_ip "webvmpublicip" {
  count                        = var.webvm_count
  name                         = "${var.webvm_prefix}-pip-${format("%02d", count.index+1)}"
  location                     = azurerm_resource_group.rg.location
  resource_group_name          = azurerm_resource_group.rg.name
  allocation_method            = "Static"
  sku                          = "Standard"
  domain_name_label            = "vmpip-${lower(random_id.random_name.hex)}-${format("%02d", count.index+1)}"
}


# Create Web Server(s) NICs
resource azurerm_network_interface "webnic" {
  count               = var.webvm_count
  name                = "${var.webvm_prefix}-nic-${format("%02d", count.index+1)}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                                    = "dmzfe"
    subnet_id                               = azurerm_subnet.subnet.id
    private_ip_address_allocation           = "dynamic"
    public_ip_address_id                    = element(azurerm_public_ip.webvmpublicip.*.id, count.index)
  }
}

# Create SQL Server(s) NICs
resource azurerm_network_interface "sqlnic" {
  count               = var.sqlvm_count
  name                = "${var.sqlvm_prefix}-nic-${format("%02d", count.index+1)}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                                    = "dmzbe"
    subnet_id                               = azurerm_subnet.subnet.id
    private_ip_address_allocation           = "dynamic"
  }
}


#---------------------------------------------#
# Create Infrastructure Compute Components:   #
# 1. Create Availability Sets                 #
# 2. Windows Virtual Machines                 #
#---------------------------------------------#

# Create an availability set for web servers
resource azurerm_availability_set "web_as" {
  name                = var.webavailability_set_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  managed             = "true"
}

# Create an availability set for sql servers
resource azurerm_availability_set "sql_as" {
  name                = var.sqlavailability_set_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  managed             = "true"
}

# Create Web VMs
resource azurerm_windows_virtual_machine "webvm" {
  count                 = var.webvm_count
  name                  = "${var.webvm_prefix}-${format("%02d", count.index+1)}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = "Standard_DS1_v2"
  admin_username        = var.vmusername
  admin_password        = var.vmpassword
  availability_set_id   = azurerm_availability_set.web_as.id
  network_interface_ids = [
    element(azurerm_network_interface.webnic.*.id, count.index),
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}

# create sql server VMs
resource azurerm_windows_virtual_machine "sqlvm" {
  count                 = var.sqlvm_count
  name                  = "${var.sqlvm_prefix}-${format("%02d", count.index+1)}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = "Standard_DS3_v2"
  admin_username        = var.vmusername
  admin_password        = var.vmpassword
  availability_set_id   = azurerm_availability_set.sql_as.id
  network_interface_ids = [
    element(azurerm_network_interface.sqlnic.*.id, count.index),
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftSQLServer"
    offer     = "SQL2017-WS2016"
    sku       = "web"
    version   = "latest"
  }
}


#---------------------------------------------#
# Backup Infrastructure                       #
# 1. Create recovery services vault           #
# 2. Create Backup Policy                     #
# 3. Apply Policy to VMs                      #
#---------------------------------------------#


# Create Recovery Services Vault
resource "azurerm_recovery_services_vault" "vault" {
  name                = "vault-${lower(random_id.random_name.hex)}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  soft_delete_enabled = true
}

# create backup policy
resource "azurerm_backup_policy_vm" "policy" {
  name                = var.backup_policy_name
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name

  timezone = "UTC"

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 14
  }

  retention_weekly {
    count    = 3
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["Last"]
  }

  retention_yearly {
    count    = 3
    weekdays = ["Sunday"]
    weeks    = ["Last"]
    months   = ["December"]
  }
}

# apply backup policy to virtual machines
resource "azurerm_backup_protected_vm" "protectwebvm" {
  count               = var.webvm_count
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  source_vm_id        = element(azurerm_windows_virtual_machine.webvm.*.id, count.index)
  backup_policy_id    = azurerm_backup_policy_vm.policy.id
}

resource "azurerm_backup_protected_vm" "protectsqlvm" {
  count               = var.sqlvm_count
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  source_vm_id        = element(azurerm_windows_virtual_machine.sqlvm.*.id, count.index)
  backup_policy_id    = azurerm_backup_policy_vm.policy.id
}