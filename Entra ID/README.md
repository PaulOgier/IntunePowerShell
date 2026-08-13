# Get-EntraSmsVoiceMfaExposure.ps1

Reports who in a Microsoft Entra ID tenant still depends on SMS or voice-call MFA, and would therefore be locked out when Microsoft stops delivering them.

The script only reads. It writes nothing to the tenant and changes no user.

## Why

Microsoft [announced on 13 July 2026](https://www.microsoft.com/en-us/security/blog/2026/07/13/microsoft-entra-id-security-updates-passkeys-are-the-default-authentication-method-in-entra-id/) that passkeys become the default authentication method in Entra ID:

| Date | What happens |
|---|---|
| 1 September 2026 | Passkeys become the default. Users enabled for SMS or voice are auto-enabled for passkeys and prompted to register one at their next MFA sign-in. |
| 18 September 2026 | Supported third-party telecom providers and pricing are published. |
| 30 October 2026 | Admins can select a third-party telecom provider through the Microsoft Security Store. |
| 1 February 2027 | Microsoft retires its own SMS and voice delivery. No opt-out. |

After 1 February 2027, anyone whose only registered second factor is a phone number cannot sign in. Organisations that still need SMS must contract a carrier directly and pay for the traffic.

This affects every Entra ID tenant in the public cloud, new and existing.

The script answers the first question you need: who is exposed, and whether any of them is an administrator.

## What it reports

For every enabled member account, a row giving the registered authentication methods and one of four verdicts:

- **BLOCKED 1 Feb 2027.** A phone number is the only factor. This is the list.
- **Phone registered, has a surviving method.** Will still be able to sign in, may still see the September prompt.
- **No MFA method registered at all.** A separate problem, surfaced for free.
- **Clear.** Nothing to do.

Directory-role holders are flagged separately on two red lines, each naming the accounts rather than only counting them: administrators whose only factor is a phone, and administrators with no second factor at all.

The second line exists because the first one missed a real case in a live tenant. An administrator holding a directory role with nothing registered at all is not "blocked in February", so it fell through the phone-only count, and the only thing describing the account was a housekeeping label reading "unlicensed admin account, expected, leave alone". Correct about the licence, wrong about everything else.

Output goes to a CSV and a console summary.

### The authentication methods policy

Before the user list, the script prints the tenant's authentication methods policy and its `PolicyMigrationState`.

A tenant reading `preMigration` or `migrationInProgress` is still governed by the legacy per-user MFA settings, which this API cannot see. Every "disabled" in the policy output should be read as "unknown" until the state reads `migrationComplete`.

The symptom is a policy claiming SMS and Microsoft Authenticator are both disabled while half the tenant is visibly using them. Both are true at once: the methods policy is untouched and legacy per-user MFA is doing the work.

Two consequences before you change anything:

- Enabling FIDO2 in the methods policy is enough to let passkeys be registered. The migration does not have to be finished first.
- Turning a method off means turning it off in both places. Disabling SMS in the methods policy alone changes nothing while the legacy settings still allow it.

### Unlicensed accounts that can still sign in

A second section lists enabled accounts with no licence assigned. That combination is usually a leaver who was never offboarded, or a shared mailbox whose user object was never blocked.

Accounts holding a directory role are excluded from that list. An unlicensed admin account is a deliberate pattern, not an oversight.

The script flags them and leaves the judgement to you. It can tell you nobody is paying for an account. It cannot tell you nobody is using it.

## Requirements

PowerShell 7 is recommended. It works on Windows PowerShell 5.1, but the Graph SDK is slow there and prone to assembly-loading conflicts.

Four Microsoft Graph modules are needed. The script checks for them and offers to install them for the current user if they are missing:

- Microsoft.Graph.Authentication
- Microsoft.Graph.Users
- Microsoft.Graph.Identity.SignIns
- Microsoft.Graph.Identity.DirectoryManagement

If they are missing it lists them and asks before installing anything. Answering no prints the `Install-Module` line and exits. `-InstallMissingModules` skips the question for unattended runs, where the prompt would hang instead. TLS 1.2 and the NuGet provider are set first, which Windows PowerShell 5.1 needs and 7.x ignores.

Sign in as Global Reader or Global Administrator. The delegated scopes requested are `User.Read.All`, `UserAuthenticationMethod.Read.All`, `Policy.Read.All`, `RoleManagement.Read.Directory` and `Organization.Read.All`, all read-only. First run shows a consent screen for the Microsoft Graph Command Line Tools application, which needs a Global Administrator to approve.

## Running it

```powershell
.\Get-EntraSmsVoiceMfaExposure.ps1
```

Both parameters are optional:

```powershell
.\Get-EntraSmsVoiceMfaExposure.ps1 `
    -TenantId contoso.com `
    -OutputPath "$HOME/Desktop/contoso-mfa-audit.csv"
```

`-OutputPath` defaults to the tenant name and today's date in the current directory.

`-TenantId` does more than pick a tenant. Given a GUID, the script compares it against the tenant it actually signed in to and exits if they differ, printing both. Running this across a dozen tenants in one sitting, a cached token that drops you in the wrong one produces output that looks completely normal, and the mistake surfaces later as one organisation's user list in another organisation's report. Pass the GUID every time, and run `Disconnect-MgGraph` between tenants:

```powershell
Disconnect-MgGraph
.\Get-EntraSmsVoiceMfaExposure.ps1 -TenantId 00000000-1111-2222-3333-444444444444 -OutputPath .\contoso.csv
```

A domain rather than a GUID skips the comparison, since the connected context reports a GUID and there is nothing to compare against.

### Checking one person

`-User` takes one or more UPNs and checks only those, instead of reading the whole tenant.

```powershell
.\Get-EntraSmsVoiceMfaExposure.ps1 -User jsmith@contoso.com
.\Get-EntraSmsVoiceMfaExposure.ps1 -User jsmith@contoso.com, ajones@contoso.com
```

It prints each account in full rather than a tenant summary, and writes no CSV unless `-OutputPath` is given, so a one-person check cannot land on top of a full export.

Two uses. Re-reading a user whose row came back `UNREAD` after a Graph timeout, without paying for another full pass. And confirming one person is ready before a cutover or a licence change.

Accounts named this way are returned even when they are disabled or guests. A lookup that came back empty because of a filter would be worse than useless.

The tenant-level policy block still prints, since it costs one call and is the context for reading anybody's row.

### Sign-in dates

`-IncludeSignInActivity` adds a `LastSignIn` column, which lets unlicensed accounts be reported as dormant rather than merely unlicensed.

It is off by default for two reasons. It needs Microsoft Entra ID P1 in the target tenant, so an Office 365-only tenant returns nothing useful. And it requires `AuditLog.Read.All`, a broader consent than the rest of the script asks for. Neither is worth requesting in a tenant that cannot use the result.

### Being asked to sign in twice

Two different things can each produce a second prompt, and they are worth telling apart.

A screen listing the requested permissions with an Accept button is **consent**, not a second sign-in. Every tenant is a first-ever connection for the Microsoft Graph Command Line Tools application, so that tenant's Global Administrator has to approve the scopes once. It does not recur.

A screen asking for credentials again is **Web Account Manager**. Graph SDK 2.34 made WAM the default on Windows and removed the ability to disable it, so the native Windows account picker appears and a browser sign-in can follow it. `-UseDeviceCode` sidesteps that with a single flow:

```powershell
.\Get-EntraSmsVoiceMfaExposure.ps1 -TenantId contoso.com -UseDeviceCode
```

Check which SDK you have with `(Get-Module Microsoft.Graph.Authentication -ListAvailable | Select-Object -First 1).Version`.

### Unattended runs

`-InstallMissingModules` installs missing modules without the confirmation prompt, which would otherwise hang a scheduled run.

## Notes and limits

**`IsAdmin` sees only active role assignments.** An eligible-but-not-activated PIM assignment does not appear, so on a tenant using PIM that column undercounts. Treat it as a floor.

**Guests are excluded**, filtered in code rather than in the Graph query. A synced account can have a null `userType`, and filtering on `userType eq 'Member'` would drop it silently.

**Phone numbers are returned as they were entered.** Numbers carrying both a country code and a trunk zero, such as `+27 0821234567`, are common and may already be failing delivery.

**Every Graph call carries an explicit `-ErrorAction Stop`.** The SDK raises API failures as non-terminating errors that `$ErrorActionPreference` does not catch. Without it, a 403 prints in red and the script carries on with no data and a cheerful summary of zero. If you adapt this script, keep that.

**A failed run will not overwrite a good CSV.** If no users come back, nothing is written.
