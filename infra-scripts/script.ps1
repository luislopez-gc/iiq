# script.ps1
# Tomcat 9 Installation Script for Windows Server 2025
# This script installs Microsoft OpenJDK, Apache Tomcat 9, Microsoft JDBC Driver, Microsoft SQL Server Developer Edition, OpenSSH

#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory = $true)]
    [string] $tomcat_admin_username,

    [Parameter(Mandatory = $true)]
    [string] $tomcat_admin_password,

    [Parameter(Mandatory = $true)]
    [string] $sql_sa_password
)

# =========================
# Config (edit if desired)
# =========================
$downloadDir   = "C:\Temp\TomcatInstall"
$installDir    = "C:\Program Files\Apache Software Foundation\Tomcat 9.0"
$jdkInstallDir = "C:\Program Files\Microsoft\jdk-21"
$serviceName   = "Tomcat9"

# SQL Server install preferences
$SqlInstanceName        = "MSSQLSERVER"              # default instance
$SqlSysAdminAccounts    = @("Administrators")        # add local Administrators as sysadmin
$SqlMediaRoot           = Join-Path $downloadDir "sqlmedia"
$SqlMediaPath           = $SqlMediaRoot              # where Setup.exe media will be placed
$OpenFirewallForSql     = $true
$SqlTcpPort             = 1433                       # <-- static TCP port you want (change if needed)

# Microsoft official SSEI (SQL Server 2022 Developer) fallback URL
$SqlSseiDownloadUrl     = "https://go.microsoft.com/fwlink/p/?linkid=2215158&clcid=0x409&culture=en-us&country=us"

# Create download directory (inline, no helper)
if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
}

# ==========================================
# Install Microsoft OpenJDK (x64) if missing
# ==========================================
Write-Host "`n========== Installing Microsoft OpenJDK ==========" -ForegroundColor Magenta
$javaInstalled = $false
try {
    $javaVersion = & java -version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Java appears installed:" -ForegroundColor Cyan
        Write-Host $javaVersion[0]
        $javaInstalled = $true
    }
} catch {}

if (-not $javaInstalled) {
    Write-Host "Downloading Microsoft OpenJDK 21 (x64) MSI..." -ForegroundColor Cyan
    $jdkUrl     = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.msi"
    $jdkMsiPath = Join-Path $downloadDir "microsoft-jdk-21.msi"

    try {
        Invoke-WebRequest -Uri $jdkUrl -OutFile $jdkMsiPath -UseBasicParsing
        Write-Host "JDK download complete." -ForegroundColor Green
    } catch {
        Write-Host "Error downloading Microsoft OpenJDK: $_" -ForegroundColor Red
        exit 1
    }

    Write-Host "Installing Microsoft OpenJDK 21..." -ForegroundColor Cyan
    try {
        $installArgs = @(
            "/i", "`"$jdkMsiPath`"", "/quiet", "/norestart",
            "ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome",
            "INSTALLDIR=`"$jdkInstallDir`""
        )
        Start-Process "msiexec.exe" -ArgumentList $installArgs -Wait -NoNewWindow
        Write-Host "Microsoft OpenJDK installed." -ForegroundColor Green

        # Refresh env
        $env:JAVA_HOME = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", [System.EnvironmentVariableTarget]::Machine)
        $env:Path      = [System.Environment]::GetEnvironmentVariable("Path",      [System.EnvironmentVariableTarget]::Machine)
    } catch {
        Write-Host "Error installing Microsoft OpenJDK: $_" -ForegroundColor Red
        exit 1
    }
}

# ======================================
# Install Apache Tomcat 9 (Windows x64)
# ======================================
Write-Host "`n========== Installing Apache Tomcat 9 ==========" -ForegroundColor Magenta
Write-Host "Fetching latest Tomcat 9 version information..." -ForegroundColor Cyan

$tomcatDownloadsUrl = "https://tomcat.apache.org/download-90.cgi"
$webContent = Invoke-WebRequest -Uri $tomcatDownloadsUrl -UseBasicParsing

$versionPattern = 'https://[^"]+/tomcat-9/v(9\.[0-9]+\.[0-9]+)/'
if ($webContent.Content -match $versionPattern) {
    $latestVersion = $Matches[1]
    Write-Host "Latest Tomcat 9 version: $latestVersion" -ForegroundColor Green
} else {
    Write-Host "Could not determine latest version. Using default version 9.0.96" -ForegroundColor Yellow
    $latestVersion = "9.0.96"
}

