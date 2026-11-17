<#
.SYNOPSIS
    Автоматическое обновление net-snmp 5.9.4 -> 5.9.5 в кастомной CMake-раскладке.
.DESCRIPTION
    Копирует обновлённые файлы из overlay, вносит точечные правки в net-snmp-config.h
    и CMakeLists.var, проверяет результат. Не требует ручного редактирования.
.PARAMETER RepoPath
    Путь к вашему репозиторию (по умолчанию D:\repos\netsnmp).
.PARAMETER OverlayPath
    Путь к распакованному архиву ветки update/5.9.5 (содержит netsnmp/, netsnmpagent/, snmpnetstat/ и *.md).
.PARAMETER Commit
    Если указан — автоматически создаёт коммит после успешного обновления.
.EXAMPLE
    .\apply-update.ps1 -RepoPath D:\repos\netsnmp -OverlayPath C:\Downloads\net-snmp-update-5.9.5
#>
[CmdletBinding()]
param(
    [string]$RepoPath = "D:\repos\netsnmp",
    [Parameter(Mandatory=$true)][string]$OverlayPath,
    [switch]$Commit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# --- Validate paths ---
if (-not (Test-Path $RepoPath)) { throw "RepoPath not found: $RepoPath" }
if (-not (Test-Path $OverlayPath)) { throw "OverlayPath not found: $OverlayPath" }
$configH = Join-Path $RepoPath "netsnmp\include\net-snmp\net-snmp-config.h"
$cmakeVar = Join-Path $RepoPath "netsnmp\CMakeLists.var"
if (-not (Test-Path $configH)) { throw "net-snmp-config.h not found at $configH" }
if (-not (Test-Path $cmakeVar)) { throw "CMakeLists.var not found at $cmakeVar" }

# --- Detect line ending & encoding helper ---
function Read-TextFile($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    # strip BOM if present
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}
function Write-TextFile($path, $text) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

# --- Backups ---
Write-Step "Creating backups"
$bakConfig = "$configH.bak-594"
$bakCmake  = "$cmakeVar.bak-594"
Copy-Item $configH $bakConfig -Force
Copy-Item $cmakeVar $bakCmake -Force
Write-Ok "Backed up config.h and CMakeLists.var (.bak-594)"

try {

# ============================================================
# STEP 1: Copy overlay files
# ============================================================
Write-Step "Step 1: Copying updated source/header files"
$excludeNames = @('README.md','CONFIG_H_MERGE_GUIDE.md','CMAKELISTS_VAR_ADDITIONS.md','.gitignore','.DS_Store','apply-update.ps1')
$copied = 0
Get-ChildItem -Path $OverlayPath -Recurse -File | Where-Object {
    $excludeNames -notcontains $_.Name
} | ForEach-Object {
    $rel = $_.FullName.Substring($OverlayPath.Length).TrimStart('\','/')
    $dest = Join-Path $RepoPath $rel
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Copy-Item $_.FullName $dest -Force
    $copied++
}
if ($copied -lt 260) { throw "Expected ~265 files, copied only $copied. Check OverlayPath structure." }
Write-Ok "Copied $copied files"

# ============================================================
# STEP 2: Edit net-snmp-config.h
# ============================================================
Write-Step "Step 2: Applying config.h merge edits"
$h = Read-TextFile $configH
$originalH = $h
$nl = if ($h.Contains("`r`n")) { "`r`n" } else { "`n" }
$editCount = 0

# 2.1 NETSNMP_REQUIRE_SEMICOLON
$oldMacro = '#define NETSNMP_REQUIRE_SEMICOLON extern void netsnmp_unused_function(void)'
$newMacro = '#define NETSNMP_REQUIRE_SEMICOLON struct netsnmp_unused_struct'
if ($h.Contains($oldMacro)) {
    $h = $h.Replace($oldMacro, $newMacro)
    $editCount++; Write-Ok "2.1 NETSNMP_REQUIRE_SEMICOLON updated"
} elseif ($h.Contains($newMacro)) {
    Write-Ok "2.1 NETSNMP_REQUIRE_SEMICOLON already updated (skip)"
} else {
    throw "2.1 Cannot find NETSNMP_REQUIRE_SEMICOLON macro line"
}

# 2.2 AES CFB128 conditional — handle both upstream-style and hand-modified inner pattern
# Pattern A: full upstream condition with NETSNMP_USE_OPENSSL + INTERNAL_CRYPTO alternative
$aesPatternA = '(?m)^#if\s+\(defined\(NETSNMP_USE_OPENSSL\)\s*&&\s*defined\(HAVE_OPENSSL_AES_H\)\s*&&\s*defined\(HAVE_AES_CFB128_ENCRYPT\)\)\s*\|\|\s*defined\(NETSNMP_USE_INTERNAL_CRYPTO\)'
$aesReplacementA = @"
#if (defined(NETSNMP_USE_OPENSSL) &&            \
     defined(HAVE_OPENSSL_AES_H) &&             \
     defined(HAVE_AES_CFB128_ENCRYPT) &&        \
     defined(HAVE_EVP_AES_128_CFB)) ||          \
    defined(NETSNMP_USE_INTERNAL_CRYPTO)
"@.Replace("`r`n","`n").Replace("`n",$nl)
# Pattern B: simplified inner condition (inside outer #ifdef NETSNMP_USE_OPENSSL), flexible spacing
$aesPatternB = '(?m)^#if\s+defined\(HAVE_OPENSSL_AES_H\)\s*&&\s*defined\(HAVE_AES_CFB128_ENCRYPT\)\s*$'
$aesReplacementB = '#if defined(HAVE_OPENSSL_AES_H) && defined(HAVE_AES_CFB128_ENCRYPT) && defined(HAVE_EVP_AES_128_CFB)'
if ($h -match $aesPatternA) {
    $h = [regex]::Replace($h, $aesPatternA, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $aesReplacementA })
    $editCount++; Write-Ok "2.2 AES CFB128 conditional updated (upstream pattern)"
} elseif ($h -match $aesPatternB) {
    $h = [regex]::Replace($h, $aesPatternB, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $aesReplacementB })
    $editCount++; Write-Ok "2.2 AES CFB128 conditional updated (inner pattern)"
} elseif ($h.Contains('HAVE_EVP_AES_128_CFB')) {
    Write-Ok "2.2 AES conditional already updated (skip)"
} else {
    throw "2.2 Cannot find AES CFB128 #if block (tried upstream and inner patterns)"
}

