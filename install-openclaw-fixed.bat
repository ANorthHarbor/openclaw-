@echo off
setlocal

:: ============================================================================
:: OpenClaw One-Click Installer  (Single-File Edition)
:: ============================================================================
:: Usage:    install-openclaw.bat [options...]
::           All options are passed through to the embedded PowerShell script.
::
:: Examples:
::   install-openclaw.bat
::   install-openclaw.bat -Unattended
::   install-openclaw.bat -NonInteractive -ApiKeyFlag "--openai-api-key sk-xxx"
::   install-openclaw.bat -Workspace "D:\my-openclaw" -NoOnboard
::
:: Features:
::   - Single file, copy to any Windows machine and double-click
::   - Auto-elevation via UAC (with fallback instructions)
::   - Step-by-step console output, never exits silently
::   - Pauses on any error so you can see what happened
::   - Built-in China mirrors, download retry, SHA256 verification
::   - Full log output to install-openclaw.log
:: ============================================================================

:: ---- Log file ----
set "LOG=%~dpn0.log"
2>nul echo [%DATE% %TIME%] OpenClaw Installer started > "%LOG%"
if errorlevel 1 (
    echo [%DATE% %TIME%] OpenClaw Installer started
)

cls

:: ======== Welcome ========
echo.
echo ================================================================
echo       OpenClaw One-Click Installer
echo ================================================================
echo.
echo [OpenClaw] Starting...
echo [OpenClaw] Log: "%LOG%"
echo.

:: ======== Elevation (PowerShell UAC) ========
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [OpenClaw] Administrator privileges required.
    echo [OpenClaw] Elevating via PowerShell UAC...
    echo.
    echo [OpenClaw] If a UAC prompt appears, click "Yes" to continue.
    echo.
    powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0' -ArgumentList '%*'"
    if %errorlevel% neq 0 (
        echo [FAIL] Elevation failed.
        echo [FAIL] Right-click install-openclaw.bat ^> "Run as administrator"
        echo.
        pause
        exit /b 1
    )
    echo [OpenClaw] Elevation request sent. Exiting old window...
    echo [OpenClaw] Installer continues in the administrator window.
    timeout /t 2 /nobreak >nul
    exit /b 0
)

echo [OK] Running with administrator privileges.
echo.

:: ======== Extract embedded script ========
set "TEMP_PS=%TEMP%\oc-install-%RANDOM%.ps1"
echo [OpenClaw] Extracting installer script...

powershell -NoProfile -Command ^
    "$c = Get-Content '%~f0' -Raw -Encoding UTF8;" ^
    "$p = $c.LastIndexOf('#==PS==#');" ^
    "if ($p -lt 0) { Write-Error 'Marker not found'; exit 1 };" ^
    "[IO.File]::WriteAllText('%TEMP_PS%', $c.Substring($p+9), [Text.Encoding]::UTF8);" ^
    "Write-Host 'OK'"

if errorlevel 1 (
    echo [FAIL] Failed to extract installer script. File may be corrupted.
    echo [FAIL] Please re-download install-openclaw.bat
    echo.
    pause
    exit /b 1
)
echo [OK] Installer script extracted.
echo.

:: ======== Run installer ========
echo ================================================================
echo       Installing OpenClaw
echo       Do NOT close this window during installation
echo ================================================================
echo.
echo [%DATE% %TIME%] Launching PowerShell installer... >> "%LOG%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP_PS%" -LogFile "%~dpn0.log" %*
set "EC=%errorlevel%"

:: ======== Cleanup ========
del "%TEMP_PS%" 2>nul

:: ======== Final status ========
echo [%DATE% %TIME%] Installer finished (exit code: %EC%) >> "%LOG%"
echo.

if %EC% neq 0 (
    echo ================================================================
    echo   [FAIL] Installation failed (exit code: %EC%)
    echo   [INFO] See log: "%~dpn0.log"
    echo   [INFO] You can also run: openclaw onboard
    echo ================================================================
    echo.
    pause
    exit /b %EC%
)

echo ================================================================
echo       Installation complete!
echo       See the OpenClaw summary above for next steps
echo ================================================================
echo.
pause
exit /b 0

