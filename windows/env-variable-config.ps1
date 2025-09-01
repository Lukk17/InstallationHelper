Write-Output "Setting JAVA_HOME in path.."
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$javaHome = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")

# Create the new Path string with JAVA_HOME\bin at the very top
$newPath = "$($javaHome)\bin;$($machinePath)"

# Set the new system-wide Path
[System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
Write-Output "JAVA_HOME path updated."


Write-Output "---------------------------------------------------"
Write-Output "Setting ANDROID_HOME and ANDROID_SDK_ROOT in path.."

$sdkPath = "C:\tools\android"

# --- SCRIPT (Run as Administrator) ---
# 1. Set the modern, primary variable
[System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $sdkPath, "Machine")
Write-Host "ANDROID_SDK_ROOT set to '$sdkPath'"

# 2. Set the older, compatibility variable to the same value
[System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdkPath, "Machine")
Write-Host "ANDROID_HOME set to '$sdkPath' for compatibility"

# 3. Update the system PATH using the modern variable
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Define the paths to add
$pathsToAdd = @(
    (Join-Path $sdkPath "platform-tools")
    (Join-Path $sdkPath "cmdline-tools\latest\bin")
    (Join-Path $sdkPath "emulator")
)

# Filter out paths that are already in the Path to avoid duplicates
$uniquePathsToAdd = $pathsToAdd | Where-Object { -not ($machinePath -split ';').Contains($_) }

if ($uniquePathsToAdd.Count -gt 0) {
    # Append only the new, unique paths
    $newPath = ($machinePath, $uniquePathsToAdd) -join ';'
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Write-Host "The required Android SDK paths have been added to the system PATH."
} else {
    Write-Host "The required Android SDK paths are already in the system PATH."
}

