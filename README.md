# PowerShell

Scripts written to solve real Microsoft 365, Entra ID and Intune administration problems, published in case they save someone else an afternoon.

Nothing here is a framework or a module. Each script does one job, runs on its own, and was written because the console could not answer the question or could not do the work at scale.

## What is in here

**Entra ID.** `Get-EntraSmsVoiceMfaExposure.ps1` reports who in a tenant would be unable to sign in when Microsoft stops delivering SMS and voice MFA on 1 February 2027, and flags unlicensed accounts that can still sign in. It only reads.

**Bitdefender.** `Uninstall-Bitdefender.ps1` silently removes Bitdefender and starts BitLocker decryption. Written to be deployed from Intune as a system-context script.

**Goto Assist.** `GotoAssist_Uninstall_reinstall.ps1` strips every trace of an existing GoTo Assist installation and installs a specified version over the top. For the installations that will not come off any other way.

Some folders carry their own README with the detail.

## Before you run any of it

Test on a lab machine or a machine you can afford to break. The uninstall scripts are deliberately destructive and will happily delete registry keys and program folders on a healthy installation.

Read the configuration block at the top of a script before running it. Product codes, folder paths and log locations are all set there, and the defaults reflect the environment the script was written for rather than yours.

The Entra ID script is the exception: it only reads, and it writes nothing to the tenant.

Scripts are provided as-is, with no warranty. If one of them breaks something, that is on you.
