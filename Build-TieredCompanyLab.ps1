<#
================================================================================
 Build-TieredCompanyLab.ps1
================================================================================
 Builds a realistic fictional company in Active Directory following the
 Microsoft tiered administration model (Tier 0 / 1 / 2), aligned with
 least-privilege / separation-of-duties principles.

 RUN ON THE DC, in an ELEVATED PowerShell window.

 Design (grounded in Microsoft tiered model + AD OU best practice):
   - Object-type top level (Employees / Workstations / Servers / Groups / SvcAccts)
   - Departments nested under Employees (org-chart axis kept separate from tier axis)
   - Admin identities in a separate tiered tree (Admin\Tier0|Tier1|Tier2)
   - IT staff get PAIRED accounts: a normal daily account + a separate admin
     account placed in the correct tier
   - Tiered security groups + GPO scaffolding scoped per tier (no cross-tier links)

 Idempotent: checks before creating; safe to re-run.
 Everything is removable - teardown one-liner printed at the end.

 Default passwords:
   Standard users : CHANGE-ME-StdPw
   Admin accounts : CHANGE-ME-AdmPw  (separate, as the tier model requires)
 Change $StdPw / $AdmPw below if desired.
================================================================================
#>

# ============================ SETTINGS ============================
$Dom        = Get-ADDomain
$DomainDN   = $Dom.DistinguishedName
$NetBIOS    = $Dom.NetBIOSName
$DnsRoot    = $Dom.DNSRoot
$StdPw      = ConvertTo-SecureString "CHANGE-ME-StdPw" -AsPlainText -Force
$AdmPw      = ConvertTo-SecureString "CHANGE-ME-AdmPw"   -AsPlainText -Force
$ProtectOU  = $false   # set $true once you're done building, to prevent accidental deletion
# ==================================================================

Import-Module ActiveDirectory -ErrorAction Stop
$haveGPO = $false
try { Import-Module GroupPolicy -ErrorAction Stop; $haveGPO = $true } catch {}

# ---------- helpers ----------
function New-OUIfMissing {
    param([string]$Name,[string]$Path)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $ProtectOU
        Write-Host "  + OU  $dn" -ForegroundColor Green
    }
    return $dn
}
function New-GroupIfMissing {
    param([string]$Name,[string]$Path,[string]$Scope="Global",[string]$Desc="")
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $Name -GroupScope $Scope -GroupCategory Security -Path $Path -Description $Desc
        Write-Host "  + GRP $Name" -ForegroundColor Green
    }
}
function New-UserIfMissing {
    param(
        [string]$First,[string]$Last,[string]$Sam,[string]$OU,
        [securestring]$Pw,[string]$Title,[string]$Dept,[switch]$IsAdmin
    )
    if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) { return }
    $display = if ($IsAdmin) { "$First $Last (ADM)" } else { "$First $Last" }
    $upn = "$Sam@$DnsRoot"
    New-ADUser -Name $display -GivenName $First -Surname $Last -SamAccountName $Sam `
        -UserPrincipalName $upn -Path $OU -AccountPassword $Pw -Enabled $true `
        -Title $Title -Department $Dept -ChangePasswordAtLogon $false
    Write-Host ("  + USR {0,-22} {1}" -f $Sam, $Title) -ForegroundColor Gray
}
function Get-Sam {
    param([string]$First,[string]$Last,[switch]$Admin)
    $base = ("{0}.{1}" -f $First, $Last).ToLower() -replace "[^a-z.]",""
    if ($Admin) { $base = "adm-$base" }
    if ($base.Length -gt 20) { $base = $base.Substring(0,20) }
    return $base
}

