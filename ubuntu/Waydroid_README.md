
## Ubuntu needs to run on Wayland. 

To check it:
```shell
echo $XDG_SESSION_TYPE
```
it should return output `Wayland`  

-----------------------------------

### If returned value is `x11`:

https://www.reddit.com/r/Ubuntu/comments/u9751a/ubuntu_2204_lts_not_using_wayland/
https://bugs.launchpad.net/ubuntu/+source/gdm3/+bug/1968929/comments/28
https://linuxconfig.org/how-to-enable-disable-wayland-on-ubuntu-22-04-desktop

To file `/etc/gdm3/custom.conf` add: `WaylandEnable=true`.  
Simple commend for it:
```shell
sudo sed -i 's/#WaylandEnable=false/WaylandEnable=true/g' /etc/gdm3/custom.conf
```
Next you need to create file: `/etc/modprobe.d/nvidia-power-management.conf`  
with line:
`options nvidia NVreg_PreserveVideoMemoryAllocations=1`  
Simple commend for it:
```shell
sudo bash -c "echo 'options nvidia NVreg_PreserveVideoMemoryAllocations=1' >> /etc/modprobe.d/nvidia-power-management.conf"
```
and restart desktop env:  
```shell
sudo systemctl restart gdm3
```
Now log off (not just lock) and on login screen when typing password click on gear icon and change to Wayland.  
(sometimes gear will show itself after typing password)

-----------------------------------

## Waydroid first launch

https://docs.waydro.id/usage/install-on-desktops
https://computingforgeeks.com/run-android-operating-system-on-linux-using-waydroid/

To launch search for it in ubuntu applications (super key) and start from there.  
Sometimes it can take few minutes to first window to appear (be patience).  

When it starts there will be initialization - do NOT select GAPPS  
(it will install official Google services which won't work because this device is not authorized)

If after few minutes nothing happened:
```shell
sudo waydroid init
sudo systemctl start waydroid-container
sudo waydroid container start
waydroid session start
waydroid show-full-ui
waydroid app list
```

-----------------------------------
## Setup

To launch every app in different window:
```shell
waydroid prop set persist.waydroid.multi_windows true
sudo systemctl restart waydroid-container
```

-----------------------------------
## Troubleshooter

### Restart:
```shell
sudo systemctl stop waydroid-container.service
sudo rm -rf /var/lib/waydroid /home/.waydroid ~/waydroid ~/.share/waydroid ~/.local/share/applications/*aydroid* ~/.local/share/waydroid
sudo waydroid init -f
systemctl start waydroid-container.service
```


