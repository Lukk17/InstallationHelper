#!/bin/bash

echo "Installing Android Studio.."
sudo snap install android-studio --classic

echo
echo "Running Android Studio.."
echo "Please setup Emulator and name it 'Pixel'"
android-studio

echo
echo "Configuring shortcut for Android Emulator"
sudo mkdir /opt/emulator
sudo cp ./icons/android.png /opt/emulator/android.png
sudo cp ./shortcuts/android.desktop /usr/share/applications/android.desktop
