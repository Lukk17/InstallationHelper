#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./0.ArchAnsibleInstall.sh)"
  exit
fi

echo "Installing Ansible on Arch Linux..."
pacman -Sy --noconfirm ansible

echo "Ansible installed successfully."
