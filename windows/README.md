# Windows Installation

---
Script won't install (require manual installation):
```
Acrylic WiFi Analyzer
```
```
NetSpot
```

---

To be able to install script paste into admin powershell:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
```

Unblock `installer.ps1` script file:  
Go to script properties (alt + enter) and click on checkbox "unblock"

--------------------------------------
After install

1. Change folder to install games in each game app (Ubisoft, EA, GOG).

2. Update shortcuts to programs, games. Put shortcuts into global directory:  
   `C:\ProgramData\Microsoft\Windows\Start Menu\Programs`

   Delete unwanted shortcuts from local directory:  
   `C:\Users\Lukk\AppData\Roaming\Microsoft\Windows\Start Menu\Programs`

    Folders to create in global directory: Android, Dev, Edit, Ent (entertainment), Gry, OC, Social.  

3. Create shortcut in task bar for "PC" etc. Copy this project folder "shortcut" to `%USERPROFILE%\Links\shortcuts\`  
   And folder "icons" to `%USERPROFILE%\Links\shortcuts\icons\`  
   Then right-click on shortcut -> "Show more options" -> "Pin to taskbar"

4. Install Nimbus, Google Keep as Chrome apps and pin to taskbar
5. Pin Trello to Taskbar
6. Import Hibernation at 2AM task into Task Scheduler (command `shutdown /h /t 0`):
   * `Win + R` type `taskschd.msc`
   * In the Action menu, choose "Import Task..."
   * Open `Hibernate@2AM` task from this project folder `tasks`


--------------------------------------
Folders with windows icons (for changing shortcuts icons)  
`C:\WINDOWS\system32\imageres.dll`  

`%SystemRoot%\System32\SHELL32.dll`

To see All Application (with Microsoft Store apps):  
`WINKEY + R` and type `shell:AppsFolder`
or use shortcut "WinApps" in shortcut folder

--------------------------------------

Adding manually installed programs to Chocolatey:  
https://www.reddit.com/r/chocolatey/comments/hfhyc9/adding_previously_installed_apps_to_chocolatey/

```powershell
choco install <packegeName> -n
```

--------------------------------------

Upgrading all packages:

```powershell
choco upgrade all -y
```

--------------------------------------

Chocolatey package browser:  
https://community.chocolatey.org/packages

--------------------------------------
To specify install folder

As example:

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

--------------------------------------
Uninstalling

```powershell
choco uninstall <packageName>
```

--------------------------------------
Export config (as `package.config` file in dir where terminal is set)

```powershell
choco export
```

--------------------------------------

Restore all apps from Chocolatey exported config, which be found in chocolatey.config file.

```powershell
choco install .\chocolatey.config
```

--------------------------------------

Show Microsoft store installed apps:

```powershell
winget list --source "msstore"
```

--------------------------------------

If `winget` generate error `CommandNotFoundException` add it to windows path:
`C:\Users\%USERPROFILE%\AppData\Local\Microsoft\WindowsApps`
