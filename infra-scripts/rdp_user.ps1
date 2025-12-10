# rd_user.ps1
# This script adds a user to the Remote Desktop Users and Administrators groups on a Windows machine.
# Usage: .\rd_user.ps1 -UserName 'username'
param(
    [Parameter(Mandatory)]
    [string]$UserName
)

$ErrorActionPreference = 'Stop'

# Basic input validation
if ([string]::IsNullOrWhiteSpace($UserName)) {
    throw "UserName parameter is empty or whitespace."
}

# Add to Remote Desktop Users only if absent
if (-not (Get-LocalGroupMember -Group 'Remote Desktop Users' -Member $UserName -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $UserName
}

# Add to Administrators only if absent
if (-not (Get-LocalGroupMember -Group 'Administrators' -Member $UserName -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember -Group 'Administrators' -Member $UserName
}
