# Windows Installation

To be able to install script paste into admin powershell:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
```

Unblock `installer.ps1` script file:
Go to script properties (alt + enter) and click on checkbox "unblock"

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


