# script.ps1
# Tomcat 9 Installation Script for Windows Server 2025
# This script installs Microsoft OpenJDK, Apache Tomcat 9, and Microsoft JDBC Driver

# Requires Administrator privileges
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [string] $tomcat_admin_username,

    [Parameter(Mandatory = $true)]
    [string] $tomcat_admin_password
)

# Configuration
$downloadDir = "C:\Temp\TomcatInstall"
$installDir = "C:\Program Files\Apache Software Foundation\Tomcat 9.0"
$jdkInstallDir = "C:\Program Files\Microsoft\jdk-21"
$serviceName = "Tomcat9"

# Create download directory if it doesn't exist
if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
    Write-Host "Created download directory: $downloadDir" -ForegroundColor Green
}

Write-Host "`n========== Installing Microsoft OpenJDK ==========" -ForegroundColor Magenta

# Check if Java is already installed
$javaInstalled = $false
try {
    $javaVersion = & java -version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Java is already installed:" -ForegroundColor Yellow
        Write-Host $javaVersion[0] -ForegroundColor Yellow
        $javaInstalled = $true
    }
} catch {
    Write-Host "No Java installation detected. Installing Microsoft OpenJDK..." -ForegroundColor Cyan
}

if (-not $javaInstalled) {
    # Download Microsoft OpenJDK 21 (LTS)
    Write-Host "Downloading Microsoft OpenJDK 21..." -ForegroundColor Cyan
    $jdkUrl = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.msi"
    $jdkMsiPath = Join-Path $downloadDir "microsoft-jdk-21.msi"
    
    try {
        Invoke-WebRequest -Uri $jdkUrl -OutFile $jdkMsiPath -UseBasicParsing
        Write-Host "Download completed successfully" -ForegroundColor Green
    } catch {
        Write-Host "Error downloading Microsoft OpenJDK: $_" -ForegroundColor Red
        exit 1
    }

    # Install Microsoft OpenJDK silently
    Write-Host "Installing Microsoft OpenJDK 21..." -ForegroundColor Cyan
    try {
        $installArgs = @(
            "/i"
            "`"$jdkMsiPath`""
            "/quiet"
            "/norestart"
            "ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome"
            "INSTALLDIR=`"$jdkInstallDir`""
        )
        
        Start-Process "msiexec.exe" -ArgumentList $installArgs -Wait -NoNewWindow
        Write-Host "Microsoft OpenJDK installed successfully" -ForegroundColor Green
        
        # Refresh environment variables
        $env:JAVA_HOME = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", [System.EnvironmentVariableTarget]::Machine)
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
        
    } catch {
        Write-Host "Error installing Microsoft OpenJDK: $_" -ForegroundColor Red
        exit 1
    }

    # Verify Java installation
    Start-Sleep -Seconds 2
    try {
        $javaVersion = & java -version 2>&1
        Write-Host "`nJava installation verified:" -ForegroundColor Green
        Write-Host $javaVersion[0] -ForegroundColor White
    } catch {
        Write-Host "Warning: Java installation may not be complete. Path may need refresh." -ForegroundColor Yellow
    }
}


Write-Host "`n========== Installing Apache Tomcat 9 ==========" -ForegroundColor Magenta

Write-Host "Fetching latest Tomcat 9 version information..." -ForegroundColor Cyan

# Download the Tomcat 9 downloads page to find the latest version
$tomcatDownloadsUrl = "https://tomcat.apache.org/download-90.cgi"
$webContent = Invoke-WebRequest -Uri $tomcatDownloadsUrl -UseBasicParsing

# Extract the latest version number
$versionPattern = 'https://[^"]+/tomcat-9/v(9\.[0-9]+\.[0-9]+)/'
if ($webContent.Content -match $versionPattern) {
    $latestVersion = $Matches[1]
    Write-Host "Latest Tomcat 9 version: $latestVersion" -ForegroundColor Green
} else {
    Write-Host "Could not determine latest version. Using default version 9.0.96" -ForegroundColor Yellow
    $latestVersion = "9.0.96"
}

# Construct download URLs
$majorVersion = $latestVersion.Split('.')[0] + "." + $latestVersion.Split('.')[1]
$baseUrl = "https://archive.apache.org/dist/tomcat/tomcat-9/v$latestVersion/bin"
$zipFileName = "apache-tomcat-$latestVersion-windows-x64.zip"
$zipUrl = "$baseUrl/$zipFileName"
$zipPath = Join-Path $downloadDir $zipFileName

Write-Host "Downloading Tomcat 9 from: $zipUrl" -ForegroundColor Cyan

try {
    # Download the ZIP file (MSI installer is not available for Tomcat)
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Write-Host "Download completed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error downloading Tomcat: $_" -ForegroundColor Red
    exit 1
}

# Extract the ZIP file
Write-Host "Extracting Tomcat to temporary location..." -ForegroundColor Cyan
$extractPath = Join-Path $downloadDir "extracted"
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Get the extracted folder name
$extractedFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1

