#!/bin/bash

echo
echo "--------------"
echo "| Cleaning.. |"
echo "--------------"

sudo apt --fix-broken install -y
yes | sudo rm -R "$temp_folder_path"
