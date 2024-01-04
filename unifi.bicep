param vmName string

@description('')
@allowed([
  'Standard_B1s'
  'Standard_B1ms'
  'Standard_B2s'
  'Standard_B2ms'
  'Standard_F2s'
])
param vmSize string = 'Standard_B1ms'

@description('The name for the virtual network.')
param virtualNetworkName string

@description('The IPv4 address space of the virtual network.')
param addressSpace string = '10.0.0.0/24'

@description('The storage account name used for the backups. (leave empty for automatic name)')
param backupStorageAccountName string = ''

@description('The admin username for the VM.')
param adminUsername string = 'azureuser'

@description('The public SSH key used for admin login on the VM.')
param adminPublicKey string

@description('Public IP address of the home network. The NSG will restrict access to this IP.')
param homePublicIP string

@description('The port number to expose for SSH access to the VM. Will be NAT\'d to 22.')
param sshNatPort int = 22

@description('The Azure region to deploy resources to.')
param location string = resourceGroup().location

var suffix = take(uniqueString(resourceGroup().id), 4)
var computerName = toUpper(vmName)
var cidrParts = split(addressSpace, '/')
var addressSpaceParts = split(cidrParts[0], '.')
var addressPrefix24 = '${addressSpaceParts[0]}.${addressSpaceParts[1]}.${addressSpaceParts[2]}'
var subnetName = 'unifi'
var networkInterfaceName = '${vmName}-nic'
var availabilitySetName = '${vmName}-as'
var backupStgAcc = empty(backupStorageAccountName) ? 'backup${suffix}' : backupStorageAccountName
var pipName = '${vmName}-pip'
var lbName = '${vmName}-lb'
var mountFields = [
  '//${backupStgAcc}.file.${environment().suffixes.storage}/backup'
  '/azure'
  'cifs'
  'vers=3.0,credentials=/root/.smbcreds,dir_mode=0777,file_mode=0777,sec=ntlmssp'
  '0'
  '0'
]
var cloudInitFormat = loadTextContent('cloud-config.yml')

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-06-01' = {
  name: 'Unifi-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-ssh'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: homePublicIP
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-inform-home'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: homePublicIP
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '8080'
        }
      }
      {
        name: 'Allow-inform-lb'
        properties: {
          priority: 130
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '8080'
        }
      }
      {
        name: 'Allow-ubntui-home'
        properties: {
          priority: 140
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: homePublicIP
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '8443'
        }
      }
      {
        name: 'Allow-ubntui-lb'
        properties: {
          priority: 150
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '8443'
        }
      }
      {
        name: 'Allow-http-redirect'
        properties: {
          priority: 160
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: homePublicIP
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '8880'
        }
      }
      {
        name: 'Allow-https-redirect'
        properties: {
          priority: 170
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: homePublicIP
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '8843'
        }
      }
      {
        name: 'Allow-mobile-speedtest'
        properties: {
          priority: 180
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: homePublicIP
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6789'
        }
      }
      {
        name: 'Allow-stun'
        properties: {
          priority: 190
          protocol: 'Udp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: homePublicIP
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3478'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-06-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '${addressPrefix24}.0/25'
          networkSecurityGroup: {
            id: nsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [
                'uksouth'
                'ukwest'
              ]
            }
          ]
        }
      }
    ]
  }

  resource subnet 'subnets' existing = {
    name: subnetName
  }
}

resource pip 'Microsoft.Network/publicIPAddresses@2023-06-01' = {
  name: pipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

var lbFrontEndRef = {
  id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'PublicEndpoint')
}
var lbBackEndRef = {
  id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'unificntr')
}
var lbProbeRef = {
  id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'inform')
}
var lbNatRuleRef = {
  id: resourceId('Microsoft.Network/loadBalancers/inboundNatRules', lbName, 'ssh')
}