# Create installation directory if it doesn't exist
$installParentDir = Split-Path $installDir -Parent
if (-not (Test-Path $installParentDir)) {
    New-Item -ItemType Directory -Path $installParentDir -Force | Out-Null
}

# Move Tomcat to installation directory
Write-Host "Installing Tomcat to: $installDir" -ForegroundColor Cyan
if (Test-Path $installDir) {
    Write-Host "Removing existing installation..." -ForegroundColor Yellow
    Remove-Item -Path $installDir -Recurse -Force
}
Move-Item -Path $extractedFolder.FullName -Destination $installDir -Force

# Unblock executables (MOTW)
Write-Info "Unblocking binaries..."
Get-ChildItem (Join-Path $installDir "bin\*.exe") -ErrorAction SilentlyContinue | ForEach-Object { Unblock-File $_.FullName }

# Validate presence of x64 service wrapper (CLI)
$tomcatSvcCli = Join-Path $installDir "bin\tomcat9.exe"
if (-not (Test-Path $tomcatSvcCli)) {
    Write-Err "tomcat9.exe not found under $($installDir)\bin. Ensure the Windows x64 ZIP was used."
    exit 1
}

# Set CATALINA_HOME environment variable
Write-Host "Setting CATALINA_HOME environment variable..." -ForegroundColor Cyan
[System.Environment]::SetEnvironmentVariable("CATALINA_HOME", $installDir, [System.EnvironmentVariableTarget]::Machine)

# Set JAVA_HOME for the service if not already set
$javaHome = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", [System.EnvironmentVariableTarget]::Machine)
if ([string]::IsNullOrEmpty($javaHome)) {
    Write-Host "Setting JAVA_HOME environment variable..." -ForegroundColor Cyan
    if (Test-Path $jdkInstallDir) {
        [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkInstallDir, [System.EnvironmentVariableTarget]::Machine)
    } else {
        # Try to find Java installation
        $javaExe = Get-Command java -ErrorAction SilentlyContinue
        if ($javaExe) {
            $javaBinPath = Split-Path $javaExe.Source
            $detectedJavaHome = Split-Path $javaBinPath
            [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $detectedJavaHome, [System.EnvironmentVariableTarget]::Machine)
            Write-Host "JAVA_HOME set to: $detectedJavaHome" -ForegroundColor Green
        }
    }
}

# Install Tomcat as a Windows service
Write-Host "Installing Tomcat as a Windows service..." -ForegroundColor Cyan
$serviceExe = Join-Path $installDir "bin\service.bat"

