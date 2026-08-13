<#
.SYNOPSIS
    Who in this Entra tenant still depends on SMS or voice-call MFA.

.DESCRIPTION
    Microsoft retires Microsoft-provided SMS and voice delivery on 1 February 2027
    (passkeys become the default from 1 September 2026). Anyone whose only usable
    second factor is a phone number stops being able to sign in on that date.

    Enumerates every enabled member account, lists its registered authentication
    methods, and classifies each user by what they would still have on 1 Feb 2027.
    Admins are flagged separately: an admin whose only factor is SMS is a tenant
    lockout, not a user inconvenience.

    Read-only. Writes one CSV per run.

.PARAMETER TenantId
    Optional. Domain or GUID, to be certain which tenant you land in when the
    signing-in account has access to several.

.PARAMETER OutputPath
    Optional. Defaults to .\<tenantname>-sms-voice-audit-<yyyy-MM-dd>.csv on a
    tenant-wide run. A -User run writes no CSV unless this is given, so a
    one-person check cannot overwrite a full export.

.PARAMETER User
    One or more UPNs to check instead of the whole tenant. Prints each account in
    full rather than a tenant summary. Named accounts are returned even if they
    are disabled or guests, so a lookup never silently comes back empty.

.PARAMETER IncludeSignInActivity
    Adds a LastSignIn column. Needs Entra ID P1 in the target tenant and requests
    AuditLog.Read.All, so it is off by default - an Office 365-only tenant gets a
    403 and nothing else. Without it, dormancy cannot be measured and unlicensed
    accounts are flagged for review rather than named as dead.

.PARAMETER UseDeviceCode
    Sign in with a device code rather than the default Windows flow. Graph SDK
    2.34 made Web Account Manager the default and removed the ability to turn it
    off, so on Windows the native account picker appears and then a browser does
    too, which looks like two sign-ins. This makes it one.

    Note that the separate consent screen on a tenant's first-ever connection is
    not the same thing and will still appear once per tenant.

.PARAMETER InstallMissingModules
    Install any missing Microsoft Graph modules without asking first. Only needed
    for unattended runs, where the confirmation prompt would hang.

.NOTES
    Needs a Global Reader (or Global Admin) sign-in. Four Microsoft Graph modules
    are required and the script offers to install them if they are absent.

    Every Graph call carries an explicit -ErrorAction Stop. The SDK raises API
    failures as non-terminating errors that $ErrorActionPreference does not catch,
    so without it a 403 prints in red and the script carries on with no data.
#>

