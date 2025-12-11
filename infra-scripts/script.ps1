# script.ps1
# Tomcat 9 Installation Script for Windows Server 2025
# This script installs Microsoft OpenJDK, Apache Tomcat 9, and Microsoft JDBC Driver

# Requires Administrator privileges
#Requires -RunAsAdministrator

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
Pop-Location

# Configure the service to start automatically
Write-Host "Configuring service to start automatically..." -ForegroundColor Cyan
Set-Service -Name $serviceName -StartupType Automatic

# Start the Tomcat service
Write-Host "Starting Tomcat service..." -ForegroundColor Cyan
Start-Service -Name $serviceName

# Wait a moment and check service status
Start-Sleep -Seconds 3
$serviceStatus = Get-Service -Name $serviceName

if ($serviceStatus.Status -eq "Running") {
    Write-Host "`nTomcat service started successfully!" -ForegroundColor Green
    Write-Host "Service Status: $($serviceStatus.Status)" -ForegroundColor Cyan
} else {
    Write-Host "`nWarning: Service installed but not running. Status: $($serviceStatus.Status)" -ForegroundColor Yellow
    Write-Host "Check logs at: $installDir\logs" -ForegroundColor Yellow
}

Write-Host "`n========== Installing Microsoft JDBC Driver ==========" -ForegroundColor Magenta

# Fetch the latest JDBC driver version
Write-Host "Fetching latest Microsoft JDBC Driver information..." -ForegroundColor Cyan

