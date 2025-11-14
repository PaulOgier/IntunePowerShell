# =========================================================================
# Bitdefender Silent Uninstall Script for Microsoft Intune
#
# LOGIC: 
# 1. Check for Bitdefender files.
# 2. If NOT found: STOP. Exit 0.
# 3. If found:
#    a. Run uninstaller.
#    b. Verify removal.
#    c. If uninstall FAILS: STOP. Exit 1.
#    d. If uninstall SUCCEEDS:
#       i. Create 'Bitdefender_Removed.txt' file.
#       ii. Initiate BitLocker decryption.
#       iii. Exit 0 (or 1 if decryption fails to start).
# =========================================================================

# --- Log Configuration ---
$logFolder = "C:\Intel"
$logFile = Join-Path -Path $logFolder -ChildPath "Bitdefender_Uninstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

try {
    if (-not (Test-Path $logFolder)) {
        Write-Warning "Log folder C:\Intel not found. Attempting to create it."
        New-Item -Path $logFolder -ItemType Directory -Force -ErrorAction Stop
    }
} catch {
    Write-Error "FATAL: Could not create log directory C:\Intel. $_"
    Write-Error "Script will continue, but transcript logging will be disabled."
}

try {
    Start-Transcript -Path $logFile -ErrorAction Stop
} catch {
    Write-Warning "Failed to start transcript logging to $logFile. $_"
}