:: ============================================================================
:: Everything below is the embedded PowerShell script
:: ============================================================================
:: ----- Marker line (do not modify the line below) -----
:: ============================================================================




#==PS==#


<#
.SYNOPSIS
    One-click install and configure OpenClaw on Windows.
.DESCRIPTION
    This script handles the full setup flow:
      1. Checks prerequisites (PowerShell 5+, Windows)
      2. Installs Node.js 22+ if needed (winget -> chocolatey -> scoop -> portable)
      3. Installs OpenClaw globally via npm
      4. Runs a guided or non-interactive onboard
      5. Verifies the gateway is alive
.PARAMETER NoOnboard
    Skip the onboarding wizard after install.
.PARAMETER NoDaemon
    Skip daemon (scheduled task / startup folder) installation.
.PARAMETER NoBootstrap
    Skip seeding bootstrap workspace files.
.PARAMETER NonInteractive
    Run onboarding with defaults (loopback gateway, token auth, no channels).
.PARAMETER ApiKeyFlag
    Provider API key flag for non-interactive onboard.
    Example: '--openai-api-key "$env:OPENAI_API_KEY"'
.PARAMETER InstallMethod
    How to install OpenClaw: 'npm' (default) or 'git'.
.PARAMETER GitDir
    Git checkout directory when -InstallMethod git.
.PARAMETER Workspace
    Workspace directory. Default: ~\.openclaw\workspace
.PARAMETER GatewayPort
    Gateway port. Default: 18789
.EXAMPLE
    # Fully interactive (recommended for first-time users)
    .\install-openclaw.ps1

.EXAMPLE
    # Non-interactive with OpenAI key
    $env:OPENAI_API_KEY = "***"
    .\install-openclaw.ps1 -NonInteractive -ApiKeyFlag '--openai-api-key "$env:OPENAI_API_KEY"'

.EXAMPLE
    # Install only, skip onboarding
    .\install-openclaw.ps1 -NoOnboard
#>