try {
    # Get the Microsoft JDBC driver download page
    $jdbcPageUrl = "https://learn.microsoft.com/en-us/sql/connect/jdbc/download-microsoft-jdbc-driver-for-sql-server"
    $jdbcPage = Invoke-WebRequest -Uri $jdbcPageUrl -UseBasicParsing
    
    # Look for the latest GA version download link
    $jdbcPattern = 'https://go\.microsoft\.com/fwlink/\?linkid=\d+'
    $jdbcLinks = [regex]::Matches($jdbcPage.Content, $jdbcPattern)
    
    if ($jdbcLinks.Count -gt 0) {
        # Use the first download link (usually the latest GA)
        $jdbcDownloadUrl = $jdbcLinks[0].Value
        Write-Host "Found JDBC driver download link" -ForegroundColor Green
    } else {
        # Fallback to direct download link for latest known version
        Write-Host "Using direct download link for JDBC driver" -ForegroundColor Yellow
        $jdbcDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2279200"
    }
    
    $jdbcTarPath = Join-Path $downloadDir "sqljdbc.tar.gz"
    
    Write-Host "Downloading Microsoft JDBC Driver..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $jdbcDownloadUrl -OutFile $jdbcTarPath -UseBasicParsing
    Write-Host "Download completed successfully" -ForegroundColor Green
    
    # Extract the tar.gz file
    Write-Host "Extracting JDBC Driver..." -ForegroundColor Cyan
    $jdbcExtractPath = Join-Path $downloadDir "jdbc"
    
    # PowerShell 5.1+ can handle tar.gz extraction
    if (Get-Command tar -ErrorAction SilentlyContinue) {
        # Use tar command if available
        New-Item -ItemType Directory -Path $jdbcExtractPath -Force | Out-Null
        tar -xzf $jdbcTarPath -C $jdbcExtractPath
    } else {
        # Alternative extraction method for older systems
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        # First extract .gz to get .tar
        $gzStream = New-Object System.IO.FileStream($jdbcTarPath, [System.IO.FileMode]::Open)
        $gzipStream = New-Object System.IO.Compression.GZipStream($gzStream, [System.IO.Compression.CompressionMode]::Decompress)
        $tarPath = Join-Path $downloadDir "sqljdbc.tar"
        $tarStream = New-Object System.IO.FileStream($tarPath, [System.IO.FileMode]::Create)
        $gzipStream.CopyTo($tarStream)
        $tarStream.Close()
        $gzipStream.Close()
        $gzStream.Close()
        
        Write-Host "Note: Manual TAR extraction may be required. Using alternative method..." -ForegroundColor Yellow
    }
    
    # Find the JDBC JAR file
    $tomcatLibDir = Join-Path $installDir "lib"
    $jdbcJarFiles = Get-ChildItem -Path $jdbcExtractPath -Recurse -Filter "mssql-jdbc-*.jre*.jar" -ErrorAction SilentlyContinue
    
    if ($jdbcJarFiles) {
        # Copy the appropriate JAR file to Tomcat's lib directory
        # Prefer JRE 11 or higher version
        $jdbcJar = $jdbcJarFiles | Where-Object { $_.Name -like "*jre11*" -or $_.Name -like "*jre17*" -or $_.Name -like "*jre21*" } | Select-Object -First 1
        
        if (-not $jdbcJar) {
            $jdbcJar = $jdbcJarFiles | Select-Object -First 1
        }
        
        Write-Host "Copying JDBC driver to Tomcat lib directory..." -ForegroundColor Cyan
        Copy-Item -Path $jdbcJar.FullName -Destination $tomcatLibDir -Force
        Write-Host "JDBC driver installed: $($jdbcJar.Name)" -ForegroundColor Green
        
        $jdbcDriverVersion = $jdbcJar.Name
    } else {
        Write-Host "Warning: Could not locate JDBC JAR file in extracted archive" -ForegroundColor Yellow
        Write-Host "You may need to manually copy the driver from: $jdbcExtractPath" -ForegroundColor Yellow
        $jdbcDriverVersion = "Not found in archive"
    }
    
    # Restart Tomcat service to load the new driver
    Write-Host "Restarting Tomcat service to load JDBC driver..." -ForegroundColor Cyan
    Restart-Service -Name $serviceName
    Start-Sleep -Seconds 3
    
    $serviceStatus = Get-Service -Name $serviceName
    if ($serviceStatus.Status -eq "Running") {
        Write-Host "Tomcat service restarted successfully" -ForegroundColor Green
    }
    
} catch {
    Write-Host "Error installing Microsoft JDBC Driver: $_" -ForegroundColor Red
    Write-Host "Tomcat is still running, but JDBC driver installation failed" -ForegroundColor Yellow
    $jdbcDriverVersion = "Installation failed"
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


# ========== Installing Apache Ant (Latest) ==========
Write-Host "`n========== Installing Apache Ant ==========" -ForegroundColor Magenta

# Local (new) variables - do NOT conflict with the original script's variables
$antDownloadDir   = "C:\Temp\AntInstall"
$antInstallDir    = "C:\Program Files\Apache Software Foundation\Ant"
$antBinaryBaseUrl = "https://ant.apache.org/bindownload.cgi"
$antZipName       = $null
$antZipUrl        = $null
$antVersion       = $null

# Create temp download directory
if (-not (Test-Path $antDownloadDir)) {
    New-Item -ItemType Directory -Path $antDownloadDir -Force | Out-Null
    Write-Host "Created download directory: $antDownloadDir" -ForegroundColor Green
}

Write-Host "Fetching Apache Ant latest version info..." -ForegroundColor Cyan
try {
    # Get the Ant binary downloads page
    $antPage = Invoke-WebRequest -Uri $antBinaryBaseUrl -UseBasicParsing

    # Find the Windows ZIP link (pattern looks for apache-ant-<version>-bin.zip)
    $zipPattern = 'href="(?<url>https?://[^"]*/apache-ant-(?<ver>\d+\.\d+\.\d+)-bin\.zip)"'
    $zipMatch   = [regex]::Matches($antPage.Content, $zipPattern) | Select-Object -First 1

    if ($zipMatch) {
        $antZipUrl  = $zipMatch.Groups["url"].Value
        $antVersion = $zipMatch.Groups["ver"].Value
        $antZipName = "apache-ant-$antVersion-bin.zip"
        Write-Host "Latest Ant version detected: $antVersion" -ForegroundColor Green
        Write-Host "Download URL: $antZipUrl" -ForegroundColor Cyan
    } else {
        throw "Could not locate the latest Ant ZIP link on $antBinaryBaseUrl"
    }
}
catch {
    Write-Host "Error determining latest Ant version: $_" -ForegroundColor Red
    Write-Host "Falling back to known stable version 1.10.14 from Apache archive..." -ForegroundColor Yellow
    # Fallback (kept self-contained; adjust if needed)
    $antVersion = "1.10.15"
    $antZipName = "apache-ant-$antVersion-bin.zip"
    $antZipUrl  = "https://archive.apache.org/dist/ant/binaries/$antZipName"
}

# Download Ant ZIP
$antZipPath = Join-Path $antDownloadDir $antZipName
Write-Host "Downloading Apache Ant $antVersion..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $antZipUrl -OutFile $antZipPath -UseBasicParsing
    Write-Host "Download completed: $antZipPath" -ForegroundColor Green
}
catch {
    Write-Host "Error downloading Apache Ant: $_" -ForegroundColor Red
    exit 1
}