Write-Host "`n========== TIER / ADMIN TREE ==========" -ForegroundColor Cyan
$AdminDN = New-OUIfMissing "Admin" $DomainDN
$Tiers = "Tier0","Tier1","Tier2"
$TierDN = @{}
foreach ($t in $Tiers) {
    $TierDN[$t] = New-OUIfMissing $t $AdminDN
    New-OUIfMissing "Accounts" $TierDN[$t] | Out-Null
    New-OUIfMissing "Groups"   $TierDN[$t] | Out-Null
    $devName = switch ($t) { "Tier0" {"Devices"} "Tier1" {"Servers"} "Tier2" {"Workstations"} }
    New-OUIfMissing $devName $TierDN[$t] | Out-Null
}
$T0Accts = "OU=Accounts,$($TierDN['Tier0'])"
$T1Accts = "OU=Accounts,$($TierDN['Tier1'])"
$T2Accts = "OU=Accounts,$($TierDN['Tier2'])"
$T0Grp   = "OU=Groups,$($TierDN['Tier0'])"
$T1Grp   = "OU=Groups,$($TierDN['Tier1'])"
$T2Grp   = "OU=Groups,$($TierDN['Tier2'])"

Write-Host "`n========== TIERED ADMIN GROUPS ==========" -ForegroundColor Cyan
New-GroupIfMissing "Tier0-Admins" $T0Grp "Global" "Domain/identity admins - Tier 0 only"
New-GroupIfMissing "Tier1-ServerAdmins" $T1Grp "Global" "Server & infrastructure admins - Tier 1"
New-GroupIfMissing "Tier1-NetworkAdmins" $T1Grp "Global" "Network admins - Tier 1"
New-GroupIfMissing "Tier1-SOC-Analysts" $T1Grp "Global" "SOC analysts - monitoring, Tier 1"
New-GroupIfMissing "Tier2-Helpdesk-L1" $T2Grp "Global" "Level 1 helpdesk - workstation/user support"
New-GroupIfMissing "Tier2-Helpdesk-L2" $T2Grp "Global" "Level 2 helpdesk - desktop support"

Write-Host "`n========== OBJECT-TYPE TOP LEVEL ==========" -ForegroundColor Cyan
$EmpDN  = New-OUIfMissing "Employees"      $DomainDN
$WksDN  = New-OUIfMissing "Workstations"   $DomainDN
$SrvDN  = New-OUIfMissing "Servers"        $DomainDN
$GrpDN  = New-OUIfMissing "Groups"         $DomainDN
$SvcDN  = New-OUIfMissing "ServiceAccounts" $DomainDN

Write-Host "`n========== DEPARTMENT OUs (under Employees) ==========" -ForegroundColor Cyan
$Departments = "Executive","HumanResources","Finance","Sales","Marketing",
               "Operations","Legal","CustomerService","IT"
$DeptDN = @{}
foreach ($d in $Departments) { $DeptDN[$d] = New-OUIfMissing $d $EmpDN }
# IT sub-divided (the one dept that needs distinct delegation/policy)
$ITHelpdesk = New-OUIfMissing "Helpdesk"       $DeptDN["IT"]
$ITInfra    = New-OUIfMissing "Infrastructure" $DeptDN["IT"]
$ITSecurity = New-OUIfMissing "Security"       $DeptDN["IT"]

Write-Host "`n========== DEPARTMENT (RESOURCE) GROUPS ==========" -ForegroundColor Cyan
foreach ($d in $Departments) {
    New-GroupIfMissing "$d-Team" $GrpDN "Global" "$d department members"
}
foreach ($g in "VPN-Users","FileShare-RW","FileShare-RO","AllStaff") {
    New-GroupIfMissing $g $GrpDN "Global" "Resource access group"
}

# =============================================================================
#  PEOPLE
#  Non-IT departments: standard users only.
#  IT staff: PAIRED - normal account in Employees\IT\..  +  admin account in Admin\TierX
# =============================================================================

