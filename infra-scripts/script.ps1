
# Requires: Run as Administrator
# Purpose: Install MS OpenJDK 17 + Apache Tomcat 9 and run Tomcat as a Windows Service

$ErrorActionPreference = "Stop"

# --- Prep: Paths & Versions ---
$TempDir = "C:\Temp"
$TomcatBase = "C:\Tomcat"
$TomcatVersion = "9.0.85"     # Update here if you need a newer Tomcat 9 release
$TomcatZip = "apache-tomcat-$TomcatVersion-windows-x64.zip"
$TomcatDownloadUrl = "https://downloads.apache.org/tomcat/tomcat-9/v$TomcatVersion/bin/$TomcatZip"
$TomcatHome = Join-Path $TomcatBase "apache-tomcat-$TomcatVersion"
$ServiceName = "Tomcat9"      # Windows service name

# Ensure directories exist
New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
New-Item -Path $TomcatBase -ItemType Directory -Force | Out-Null

Write-Host "Installing MS OpenJDK 17..." -ForegroundColor Cyan

# --- Install Microsoft OpenJDK 17 ---
$JdkMsiUrl = "https://aka.ms/download-jdk/microsoft-jdk-17.0.10-windows-x64.msi"
$JdkMsiPath = Join-Path $TempDir "jdk.msi"

Invoke-WebRequest -Uri $JdkMsiUrl -OutFile $JdkMsiPath
Start-Process msiexec.exe -ArgumentList "/i `"$JdkMsiPath`" /quiet /norestart" -Wait

# Derive JAVA_HOME from typical installation path; adjust if your JDK version differs
$JavaHome = "C:\Program Files\Microsoft\jdk-17.0.10"
if (-not (Test-Path $JavaHome)) {
    # Fallback: try to auto-detect latest Microsoft JDK 17 folder
    $javaCandidates = Get-ChildItem "C:\Program Files\Microsoft" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "jdk-17*" }
    if ($javaCandidates) { $JavaHome = $javaCandidates | Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName } }
}

Write-Host "Setting JAVA_HOME=$JavaHome" -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable("JAVA_HOME", $JavaHome, "Machine")

# --- Install Apache Tomcat 9 ---
Write-Host "Downloading Apache Tomcat $TomcatVersion..." -ForegroundColor Cyan
$TomcatZipPath = Join-Path $TempDir "tomcat.zip"
Invoke-WebRequest -Uri $TomcatDownloadUrl -OutFile $TomcatZipPath

Write-Host "Expanding Tomcat to $TomcatHome ..." -ForegroundColor Cyan
Expand-Archive -Path $TomcatZipPath -DestinationPath $TomcatBase -Force

Write-Host "Setting CATALINA_HOME=$TomcatHome" -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable("CATALINA_HOME", $TomcatHome, "Machine")

# --- Create Tomcat as Windows Service using prunsrv (tomcat9.exe) ---
$BinDir = Join-Path $TomcatHome "bin"
$PrunSrv = Join-Path $BinDir "tomcat9.exe"   # prunsrv executable
$PrunW   = Join-Path $BinDir "tomcat9w.exe"  # GUI config tool (optional)

# Ensure required folders for logs
$LogPath = Join-Path $TomcatHome "logs"
New-Item -Path $LogPath -ItemType Directory -Force | Out-Null

# Classpath includes bootstrap + tomcat-juli jars
$Classpath = @(
    "`"$TomcatHome\bin\bootstrap.jar`"",
    "`"$TomcatHome\bin\tomcat-juli.jar`""
) -join ";"

# JVM DLL auto
$JvmDll = "auto"

# Install the service (//IS// creates or replaces)
Write-Host "Installing Windows Service '$ServiceName'..." -ForegroundColor Cyan
& $PrunSrv //IS//$ServiceName `
  --DisplayName="Apache Tomcat $TomcatVersion" `
  --Description="Apache Tomcat $TomcatVersion (Java-servlet container) running as a Windows Service" `
  --Startup=auto `
  --StartMode=jvm `
  --StopMode=jvm `
  --JavaHome="$JavaHome" `
  --Jvm="$JvmDll" `
  --Classpath="$Classpath" `
  --StartClass=org.apache.catalina.startup.Bootstrap `
  --StartParams=start `
  --StopClass=org.apache.catalina.startup.Bootstrap `
  --StopParams=stop `
  --LogPath="$LogPath" `
  --StdOutput=auto `
  --StdError=auto `
  --PidFile="$TomcatHome\tomcat.pid" `
  --StartPath="$TomcatHome"

# Optional: Set JVM options (memory, file encoding, etc.)
# You can append multiple --JvmOptions by repeating the flag or using a single string with spaces.
& $PrunSrv //US//$ServiceName `
  --JvmOptions="-Dfile.encoding=UTF-8 -Djava.io.tmpdir=$TempDir -Xms512m -Xmx1024m"

# --- Open Windows Firewall for Tomcat default port 8080 ---
Write-Host "Opening Windows Firewall port 8080 for Tomcat..." -ForegroundColor Cyan
$fwRuleName = "Allow Tomcat 8080"
if (-not (Get-NetFirewallRule -DisplayName $fwRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $fwRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 | Out-Null
}

# --- Set service to Automatic and start it ---
Write-Host "Setting service to Automatic and starting..." -ForegroundColor Cyan
Set-Service -Name $ServiceName -StartupType Automatic
Start-Service -Name $ServiceName

# --- Basic verification ---
Write-Host "Service status:" -ForegroundColor Cyan
Get-Service -Name $ServiceName

Write-Host "`nTomcat installed at: $TomcatHome" -ForegroundColor Green
Write-Host "JAVA_HOME: $JavaHome" -ForegroundColor Green
Write-Host "CATALINA_HOME: $TomcatHome" -ForegroundColor Green
Write-Host "Tomcat is listening on port 8080 (default). Browse: http://<external-ip>:8080/" -ForegroundColor Yellow