[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$OutputPath,

    # One or more UPNs to check instead of the whole tenant. Use it to re-check a
    # user whose row came back UNREAD, or to confirm one person before a cutover,
    # without re-reading every account. Disabled users and guests are returned
    # when named explicitly; the tenant-wide run still skips them.
    [string[]]$User,

    # Adds a LastSignIn column so dormant accounts can be named rather than just
    # flagged as unlicensed. Off by default: it needs Entra ID P1 AND a broader
    # AuditLog.Read.All consent in the client's tenant, and neither is worth
    # asking for on a tenant that cannot use it.
    [switch]$IncludeSignInActivity,

    # Install any missing Graph modules without asking. For unattended runs, where
    # the confirmation prompt would just hang.
    [switch]$InstallMissingModules,

    # Sign in with a device code instead of the default Windows flow. Graph SDK
    # 2.34 forced Web Account Manager on and it can no longer be disabled, so on
    # Windows the native account picker fires first and a browser follows, which
    # reads as being asked to sign in twice. A device code is one flow.
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'

# Fail on the missing prerequisite, not thirty lines later on a missing cmdlet.
$required = @(
    'Microsoft.Graph.Authentication'
    'Microsoft.Graph.Users'
    'Microsoft.Graph.Identity.SignIns'
    'Microsoft.Graph.Identity.DirectoryManagement'
)
$missing = @($required | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
if ($missing.Count) {
    Write-Host "Missing Microsoft Graph modules:" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  $_" }

    if (-not $InstallMissingModules) {
        $answer = Read-Host "`nInstall them now from the PSGallery, for this user only? (y/N)"
        if ($answer -notmatch '^y') {
            Write-Host "`nInstall them yourself with:`n" -ForegroundColor Yellow
            Write-Host "  Install-Module $($required -join ', ') -Scope CurrentUser -Force -AllowClobber`n"
            exit 1
        }
    }

    # Windows PowerShell 5.1 still defaults to TLS 1.0, which the PSGallery
    # refuses. Harmless on 7.x, so it is set unconditionally.
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }

    Write-Host "Installing..." -ForegroundColor Cyan
    Install-Module -Name $missing -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    Write-Host "Done.`n" -ForegroundColor Green
}

$scopes = @(
    'User.Read.All',
    'UserAuthenticationMethod.Read.All',
    'Policy.Read.All',
    'RoleManagement.Read.Directory',
    'Organization.Read.All'
)
if ($IncludeSignInActivity) { $scopes += 'AuditLog.Read.All' }

# -NoWelcome only exists in the Graph SDK v2 Connect-MgGraph; drop it on v1 rather
# than failing on an unknown parameter.
$connect = @{ Scopes = $scopes }
if ($TenantId)        { $connect.TenantId = $TenantId }
if ($UseDeviceCode)   { $connect.UseDeviceCode = $true }
if ((Get-Command Connect-MgGraph).Parameters.ContainsKey('NoWelcome')) { $connect.NoWelcome = $true }
Connect-MgGraph @connect

$ctx = Get-MgContext

# Running this across many client tenants in one sitting, a cached token that
# lands you in the wrong tenant produces output that looks entirely normal. If
# -TenantId was given as a GUID, refuse to continue unless it matches.
if ($TenantId -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -and
    $ctx.TenantId -ne $TenantId) {
    Write-Host "WRONG TENANT." -ForegroundColor Red
    Write-Host "  asked for : $TenantId"
    Write-Host "  signed in : $($ctx.TenantId)  as $($ctx.Account)"
    Write-Host "`nRun Disconnect-MgGraph and try again." -ForegroundColor Yellow
    exit 1
}
# GET /organization is least-privileged at User.Read, but a restricted role or a
# tenant that hides it should not kill the whole run - the tenant ID is enough.
try   { $tenantName = (Get-MgOrganization -ErrorAction Stop)[0].DisplayName } catch { }
if ([string]::IsNullOrWhiteSpace($tenantName)) { $tenantName = $ctx.TenantId }
Write-Host "Tenant: $tenantName ($($ctx.TenantId))" -ForegroundColor Cyan

# A -User run writes a CSV only when one is asked for by name. Auto-naming it
# would drop a two-row file on top of the full tenant export.
if (-not $OutputPath -and -not $User) {
    $safe = ($tenantName -replace '[^\w\-]', '-')
    $OutputPath = Join-Path (Get-Location) "$safe-sms-voice-audit-$(Get-Date -Format 'yyyy-MM-dd').csv"
}

# --- Tenant-level method policy -------------------------------------------------
# Tells us whether passkeys can even be registered today, and whether SMS/voice
# are still switched on. Both decide what the client's rollout has to change.
# Print whatever the tenant returns rather than a hard-coded list of ids - the
# set of configurations grows (QrCodePin, X509Certificate) and the casing of the
# ids is not worth guessing.
Write-Host "`nAuthentication methods policy:" -ForegroundColor Cyan
try {
    $policy = Get-MgPolicyAuthenticationMethodPolicy -ErrorAction Stop
    foreach ($m in ($policy.AuthenticationMethodConfigurations | Sort-Object Id)) {
        Write-Host ("  {0,-24} {1}" -f $m.Id, $m.State)
    }

    # preMigration means these states are cosmetic: the tenant is still driven by
    # the legacy per-user MFA and SSPR settings, which this API cannot see. Read
    # every "disabled" above as "unknown" until this says migrationComplete.
    $migration = $policy.PolicyMigrationState
    Write-Host ("`n  Policy migration state   {0}" -f $migration) -ForegroundColor Cyan
    if ($migration -ne 'migrationComplete') {
        Write-Host "  Legacy per-user MFA settings still apply and are NOT visible here." -ForegroundColor Yellow
        Write-Host "  Confirm methods in the legacy portal before quoting these states to a client." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  could not read: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- Directory-role holders -----------------------------------------------------
# Only activated roles are returned; an eligible-but-not-active PIM assignment
# will not appear here, so treat this as a floor, not the full admin list.
$adminIds = New-Object 'System.Collections.Generic.HashSet[string]'
try {
    foreach ($role in Get-MgDirectoryRole -All -ErrorAction Stop) {
        foreach ($member in Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All -ErrorAction Stop) {
            [void]$adminIds.Add($member.Id)
        }
    }
} catch {
    Write-Host "Could not enumerate directory roles: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "IsAdmin will read false for everyone - do not trust that column." -ForegroundColor Yellow
}
Write-Host "`nDirectory-role holders (active assignments): $($adminIds.Count)"

# --- Per user -------------------------------------------------------------------
# Guests are excluded in code, not in the filter: a synced account can have a null
# userType, and "userType eq 'Member'" would drop it without saying so.
$props = @('Id', 'UserPrincipalName', 'DisplayName', 'AccountEnabled', 'UserType',
           'AssignedLicenses', 'CreatedDateTime')

# Every Graph call needs an explicit -ErrorAction Stop: the SDK raises API failures
# as non-terminating errors that $ErrorActionPreference does not catch, so without
# it a 403 prints in red and the script sails on with zero users.
$haveSignIn = $false
$wanted = if ($IncludeSignInActivity) { $props + 'SignInActivity' } else { $props }

if ($User) {
    # Named users are fetched one at a time and returned as asked for, including
    # disabled accounts and guests. Filtering those out here would silently
    # return nothing for exactly the account someone is trying to look up.
    $users = foreach ($upn in $User) {
        try {
            Get-MgUser -UserId $upn -Property $wanted -ErrorAction Stop
            if ($IncludeSignInActivity) { $haveSignIn = $true }
        } catch {
            try {
                Get-MgUser -UserId $upn -Property $props -ErrorAction Stop
            } catch {
                Write-Host "Could not read ${upn}: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Red
            }
        }
    }
} else {
    if ($IncludeSignInActivity) {
        try {
            $users = Get-MgUser -All -Filter "accountEnabled eq true" `
                                -Property $wanted -ErrorAction Stop
            $haveSignIn = $true
        } catch {
            Write-Host "signInActivity unavailable: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Yellow
            Write-Host "Continuing without it - LastSignIn will be blank." -ForegroundColor Yellow
        }
    }
    if (-not $haveSignIn) {
        $users = Get-MgUser -All -Filter "accountEnabled eq true" -Property $props -ErrorAction Stop
    }
    # Guests are excluded in code, not in the filter: a synced account can have a
    # null userType, and "userType eq 'Member'" would drop it without saying so.
    $users = $users | Where-Object { $_.UserType -ne 'Guest' }
}

$users = $users | Sort-Object UserPrincipalName

$users = @($users)
if ($User) { Write-Host "Accounts requested: $($users.Count) of $($User.Count)`n" }
else       { Write-Host "Enabled member accounts: $($users.Count)`n" }

$done = 0
$rows = foreach ($u in $users) {
    $done++
    Write-Progress -Activity 'Reading authentication methods' -Status $u.UserPrincipalName `
                   -PercentComplete (($done / [Math]::Max($users.Count, 1)) * 100)

    $phoneTypes = @()
    $phoneNums  = @()
    $strong     = @()   # survives the SMS/voice retirement
    $weakOther  = @()   # exists but is not a usable interactive second factor
    $verdict    = $null

    try {
        $methods = Get-MgUserAuthenticationMethod -UserId $u.Id -All -ErrorAction Stop
    } catch {
        $methods = @()
        $weakOther += "ERROR: $($_.Exception.Message)"
        $verdict = 'UNREAD'
    }

    foreach ($m in $methods) {
        # The SDK returns the concrete method type only inside AdditionalProperties.
        $type = if ($m.AdditionalProperties) { [string]$m.AdditionalProperties['@odata.type'] } else { '' }

        # Every clause breaks: without it, a passwordless Authenticator method
        # matches both the passwordless and the push wildcard and is counted twice.
        switch -Wildcard ($type) {
            '*phoneAuthenticationMethod' {
                $phoneTypes += [string]$m.AdditionalProperties['phoneType']
                $phoneNums  += [string]$m.AdditionalProperties['phoneNumber']
                break
            }
            '*fido2AuthenticationMethod'                              { $strong += 'Passkey/FIDO2';               break }
            '*passwordlessMicrosoftAuthenticatorAuthenticationMethod' { $strong += 'Authenticator passwordless';  break }
            '*microsoftAuthenticatorAuthenticationMethod'             { $strong += 'Authenticator push';          break }
            '*windowsHelloForBusinessAuthenticationMethod'            { $strong += 'Windows Hello';               break }
            '*platformCredentialAuthenticationMethod'                 { $strong += 'Platform credential';         break }
            '*softwareOathAuthenticationMethod'                       { $strong += 'Software OATH (TOTP)';        break }
            '*hardwareOathAuthenticationMethod'                       { $strong += 'Hardware OATH token';         break }
            '*emailAuthenticationMethod'                              { $weakOther += 'Email (SSPR only)';        break }
            '*temporaryAccessPassAuthenticationMethod'                { $weakOther += 'Temporary Access Pass';    break }
            '*passwordAuthenticationMethod'                           { break }   # everyone has one
            default                                                   { $weakOther += $type }
        }
    }

    $strong = @($strong | Select-Object -Unique)

    if (-not $verdict) {
        $verdict =
            if ($phoneTypes.Count -gt 0 -and $strong.Count -eq 0) { 'BLOCKED 1 Feb 2027 - phone is the only factor' }
            elseif ($phoneTypes.Count -gt 0)                      { 'Phone registered, has a surviving method' }
            elseif ($strong.Count -eq 0)                          { 'No MFA method registered at all' }
            else                                                  { 'Clear' }
    }

    # --- Housekeeping: enabled accounts nobody is paying for -----------------
    # An unlicensed account that can still sign in is the leaver-not-offboarded
    # shape. The script cannot know who left, so it flags rather than decides -
    # and never flags a role holder, since an unlicensed admin account is a
    # deliberate pattern, not an oversight.
    $isAdmin    = $adminIds.Contains($u.Id)
    $isLicensed = @($u.AssignedLicenses).Count -gt 0
    $lastSignIn = $null
    if ($haveSignIn -and $u.SignInActivity) {
        $lastSignIn = $u.SignInActivity.LastSignInDateTime
        if (-not $lastSignIn) { $lastSignIn = $u.SignInActivity.LastNonInteractiveSignInDateTime }
    }
    $dormantDays = if ($lastSignIn) { [int]((Get-Date) - $lastSignIn).TotalDays } else { $null }

    $housekeeping =
        if ($isLicensed)                              { '' }
        elseif ($isAdmin -and $strong.Count -eq 0 -and $phoneTypes.Count -eq 0) {
                                                        'ADMIN WITH NO MFA - a password is the only control' }
        elseif ($isAdmin)                             { 'Unlicensed admin account - expected, leave alone' }
        elseif ($null -ne $dormantDays -and $dormantDays -ge 90) {
                                                        "BLOCK SIGN-IN - unlicensed, no sign-in for $dormantDays days" }
        elseif ($null -ne $dormantDays)               { "Unlicensed but signed in $dormantDays days ago - confirm before blocking" }
        else                                          { 'REVIEW - unlicensed and sign-in still allowed' }

    # One shape for every row, error rows included - Export-Csv takes its headers
    # from the first object only, so a differently-shaped first row silently drops
    # columns for the whole file.
    [pscustomobject]@{
        UserPrincipalName = $u.UserPrincipalName
        DisplayName       = $u.DisplayName
        IsAdmin           = $isAdmin
        Licensed          = $isLicensed
        LastSignIn        = if ($lastSignIn) { $lastSignIn.ToString('yyyy-MM-dd') } else { '' }
        PhoneTypes        = @($phoneTypes | Select-Object -Unique) -join '; '
        PhoneNumbers      = @($phoneNums  | Select-Object -Unique) -join '; '
        SurvivingMethods  = $strong -join '; '
        OtherMethods      = @($weakOther | Select-Object -Unique) -join '; '
        Verdict           = $verdict
        Housekeeping      = $housekeeping
    }
}

Write-Progress -Activity 'Reading authentication methods' -Completed

$rows = @($rows)

# Never let a failed run overwrite a good CSV with an empty one.
if (-not $rows.Count) {
    Write-Host "`nNo users returned - nothing written. Previous CSV left alone." -ForegroundColor Red
    exit 1
}
if ($OutputPath) { $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 }

# --- One or a few named users: print them, skip the tenant statistics ------------
# Counting "1 of 1 enabled members" tells nobody anything. Show the account.
if ($User) {
    foreach ($r in $rows) {
        Write-Host ("`n===== {0} =====" -f $r.UserPrincipalName) -ForegroundColor Cyan
        Write-Host ("  Name              : {0}" -f $r.DisplayName)
        Write-Host ("  Directory role    : {0}" -f $(if ($r.IsAdmin) { 'YES' } else { 'no' }))
        Write-Host ("  Licensed          : {0}" -f $(if ($r.Licensed) { 'yes' } else { 'NO' }))
        if ($r.LastSignIn)   { Write-Host ("  Last sign-in      : {0}" -f $r.LastSignIn) }
        if ($r.PhoneTypes)   { Write-Host ("  Phone             : {0}  ({1})" -f $r.PhoneNumbers, $r.PhoneTypes) }
        Write-Host ("  Surviving methods : {0}" -f $(if ($r.SurvivingMethods) { $r.SurvivingMethods } else { 'NONE' }))
        if ($r.OtherMethods)  { Write-Host ("  Other             : {0}" -f $r.OtherMethods) }

        $colour = switch -Wildcard ($r.Verdict) {
            'BLOCKED*' { 'Red';    break }
            'UNREAD'   { 'Yellow'; break }
            'No MFA*'  { 'Yellow'; break }
            default    { 'Green' }
        }
        Write-Host ("  Verdict           : {0}" -f $r.Verdict) -ForegroundColor $colour
        if ($r.Housekeeping) { Write-Host ("  Housekeeping      : {0}" -f $r.Housekeeping) -ForegroundColor Yellow }
    }
    if ($OutputPath) { Write-Host "`nCSV: $OutputPath" }
    return
}

# --- Summary --------------------------------------------------------------------
$blocked      = @($rows | Where-Object { $_.Verdict -like 'BLOCKED*' })
$blockedAdmin = @($blocked | Where-Object { $_.IsAdmin })
$noMfa        = @($rows | Where-Object { $_.Verdict -eq 'No MFA method registered at all' })
$adminNoMfa   = @($rows | Where-Object { $_.IsAdmin -and $_.Verdict -eq 'No MFA method registered at all' })
$unread       = @($rows | Where-Object { $_.Verdict -eq 'UNREAD' })
$phoneAny     = @($rows | Where-Object { $_.PhoneTypes })

Write-Host "`n===== $tenantName =====" -ForegroundColor Cyan
Write-Host ("Enabled members                         : {0}" -f $rows.Count)
Write-Host ("Have a phone number registered          : {0}" -f $phoneAny.Count)
Write-Host ("LOCKED OUT on 1 Feb 2027 (phone only)   : {0}" -f $blocked.Count) -ForegroundColor Yellow
Write-Host ("  ...of those, directory-role holders   : {0}" -f $blockedAdmin.Count) -ForegroundColor Red
Write-Host ("No MFA method registered at all         : {0}" -f $noMfa.Count)
if ($adminNoMfa.Count) {
    Write-Host ("  ...of those, DIRECTORY-ROLE HOLDERS    : {0}" -f $adminNoMfa.Count) -ForegroundColor Red
}
if ($unread.Count) {
    Write-Host ("COULD NOT READ (permissions?)           : {0}" -f $unread.Count) -ForegroundColor Yellow
}
if ($OutputPath) { Write-Host ("`nCSV: $OutputPath") }

if ($blockedAdmin.Count) {
    Write-Host "`nAdmins whose only factor is a phone:" -ForegroundColor Red
    $blockedAdmin | ForEach-Object { Write-Host "  $($_.UserPrincipalName)" }
}
if ($adminNoMfa.Count) {
    Write-Host "`nAdmins with NO second factor at all:" -ForegroundColor Red
    $adminNoMfa | ForEach-Object { Write-Host "  $($_.UserPrincipalName)" }
}

# --- Housekeeping ---------------------------------------------------------------
$house = @($rows | Where-Object { $_.Housekeeping -and $_.Housekeeping -notlike 'Unlicensed admin*' })
if ($house.Count) {
    Write-Host "`n----- Unlicensed accounts that can still sign in: $($house.Count) -----" -ForegroundColor Yellow
    if (-not $haveSignIn) {
        Write-Host "No sign-in dates available, so none of these can be called dormant." -ForegroundColor Yellow
    }
    $house | Sort-Object UserPrincipalName | ForEach-Object {
        Write-Host ("  {0,-40} {1}" -f $_.UserPrincipalName, $_.Housekeeping)
    }
    Write-Host "`nBlocking sign-in does not delete the account or its mailbox." -ForegroundColor DarkGray
    Write-Host "In the admin centre: user -> Account -> Block sign-in." -ForegroundColor DarkGray
}