# 2.3 __STDC_WANT_IEC_60559_EXT__ guard before FUNCS_EXT
$stdcGuard = @"
/* Enable extensions specified by C23 Annex F.  */
#ifndef __STDC_WANT_IEC_60559_EXT__
# undef __STDC_WANT_IEC_60559_EXT__
#endif
"@.Replace("`r`n","`n").Replace("`n",$nl)
$funcsAnchor = '/* Enable extensions specified by ISO/IEC TS 18661-4:2015.'
if ($h.Contains('__STDC_WANT_IEC_60559_EXT__')) {
    Write-Ok "2.3 STDC guard already present (skip)"
} elseif ($h.Contains($funcsAnchor)) {
    $idx = $h.IndexOf($funcsAnchor)
    $h = $h.Substring(0,$idx) + $stdcGuard + $nl + $h.Substring($idx)
    $editCount++; Write-Ok "2.3 STDC IEC_60559_EXT guard inserted"
} else {
    # fallback: insert before first __STDC_WANT occurrence
    $m = [regex]::Match($h, '(?m)^.*__STDC_WANT_IEC_60559_FUNCS_EXT__')
    if ($m.Success) {
        $lineStart = $h.LastIndexOf($nl, $m.Index) + $nl.Length
        if ($lineStart -lt $nl.Length) { $lineStart = 0 }
        $h = $h.Substring(0,$lineStart) + $stdcGuard + $nl + $h.Substring($lineStart)
        $editCount++; Write-Ok "2.3 STDC guard inserted (fallback anchor)"
    } else {
        throw "2.3 Cannot find __STDC_WANT_IEC_60559_FUNCS_EXT__ anchor"
    }
}