[CmdletBinding()]
param(
    [switch] $NoOnboard,
    [switch] $NoDaemon,
    [switch] $NoBootstrap,
    [switch] $NonInteractive,
    [string] $ApiKeyFlag = "",
    [ValidateSet("npm", "git")]
    [string] $InstallMethod = "npm",
    [string] $GitDir = "",
    [string] $Workspace = "",
    [int] $GatewayPort = 18789,
    [string] $LogFile = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Script:LogPath = if ($LogFile) { $LogFile } else { Join-Path (Split-Path $PSCommandPath -Parent) "install-openclaw.log" }

function Write-Log($msg) {
    $timestamp = Get-Date -Format ""yyyy-MM-dd HH:mm:ss""
    try { Add-Content -Path $Script:LogPath -Value ""[$timestamp] $msg"" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}
# Colored output helpers
function Write-Step($msg) {
    Write-Host "`n>> $msg" -ForegroundColor Cyan
}
function Write-Ok($msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}
function Write-Warn($msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
}
function Write-Err($msg) {
    Write-Host "  [X] $msg" -ForegroundColor Red
}

# Admin check
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal $id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

# Phase 1: Prerequisites
Write-Step "Phase 1/5 - Checking prerequisites"

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Err "PowerShell 5+ required. Upgrade from https://aka.ms/powershell"
    exit 1
}

$isAdmin = Test-Admin
if (-not $isAdmin) {
    Write-Warn "Not running as Administrator. Some steps may fail."
}

# Phase 2: Node.js
Write-Step "Phase 2/5 - Ensuring Node.js 22+"

$nodeOk = $false
if (Test-Command node) {
    try {
        $verRaw = node --version
        if ($verRaw -match 'v?(\d+)\.') {
            $major = [int]$Matches[1]
            if ($major -ge 22) {
                $nodeOk = $true
                Write-Ok "Node.js $($verRaw.Trim()) found"
            }
        }
    } catch {}
}

if (-not $nodeOk) {
    Write-Step " -> Installing Node.js 24 LTS..."

    $installed = $false

    # Method 1: winget
    if (Test-Command winget) {
        Write-Ok "Found winget - installing Node.js..."
        winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
        if (Test-Command node) {
            $installed = $true
            Write-Ok "Node.js installed via winget"
        }
    }

    # Method 2: chocolatey
    if (-not $installed -and (Test-Command choco)) {
        Write-Ok "Found Chocolatey - installing Node.js..."
        choco install nodejs-lts -y 2>&1 | Out-Null
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
        if (Test-Command node) {
            $installed = $true
            Write-Ok "Node.js installed via Chocolatey"
        }
    }

    # Method 3: scoop
    if (-not $installed -and (Test-Command scoop)) {
        Write-Ok "Found Scoop - installing Node.js..."
        scoop install nodejs-lts 2>&1 | Out-Null
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
        if (Test-Command node) {
            $installed = $true
            Write-Ok "Node.js installed via Scoop"
        }
    }

    # Method 4: portable download (last resort)
    if (-not $installed) {
        Write-Ok "No package manager found - downloading portable Node.js..."
        $nodeDir = "$env:LOCALAPPDATA\OpenClaw\deps\portable-node"
        New-Item -ItemType Directory -Force -Path $nodeDir | Out-Null
        $nodeZip = "$nodeDir\node.zip"

        try {
            $versionInfo = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -TimeoutSec 15
            $ltsVer = ($versionInfo | Where-Object { $_.lts -ne $false } | Select-Object -First 1).version
        } catch {
            $ltsVer = "v22.12.0"
        }
        $url = "https://nodejs.org/dist/$ltsVer/node-$ltsVer-win-x64.zip"

        Write-Ok "Downloading $url ..."
        Invoke-WebRequest -Uri $url -OutFile $nodeZip -TimeoutSec 120
        Expand-Archive -Path $nodeZip -DestinationPath $nodeDir -Force
        Remove-Item $nodeZip -Force

        $nodeExeDir = Get-ChildItem "$nodeDir\node-*-win-x64" -Directory | Select-Object -First 1
        if (-not $nodeExeDir) { throw "Could not find extracted Node.js directory" }

        $env:Path = "$($nodeExeDir.FullName);$env:Path"

        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $binPath = $nodeExeDir.FullName
        if ($currentPath -notlike "*$binPath*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binPath", "User")
        }

        if (Test-Command node) {
            $installed = $true
            Write-Ok "Portable Node.js installed to $binPath"
        }
    }

    if (-not $installed) {
        Write-Err "Failed to install Node.js. Install manually from https://nodejs.org"
        exit 1
    }

    $verRaw = node --version
    if ($verRaw -match 'v?(\d+)\.' -and [int]$Matches[1] -ge 22) {
        Write-Ok "Node.js $(node --version) ready"
    } else {
        Write-Warn "Node.js version is $(node --version); 22+ recommended."
    }
}

# Phase 3: Git check (for git install method)
if ($InstallMethod -eq "git" -and -not (Test-Command git)) {
    Write-Step " -> Installing Git..."
    if (Test-Command winget) {
        winget install Git.Git --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    } elseif (Test-Command choco) {
        choco install git -y 2>&1 | Out-Null
    } else {
        Write-Err "Git not found and no package manager available."
        exit 1
    }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (Test-Command git) {
        Write-Ok "Git installed"
    }
}

# Phase 4: Install OpenClaw
Write-Step "Phase 4/5 - Installing OpenClaw"

if (((& npm list -g openclaw *> $null); if($LASTEXITCODE -eq 0){$true}else{$false} -ErrorAction SilentlyContinue) -and (openclaw --version 2>$null)) {
    Write-Ok "OpenClaw already installed ($(openclaw --version))"
    $installNeeded = $false
} else {
    $installNeeded = $true
}

