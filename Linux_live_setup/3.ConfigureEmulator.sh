#!/bin/bash

echo
echo "----------------------------"
echo "| Running Android Studio.. |"
echo "----------------------------"
echo
echo "Please delete existing and setup new Emulator with Play Store in Android Studio and name it 'Pixel'"
echo "With Boot option: Cold boot"
echo
echo

android-studio

# =====================================================================================

echo
echo "---------------------------------------------"
echo "| Configuring shortcut for Android Emulator |"
echo "---------------------------------------------"
echo

sudo mkdir /opt/emulator
sudo cp ./icons/android.png /opt/emulator/android.png
sudo cp ./shortcuts/android.desktop /usr/share/applications/android.desktop
