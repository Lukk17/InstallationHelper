Write-Output "Setting dev apps default folder"
$appsConfigPath = Join-Path $env:USERPROFILE "apps_config"
# Create the new config folder if it doesn't exist
if (-not (Test-Path $appsConfigPath)) {
    New-Item -Path $appsConfigPath -ItemType Directory
}

# For Gradle
[System.Environment]::SetEnvironmentVariable("GRADLE_USER_HOME", (Join-Path $appsConfigPath ".gradle"), "User")
# For Docker
[System.Environment]::SetEnvironmentVariable("DOCKER_CONFIG", (Join-Path $appsConfigPath ".docker"), "User")
# For Maven (the .m2 folder)
[System.Environment]::SetEnvironmentVariable("M2_HOME", (Join-Path $appsConfigPath ".m2"), "User")
# For Android Studio user settings
[System.Environment]::SetEnvironmentVariable("ANDROID_SDK_HOME", (Join-Path $appsConfigPath ".android"), "User")
# For Kubernetes config (k8slens, kubectl)
[System.Evironment]::SetEnvironmentVariable("KUBECONFIG", (Join-Path $appsConfigPath ".kube\config"), "User")
