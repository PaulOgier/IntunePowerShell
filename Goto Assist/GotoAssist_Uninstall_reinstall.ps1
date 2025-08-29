# Requires Administrator privileges to run
# To run: Open POwershell as Administrator and then run the command below
# powershell.exe -ExecutionPolicy Bypass -File .\GotoAssist_Uninstall_reinstall.ps1

# --- Configuration for checks ---

$logFile = "C:\Intel\Install\UninstallLog.txt" # Log file path updated to C:\Intel\Install
$skipFile = "C:\Intel\Install\Goto_V2.txt" # File to check for skipping script execution

# Product Codes for MSI-based uninstalls
$msiProductCodes = @(
    "{2A361CF9-8DC2-BC95-4BBA-108B5074A50A}",
    "{39D79B86-76F6-0D2A-DF9C-360F90872AA4}",
    "{3A322358-03A6-2C23-1C0D-67382D9B35A7}"
    # Add more MSI product codes here as needed
)

# Configuration for Executable-based uninstallers
$exeUninstallers = @(
    @{
        Description = "GoToAssist Unattended Remover"
        SearchPath  = "C:\Program Files (x86)\GoToAssist Remote Support Unattended"
        FileName    = "GoToAssistUnattendedRemover.exe"
        Arguments   = "/s"
    }
    # Add more executable uninstallers here in the future. For example:
    # @{
    #     Description = "Another Program Uninstaller"
    #     SearchPath  = "C:\Program Files\Another Program"
    #     FileName    = "uninstaller.exe"
    #     Arguments   = "/silent /norestart"
    # }
)


# Configuration for GoToAssist (manual cleanup)
$goToAssistAppName = "GoToAssist Customer 4.8.0.1732" # DisplayName from registry
$goToAssistRegistryPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
$goToAssistRegistryKeyName = "GoToAssist Express Customer" # Key name from registry
$goToAssistAppFolder = "C:\Program Files (x86)\GoToAssist Remote Support Customer" # Main installation folder
$goToAssistUnattendedFolder = "C:\Program Files (x86)\GoToAssist Remote Support Unattended" # Second folder to delete

# Comprehensive list of process names (without .exe)
$goToAssistProcessNames = @(
    "g2ax_service",
    "g2ax_system_customer",
    "g2ax_user_customer",
    "g2ax_comm_customer",
    "g2ax_uninstaller_customer",
    "GoToAssistUnattended",
    "GoToAssistRemoteControl",
    "GoToAssistUnattendedUi",
    "GoToAssistLoggerProcess", # This is the main culprit from logs
    "GoToAssistNetworkChecker",
    "GoToAssistProcessChecker",
    "GoToAssist Remote Support (32 bit)",
    "GoToAssistCrashHandler (32 bit)",
    "GoToAssistCrashHandler"
)
$goToAssistServiceNames = @(
    "GoToAssist Remote Support Customer"
)

# Configuration for New GoToAssist Installation
$newMsiFileName = "GoToAssist_Remote_Support_Unattended.msi"
$newMsiPath = Join-Path -Path $PSScriptRoot -ChildPath $newMsiFileName # Gets the script's directory automatically


# --- Functions ---

