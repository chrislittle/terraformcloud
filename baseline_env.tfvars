variable "vm_count" {
  default = "1"
  description = "Number of VMs to build"
}
variable "region" {
  default = "eastus"
  description = "Azure region"
}
variable "vnet_address_space" {
  default = "10.0.0.0/16"
  description = "new vnet ip address CIDR"
}
variable "dmz_address_prefix" {
  default = "10.0.1.0/24"
  description = "subnet CIDR address for vnet"
}
variable "vmusername" {
  default = "asrdemouser"
  description = "windows server username"
}
variable "vmpassword" {
  description = "password for windows server username"
}