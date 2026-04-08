#!/bin/bash

# Ensure script is run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./0.AnsibleInstall.sh)"
  exit
fi

echo "Installing Ansible on Ubuntu/Debian..."
apt update
apt install software-properties-common -y
add-apt-repository --yes --update ppa:ansible/ansible
apt install ansible -y

echo "Ansible installed successfully."
