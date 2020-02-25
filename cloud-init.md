# cloud-init

## The cloud-init script used to configure the virtual machine.

```yaml
#cloud-config

timezone: Europe/London

apt:
  sources:
    100-ubnt-unifi:
      keyid: 06E85760C0A52C50 
      keyserver: keyserver.ubuntu.com
      source: "deb https://www.ui.com/downloads/unifi/debian stable ubiquiti"
    mongodb-org-3.4:
      keyid: 0C49F3730359A14518585931BC711F9BA15703C6
      source: "deb https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.4 multiverse"

packages:
- ca-certificates
- apt-transport-https
- openjdk-8-jdk-headless
- mongodb-org-server
- binutils
- ca-certificates-java
- java-common
- jsvc
- libcommons-daemon-java
- unifi
package_update: true
package_upgrade: true
package_reboot_if_required: true

bootcmd:
- if [ ! -d '/azure' ]; then mkdir /azure; fi
runcmd:
- |
  if [ ! -d '/azure/autobackup' ]; then 
    mkdir /azure/autobackup 
  fi
  if [ ! -L '/var/lib/unifi/backup' -a -d '/var/lib/unifi/backup' ]; then 
    rm -rf /var/lib/unifi/backup 
    cd /var/lib/unifi/ 
    ln -s /azure backup 
    chown -h unifi:unifi backup 
  fi

write_files:
- path: /root/.smbcreds
  owner: root:root
  permissions: '0600'
  content: |
    username='backupStgAcc'
    password=STORAGEKEY

mounts:
- [ "//backupStgAcc.file.core.windows.net/backup", "/azure", "cifs", "vers=3.0,credentials=/root/.smbcreds,dir_mode=0777,file_mode=0777,sec=ntlmssp", "0", "0" ]
```
