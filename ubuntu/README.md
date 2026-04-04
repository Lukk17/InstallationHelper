https://askubuntu.com/questions/648434/why-does-my-custom-launcher-open-under-a-separate-icon

desktop shortcuts for snap:  
```/var/lib/snapd/desktop/applications```  
desktop shortcuts for apps:  
```/usr/share/applications```

Wallpaper download from wallpapertip.com and wallpaperswide.com

How to install:
1. Run with `sudo` script `0.PrepareScripts.sh`
2. `1.UbuntuNewInstall.sh`
3. Install browsers addons
4. `2.UbuntuConfigure.sh`

5. `3.ToggleWayland` - **REQUIRES NVIDIA driver version 535 !!**  
    will add `nvidia-drm.modeset=1` parameter to GRUB config,  
    which is crucial for NVIDIA users on Ubuntu 24.04. 
    Without it, GDM will force X11 regardless of your Wayland settings.

    For NVIDIA users: GDM blocks Wayland by default with drivers version more recent than 510 on NVIDIA systems.   
    
    To override this edit file:
    ```bash  
    sudo subl /etc/udev/rules.d/61-gdm.rules  
    ```
    comment out lines:
    
    75
    ```
    #ATTR{version}=="[5-9][1-9][0-9].*", GOTO="gdm_prefer_xorg"
    ```
    77
    ```
    #GOTO="gdm_prefer_xorg"
    ```

6. Hibernation
    Sometimes it can fail due to
    ```
    INFO: task setfont:9848 blocked for more than 245 seconds.
    ```
    
    to fix that:
    
    Run commands to disable the problematic services _only_ for suspend and hibernate, without affecting the normal operation of your system.
    
    ```bash
    sudo systemctl mask systemd-vconsole-setup.service
    ```
    and
    ```bash
    sudo systemctl mask console-setup.service
    ```
   now reboot system.


------------------------------------

### After install

#### Google account login
Log into Google account in gnome settings "Online Account"

#### Mounting shared disk at startup

1. Open the "Disks" application. (You can find it by searching in your activities). 
2. Select the drive you want to mount from the list on the left. 
3. In the "Volumes" section, click on the partition you want to mount. 
4. Click the gear icon below the volumes and select "Edit Mount Options...". 
5. A new window will open. Toggle off "User Session Defaults" at the top. 
6. Ensure that "Mount at system startup" is checked.
7. (Optional but recommended) In the "Display Name" field, you can give the drive a memorable name. 
8. Click OK and enter your password.

#### Setting the same screen settings for the system login page

```shell
sudo cp ~/.config/monitors.xml /var/lib/gdm3/.config/
```

#### Sharing the same project with Windows
It can be detected as dubious ownership to fix that: 
```shell
git config --global --add safe.directory '*'
```

------------------------------------

### Install details

From 23.10 Ubuntu, Firefox is available only via snap.

Postgres is installed via snap

-------------------------------------

### Desktop shortcut names

```text
'org.gnome.Nautilus.desktop'
'brave-browser.desktop'
'sublime-text_subl.desktop'
'intellij-idea-ultimate_intellij-idea-ultimate.desktop' 
'lens.desktop'
'postman.desktop'
```

-------------------------------------

### Linux commands

```shell
gsettings get org.gnome.shell favorite-apps
```

---

### Java SDK versions

To use in terminal given version:
```shell
sdk use java 17.0.10-tem
```

To set global default:
```shell
sdk default java 21.0.2-tem
```