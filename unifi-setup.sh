#!/bin/bash

if [ ! -d '/azure/autobackup' ]; then
    mkdir /azure/autobackup
fi
if [ ! -L '/var/lib/unifi/backup' -a -d '/var/lib/unifi/backup' ]; then
    rm -rf /var/lib/unifi/backup
    cd /var/lib/unifi/
    ln -s /azure backup
    chown -h unifi:unifi backup
fi