# Run the service install command
Push-Location (Join-Path $installDir "bin")
try {
    & cmd.exe /c "service.bat install $serviceName"
    Write-Host "Service installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error installing service: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}

# -----------------------------
# Configure JVM heap for service (512 MB .. 2048 MB) via CLI (Procrun)
# -----------------------------
Write-Info "Configuring JVM heap (min=512MB, max=2048MB) for service '$serviceName'..."
$memoryConfigSucceeded = $false
try {
    & $tomcatSvcCli //US//$serviceName --JvmMs=512 --JvmMx=2048
    Write-Ok "Service JVM heap configured via tomcat9.exe."
    $memoryConfigSucceeded = $true
} catch {
    Write-Warn "Failed to update service via tomcat9.exe: $_"
}

# Fallback: ensure setenv.bat provides the same heap settings for non-service starts
$setenvPath = Join-Path $installDir "bin\setenv.bat"
if (-not $memoryConfigSucceeded) {
    Write-Host "Applying fallback heap settings in setenv.bat..." -ForegroundColor Yellow
    $setenvContent = @(
        "REM Auto-generated by installer to set JVM heap for Tomcat",
        'set "JAVA_OPTS=-Xms512m -Xmx2048m %JAVA_OPTS%"'
    ) -join [Environment]::NewLine

    Set-Content -Path $setenvPath -Value $setenvContent -Encoding ASCII
    Write-Host "Fallback JAVA_OPTS written to: $setenvPath" -ForegroundColor Green
}

# >>> Create tomcat-users.xml with admin/manager access <<<
# Helper to escape XML special characters
function Escape-Xml([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&apos;")
}

$escapedUser = Escape-Xml $tomcat_admin_username
$escapedPass = Escape-Xml $tomcat_admin_password

$tomcatUsersPath = Join-Path $installDir "conf\tomcat-users.xml"
Write-Host "Creating Tomcat users configuration at: $tomcatUsersPath" -ForegroundColor Cyan

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

# Ensure conf directory exists (should already)
$confDir = Join-Path $installDir "conf"
if (-not (Test-Path $confDir)) {
    New-Item -Path $confDir -ItemType Directory -Force | Out-Null
}
Set-Content -Path $tomcatUsersPath -Value $tomcatUsersXml -Encoding UTF8

# Optionally, tighten file permissions to Administrators only (uncomment if desired)
# try {
#     $acl = Get-Acl $tomcatUsersPath
#     $admins = New-Object System.Security.Principal.NTAccount("Administrators")
#     $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($admins, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
#     $acl.SetAccessRuleProtection($true, $false) # disable inheritance
#     $acl.SetAccessRule($rule)
#     Set-Acl -Path $tomcatUsersPath -AclObject $acl
#     Write-Host "Secured tomcat-users.xml ACL to Administrators." -ForegroundColor Green
# } catch {
#     Write-Host "Warning: Could not adjust ACL: $_" -ForegroundColor Yellow
# }

Pop-Location

# Configure the service to start automatically
Write-Host "Configuring service to start automatically..." -ForegroundColor Cyan
Set-Service -Name $serviceName -StartupType Automatic

# Restart the service to apply memory settings
Write-Host "Restarting Tomcat service to apply memory settings..." -ForegroundColor Cyan
try {
    if ((Get-Service -Name $serviceName).Status -eq "Running") {
        Restart-Service -Name $serviceName -Force
    } else {
        Start-Service -Name $serviceName
    }
} catch {
    Write-Host "Error starting/restarting service: $_" -ForegroundColor Red
}

# Wait a moment and check service status
Start-Sleep -Seconds 3
$serviceStatus = Get-Service -Name $serviceName

if ($serviceStatus.Status -eq "Running") {
    Write-Host "`nTomcat service started successfully!" -ForegroundColor Green
    Write-Host "Service Status: $($serviceStatus.Status)" -ForegroundColor Cyan
    Write-Host "Heap settings applied: Min=512MB, Max=2048MB (via prunsrv or setenv.bat fallback)" -ForegroundColor Cyan
} else {
    Write-Host "`nWarning: Service installed but not running. Status: $($serviceStatus.Status)" -ForegroundColor Yellow
    Write-Host "Check logs at: $installDir\logs" -ForegroundColor Yellow
}


# Cleanup
Write-Host "`nCleaning up temporary files..." -ForegroundColor Cyan
Remove-Item -Path $downloadDir -Recurse -Force
Write-Host "Cleanup completed" -ForegroundColor Green

Write-Host "`n========== Configuring Windows Firewall ==========" -ForegroundColor Magenta

# Open Windows Firewall for Tomcat port 8080
Write-Host "Opening Windows Firewall for Tomcat (port 8080)..." -ForegroundColor Cyan

try {
    # Check if firewall rule already exists
    $existingRule = Get-NetFirewallRule -DisplayName "Apache Tomcat 9 (HTTP)" -ErrorAction SilentlyContinue
    
    if ($existingRule) {
        Write-Host "Firewall rule already exists. Updating..." -ForegroundColor Yellow
        Remove-NetFirewallRule -DisplayName "Apache Tomcat 9 (HTTP)" -ErrorAction SilentlyContinue
    }
    
    # Create new firewall rule for inbound traffic on port 8080
    New-NetFirewallRule -DisplayName "Apache Tomcat 9 (HTTP)" `
                        -Description "Allow inbound HTTP traffic to Apache Tomcat 9 on port 8080" `
                        -Direction Inbound `
                        -Protocol TCP `
                        -LocalPort 8080 `
                        -Action Allow `
                        -Profile Domain,Private,Public `
                        -Enabled True | Out-Null
    
    Write-Host "Windows Firewall rule created successfully" -ForegroundColor Green
    Write-Host "  Rule Name: Apache Tomcat 9 (HTTP)" -ForegroundColor White
    Write-Host "  Port: 8080 (TCP)" -ForegroundColor White
    Write-Host "  Direction: Inbound" -ForegroundColor White
    Write-Host "  Profiles: Domain, Private, Public" -ForegroundColor White
    
} catch {
    Write-Host "Error configuring Windows Firewall: $_" -ForegroundColor Red
    Write-Host "You may need to manually open port 8080 in Windows Firewall" -ForegroundColor Yellow
}
Write-Host "`n========== Installation Summary ==========" -ForegroundColor Magenta
Write-Host "Java:" -ForegroundColor Cyan
try {
    $finalJavaVersion = & java -version 2>&1
    Write-Host "  Version: $($finalJavaVersion[0])" -ForegroundColor White
    $currentJavaHome = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", [System.EnvironmentVariableTarget]::Machine)
    Write-Host "  JAVA_HOME: $currentJavaHome" -ForegroundColor White
} catch {
    Write-Host "  Status: Installed (may require system restart)" -ForegroundColor Yellow
}

Write-Host "`nTomcat:" -ForegroundColor Cyan
Write-Host "  Version: $latestVersion" -ForegroundColor White
Write-Host "  Install Location: $installDir" -ForegroundColor White
Write-Host "  Service Name: $serviceName" -ForegroundColor White
Write-Host "  Service Status: $($serviceStatus.Status)" -ForegroundColor White
Write-Host "  Web Interface: http://localhost:8080" -ForegroundColor White
Write-Host "  Manager App: http://localhost:8080/manager" -ForegroundColor White
Write-Host "  (Configure credentials in conf/tomcat-users.xml)" -ForegroundColor Gray

Write-Host "`n========== Installation Complete! ==========" -ForegroundColor Green
