# GoTo Assist Universal Uninstall & Reinstall Script

This PowerShell script is an aggressive and comprehensive utility designed to forcefully remove all traces of existing GoTo Assist installations from a Windows system and then install a new, specified version. It is intended for IT administrators to clean up corrupted or stubborn installations that cannot be removed through standard methods.

## Overview
The script performs a multi-stage cleanup process to ensure that old versions of GoTo Assist are completely eradicated before attempting to install a new one. It is designed to be robust, with detailed logging, retry logic for file deletion, and a safety mechanism to prevent it from running more than once on a target machine.

This can be run from Intune with the install command
powershell.exe -ExecutionPolicy Bypass -File GotoAssist_Uninstall_reinstall.ps1


## Features
Multi-Method Uninstallation:
Attempts a clean uninstallation using standard MSI product codes.
Performs a forceful manual cleanup for stubborn or corrupted installations.

## Aggressive Cleanup:
Stops & Disables Services: Finds and terminates all known GoTo Assist services.
Kills Processes: Iteratively stops all known GoTo Assist processes by name and file path to break process-respawn loops.
Deletes Registry Keys: Removes uninstall entries and other configuration data from the Windows Registry.
Deletes Folders: Forcefully removes application folders from Program Files (x86).

## New Version Installation:
After the cleanup, it automatically installs a new version of GoTo Assist from an MSI file.

## Detailed Logging:
Creates a comprehensive log file at C:\Intel\Install\UninstallLog.txt that records every action, success, warning, and error.

## Safety Skip-File:
Creates a file (C:\Intel\Install\Goto_V2.txt) upon successful installation to prevent the script from running again on the same machine.
This is a location that most Windows machines have and has no permission issues. You can update this to be whatever you want.

## Prerequisites
Windows OS: The script is designed for Windows environments.

Administrator Privileges: The script must be run with Administrator privileges to stop services, modify the registry, and delete system files.

From Intune it should be run from "Install behavior - System"

New MSI Installer: A new GoTo Assist MSI installer file (e.g., GoToAssist_Remote_Support_Unattended.msi) must be placed in the same directory as the PowerShell script and called exactly the same, otherwise it will not work in the script.

### How to Use
Prepare the Files:
Place the Uninstall-GoToAssist.ps1 script in a folder.
Place the new GoToAssist_Remote_Support_Unattended.msi installer file in the same folder.

Set Execution Policy (If Needed):
If you haven't run PowerShell scripts before, you may need to set the execution policy. Open PowerShell as an Administrator and run:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process

Run the Script:
Right-click the Uninstall-GoToAssist.ps1 file and select "Run with PowerShell".

Alternatively, open a PowerShell window as an Administrator, navigate to the script's directory, and execute it:

.\Uninstall-GoToAssist.ps1

Monitor and Verify:
The script will output its progress to the console.
After completion, check the log file at C:\Intel\Install\UninstallLog.txt for a detailed report of the operations performed.

### Configuration
The script includes a configuration section at the top where you can customize its behavior by modifying the variables.

$logFile: The full path for the output log file.

$skipFile: The full path for the skip-file that prevents the script from running again.

$msiProductCodes: A list of MSI product codes for older versions you want to target for uninstallation. If you want to get other product codes for your situation, please either check the registy or uninstallview from https://www.nirsoft.net/utils/uninstall_view.html

$goToAssistAppName, $goToAssistRegistryPath, etc.: Variables that define the specific names, registry keys, and folder paths for the manual cleanup process.

$newMsiFileName: The filename of the new MSI installer. This must match the file you placed alongside the script.

> [!WARNING]
> This script is designed to be destructive and forcefully removes files and registry entries. It is highly effective but should be used with caution.  
> **Test First:** Always test the script in a controlled environment or on a non-critical machine before deploying it to production systems.  
> **Review Configuration:** Ensure the product codes, application names, and folder paths in the configuration section match the versions you are targeting.  
> **No Warranty:** This script is provided as-is. The author is not responsible for any data loss or system instability that may result from its use.  