# 2.4 Insert new HAVE_* symbols after their predecessors (in order)
$newSymbols = @(
    @{ Sym='HAVE_ASN_BOOLEAN'; After='HAVE_ASN1_STRING_GET0_DATA'; Block="/* Define to 1 if the 'ASN_BOOLEAN' constant is defined in an SSL header file. */${nl}#undef HAVE_ASN_BOOLEAN" },
    @{ Sym='HAVE_ASN_INTEGER'; After='HAVE_ASN_BOOLEAN'; Block="/* Define to 1 if the 'ASN_INTEGER' constant is defined in an SSL header file. */${nl}#undef HAVE_ASN_INTEGER" },
    @{ Sym='HAVE_ASN_OBJECT_ID'; After='HAVE_ASN_INTEGER'; Block="/* Define to 1 if the 'ASN_OBJECT_ID' constant is defined in an SSL header file. */${nl}#undef HAVE_ASN_OBJECT_ID" },
    @{ Sym='HAVE_ASN_SEQUENCE'; After='HAVE_ASN_OBJECT_ID'; Block="/* Define to 1 if the 'ASN_SEQUENCE' constant is defined in an SSL header file. */${nl}#undef HAVE_ASN_SEQUENCE" },
    @{ Sym='HAVE_ASN_SET'; After='HAVE_ASN_SEQUENCE'; Block="/* Define to 1 if the 'ASN_SET' constant is defined in an SSL header file. */${nl}#undef HAVE_ASN_SET" },
    @{ Sym='HAVE_ERR_GET_ERROR_FUNC'; After='HAVE_ERR_GET_ERROR_ALL'; Block="/* Define to 1 if you have the 'ERR_get_error_func' function. */${nl}#undef HAVE_ERR_GET_ERROR_FUNC" },
    @{ Sym='HAVE_EVP_AES_128_CFB'; After='HAVE_EVAL_PV'; Block="/* Define to 1 if you have the 'EVP_aes_128_cfb' function. */${nl}#undef HAVE_EVP_AES_128_CFB" },
    @{ Sym='HAVE_GETNETGRENT'; After='HAVE_GETMNTINFO'; Block="/* Define to 1 if you have the 'getnetgrent' function. */${nl}#undef HAVE_GETNETGRENT" },
    @{ Sym='HAVE_IPV6_RECVPKTINFO'; After='HAVE_IPHLPAPI_H'; Block="/* Set if IPV6_RECVPKTINFO is usable */${nl}#undef HAVE_IPV6_RECVPKTINFO" },
    @{ Sym='HAVE_LIBSSH2_SESSION_HANDSHAKE'; After='HAVE_LIBSSH2'; Block="/* Define to 1 if you have the 'libssh2_session_handshake' function. */${nl}#undef HAVE_LIBSSH2_SESSION_HANDSHAKE" },
    @{ Sym='HAVE_MALLOC_TRIM'; After='HAVE_MALLOC_H'; Block="/* Define to 1 if you have the 'malloc_trim' function. */${nl}#undef HAVE_MALLOC_TRIM" },
    @{ Sym='HAVE_NETGROUP_H'; After='HAVE_NETDB_H'; Block="/* Define to 1 if you have the <netgroup.h> header file. */${nl}#undef HAVE_NETGROUP_H" },
    @{ Sym='HAVE_NETLINK_CACHE_H'; After='HAVE_NETIPX_IPX_H'; Block="/* Define to 1 if you have the <netlink/cache.h> header file. */${nl}#undef HAVE_NETLINK_CACHE_H" },
    @{ Sym='HAVE_NETLINK_MSG_H'; After='HAVE_NETLINK_CACHE_H'; Block="/* Define to 1 if you have the <netlink/msg.h> header file. */${nl}#undef HAVE_NETLINK_MSG_H" },
    @{ Sym='HAVE_NETLINK_ROUTE_ADDR_H'; After='HAVE_NETLINK_NETLINK_H'; Block="/* Define to 1 if you have the <netlink/route/addr.h> header file. */${nl}#undef HAVE_NETLINK_ROUTE_ADDR_H" },
    @{ Sym='HAVE_NETLINK_ROUTE_LINK_H'; After='HAVE_NETLINK_ROUTE_ADDR_H'; Block="/* Define to 1 if you have the <netlink/route/link.h> header file. */${nl}#undef HAVE_NETLINK_ROUTE_LINK_H" },
    @{ Sym='HAVE_NETLINK_SOCKET_H'; After='HAVE_NETLINK_ROUTE_LINK_H'; Block="/* Define to 1 if you have the <netlink/socket.h> header file. */${nl}#undef HAVE_NETLINK_SOCKET_H" },
    @{ Sym='HAVE_OPENSSL_ERR_H'; After='HAVE_OPENSSL_DH_H'; Block="/* Define to 1 if you have the <openssl/err.h> header file. */${nl}#undef HAVE_OPENSSL_ERR_H" },
    @{ Sym='HAVE_OPENSSL_SSL_H'; After='HAVE_OPENSSL_SK_VALUE'; Block="/* Define to 1 if you have the <openssl/ssl.h> header file. */${nl}#undef HAVE_OPENSSL_SSL_H" },
    @{ Sym='HAVE_SSL_CTX_SET_COOKIE_GENERATE_CB'; After='HAVE_SSIZE_T'; Block="/* Define to 1 if you have the 'SSL_CTX_set_cookie_generate_cb' function. */${nl}#undef HAVE_SSL_CTX_SET_COOKIE_GENERATE_CB" },
    @{ Sym='HAVE_SYS_CALLOUT_H'; After='HAVE_SYSTEM'; Block="/* Define to 1 if you have the <sys/callout.h> header file. */${nl}#undef HAVE_SYS_CALLOUT_H" },
    @{ Sym='HAVE_SYS_OSD_H'; After='HAVE_SYS_NDIR_H'; Block="/* Define to 1 if you have the <sys/osd.h> header file. */${nl}#undef HAVE_SYS_OSD_H" },
    @{ Sym='HAVE_VOID_EVP_MD_CTX_INIT'; After='HAVE_VM_VM_PARAM_H'; Block="/* Define this macro if EVP_MD_CTX_init() returns void */${nl}#undef HAVE_VOID_EVP_MD_CTX_INIT" },
    @{ Sym='HAVE_WOLFSSL_WOLFCRYPT_ASN_H'; After='HAVE_WINSOCK_H'; Block="/* Define to 1 if you have the <wolfssl/wolfcrypt/asn.h> header file. */${nl}#undef HAVE_WOLFSSL_WOLFCRYPT_ASN_H" },
    @{ Sym='HAVE_WOLFSSL_WOLFCRYPT_LOGGING_H'; After='HAVE_WOLFSSL_WOLFCRYPT_ASN_H'; Block="/* Define to 1 if you have the <wolfssl/wolfcrypt/logging.h> header file. */${nl}#undef HAVE_WOLFSSL_WOLFCRYPT_LOGGING_H" }
)
$inserted = 0; $skipped = 0
foreach ($entry in $newSymbols) {
    $sym = $entry.Sym; $after = $entry.After; $block = $entry.Block
    if ($h -match "(?m)^#\s*(define|undef)\s+$sym\b") { $skipped++; continue }
    # Find anchor line (define or undef of predecessor), insert block after its full line
    $anchorPat = "(?m)^#\s*(?:define|undef)\s+$after\b[^\r\n]*"
    $am = [regex]::Match($h, $anchorPat)
    if (-not $am.Success) {
        # predecessor might be commented-out undef: /* #undef SYM */
        $anchorPat2 = "(?m)/\*\s*#\s*undef\s+$after\s*\*/"
        $am = [regex]::Match($h, $anchorPat2)
    }
    if ($am.Success) {
        $insertAt = $am.Index + $am.Length
        $h = $h.Substring(0,$insertAt) + $nl + $block + $h.Substring($insertAt)
        $inserted++
    } else {
        throw "2.4 Cannot find anchor '$after' for inserting '$sym'"
    }
}
Write-Ok "2.4 New HAVE_* symbols: $inserted inserted, $skipped already present"
$editCount += $inserted

