#!/bin/bash
sudo apt-get -y update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | \
sudo gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
sudo gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo chmod 644 /usr/share/keyrings/hashicorp-archive-keyring.gpg 
sudo apt -y update
sudo apt-get -y install terraform