function Write-Log {
    Param(
        [string]$Message,
        [string]$LogType = "INFO" # Can be INFO, WARNING, ERROR
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - [$LogType] - $Message"
    Add-Content -Path $logFile -Value $logEntry
    Write-Host "$logEntry" # Also output to console
}

# --- Main Script Logic ---

Write-Host "Starting universal uninstallation/installation script..."
Write-Log "Starting universal uninstallation/installation script."

# --- Check for skip file ---
if (Test-Path $skipFile) {
    $skipMessage = "Skip file '$skipFile' found. Aborting script execution (assuming new GoToAssist is already installed)."
    Write-Host $skipMessage -ForegroundColor Yellow
    Write-Log $skipMessage "INFO"
    exit # Exit the script immediately
}
# --- End check for skip file ---


# --- Section 1: MSI-Based Uninstalls ---
Write-Host "`n--- Running MSI-Based Uninstalls ---"
Write-Log "Running MSI-Based Uninstalls."

foreach ($productCode in $msiProductCodes) {
    Write-Host "Attempting to uninstall MSI product: $productCode..."
    Write-Log "Attempting to uninstall MSI product: $productCode..."

    $isMsiInstalled = $false
    try {
        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        foreach ($keyPath in $uninstallKeys) {
            $checkPath = Join-Path -Path $keyPath -ChildPath $productCode
            if (Test-Path $checkPath) {
                $isMsiInstalled = true
                break
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $logMessage = "WARNING: Could not check if MSI " + $productCode + " is installed. Error: " + $errorMessage
        Write-Log $logMessage "WARNING"
    }

    if ($isMsiInstalled) {
        $uninstargs = "/X $productCode /qn"
        try {
            $results = Start-Process "msiexec.exe" -ArgumentList $uninstargs -Wait -Passthru -WindowStyle Hidden -ErrorAction Stop
            if ($results.exitcode -eq 0) {
                Write-Host "Successfully uninstalled MSI product: $productCode."
                Write-Log "Successfully uninstalled MSI product: $productCode."
            } elseif ($results.exitcode -eq 3010) {
                Write-Warning "Uninstallation of MSI product $productCode requires a reboot (Exit Code: 3010)."
                Write-Log "WARNING: Uninstallation of MSI product $productCode requires a reboot (Exit Code: 3010)." "WARNING"
            } else {
                Write-Warning "Uninstallation of MSI product $productCode failed with exit code: $($results.exitcode)."
                Write-Log "ERROR: Uninstallation of MSI product $productCode failed with exit code: $($results.exitcode)." "ERROR"
            }
        }
        catch {
            $exceptionMessage = $_.Exception.Message
            $errorOutput = "An error occurred while trying to start MSI uninstallation for " + $productCode + ": " + $exceptionMessage
            Write-Error $errorOutput
            Write-Log $errorOutput "ERROR"
        }
    } else {
        Write-Host "MSI product $productCode is not installed (or registry entry not found), skipping uninstallation."
        Write-Log "MSI product $productCode is not installed (or registry entry not found), skipping uninstallation."
    }
}
# --- End of MSI-Based Uninstalls ---


# --- Section 1.5: Executable-Based Uninstalls ---
Write-Host "`n--- Running Executable-Based Uninstalls ---"
Write-Log "Running Executable-Based Uninstalls."

foreach ($uninstaller in $exeUninstallers) {
    Write-Host "Handling uninstaller: $($uninstaller.Description)..."
    Write-Log "Handling uninstaller: $($uninstaller.Description)..."

    $uninstallerPath = $null
    # Check if the base search path exists
    if (Test-Path $uninstaller.SearchPath) {
        # Find the executable file within the search path and its subdirectories
        $uninstallerPath = Get-ChildItem -Path $uninstaller.SearchPath -Filter $uninstaller.FileName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    } else {
        Write-Host "Search path '$($uninstaller.SearchPath)' not found. Skipping."
        Write-Log "Search path '$($uninstaller.SearchPath)' not found. Skipping."
        continue # Move to the next uninstaller in the list
    }

    if ($uninstallerPath) {
        Write-Host "Found uninstaller at: '$($uninstallerPath.FullName)'. Attempting to run."
        Write-Log "Found uninstaller at: '$($uninstallerPath.FullName)'. Attempting to run."
        try {
            $results = Start-Process -FilePath $uninstallerPath.FullName -ArgumentList $uninstaller.Arguments -Wait -Passthru -WindowStyle Hidden -ErrorAction Stop
            if ($results.exitcode -eq 0) {
                Write-Host "Successfully ran uninstaller '$($uninstaller.Description)'."
                Write-Log "Successfully ran uninstaller '$($uninstaller.Description)'."
            } else {
                Write-Warning "Uninstaller '$($uninstaller.Description)' finished with a non-zero exit code: $($results.exitcode)."
                Write-Log "WARNING: Uninstaller '$($uninstaller.Description)' finished with a non-zero exit code: $($results.exitcode)." "WARNING"
            }
        }
        catch {
            $exceptionMessage = $_.Exception.Message
            $errorOutput = "An error occurred while trying to run uninstaller '$($uninstaller.Description)': $exceptionMessage"
            Write-Error $errorOutput
            Write-Log $errorOutput "ERROR"
        }
    } else {
        Write-Host "Uninstaller file '$($uninstaller.FileName)' not found in path '$($uninstaller.SearchPath)'. Skipping."
        Write-Log "Uninstaller file '$($uninstaller.FileName)' not found in path '$($uninstaller.SearchPath)'. Skipping."
    }
}
# --- End of Executable-Based Uninstalls ---


# --- Section 2: Manual Cleanup for GoToAssist ---
Write-Host "`n--- Running Manual Cleanup for GoToAssist ---"
Write-Log "Running Manual Cleanup for GoToAssist."

# Check if GoToAssist is perceived as installed
$fullGoToAssistRegistryPath = Join-Path -Path $goToAssistRegistryPath -ChildPath $goToAssistRegistryKeyName
$isGoToAssistInstalled = (Test-Path $fullGoToAssistRegistryPath) -or (Test-Path $goToAssistAppFolder) -or (Test-Path $goToAssistUnattendedFolder)

if ($isGoToAssistInstalled) {
    Write-Host "'$goToAssistAppName' appears to be installed. Proceeding with manual cleanup."
    Write-Log "'$goToAssistAppName' appears to be installed. Proceeding with manual cleanup."

    # Step 1: Stop and Disable Services
    Write-Host "Attempting to stop and disable GoToAssist services..."
    Write-Log "Attempting to stop and disable GoToAssist services."
    foreach ($serviceName in $goToAssistServiceNames) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.Status -ne "Stopped") {
                    Write-Host "Stopping service '$serviceName'..."
                    Write-Log "Stopping service '$serviceName'..."
                    Stop-Service -InputObject $service -Force -ErrorAction Stop
                    Write-Host "Service '$serviceName' stopped."
                    Write-Log "Service '$serviceName' stopped."
                }
                # Set service to disabled to prevent restart
                Write-Host "Disabling service '$serviceName'..."
                Write-Log "Disabling service '$serviceName'..."
                Set-Service -InputObject $service -StartupType Disabled -ErrorAction Stop
                Write-Host "Service '$serviceName' disabled."
                Write-Log "Service '$serviceName' disabled."
            } else {
                Write-Host "Service '$serviceName' not found, skipping stopping/disabling."
                Write-Log "Service '$serviceName' not found, skipping stopping/disabling."
            }
        }
        catch {
            $exceptionMessage = $_.Exception.Message
            Write-Warning "Could not stop/disable service '$serviceName': $exceptionMessage (might not be running or insufficient permissions)."
            Write-Log "WARNING: Could not stop/disable service '$serviceName': $exceptionMessage." "WARNING"
        }
    }

    # Step 2: Iterative Process Stopping Loop
    Write-Host "Attempting to stop GoToAssist processes iteratively until no more are found..."
    Write-Log "Attempting to stop GoToAssist processes iteratively until no more are found."

    $processesStillRunning = $true
    $killAttempts = 0
    $maxKillAttempts = 10 # Prevent infinite loops

    while ($processesStillRunning -and ($killAttempts -lt $maxKillAttempts)) {
        $processesStillRunning = $false
        $killAttempts++
        Write-Host "Kill attempt #$killAttempts."
        Write-Log "Kill attempt #$killAttempts."

        # Find processes by specific names
        foreach ($processName in $goToAssistProcessNames) {
            try {
                $processesToStop = Get-Process -Name $processName -ErrorAction SilentlyContinue
                if ($processesToStop) {
                    foreach ($proc in $processesToStop) {
                        Write-Host "Stopping process by name '$($proc.ProcessName)' (PID: $($proc.Id))..."
                        Write-Log "Stopping process by name '$($proc.ProcessName)' (PID: $($proc.Id))..."
                        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                        Write-Host "Process '$($proc.ProcessName)' (PID: $($proc.Id)) stopped successfully."
                        Write-Log "Process '$($proc.ProcessName)' (PID: $($proc.Id)) stopped successfully."
                        $processesStillRunning = $true # Found and killed something, loop again
                    }
                }
            }
            catch {
                $exceptionMessage = $_.Exception.Message
                Write-Warning "Could not stop process by name '$processName': $exceptionMessage (might be insufficient permissions or persistent lock)."
                Write-Log "WARNING: Could not stop process by name '$processName': $exceptionMessage." "WARNING"
                $processesStillRunning = $true # Treat as still running if we failed to kill
            }
        }

        # Find processes by path (if not already handled by name)
        try {
            $allGoToAssistProcessesByPath = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                ($null -ne $_.Path) -and ($_.Path -like "*GoToAssist Remote Support Customer*" -or $_.Path -like "*GoToAssist Remote Support Unattended*")
            }

            if ($allGoToAssistProcessesByPath) {
                foreach ($proc in $allGoToAssistProcessesByPath) {
                    # Only stop if it's still running (might have been killed by name already)
                    if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
                        Write-Host "Stopping GoToAssist process: '$($proc.ProcessName)' (PID: $($proc.Id)) from path: '$($proc.Path)'..."
                        Write-Log "Stopping GoToAssist process: '$($proc.ProcessName)' (PID: $($proc.Id)) from path: '$($proc.Path)'."
                        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                        Write-Host "Process '$($proc.ProcessName)' (PID: $($proc.Id)) stopped successfully."
                        Write-Log "Process '$($proc.ProcessName)' (PID: $($proc.Id)) stopped successfully."
                        $processesStillRunning = $true # Found and killed something, loop again
                    }
                }
            }
        }
        catch {
            $exceptionMessage = $_.Exception.Message
            Write-Warning "Could not stop GoToAssist-related processes by path: $exceptionMessage (might be insufficient permissions or persistent lock)."
            Write-Log "WARNING: Could not stop GoToAssist-related processes by path: $exceptionMessage." "WARNING"
            $processesStillRunning = $true # Treat as still running if we failed to kill
        }

        if ($processesStillRunning -and ($killAttempts -lt $maxKillAttempts)) {
            Write-Host "Some GoToAssist processes were found and killed. Waiting 2 seconds before next kill attempt..."
            Write-Log "Some GoToAssist processes were found and killed. Waiting 2 seconds before next kill attempt."
            Start-Sleep -Seconds 2 # Small delay between kill attempts in the loop
        }
    }

    if ($killAttempts -ge $maxKillAttempts -and $processesStillRunning) {
        Write-Warning "Max kill attempts reached. Some GoToAssist processes might still be running."
        Write-Log "WARNING: Max kill attempts reached. Some GoToAssist processes might still be running." "WARNING"
    } else {
        Write-Host "All identified GoToAssist processes appear to be stopped."
        Write-Log "All identified GoToAssist processes appear to be stopped."
    }

    # Final delay before trying to delete folders to ensure all handles are released
    Write-Host "Waiting 5 seconds for all processes to fully release file handles after final kill attempts..."
    Write-Log "Waiting 5 seconds for all processes to fully release file handles after final kill attempts..."
    Start-Sleep -Seconds 5

    # Step 3: Delete Registry Entry
    Write-Host "Attempting to delete GoToAssist registry entry: '$fullGoToAssistRegistryPath'..."
    Write-Log "Attempting to delete GoToAssist registry entry: '$fullGoToAssistRegistryPath'."
    if (Test-Path $fullGoToAssistRegistryPath) {
        try {
            # Optional: Backup the key before deleting (simple export to a .reg file)
            $backupRegPath = "$env:TEMP\GoToAssist_Uninstall_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
            Write-Host "Backing up registry key to '$backupRegPath'..."
            reg export "$($fullGoToAssistRegistryPath.Replace('HKLM:\','HKEY_LOCAL_MACHINE\'))" "$backupRegPath" /y | Out-Null
            Write-Host "Registry key backed up."
            Write-Log "Registry key backed up to '$backupRegPath'."

            Remove-Item -Path $fullGoToAssistRegistryPath -Recurse -Force -ErrorAction Stop
            Write-Host "Registry entry deleted successfully."
            Write-Log "Registry entry deleted successfully."
        }
        catch {
            $exceptionMessage = $_.Exception.Message
            $errorOutput = "Failed to delete registry entry '" + $fullGoToAssistRegistryPath + "': " + $exceptionMessage + "."
            Write-Error $errorOutput
            Write-Log $errorOutput "ERROR"
        }
    } else {
        Write-Host "GoToAssist registry entry not found, skipping deletion."
        Write-Log "GoToAssist registry entry not found, skipping deletion."
    }

