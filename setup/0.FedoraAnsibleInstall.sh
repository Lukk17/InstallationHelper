#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./0.FedoraAnsibleInstall.sh)"
  exit
fi

echo "Installing Ansible on Fedora..."
dnf install -y ansible

echo "Ansible installed successfully."
