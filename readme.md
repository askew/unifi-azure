# Run your own [Unifi][1] Controller in Azure

To deploy to your Azure subscription, select the following button:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)][8]

This repo contains an Azure Resource Manager (ARM) template that will deploy and configure the Unifi controller software from [Ubiquiti][2] on a virtual machine in Azure.

The VM is a Linux VM running Ubuntu server 18.04 (LTS). The software is configured using a [cloud-init][4] script and follows the Unifi installation proceedure documented at [UniFi - How to Install and Update via APT on Debian or Ubuntu][5].

The ARM template also deploys a storage account with [Azure Files][6] that is used for the automated backups of the Unifi software. The cloud-init script sets up a mount point for the file share and creates a symbolic link from the default backup directory to the file share. There are two ways this could have been achieved: Using a symbolic link to redirect the backup location; or by setting a custom location in the `system.properties` file as described in [How to Change the Location of the Backup File][7]

![Azure Resources](architecture.png)

## Cloud-init

The Unifi set-up is all done through a relatively straight forward cloud-init script. The ARM template constructs the clout-init adding in the storage details for the shared files. This means it is stored in a pretty horrible single-line `concat()` statement. To see what the script looks like it's formatted properly in [cloud-init](./cloudinit.md)

## Manual Steps

The ARM template will set up the Azure resources and Unifi controller software, but there are a few manual steps that will still need to be performed.

### SSL Certificate

The default Unifi install will have a self-signed SSL certificate. The certificate is stored in the file `/usr/lib/unifi/data/keystore` which is a standard Java keystore file. It is protected with the seemingly well known password `aircontrolenterprise`. If you have a valid certificate in PKCS12 format you cant replace the default one with the following

```bash
service unifi stop
keytool -importkeystore -srckeystore ./yourcert.pfx -srcstoretype pkcs12 -destkeystore /usr/lib/unifi/data/keystore -deststoretype pkcs12 -deststorepass 'aircontrolenterprise'
service unifi start
```

### Backups

If you intend to migrate you set up from a backup then you can copy the backup files to the Azure storage account. You can do this one of multiple ways:

  * Uploading directly into the Azure Portal
  * Use the [Azure Storage Explorer][9] tool
  * Mount the SMB share on the machine where you have the backups stored.

## Known Issues

  1. On first deployment the Unifi web endpoint fails to negociate an SSL connection. Restarting the VM seems to fix this.
  
  > The connection for this site is not secure
  >
  > *ip-address* uses an unsupported protocol.
  >
  > `ERR_SSL_VERSION_OR_CIPHER_MISMATCH`




[1]: https://unifi-network.ui.com/ "Ubiquiti Unifi"
[2]: https://www.ui.com
[3]: https://docs.microsoft.com/en-us/azure/virtual-machines/linux/using-cloud-init
[4]: https://cloudinit.readthedocs.io/en/latest/
[5]: https://help.ubnt.com/hc/en-us/articles/220066768-UniFi-How-to-Install-and-Update-via-APT-on-Debian-or-Ubuntu "UniFi - How to Install and Update via APT on Debian or Ubuntu"
[6]: https://docs.microsoft.com/azure/storage/files/storage-files-introduction "What is Azure Files?"
[7]: https://help.ubnt.com/hc/en-us/articles/226218448-UniFi-How-to-Configure-Auto-Backup#2 "UniFi - How to Configure Auto Backup"
[8]: https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Faskew%2Funifi-azure%2Fmaster%2Fazuredeploy.json "Deploy to Azure"
[9]: https://azure.microsoft.com/en-us/features/storage-explorer/ "Azure Storage Explorer"