# 2.5 Remove HAVE_SECURITY_CRYPTOKI_H
$cryptokiPat = '(?m)^.*HAVE_SECURITY_CRYPTOKI_H.*\r?\n?'
if ($h -match $cryptokiPat) {
    $h = [regex]::Replace($h, $cryptokiPat, '')
    $editCount++; Write-Ok "2.5 HAVE_SECURITY_CRYPTOKI_H removed"
} else {
    Write-Ok "2.5 HAVE_SECURITY_CRYPTOKI_H not present (skip)"
}

Write-TextFile $configH $h
Write-Ok "config.h saved ($editCount edits applied)"

# ============================================================
# STEP 3: Edit CMakeLists.var
# ============================================================
Write-Step "Step 3: Updating CMakeLists.var"
$v = Read-TextFile $cmakeVar
$vnl = if ($v.Contains("`r`n")) { "`r`n" } else { "`n" }
$varEdits = 0

# 3.1 freebsd15/16 after freebsd14
if ($v.Contains('include/net-snmp/system/freebsd15.h')) {
    Write-Ok "3.1 freebsd15/16 already present (skip)"
} else {
    $anchor = 'include/net-snmp/system/freebsd14.h'
    if (-not $v.Contains($anchor)) { throw "3.1 Anchor freebsd14.h not found in CMakeLists.var" }
    $v = $v.Replace($anchor, $anchor + $vnl + 'include/net-snmp/system/freebsd15.h' + $vnl + 'include/net-snmp/system/freebsd16.h')
    $varEdits++; Write-Ok "3.1 freebsd15.h + freebsd16.h inserted"
}

