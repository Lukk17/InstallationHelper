https://askubuntu.com/questions/648434/why-does-my-custom-launcher-open-under-a-separate-icon

desktop shortcuts for snap:  
```/var/lib/snapd/desktop/applications```  
desktop shortcuts for apps:  
```/usr/share/applications```


Wallpaper download from wallpapertip.com and wallpaperswide.com


How to install:
1. Run with `sudo` script `0.PrepareScripts.sh`
2. `1.InstallScript.sh`
3. Install browsers addons
4. `2.SystemConfig.sh`
5. Android emulator configuration - script `3.ConfigureEmulator.sh` will launch Android Studio.  
   SDK need to be downloaded and create android emulator naming it `Pixel`.
   Then close Android Studio (script will make shortcut then). 
6. NordVPN need to be logged in with  
   ```nordvpn login --token <token>```  
   https://nordvpn.com/download/linux/
7. NordVPN auto start can be disabled in `Startup Application Preferences`  
   (to open:"super key" and type "Startup Application Preferences")
8. In `Passwords and Keys` app change `Login` keyring password to blank (no character) value.  
   It will disable pop-up when opening brave (because of sync storing in keyring).
   https://askubuntu.com/questions/867/how-can-i-stop-being-prompted-to-unlock-the-default-keyring-on-boot
9. In `Grub Customizer` change `Boot default entry after` to 1 second.