# --- Main Script Logic ---
try {
    # --- 1. Bitdefender Uninstall Configuration ---
    # ❗ IMPORTANT: Replace "YOUR_PASSWORD_HERE" with your actual Bitdefender uninstall password.
    $uninstallPassword = "YOUR_PASSWORD_HERE" 

    $downloadUrl = "https://download.bitdefender.com/SMB/Hydra/release/bst_win/uninstallTool/BEST_uninstallTool.exe"
    $tempFolder = "C:\Windows\Temp"
    $uninstallerPath = "$tempFolder\BEST_uninstallTool.exe"
    
    # --- Artifacts to check for (File Paths Only) ---
    $bdFolder = "C:\Program Files\Bitdefender\Endpoint Security"
    $filePath1 = Join-Path $bdFolder "EPConsole.exe"
    $filePath2 = Join-Path $bdFolder "EPPowerConsole.exe"
    $filePath3 = Join-Path $bdFolder "product.console.exe"

    # --- 2. Initial Check for Bitdefender ---
    Write-Host "--- Starting Bitdefender Uninstall Phase (File Check Only) ---"
    
    Write-Host "Initial check 1: Checking for file: $filePath1..."
    $filePathCheck1 = Test-Path $filePath1
    
    Write-Host "Initial check 2: Checking for file: $filePath2..."
    $filePathCheck2 = Test-Path $filePath2
    
    Write-Host "Initial check 3: Checking for file: $filePath3..."
    $filePathCheck3 = Test-Path $filePath3

    if ($filePathCheck1) { Write-Host "FOUND: Bitdefender file at: $filePath1" }
    if ($filePathCheck2) { Write-Host "FOUND: Bitdefender file at: $filePath2" }
    if ($filePathCheck3) { Write-Host "FOUND: Bitdefender file at: $filePath3" }

    # --- Main Logic Gate ---
    if ($filePathCheck1 -or $filePathCheck2 -or $filePathCheck3) {
        
        # --- BITDEFENDER IS FOUND ---
        Write-Host "Bitdefender file(s) found. Proceeding with uninstall."
        
        try {
            # --- 3a. Download Logic ---
            if (-not (Test-Path $tempFolder)) {
                New-Item -Path $tempFolder -ItemType Directory -Force
            }
            Write-Host "Downloading uninstaller from $downloadUrl..."
            Invoke-WebRequest -Uri $downloadUrl -OutFile $uninstallerPath -UseBasicParsing -ErrorAction Stop
            Write-Host "Download complete."

            # --- 3b. Run the Uninstall Command ---
            Write-Host "Running uninstaller silently. This may take a few minutes..."
            $arguments = "/password=`"$uninstallPassword`" /bruteForce /noWait"
            
            Write-Host "Executing: $uninstallerPath $arguments"
            $process = Start-Process -FilePath $uninstallerPath -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
            
            Write-Host "Uninstaller process finished with exit code: $($process.ExitCode)."
            Write-Host "Waiting 10 seconds for files to be removed..."
            Start-Sleep -Seconds 10

            # --- 3c. Verification Check ---
            Write-Host "Verification check: Re-checking for Bitdefender file artifacts..."
            $verificationFileCheck1 = Test-Path $filePath1
            $verificationFileCheck2 = Test-Path $filePath2
            $verificationFileCheck3 = Test-Path $filePath3

            if ($verificationFileCheck1 -or $verificationFileCheck2 -or $verificationFileCheck3) {
                # --- UNINSTALL FAILED ---
                Write-Error "FAILURE: Uninstaller ran, but Bitdefender file(s) are still detected."
                if ($verificationFileCheck1) { Write-Error "Still found: $filePath1" }
                if ($verificationFileCheck2) { Write-Error "Still found: $filePath2" }
                if ($verificationFileCheck3) { Write-Error "Still found: $filePath3" }
                
                Write-Host "SKIPPING BitLocker decryption phase."
                Write-Host "Script finished. Exiting with code 1."
                exit 1 # Stop all execution
            
            } else {
                # --- 3d. UNINSTALL SUCCEEDED ---
                Write-Host "SUCCESS: Verified Bitdefender files are no longer present."
                
                # --- (NEW) Create Success File ---
                try {
                    $successFile = "C:\Intel\Bitdefender_Removed.txt"
                    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    $fileContent = "Bitdefender was successfully removed by this script on: $timestamp"
                    Write-Host "Creating success file: $successFile"
                    Set-Content -Path $successFile -Value $fileContent -ErrorAction Stop
                } catch {
                    Write-Warning "Could not create success file $successFile. $_"
                    # Don't fail the script for this, just log the warning.
                }
                # --- End of New Section ---

                Write-Host "Proceeding to BitLocker decryption as planned."
                
                # --- 4. Initiate BitLocker Decryption ---
                Write-Host "--- Starting BitLocker Decryption Phase ---"
                try {
                    $encryptedDrives = Get-BitLockerVolume | Where-Object { $_.ProtectionStatus -ne 'Off' }
                    
                    if ($encryptedDrives) {
                        Write-Host "Found one or more BitLocker-protected drives. Initiating decryption..."
                        foreach ($drive in $encryptedDrives) {
                            $mountPoint = $drive.MountPoint
                            Write-Host "Attempting to disable BitLocker for: $mountPoint"
                            Disable-BitLocker -MountPoint $mountPoint -ErrorAction SilentlyContinue
                            
                            $status = Get-BitLockerVolume -MountPoint $mountPoint
                            Write-Host "Decryption for $mountPoint has been initiated."
                            Write-Host "Current Status: $($status.ProtectionStatus), Percentage: $($status.EncryptionPercentage)%."
                            Write-Host "WARNING: This decryption will continue in the background."
                        }
                    } else {
                        Write-Host "No BitLocker-protected drives found."
                    }
                    
                    Write-Host "--- Finished BitLocker Phase. ---"
                    Write-Host "All operations completed successfully. Exiting with code 0."
                    exit 0

                } catch {
                    Write-Error "An error occurred during the BitLocker check/decryption phase: $_"
                    Write-Warning "Bitdefender was uninstalled, but decryption failed to start."
                    Write-Host "Script finished. Exiting with code 1."
                    exit 1 # Exit with failure due to decryption error
                }
            }

        } catch {
            # This catches errors in the Download or Start-Process commands
            Write-Error "An error occurred during the uninstall process: $_"
            Write-Host "SKIPPING BitLocker decryption phase."
            Write-Host "Script finished with error. Exiting with code 1."
            exit 1 # Stop all execution
        }
    } else {
        # --- BITDEFENDER NOT FOUND ---
        Write-Host "Bitdefender file artifacts not found."
        Write-Host "This may mean a new security agent is already installed."
        Write-Host "SKIPPING all uninstall and decryption steps as per logic."
        Write-Host "Script finished. Exiting with code 0."
        exit 0
    }
} finally {
    # --- Stop Logging ---
    Write-Host "Stopping transcript..."
    Stop-Transcript -ErrorAction SilentlyContinue
}