# Step 4: Delete Application Folders with Retry Logic
    $foldersToDelete = @(
        $goToAssistAppFolder,
        $goToAssistUnattendedFolder
    )

    foreach ($folderPath in $foldersToDelete) {
        Write-Host "Attempting to delete application folder: '$folderPath'..."
        Write-Log "Attempting to delete application folder: '$folderPath'."

        $maxRetries = 5
        $retryDelaySeconds = 5
        $deletedFolder = $false

        if (Test-Path $folderPath) {
            for ($i = 1; $i -le $maxRetries; $i++) {
                try {
                    Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop
                    Write-Host "Application folder '$folderPath' deleted successfully on attempt $i."
                    Write-Log "Application folder '$folderPath' deleted successfully on attempt $i."
                    $deletedFolder = $true
                    break
                }
                catch {
                    # After a failure, re-check if the folder is now gone.
                    # If so, the goal is achieved, so we can exit the loop.
                    if (-not (Test-Path $folderPath)) {
                        Write-Host "Folder '$folderPath' no longer exists. Considering it successfully removed."
                        Write-Log "Folder '$folderPath' no longer exists. Considering it successfully removed."
                        $deletedFolder = $true
                        break # Exit the retry loop
                    }
                    # 

                    # If we are here, the folder still exists and the deletion failed for another reason.
                    $exceptionMessage = $_.Exception.Message
                    $errorOutput = "Attempt $i failed to delete application folder '" + $folderPath + "': " + $exceptionMessage + "."
                    Write-Warning $errorOutput
                    Write-Log $errorOutput "WARNING"

                    if ($i -lt $maxRetries) {
                        Write-Host "Retrying deletion of '$folderPath' in $retryDelaySeconds seconds..."
                        Write-Log "Retrying deletion of '$folderPath' in $retryDelaySeconds seconds..."
                        Start-Sleep -Seconds $retryDelaySeconds
                    }
                }
            }

            if (-not $deletedFolder) {
                $finalError = "Failed to delete application folder '$folderPath' after $maxRetries attempts. Manual intervention may be required."
                Write-Error $finalError
                Write-Log $finalError "ERROR"
            }
        } else {
            Write-Host "Application folder '$folderPath' not found, skipping deletion."
            Write-Log "Application folder '$folderPath' not found, skipping deletion."
        }
    } # End foreach folder

} else {
    Write-Host "'$goToAssistAppName' does not appear to be installed (registry entry or folder not found), skipping manual cleanup."
    Write-Log "'$goToAssistAppName' does not appear to be installed (registry entry or folder not found), skipping manual cleanup."
}