resource lb 'Microsoft.Network/loadBalancers@2023-06-01' = {
  name: lbName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'PublicEndpoint'
        properties: {
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'unificntr'
      }
    ]
    inboundNatRules: [
      {
        name: 'ssh'
        properties: {
          frontendIPConfiguration: lbFrontEndRef
          protocol: 'Tcp'
          frontendPort: sshNatPort
          backendPort: 22
          enableFloatingIP: false
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'ubntui'
        properties: {
          frontendIPConfiguration: lbFrontEndRef
          frontendPort: 443
          backendAddressPool: lbBackEndRef
          backendPort: 8443
          protocol: 'Tcp'
          probe: lbProbeRef
          enableFloatingIP: false
          disableOutboundSnat: true
        }
      }
      {
        name: 'inform'
        properties: {
          frontendIPConfiguration: lbFrontEndRef
          frontendPort: 8080
          backendAddressPool: lbBackEndRef
          backendPort: 8080
          protocol: 'Tcp'
          probe: lbProbeRef
          enableFloatingIP: false
          disableOutboundSnat: true
        }
      }
      {
        name: 'STUN'
        properties: {
          frontendIPConfiguration: lbFrontEndRef
          frontendPort: 3478
          backendAddressPool: lbBackEndRef
          backendPort: 3478
          protocol: 'Udp'
          probe: lbProbeRef
          enableFloatingIP: false
          disableOutboundSnat: true
        }
      }
      {
        name: 'UnifiMobile'
        properties: {
          frontendIPConfiguration: lbFrontEndRef
          frontendPort: 6789
          backendAddressPool: lbBackEndRef
          backendPort: 6789
          protocol: 'Tcp'
          probe: lbProbeRef
          enableFloatingIP: false
          disableOutboundSnat: true
        }
      }
      {
        name: 'HttpRedirect'
        properties: {
          frontendIPConfiguration: lbFrontEndRef
          frontendPort: 8880
          backendAddressPool: lbBackEndRef
          backendPort: 8880
          protocol: 'Tcp'
          probe: lbProbeRef
          enableFloatingIP: false
          disableOutboundSnat: true
        }
      }
      {
        name: 'HttpsRedirect'
        properties: {
          frontendIPConfiguration: lbFrontEndRef
          frontendPort: 8843
          backendAddressPool: lbBackEndRef
          backendPort: 8843
          protocol: 'Tcp'
          probe: lbProbeRef
          enableFloatingIP: false
          disableOutboundSnat: true
        }
      }
    ]
    outboundRules: [
      {
        name: 'default'
        properties: {
          frontendIPConfigurations: [
            lbFrontEndRef
          ]
          backendAddressPool: lbBackEndRef
          protocol: 'All'
        }
      }
    ]
    probes: [
      {
        name: 'inform'
        properties: {
          port: 8080
          protocol: 'Tcp'
          intervalInSeconds: 15
          numberOfProbes: 3
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-06-01' = {
  name: networkInterfaceName
  location: location
  dependsOn: [
    lb
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet::subnet.id
          }
          loadBalancerBackendAddressPools: [
            lbBackEndRef
          ]
          loadBalancerInboundNatRules: [
            lbNatRuleRef
          ]
          primary: true
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = {
  name: availabilitySetName
  location: location
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 5
  }
}

resource backupStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: backupStgAcc
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    accessTier: 'Cool'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [
        {
          value: homePublicIP
          action: 'Allow'
        }
      ]
      virtualNetworkRules: [
        {
          id: vnet::subnet.id
          action: 'Allow'
        }
      ]
    }
  }

  resource blob 'blobServices' = {
    name: 'default'
    properties: {
      deleteRetentionPolicy: {
        enabled: false
      }
      containerDeleteRetentionPolicy: {
        enabled: false
      }
    }
  }

  resource file 'fileServices' = {
    name: 'default'
    properties: {
      shareDeleteRetentionPolicy: {
        enabled: false
      }
    }
    resource backupShare 'shares' = {
      name: 'backup'
    }
  }
}

resource unifivm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    availabilitySet: {
      id: availabilitySet.id
    }
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              keyData: adminPublicKey
              path: '/home/${adminUsername}/.ssh/authorized_keys'
            }
          ]
        }
      }
      customData: base64(format(cloudInitFormat, backupStgAcc, backupStorage.listKeys().keys[0].value, string(mountFields)))
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      osDisk: {
        name: '${toLower(vmName)}-os'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        diskSizeGB: 32
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-minimal-jammy'
        sku: 'minimal-22_04-lts-gen2'
        version: 'latest'
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}