$baseUrl     = "https://archive.apache.org/dist/tomcat/tomcat-9/v$latestVersion/bin"
$zipFileName = "apache-tomcat-$latestVersion-windows-x64.zip"
$zipUrl      = "$baseUrl/$zipFileName"
$zipPath     = Join-Path $downloadDir $zipFileName

Write-Host "Downloading Tomcat 9 from: $zipUrl" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Write-Host "Tomcat ZIP download complete" -ForegroundColor Green
} catch {
    Write-Host "Error downloading Tomcat: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Extracting Tomcat..." -ForegroundColor Cyan
$extractPath = Join-Path $downloadDir "extracted"
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

$extractedFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1

$installParentDir = Split-Path $installDir -Parent
if (-not (Test-Path $installParentDir)) {
    New-Item -ItemType Directory -Path $installParentDir -Force | Out-Null
}

Write-Host "Installing Tomcat to: $installDir" -ForegroundColor Cyan
if (Test-Path $installDir) {
    Write-Host "Removing existing installation..." -ForegroundColor Yellow
    Remove-Item -Path $installDir -Recurse -Force
}
Move-Item -Path $extractedFolder.FullName -Destination $installDir -Force

# Unblock and validate service wrapper
Write-Host "Unblocking binaries..." -ForegroundColor Cyan
Get-ChildItem (Join-Path $installDir "bin\*.exe") -ErrorAction SilentlyContinue | ForEach-Object { Unblock-File $_.FullName }

$tomcatSvcCli = Join-Path $installDir "bin\tomcat9.exe"
if (-not (Test-Path $tomcatSvcCli)) {
    Write-Host "tomcat9.exe not found under $($installDir)\bin. Ensure the Windows x64 ZIP was used." -ForegroundColor Red
    exit 1
}

# Env vars
Write-Host "Setting CATALINA_HOME..." -ForegroundColor Cyan
[System.Environment]::SetEnvironmentVariable("CATALINA_HOME", $installDir, [System.EnvironmentVariableTarget]::Machine)

$javaHome = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", [System.EnvironmentVariableTarget]::Machine)
if ([string]::IsNullOrEmpty($javaHome)) {
    Write-Host "Setting JAVA_HOME..." -ForegroundColor Cyan
    if (Test-Path $jdkInstallDir) {
        [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkInstallDir, [System.EnvironmentVariableTarget]::Machine)
    } else {
        $javaExe = Get-Command java -ErrorAction SilentlyContinue
        if ($javaExe) {
            $javaBinPath = Split-Path $javaExe.Source
            $detectedJavaHome = Split-Path $javaBinPath
            [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $detectedJavaHome, [System.EnvironmentVariableTarget]::Machine)
            Write-Host "JAVA_HOME set to: $detectedJavaHome" -ForegroundColor Green
        }
    }
}

# Install Tomcat service
Write-Host "Installing Tomcat as a Windows service..." -ForegroundColor Cyan
Push-Location (Join-Path $installDir "bin")
try {
    cmd.exe /c "service.bat install $serviceName"
    Write-Host "Service installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error installing service: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}

# Configure heap (min=1024MB, max=4096MB) via CLI
Write-Host "Configuring JVM heap (min=1024MB, max=4096MB) for service '$serviceName'..." -ForegroundColor Cyan
$memoryConfigSucceeded = $false
try {
    & $tomcatSvcCli //US//$serviceName --JvmMs=1024 --JvmMx=4096
    Write-Host "Service JVM heap configured via tomcat9.exe." -ForegroundColor Green
    $memoryConfigSucceeded = $true
} catch {
    Write-Host "Failed to update service via tomcat9.exe: $_" -ForegroundColor Yellow
}

# Fallback for non-service starts
$setenvPath = Join-Path $installDir "bin\setenv.bat"
if (-not $memoryConfigSucceeded) {
    Write-Host "Applying fallback heap settings in setenv.bat..." -ForegroundColor Yellow
    $setenvContent = @(
        "REM Auto-generated by installer to set JVM heap for Tomcat",
        'set "JAVA_OPTS=-Xms1024m -Xmx4096m %JAVA_OPTS%"'
    ) -join [Environment]::NewLine
    Set-Content -Path $setenvPath -Value $setenvContent -Encoding ASCII
    Write-Host "Fallback JAVA_OPTS written to: $setenvPath" -ForegroundColor Green
}
Pop-Location

# tomcat-users.xml
$escapedUser = [System.Security.SecurityElement]::Escape($tomcat_admin_username)
if ($null -eq $escapedUser) { $escapedUser = "" }
$escapedPass = [System.Security.SecurityElement]::Escape($tomcat_admin_password)
if ($null -eq $escapedPass) { $escapedPass = "" }

$tomcatUsersPath = Join-Path $installDir "conf\tomcat-users.xml"
Write-Host "Creating Tomcat users configuration at: $tomcatUsersPath" -ForegroundColor Cyan

# Ensure conf directory exists
$confDir = Join-Path $installDir "conf"
if (-not (Test-Path $confDir)) {
    New-Item -ItemType Directory -Path $confDir -Force | Out-Null
}

$tomcatUsersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users xmlns="http://tomcat.apache.org/xml"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
              version="1.0">
  <!-- Roles for Manager and Host Manager applications -->
  <role rolename="manager-gui"/>
  <role rolename="admin-gui"/>
  <!-- Admin user -->
  <user username="$escapedUser" password="$escapedPass" roles="manager-gui,admin-gui"/>
</tomcat-users>
"@
Set-Content -Path $tomcatUsersPath -Value $tomcatUsersXml -Encoding UTF8

# Auto-start Tomcat service
Write-Host "Configuring Tomcat service to start automatically..." -ForegroundColor Cyan
Set-Service -Name $serviceName -StartupType Automatic

Write-Host "Starting Tomcat service..." -ForegroundColor Cyan
try {
    if ((Get-Service -Name $serviceName).Status -eq "Running") {
        Restart-Service -Name $serviceName -Force
    } else {
        Start-Service -Name $serviceName
    }
} catch {
    Write-Host "Error starting/restarting Tomcat service: $_" -ForegroundColor Red
}

# ======================================
# Install Microsoft SQL Server 2022 Developer (Mixed Mode) with TCP/IP ON
# ======================================
Write-Host "`n========== Installing Microsoft SQL Server 2022 Developer (x64) ==========" -ForegroundColor Magenta

# Ensure SQL media root exists
if (-not (Test-Path $SqlMediaRoot)) {
    New-Item -ItemType Directory -Path $SqlMediaRoot -Force | Out-Null
}

# Prefer WinGet if present; otherwise download SSEI from Microsoft and use it to fetch media
$SseiExe = $null
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    try {
        Write-Host "WinGet detected; downloading Microsoft.SQLServer.2022.Developer..." -ForegroundColor Cyan
        & winget download -e --id "Microsoft.SQLServer.2022.Developer" -d $downloadDir --accept-source-agreements --accept-package-agreements | Out-Null
        $candidate = Get-ChildItem -Path $downloadDir -Filter *.exe | Where-Object { $_.Name -match 'SQL.*SSEI.*Dev' -or $_.Name -match 'SQL.*Developer' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) {
            $SseiExe = $candidate.FullName
            Write-Host "Downloaded installer: $($candidate.Name)" -ForegroundColor Green
        }
    } catch {
        Write-Host "WinGet download failed: $_" -ForegroundColor Yellow
    }
}

if (-not $SseiExe) {
    Write-Host "Downloading SQL Server 2022 Developer web installer from Microsoft..." -ForegroundColor Cyan
    $SseiExe = Join-Path $downloadDir "SQL2022-SSEI-Dev.exe"
    try {
        Invoke-WebRequest -Uri $SqlSseiDownloadUrl -OutFile $SseiExe -UseBasicParsing
        Write-Host "SSEI download complete." -ForegroundColor Green
    } catch {
        Write-Host "Could not obtain SQL Server SSEI: $_" -ForegroundColor Red
        exit 1
    }
}

# Use SSEI to quietly download full media, then locate setup.exe (CAB first; fallback ISO)
Write-Host "Downloading SQL Server 2022 media (quiet)..." -ForegroundColor Cyan

# Attempt 1: CAB media (explicit product & language)
$dlArgsCab = @(
    "/Action=Download",
    "/MediaType=CAB",
    "/MediaPath=$SqlMediaPath",
    "/Product=Developer",
    "/Language=en-US",
    "/Quiet"
)

# Fallback attempt: ISO media
$dlArgsIso = @(
    "/Action=Download",
    "/MediaType=ISO",
    "/MediaPath=$SqlMediaPath",
    "/Product=Developer",
    "/Language=en-US",
    "/Quiet"
)

if (-not (Test-Path $SqlMediaPath)) {
    New-Item -ItemType Directory -Path $SqlMediaPath -Force | Out-Null
}

# Run CAB attempt
Start-Process -FilePath $SseiExe -ArgumentList $dlArgsCab -Wait

# Probe for setup.exe or ISO with a short wait loop
$setupExe = $null
$isoFile  = $null
for ($i=0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 3
    $setupCandidate = Get-ChildItem -Path $SqlMediaPath -Filter setup.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($setupCandidate) { $setupExe = $setupCandidate; break }
    $isoCandidate = Get-ChildItem -Path $SqlMediaPath -Filter *.iso -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($isoCandidate) { $isoFile = $isoCandidate; break }
}

# If not found, try ISO download and probe longer
if (-not $setupExe -and -not $isoFile) {
    Write-Host "CAB media not found; retrying with ISO download..." -ForegroundColor Yellow
    Start-Process -FilePath $SseiExe -ArgumentList $dlArgsIso -Wait

    for ($i=0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 3
        $setupCandidate = Get-ChildItem -Path $SqlMediaPath -Filter setup.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($setupCandidate) { $setupExe = $setupCandidate; break }
        $isoCandidate = Get-ChildItem -Path $SqlMediaPath -Filter *.iso -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($isoCandidate) { $isoFile = $isoCandidate; break }
    }
}

# If ISO found, mount and locate setup.exe on mounted volume
$mountedImage = $null
$mountedDrive = $null
if (-not $setupExe -and $isoFile) {
    Write-Host "Mounting SQL Server ISO: $($isoFile.FullName)" -ForegroundColor Cyan
    try {
        $mountedImage = Mount-DiskImage -ImagePath $isoFile.FullName -PassThru -ErrorAction Stop
        # Give it a moment to present the volume/letter
        Start-Sleep -Seconds 3
        $vol = ($mountedImage | Get-Volume)
        if (-not $vol -or -not $vol.DriveLetter) {
            Start-Sleep -Seconds 3
            $vol = ($mountedImage | Get-Volume)
        }
        if ($vol -and $vol.DriveLetter) {
            $mountedDrive = $vol.DriveLetter + ":\"
            $setupExe = Get-ChildItem -Path $mountedDrive -Filter setup.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    } catch {
        Write-Host "Failed to mount ISO: $_" -ForegroundColor Red
    }
}

if (-not $setupExe) {
    Write-Host "setup.exe not found after SSEI download (CAB or ISO). Check connectivity or proxy, or run SSEI interactively to confirm product/edition." -ForegroundColor Red
    exit 1
}

# Build unattended install arguments for Mixed Mode auth WITH TCP/IP enabled at setup
$quotedAdmins = $SqlSysAdminAccounts | ForEach-Object { '"' + $_ + '"' } | Sort-Object -Unique
$setupArgs = @(
    "/Q",
    "/IACCEPTSQLSERVERLICENSETERMS",
    "/ACTION=Install",
    "/FEATURES=SQLENGINE",
    "/INSTANCENAME=$SqlInstanceName",
    "/SQLSYSADMINACCOUNTS=" + ($quotedAdmins -join ' '),
    "/TCPENABLED=1",                 # enable TCP during setup (Developer defaults to disabled)
    "/SECURITYMODE=SQL",
    "/SAPWD=`"$sql_sa_password`"",
    "/ENU=True"
)

Write-Host "Installing SQL Server 2022 Developer silently (Mixed Mode, TCP/IP on)..." -ForegroundColor Cyan
Start-Process -FilePath $setupExe.FullName -ArgumentList $setupArgs -Wait

# If we mounted an ISO, dismount now
if ($mountedImage) {
    try {
        Dismount-DiskImage -ImagePath $mountedImage.ImagePath -ErrorAction SilentlyContinue
        Write-Host "Unmounted SQL Server ISO." -ForegroundColor Green
    } catch {
        Write-Host "Failed to unmount SQL Server ISO: $_" -ForegroundColor Yellow
    }
}

# ----------------------------
# Post-install: enforce static TCP port (IPAll/TcpPort = $SqlTcpPort; TcpDynamicPorts = "")
# ----------------------------
Write-Host "Enforcing static TCP port $SqlTcpPort..." -ForegroundColor Cyan
try {
    [void][Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
    $mc   = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
    $inst = $mc.ServerInstances[$SqlInstanceName]
    if (-not $inst) { $inst = $mc.ServerInstances["MSSQLSERVER"] }

    if ($inst) {
        $tcp = $inst.ServerProtocols["Tcp"]
        if ($tcp) {
            foreach ($ip in $tcp.IPAddresses) {
                # Clear dynamic ports everywhere
                $ip.IPAddressProperties["TcpDynamicPorts"].Value = ""
                # Set the static port only in IPAll (covers all interfaces when ListenAll=Yes)
                if ($ip.Name -eq "IPAll") {
                    $ip.IPAddressProperties["TcpPort"].Value = "$SqlTcpPort"
                }
            }
            $tcp.Alter()
            Write-Host "Static TCP port applied (IPAll/TcpPort=$SqlTcpPort)." -ForegroundColor Green
        } else {
            Write-Host "TCP protocol object not found in SMO/WMI." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Could not resolve SQL instance in SMO/WMI; skipping static port." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Static port configuration failed via SMO/WMI: $_" -ForegroundColor Yellow
}

# Set service to automatic; restart service to apply port change
try {
    Write-Host "Setting SQL Server service to Automatic..." -ForegroundColor Cyan
    Set-Service -Name "MSSQLSERVER" -StartupType Automatic -ErrorAction SilentlyContinue

    Write-Host "Restarting SQL Server service to apply TCP port change..." -ForegroundColor Cyan
    $svc = Get-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq "Running") { Restart-Service -Name "MSSQLSERVER" -Force } else { Start-Service -Name "MSSQLSERVER" }
        Write-Host "SQL Server service is running." -ForegroundColor Green
    }
} catch {
    Write-Host "Could not restart SQL Server service automatically: $_" -ForegroundColor Yellow
}

# ======================================
# Enable and Configure OpenSSH Server
# ======================================
Write-Host "`n========== Installing & Enabling OpenSSH Server ==========" -ForegroundColor Magenta

Write-Host "Installing OpenSSH Server capability..." -ForegroundColor Cyan
try {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop
    Write-Host "OpenSSH Server installed." -ForegroundColor Green
} catch {
    Write-Host "OpenSSH Server installation failed: $_" -ForegroundColor Red
}

Write-Host "Starting sshd service..." -ForegroundColor Cyan
try {
    Start-Service sshd
    Write-Host "sshd service started." -ForegroundColor Green
} catch {
    Write-Host "Could not start sshd service: $_" -ForegroundColor Yellow
}

Write-Host "Setting sshd service to Automatic startup..." -ForegroundColor Cyan
try {
    Set-Service -Name sshd -StartupType Automatic
    Write-Host "sshd configured to start automatically." -ForegroundColor Green
} catch {
    Write-Host "Could not set sshd startup type: $_" -ForegroundColor Yellow
}

# Open Windows Firewall for SSH 
Write-Host "`n========== Configuring Windows Firewall ==========" -ForegroundColor Magenta
Write-Host "Opening firewall for OpenSSH (port 22)..." -ForegroundColor Cyan

try {
    $existingSSHRule = Get-NetFirewallRule -DisplayName "OpenSSH Server" -ErrorAction SilentlyContinue
    if ($existingSSHRule) {
        Remove-NetFirewallRule -DisplayName "OpenSSH Server" -ErrorAction SilentlyContinue
    }

    New-NetFirewallRule `
        -Name "sshd" `
        -DisplayName "OpenSSH Server" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 | Out-Null

    Write-Host "Firewall rule added: OpenSSH Server (TCP 22)" -ForegroundColor Green
} catch {
    Write-Host "Firewall update for OpenSSH failed: $_" -ForegroundColor Red
}

# Open Windows Firewall for SQL TCP
if ($OpenFirewallForSql) {
    Write-Host "Opening Windows Firewall for SQL Server (TCP $SqlTcpPort)..." -ForegroundColor Cyan
    try {
        $ruleName = "Microsoft SQL Server (TCP $SqlTcpPort)"
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($existing) { Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue }
        New-NetFirewallRule -DisplayName $ruleName `
                            -Direction Inbound -Action Allow -Profile Domain,Private,Public `
                            -Protocol TCP -LocalPort $SqlTcpPort | Out-Null
        Write-Host "Firewall rule created: $ruleName" -ForegroundColor Green
    } catch {
        Write-Host "Firewall rule creation failed: $_" -ForegroundColor Yellow
    }
}

# --------------------------------------
# Windows Firewall for Tomcat (port 8080)
# --------------------------------------
Write-Host "Opening Windows Firewall for Tomcat (port 8080)..." -ForegroundColor Cyan
try {
    $existingRule = Get-NetFirewallRule -DisplayName "Apache Tomcat 9 (HTTP)" -ErrorAction SilentlyContinue
    if ($existingRule) {
        Write-Host "Firewall rule already exists. Updating..." -ForegroundColor Yellow
        Remove-NetFirewallRule -DisplayName "Apache Tomcat 9 (HTTP)" -ErrorAction SilentlyContinue
    }
    New-NetFirewallRule -DisplayName "Apache Tomcat 9 (HTTP)" `
                        -Description "Allow inbound HTTP traffic to Apache Tomcat 9 on port 8080" `
                        -Direction Inbound -Protocol TCP -LocalPort 8080 `
                        -Action Allow -Profile Domain,Private,Public -Enabled True | Out-Null
    Write-Host "Windows Firewall rule created for Tomcat." -ForegroundColor Green
} catch {
    Write-Host "Error configuring Windows Firewall for Tomcat: $_" -ForegroundColor Red
    Write-Host "You may need to open port 8080 manually." -ForegroundColor Yellow
}

# --------------------------------------
# Final status
# --------------------------------------
Write-Host "`n========== Installation Summary ==========" -ForegroundColor Magenta

Write-Host "Tomcat:" -ForegroundColor Cyan
Write-Host "  Version: $latestVersion"
Write-Host "  Install Location: $installDir"
Write-Host "  Service Name: $serviceName"
try {
    $serviceStatus = Get-Service -Name $serviceName
    Write-Host "  Service Status: $($serviceStatus.Status)"
} catch {}
Write-Host "  Web Interface: http://localhost:8080"
Write-Host "  Manager App:  http://localhost:8080/manager"
Write-Host "  Credentials:  conf\tomcat-users.xml (admin user created)"

Write-Host "`nSQL Server:" -ForegroundColor Cyan
Write-Host "  Edition:      2022 Developer"
Write-Host "  Instance:     $SqlInstanceName"
Write-Host "  Service:      MSSQLSERVER"
Write-Host "  Auth Mode:    Mixed (SQL + Windows; sa set)"
Write-Host "  TCP/IP:       Enabled at setup"
Write-Host "  Static Port:  $SqlTcpPort (IPAll)"
if ($OpenFirewallForSql) {
    Write-Host "  Firewall:     TCP $SqlTcpPort open (inbound)"
}

# --- OpenSSH Summary ---
Write-Host "`nOpenSSH:" -ForegroundColor Cyan
# Capability state
try {
    $sshCap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop
    Write-Host ("  Capability:   {0}" -f $sshCap.State)
} catch {
    Write-Host "  Capability:   Unknown (query failed)"
}
# Service status & startup
$sshSvc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
if ($sshSvc) {
    Write-Host "  Service:      sshd"
    Write-Host ("  Status:       {0}" -f $sshSvc.Status)
    Write-Host ("  Startup:      {0}" -f $sshSvc.StartType)
} else {
    Write-Host "  Service:      sshd (not found)"
}
# Firewall rule
$sshRule = Get-NetFirewallRule -DisplayName "OpenSSH Server" -ErrorAction SilentlyContinue
if ($sshRule) {
    $sshEnabled = $sshRule.Enabled
    $sshPort = "Unknown"
    try {
        $sshPortFilter = $sshRule | Get-NetFirewallPortFilter -ErrorAction Stop
        if ($sshPortFilter -and $sshPortFilter.LocalPort) { $sshPort = $sshPortFilter.LocalPort }
    } catch {}
    Write-Host ("  Firewall:     Rule present (Enabled={0}, TCP {1})" -f $sshEnabled, $sshPort)
} else {
    Write-Host "  Firewall:     Rule not present"
}

Write-Host "`n========== Installation Complete! ==========" -ForegroundColor Green