# --- Section 2.5: Additional Registry Cleanup for LogMeIn ---
Write-Host "`n--- Running Additional Registry Cleanup for LogMeIn ---"
Write-Log "Running Additional Registry Cleanup for LogMeIn."

# Define the registry paths to be deleted
$logmeinRegPathsToDelete = @(
    "HKLM:\SOFTWARE\Wow6432Node\LogMeInInc\GoToManage",
    "HKLM:\SOFTWARE\Wow6432Node\LogMeInInc\GoToAssist Express Customer"
)

# Loop through each path and attempt to delete it
foreach ($regPath in $logmeinRegPathsToDelete) {
    Write-Host "Checking for registry key: '$regPath'..."
    Write-Log "Checking for registry key: '$regPath'."

    # Check if the registry path exists before trying to delete it
    if (Test-Path $regPath) {
        Write-Host "Registry key found. Attempting to delete..."
        Write-Log "Registry key found. Attempting to delete..."
        try {
            # Use -Recurse and -Force to ensure the key and all its contents are removed
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Host "Successfully deleted registry key: '$regPath'."
            Write-Log "Successfully deleted registry key: '$regPath'."
        }
        catch {
            # Catch and log any errors that occur during deletion
            $exceptionMessage = $_.Exception.Message
            $errorOutput = "Failed to delete registry key '$regPath': $exceptionMessage."
            Write-Error $errorOutput
            Write-Log $errorOutput "ERROR"
        }
    } else {
        # If the key doesn't exist, log it and move on
        Write-Host "Registry key not found. Skipping deletion."
        Write-Log "Registry key not found. Skipping deletion."
    }
}
# --- End of Additional Registry Cleanup ---

