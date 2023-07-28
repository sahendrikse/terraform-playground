terraform {
  required_version = ">= 1.1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  org      = "acme"
  prj      = "rockets"
  env      = "staging"
  location = "westus2"
}

resource "azurerm_resource_group" "rg" {
  name     = "resources"
  location = local.location

  tags = {
    environment = local.env
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnetwork"
  address_space       = ["10.0.0.0/16"]
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = {
    environment = local.env
  }
}

resource "azurerm_subnet" "snet" {
  name                 = "subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "sg" {
  name                = "securitygroup"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = {
    environment = local.env
  }
}

resource "azurerm_network_security_rule" "sr" {
  name                        = "securityrule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.sg.name
}

resource "azurerm_subnet_network_security_group_association" "sga" {
  subnet_id                 = azurerm_subnet.snet.id
  network_security_group_id = azurerm_network_security_group.sg.id
}

resource "azurerm_public_ip" "publicip" {
  name                = "publicip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = local.location
  allocation_method   = "Dynamic"

  tags = {
    environment = local.env
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "nic"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet.id
    private_ip_address_allocation = azurerm_public_ip.publicip.allocation_method
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }

  tags = {
    environment = local.env
  }
}

resource "azurerm_linux_virtual_machine" "linuxvim" {
  name                = "linuxvim"
  resource_group_name = azurerm_resource_group.rg.name
  location            = local.location
  size                = "Standard_B4s_v2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/azurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  provisioner "local-exec" {
    command        = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityFile = "~/.ssh/azurekey"
    })
    interpreter = var.host_os == "windows" ? [ "PowerShell", "-Command" ] : [ "bash", "-c" ]
  }
}

data "azurerm_public_ip" "ipdata" {
  name = azurerm_public_ip.publicip.name
  resource_group_name = azurerm_resource_group.rg.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.linuxvim.name}: ${data.azurerm_public_ip.ipdata.ip_address}"
}
