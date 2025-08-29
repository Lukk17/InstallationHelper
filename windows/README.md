# Windows Installation

---
## Creating local user

1. The "No Internet" Method (Easiest)
   - When you get to the "Let's connect you to a network" screen, do not connect to Wi-Fi or plug in an Ethernet cable. 
   - Look for and click on the link that says "I don't have internet."
   - On the next screen, it will likely try to convince you again. Click the link that says, "Continue with limited setup."
   - The very next screen will be "Who's going to use this PC?", which is the prompt to create a local account.

2. The "Magic Email" Method (If you're already connected)
   - On the "Sign in" screen for your Microsoft account, enter the email address no@thankyou.com. 
   - Enter any random password (e.g., 123) and click "Sign in."
   - It will fail and show an "Oops, something went wrong" error. Click "Next."

3. Domain join trick
   - When it is asking you if you are setting it up for personal/home or work, you can select for work.
   - On the next page, click on Sign in Options, and choose Domain Join, it will then give you the option to create local user and bypass Microsoft account. 
   - You won't need to actually set up for domain join at all, or will this mean domain join.  
     It is just the path to get the local account creation to come up.

---
## Installing drivers

https://www.aorus.com/motherboards/X470-AORUS-GAMING-7-WIFI-rev-10/Support
https://www.gigabyte.com/Motherboard/X470-AORUS-GAMING-7-WIFI-rev-10/support#dl

---
## Script won't install 

Script will open the download website in the default browser for manual installation app like:

- Process Explorer
- Stable Diffusion Webui
- Beeper

and more...

---
## Prerequisite

To be able to install the script, paste into admin PowerShell:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
```

Unblock `installer.ps1` script file:  
Go to script properties (alt + enter) and click on checkbox "unblock"

---
## After installation

1. Change the folder to install games in each game app (Ubisoft, EA, GOG).

    <br>
2. Update shortcuts to programs, games. Put shortcuts into global directory:  
   `C:\ProgramData\Microsoft\Windows\Start Menu\Programs`

   Delete unwanted shortcuts from local directory:  
   `C:\Users\Lukk\AppData\Roaming\Microsoft\Windows\Start Menu\Programs`

    Folders to create in a global directory: Android, Dev, Edit, Ent (entertainment), Gry, OC, Social.  
   <br>

3. Create symlink for steam  
   3.1. Navigate to the folder `C:\Program Files (x86)\Steam\steamapps`  
   3.2. Once the common folder is empty, DELETE IT. Cannot create a junction if a folder with that name already exists.
   3.3. Open PowerShell as an Administrator and run:
   ```powershell
    New-Item -ItemType Junction -Path "C:\Program Files (x86)\Steam\steamapps\common" -Target "E:\"
    ```
    <br>
4. Create shortcut in task bar for "PC" etc. Copy this project folder "shortcut" to `%USERPROFILE%\Links\shortcuts\`  
   And folder "icons" to `%USERPROFILE%\Links\shortcuts\icons\`  
   Then right-click on shortcut -> "Show more options" -> "Pin to taskbar"

    <br>
5. Install Google Keep, Calendar, Gmail, Gemini, X(Grok) as Chrome apps and pin to the taskbar

    <br>
6. (Optional) Import Hibernation at 2AM task into Task Scheduler (command `shutdown /h /t 0`):
   * `Win + R` type `taskschd.msc`
   * In the Action menu, choose "Import Task..."
   * Open `Hibernate@2AM` task from this project folder `tasks`

---
## Windows day-to-day

### Autoruns

After installing your software, run Autoruns and uncheck anything in the "Logon" tab that you don't need starting with your PC.

---

### VM

1. Use `Hyper-V Manager` instead of VMWare or VirtualBox.
2. Use `Windows Sandbox` to check some apps/scripts instead running on real machine.

---

### Periodic System Health Checks

Repair the core Windows system image by downloading fresh files from Windows Update to fix deep corruption in the component store:
```powershell
DISM /Online /Cleanup-Image /RestoreHealth
```

Uses healthy (after DISM repair) component store to scan and replace any corrupted files currently in use by the operating system:
```powershell
sfc /scannow
```

### Chris Titus Tech tool

For tweaks and fixes. Trusted and well-known tech content creator.
Open source

https://christitus.com/windows-tool/
```powershell
irm christitus.com/win | iex
```

---

Upgrading all packages:

```powershell
choco upgrade all -y
```
```powershell
winget upgrade --all --accept-package-agreements --accept-source-agreements
```

---
Folders with windows icons (for changing shortcuts icons)  
`C:\WINDOWS\system32\imageres.dll`  

`%SystemRoot%\System32\SHELL32.dll`

To see All Application (with Microsoft Store apps):  
`WINKEY + R` and type `shell:AppsFolder`
or use shortcut "WinApps" in shortcut folder

---

## Chocolatey usage

Adding manually installed programs to Chocolatey:  
https://www.reddit.com/r/chocolatey/comments/hfhyc9/adding_previously_installed_apps_to_chocolatey/

```powershell
choco install <packegeName> -n
```

---

Chocolatey package browser:  
https://community.chocolatey.org/packages

---
To specify install folder

As an example:

```powershell
choco install intellijidea-ultimate --params "/InstallDir=C:\Program Files\JetBrains\IntelliJ IDEA"
```
On package page:  
https://community.chocolatey.org/packages/intellijidea-ultimate#files
In "Files", there should be `tools\chocolateyInstall.ps1` script.  
Inside is fragment like this:
```powershell
(...)
$pp = Get-PackageParameters
if ($pp.InstallDir) {
    $installDir = $pp.InstallDir
}
(...)
```
where $pp is alias for "Get-PackageParameters",  
which is taking parameter `InstallDir` from command `--params`.  
This param can be specified to `/InstallDir=C:\Program Files\JetBrains\IntelliJ IDEA`,  
which will override default install path.

---
Uninstalling

```powershell
choco uninstall <packageName>
```

---
Export config (as `package.config` file in dir where terminal is set)

```powershell
choco export
```

---

Restore all apps from Chocolatey exported config, which be found in chocolatey.config file.

```powershell
choco install .\chocolatey.config
```

---

## Winget usage

Show Microsoft store installed apps:

```powershell
winget list --source "msstore"
```

---

If `winget` generate error `CommandNotFoundException` add it to windows path:
`C:\Users\%USERPROFILE%\AppData\Local\Microsoft\WindowsApps`