# --- End of Uninstallation Section ---

Write-Host "`nUniversal uninstallation script complete. Now proceeding with new installation."
Write-Log "Universal uninstallation script complete. Now proceeding with new installation."


# --- Section 3: New GoToAssist Installation ---
Write-Host "`n--- Running New GoToAssist Installation ---"
Write-Log "Running New GoToAssist Installation."

if (Test-Path $newMsiPath) {
    Write-Host "Found MSI installer at: '$newMsiPath'."
    Write-Log "Found MSI installer at: '$newMsiPath'."
    $installArgs = "/i `"$newMsiPath`" /qn /norestart" # /qn for quiet, /norestart to prevent automatic reboot

    try {
        Write-Host "Starting new GoToAssist MSI installation..."
        Write-Log "Starting new GoToAssist MSI installation..."
        $installResults = Start-Process "msiexec.exe" -ArgumentList $installArgs -Wait -Passthru -WindowStyle Hidden -ErrorAction Stop

        if ($installResults.exitcode -eq 0) {
            Write-Host "New GoToAssist installed successfully (Exit Code: 0)."
            Write-Log "New GoToAssist installed successfully (Exit Code: 0)."

            # Create the skip file to prevent re-running uninstall/reinstall
            try {
                # Ensure the directory for the skip file exists
                $skipFileDirectory = Split-Path -Path $skipFile -Parent
                if (-not (Test-Path $skipFileDirectory)) {
                    New-Item -Path $skipFileDirectory -ItemType Directory -Force | Out-Null
                    Write-Log "Created directory for skip file: '$skipFileDirectory'."
                }
                New-Item -Path $skipFile -ItemType File -Force | Out-Null
                Write-Host "Created skip file: '$skipFile'."
                Write-Log "Created skip file: '$skipFile'."
            }
            catch {
                $exceptionMessage = $_.Exception.Message
                Write-Warning "Failed to create skip file '$skipFile': $exceptionMessage."
                Write-Log "WARNING: Failed to create skip file '$skipFile': $exceptionMessage." "WARNING"
            }

        } elseif ($installResults.exitcode -eq 3010) {
            Write-Warning "New GoToAssist installed successfully, but requires a reboot (Exit Code: 3010)."
            Write-Log "New GoToAssist installed successfully, but requires a reboot (Exit Code: 3010)." "WARNING"
            # Create the skip file even if reboot is needed, as install was successful
            try {
                # Ensure the directory for the skip file exists
                $skipFileDirectory = Split-Path -Path $skipFile -Parent
                if (-not (Test-Path $skipFileDirectory)) {
                    New-Item -Path $skipFileDirectory -ItemType Directory -Force | Out-Null
                    Write-Log "Created directory for skip file: '$skipFileDirectory'."
                }
                New-Item -Path $skipFile -ItemType File -Force | Out-Null
                Write-Host "Created skip file: '$skipFile' (reboot needed)."
                Write-Log "Created skip file: '$skipFile' (reboot needed)."
            }
            catch {
                $exceptionMessage = $_.Exception.Message
                Write-Warning "Failed to create skip file '$skipFile': $exceptionMessage."
                Write-Log "WARNING: Failed to create skip file '$skipFile': $exceptionMessage." "WARNING"
            }
        }
        else {
            Write-Error "New GoToAssist installation failed with exit code: $($installResults.exitcode)."
            Write-Log "ERROR: New GoToAssist installation failed with exit code: $($installResults.exitcode)." "ERROR"
        }
    }
    catch {
        $exceptionMessage = $_.Exception.Message
        $errorOutput = "An error occurred during new GoToAssist installation: " + $exceptionMessage
        Write-Error $errorOutput
        Write-Log $errorOutput "ERROR"
    }
} else {
    Write-Error "New GoToAssist MSI file not found at: '$newMsiPath'. Skipping installation."
    Write-Log "ERROR: New GoToAssist MSI file not found at: '$newMsiPath'. Skipping installation." "ERROR"
}

Write-Host "`nScript finished."
Write-Log "Script finished."