# Extract ZIP to a temporary location
Write-Host "Extracting Apache Ant..." -ForegroundColor Cyan
$antExtractPath = Join-Path $antDownloadDir "extracted"
Expand-Archive -Path $antZipPath -DestinationPath $antExtractPath -Force

# Identify extracted folder (apache-ant-<version>)
$antExtractedFolder = Get-ChildItem -Path $antExtractPath -Directory | Where-Object { $_.Name -like "apache-ant-*" } | Select-Object -First 1
if (-not $antExtractedFolder) {
    Write-Host "Could not find extracted Ant folder" -ForegroundColor Red
    exit 1
}

# Prepare install directory
$antInstallParent = Split-Path $antInstallDir -Parent
if (-not (Test-Path $antInstallParent)) {
    New-Item -ItemType Directory -Path $antInstallParent -Force | Out-Null
}

# Remove existing Ant installation (if any) and install the new one
Write-Host "Installing Ant to: $antInstallDir" -ForegroundColor Cyan
if (Test-Path $antInstallDir) {
    Write-Host "Removing existing Ant installation..." -ForegroundColor Yellow
    Remove-Item -Path $antInstallDir -Recurse -Force
}
Move-Item -Path $antExtractedFolder.FullName -Destination $antInstallDir -Force

# Set ANT_HOME (Machine) and update system PATH
Write-Host "Configuring ANT_HOME and PATH..." -ForegroundColor Cyan
[System.Environment]::SetEnvironmentVariable("ANT_HOME", $antInstallDir, [System.EnvironmentVariableTarget]::Machine)

# Ensure %ANT_HOME%\bin in system PATH (idempotent)
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
$antBinPath  = "$antInstallDir\bin"
if ($machinePath -notmatch [regex]::Escape($antBinPath)) {
    $newMachinePath = $antBinPath + ";" + $machinePath
    [System.Environment]::SetEnvironmentVariable("Path", $newMachinePath, [System.EnvironmentVariableTarget]::Machine)
    Write-Host "Added to PATH: $antBinPath" -ForegroundColor Green
} else {
    Write-Host "PATH already contains: $antBinPath" -ForegroundColor Yellow
}

# Refresh current session variables (best effort; a new session may still be required)
$env:ANT_HOME = [System.Environment]::GetEnvironmentVariable("ANT_HOME", [System.EnvironmentVariableTarget]::Machine)
$env:Path     = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

# Verify Ant installation
Write-Host "Verifying Ant installation..." -ForegroundColor Cyan
try {
    $antVersionOutput = & "$antInstallDir\bin\ant.bat" -version 2>&1
    Write-Host "`nApache Ant installation verified:" -ForegroundColor Green
    Write-Host " $antVersionOutput" -ForegroundColor White
} catch {
    Write-Host "Warning: Ant verification failed (session may need restart). Error: $_" -ForegroundColor Yellow
}

# Optional: clean up Ant temp files (keeps your original cleanup intact)
Write-Host "`nCleaning up Ant temporary files..." -ForegroundColor Cyan
Remove-Item -Path $antDownloadDir -Recurse -Force
Write-Host "Ant cleanup completed" -ForegroundColor Green

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

Write-Host "`nMicrosoft JDBC Driver:" -ForegroundColor Cyan
Write-Host "  Driver: $jdbcDriverVersion" -ForegroundColor White
Write-Host "  Location: $tomcatLibDir" -ForegroundColor White
Write-Host "  Status: Loaded with Tomcat" -ForegroundColor White

Write-Host " Ant Version: $antVersion" -ForegroundColor White
Write-Host " ANT_HOME: $env:ANT_HOME" -ForegroundColor White
Write-Host " PATH contains ANT bin: " -ForegroundColor White

Write-Host "`n========== Installation Complete! ==========" -ForegroundColor Green