Write-Host "`n========== STANDARD EMPLOYEES (non-IT) ==========" -ForegroundColor Cyan
# realistic roster: name, dept, title
$staff = @(
    # Executive
    @("Margaret","Whitfield","Executive","Chief Executive Officer"),
    @("Daniel","Okafor","Executive","Chief Financial Officer"),
    @("Priya","Nair","Executive","Chief Operating Officer"),
    @("Stephen","Hollis","Executive","Chief Information Officer"),
    # HR
    @("Karen","Delacroix","HumanResources","HR Director"),
    @("Tomas","Bergstrom","HumanResources","HR Business Partner"),
    @("Aisha","Rahman","HumanResources","Recruiter"),
    @("Gary","Linton","HumanResources","HR Coordinator"),
    # Finance
    @("Helen","Cho","Finance","Finance Director"),
    @("Marcus","Webb","Finance","Senior Accountant"),
    @("Natalia","Ivanova","Finance","Accounts Payable Clerk"),
    @("Derek","Flynn","Finance","Payroll Specialist"),
    @("Yuki","Tanaka","Finance","Financial Analyst"),
    # Sales
    @("Robert","Castellano","Sales","Sales Director"),
    @("Olivia","Mensah","Sales","Account Executive"),
    @("Liam","O'Brien","Sales","Account Executive"),
    @("Sofia","Reyes","Sales","Sales Development Rep"),
    @("Carl","Jorgensen","Sales","Sales Development Rep"),
    @("Amara","Diallo","Sales","Regional Sales Manager"),
    # Marketing
    @("Jasmine","Patel","Marketing","Marketing Director"),
    @("Eric","Sundqvist","Marketing","Content Manager"),
    @("Bianca","Romano","Marketing","Social Media Specialist"),
    @("Noah","Kimura","Marketing","Graphic Designer"),
    # Operations
    @("Frank","Nowak","Operations","Operations Director"),
    @("Grace","Adeyemi","Operations","Operations Manager"),
    @("Victor","Hpone","Operations","Logistics Coordinator"),
    @("Mia","Lindqvist","Operations","Facilities Coordinator"),
    @("Hassan","Karimi","Operations","Procurement Specialist"),
    # Legal
    @("Eleanor","Vance","Legal","General Counsel"),
    @("Raj","Subramanian","Legal","Corporate Counsel"),
    @("Claire","Dubois","Legal","Paralegal"),
    # Customer Service
    @("Tyrone","Jackson","CustomerService","Customer Service Manager"),
    @("Wei","Zhang","CustomerService","Support Representative"),
    @("Isabella","Conti","CustomerService","Support Representative"),
    @("Omar","Haddad","CustomerService","Support Representative"),
    @("Fiona","Gallagher","CustomerService","Support Representative")
)
foreach ($p in $staff) {
    $first,$last,$dept,$title = $p
    $sam = Get-Sam $first $last
    New-UserIfMissing -First $first -Last $last -Sam $sam -OU $DeptDN[$dept] `
        -Pw $StdPw -Title $title -Dept $dept
    Add-ADGroupMember -Identity "$dept-Team" -Members $sam -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "AllStaff"   -Members $sam -ErrorAction SilentlyContinue
}

Write-Host "`n========== IT STAFF (paired: normal + admin accounts) ==========" -ForegroundColor Cyan
# name, IT sub-OU, title, tier-of-admin-account, tier-group
$itStaff = @(
    # Helpdesk L1/L2 -> Tier 2 admin accounts
    @("Brandon","Mills",   $ITHelpdesk,"Helpdesk Analyst L1","Tier2","Tier2-Helpdesk-L1"),
    @("Chelsea","Owusu",   $ITHelpdesk,"Helpdesk Analyst L1","Tier2","Tier2-Helpdesk-L1"),
    @("Devon","Pritchard", $ITHelpdesk,"Helpdesk Analyst L1","Tier2","Tier2-Helpdesk-L1"),
    @("Renata","Silva",    $ITHelpdesk,"Desktop Support L2","Tier2","Tier2-Helpdesk-L2"),
    @("Kwame","Boateng",   $ITHelpdesk,"Desktop Support L2","Tier2","Tier2-Helpdesk-L2"),
    # Infrastructure: L3 / server / network -> Tier 1
    @("Alan","Petrov",     $ITInfra,"Systems Administrator L3","Tier1","Tier1-ServerAdmins"),
    @("Mei","Lin",         $ITInfra,"Systems Administrator L3","Tier1","Tier1-ServerAdmins"),
    @("Gustavo","Marin",   $ITInfra,"Network Administrator","Tier1","Tier1-NetworkAdmins"),
    @("Beatrice","Kovac",  $ITInfra,"Network Engineer","Tier1","Tier1-NetworkAdmins"),
    # Security: SOC -> Tier 1 (monitoring), one identity/domain admin -> Tier 0
    @("Samuel","Adeniyi",  $ITSecurity,"SOC Analyst Tier 1","Tier1","Tier1-SOC-Analysts"),
    @("Lucia","Ferreira",  $ITSecurity,"SOC Analyst Tier 2","Tier1","Tier1-SOC-Analysts"),
    @("Hannah","Goldberg", $ITSecurity,"Security Engineer","Tier1","Tier1-SOC-Analysts"),
    @("Viktor","Andersson",$ITSecurity,"Identity & Domain Admin","Tier0","Tier0-Admins")
)
$tierAcctOU = @{ "Tier0"=$T0Accts; "Tier1"=$T1Accts; "Tier2"=$T2Accts }
foreach ($p in $itStaff) {
    $first,$last,$ou,$title,$tier,$tgrp = $p
    # 1) normal daily-driver account in IT dept
    $sam = Get-Sam $first $last
    New-UserIfMissing -First $first -Last $last -Sam $sam -OU $ou -Pw $StdPw -Title $title -Dept "IT"
    Add-ADGroupMember -Identity "IT-Team" -Members $sam -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "AllStaff" -Members $sam -ErrorAction SilentlyContinue
    # 2) separate ADMIN account in the correct tier
    $asam = Get-Sam $first $last -Admin
    New-UserIfMissing -First $first -Last $last -Sam $asam -OU $tierAcctOU[$tier] `
        -Pw $AdmPw -Title "$title (Admin)" -Dept "IT" -IsAdmin
    Add-ADGroupMember -Identity $tgrp -Members $asam -ErrorAction SilentlyContinue
}

Write-Host "`n========== GPO SCAFFOLDING (tier-scoped, no cross-tier links) ==========" -ForegroundColor Cyan
if ($haveGPO) {
    $gpos = @(
        @{ Name="Tier2 - Workstation Hardening"; Target=$WksDN },
        @{ Name="Tier1 - Server Hardening";      Target=$SrvDN },
        @{ Name="Baseline - All Employees";      Target=$EmpDN },
        @{ Name="IT - Helpdesk Tools";           Target=$DeptDN["IT"] }
    )
    foreach ($g in $gpos) {
        if (-not (Get-GPO -Name $g.Name -ErrorAction SilentlyContinue)) {
            New-GPO -Name $g.Name | Out-Null
            New-GPLink -Name $g.Name -Target $g.Target -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  + GPO '$($g.Name)' linked to $($g.Target)" -ForegroundColor Green
        }
    }
    Write-Host "  (GPOs created empty - configure settings in GPMC to practice)" -ForegroundColor DarkGray
} else {
    Write-Host "  GroupPolicy module unavailable - skipped. Install RSAT-GPMC to add." -ForegroundColor Yellow
}

Write-Host "`n================ DONE ================" -ForegroundColor Cyan
Write-Host "Standard user password : CHANGE-ME-StdPw"
Write-Host "Admin account password : CHANGE-ME-AdmPw"
Write-Host "IT staff have TWO accounts each: 'first.last' (daily) and 'adm-first.last' (tiered admin)."
Write-Host ""
Write-Host "TEARDOWN (removes everything this script made):" -ForegroundColor Yellow
Write-Host "  'Admin','Employees','Workstations','Servers','Groups','ServiceAccounts' | ForEach-Object {"
Write-Host "     Get-ADOrganizationalUnit -Filter \"Name -eq '`$_'\" -SearchBase '$DomainDN' -SearchScope OneLevel |"
Write-Host "     Set-ADObject -ProtectedFromAccidentalDeletion `$false -PassThru |"
Write-Host "     Remove-ADOrganizationalUnit -Recursive -Confirm:`$false }"
Write-Host "  # plus: Get-GPO -All | ? DisplayName -match '^(Tier|Baseline|IT) ' | Remove-GPO"