# 3.2 openbsd8 after openbsd7
if ($v.Contains('include/net-snmp/system/openbsd8.h')) {
    Write-Ok "3.2 openbsd8 already present (skip)"
} else {
    $anchor = 'include/net-snmp/system/openbsd7.h'
    if (-not $v.Contains($anchor)) { throw "3.2 Anchor openbsd7.h not found in CMakeLists.var" }
    $v = $v.Replace($anchor, $anchor + $vnl + 'include/net-snmp/system/openbsd8.h')
    $varEdits++; Write-Ok "3.2 openbsd8.h inserted"
}

Write-TextFile $cmakeVar $v
Write-Ok "CMakeLists.var saved ($varEdits edits)"

# ============================================================
# STEP 4: Verification
# ============================================================
Write-Step "Step 4: Final verification"
$hCheck = Read-TextFile $configH
$vCheck = Read-TextFile $cmakeVar
$failures = @()

if (-not $hCheck.Contains('struct netsnmp_unused_struct')) { $failures += "SEMICOLON macro not updated" }
if (-not $hCheck.Contains('HAVE_EVP_AES_128_CFB')) { $failures += "AES conditional missing EVP check" }
if (-not $hCheck.Contains('__STDC_WANT_IEC_60559_EXT__')) { $failures += "STDC guard missing" }
foreach ($entry in $newSymbols) {
    if (-not ($hCheck -match "(?m)^#\s*(define|undef)\s+$($entry.Sym)\b")) { $failures += "Missing symbol $($entry.Sym)" }
}
if ($hCheck.Contains('HAVE_SECURITY_CRYPTOKI_H')) { $failures += "CRYPTOKI_H not removed" }
if (-not $vCheck.Contains('freebsd15.h')) { $failures += "CMakeLists.var missing freebsd15" }
if (-not $vCheck.Contains('freebsd16.h')) { $failures += "CMakeLists.var missing freebsd16" }
if (-not $vCheck.Contains('openbsd8.h')) { $failures += "CMakeLists.var missing openbsd8" }

if ($failures.Count -eq 0) {
    Write-Ok "ALL CHECKS PASSED"
} else {
    foreach ($f in $failures) { Write-Fail $f }
    throw "Verification failed with $($failures.Count) issue(s). Backups preserved at .bak-594"
}

# ============================================================
# Optional commit
# ============================================================
if ($Commit) {
    Write-Step "Creating git commit"
    Push-Location $RepoPath
    git add -A
    git commit -m "Update net-snmp 5.9.4 -> 5.9.5 (automated)"
    Pop-Location
    Write-Ok "Committed"
} else {
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  cd $RepoPath"
    Write-Host "  git diff --stat        # review changes"
    Write-Host "  git add -A && git commit -m 'Update net-snmp 5.9.4 -> 5.9.5'"
    Write-Host "  git tag v5.9.5"
    Write-Host "  # Then build all components to verify compilation"
}

Write-Host "`n=== UPDATE COMPLETE ===" -ForegroundColor Green

} catch {
    Write-Fail $_.Exception.Message
    Write-Host "`nRestoring backups..." -ForegroundColor Yellow
    Copy-Item $bakConfig $configH -Force
    Copy-Item $bakCmake $cmakeVar -Force
    Write-Host "Backups restored. Repository returned to pre-update state." -ForegroundColor Yellow
    exit 1
}