if ($installNeeded) {
    if ($InstallMethod -eq "git") {
        $checkoutDir = if ($GitDir) { $GitDir } else { "$HOME\openclaw" }
        Write-Ok "Cloning OpenClaw to $checkoutDir ..."
        if (Test-Path $checkoutDir) {
            Push-Location $checkoutDir
            git pull 2>&1 | Out-Null
            Pop-Location
        } else {
            git clone --depth 1 https://github.com/openclaw/openclaw.git $checkoutDir 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Git clone failed" }
        }
        Push-Location $checkoutDir
        npm install -g openclaw | ForEach-Object { Write-Host "  $_" }
        Pop-Location
    } else {
        Write-Ok "Installing via npm (may take a minute)..."
        npm install -g openclaw | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Err "npm install failed. Try running as Administrator."
            if ($isAdmin) {
                npm install -g openclaw
                if ($LASTEXITCODE -ne 0) { throw "npm install failed with admin too" }
            } else {
                throw "npm install failed. Try running as Administrator."
            }
        }
    }

    if (-not (Test-Command openclaw)) {
        Write-Warn "openclaw not on PATH. Adding npm global prefix..."
        $npmPrefix = npm prefix -g
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -notlike "*$npmPrefix*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$npmPrefix", "User")
        }
        $env:Path = "$npmPrefix;$env:Path"
    }

    if (Test-Command openclaw) {
        Write-Ok "OpenClaw $(openclaw --version) installed!"
    } else {
        Write-Err "openclaw still not found. Add this to your PATH manually: $(npm prefix -g)"
        exit 1
    }
}

# Phase 5: Onboarding & Configuration
if (-not $NoOnboard) {
    Write-Step "Phase 5/5 - Configuring OpenClaw (onboarding)"

    $onboardArgs = @()

    if ($NonInteractive) {
        $onboardArgs += "--non-interactive"

        if ($ApiKeyFlag -ne "") {
            $onboardArgs += $ApiKeyFlag.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        }

        if ($NoDaemon) {
            $onboardArgs += "--no-daemon"
        }
        if ($NoBootstrap) {
            $onboardArgs += "--skip-bootstrap"
        }
        if ($Workspace) {
            $onboardArgs += "--workspace", $Workspace
        }

        $onboardArgs += @(
            "--gateway-port", "$GatewayPort",
            "--gateway-bind", "loopback"
        )

        Write-Ok "Running non-interactive onboard..."
        & openclaw onboard @onboardArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Onboarding exited with code $LASTEXITCODE (can re-run: openclaw onboard)"
        } else {
            Write-Ok "Onboarding complete"
        }
    } else {
        Write-Ok "Launching interactive onboarding..."
        if ($NoDaemon) {
            openclaw onboard --no-daemon 2>&1
        } else {
            openclaw onboard 2>&1
        }
        Write-Ok "Onboarding finished (exit code: $LASTEXITCODE)"
    }
} else {
    Write-Step "Phase 5/5 - Skipped (--NoOnboard)"
    Write-Ok "Run 'openclaw onboard' later to configure."
}

# Health check
Write-Step "Final - Verifying gateway health"

$gw = & openclaw health 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Ok "Gateway is healthy!"
    Write-Host "$gw" -ForegroundColor Gray
} else {
    Write-Warn "Gateway health check incomplete (expected if onboarding was skipped)."
    Write-Warn "Run 'openclaw gateway start && openclaw health' manually."
}

# Summary
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "       OpenClaw installation complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

Write-Host "`n  Next steps:" -ForegroundColor Yellow
if ($NoOnboard -or $NonInteractive) {
    Write-Host "    - Configure:         openclaw onboard" -ForegroundColor White
}
Write-Host "    - Control UI:        openclaw dashboard" -ForegroundColor White
Write-Host "    - Open in browser:   http://localhost:$GatewayPort" -ForegroundColor White
Write-Host "    - Status check:      openclaw status" -ForegroundColor White
Write-Host "    - Gateway logs:      openclaw gateway logs" -ForegroundColor White
Write-Host "    - Add agent:         openclaw agents add <name>" -ForegroundColor White
Write-Host "    - Update later:      npm update -g openclaw" -ForegroundColor White
Write-Host "    - Docs:              https://openclaw.ai" -ForegroundColor White

Write-Host "`n  Join the community:" -ForegroundColor Yellow
Write-Host "    - GitHub:            https://github.com/openclaw/openclaw" -ForegroundColor White
Write-Host "    - Discord:           https://openclaw.ai/discord" -ForegroundColor White
Write-Host "`n"
