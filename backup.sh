#!/bin/bash

sudo apt update
sudo apt install -y nfs-common zip
sudo mkdir /shared
sudo chown -R ubuntu:ubuntu /shared
sudo mount -t nfs 10.10.10.22:/shared /shared
mkdir /shared/$(hostname)
zip -r /shared/$(hostname)/quil_bak_$(hostname)_$(date +%Y%m%d%H%M%S).zip $HOME/ceremonyclient/node/.config
(crontab -l 2>/dev/null; echo "0 */12 * * * zip -r /shared/\$(hostname)/quil_bak_\$(hostname)_\$(date +\%Y\%m\%d\%H\%M\%S).zip \$HOME/ceremonyclient/node/.config") | crontab -
ls /shared
ls -lrth /shared/$(hostname)
crontab -l