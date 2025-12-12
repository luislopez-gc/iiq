
# rdp_user.ps1 (DSC version enforcing WinRM policy)
configuration AddUserToGroups {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName  # e.g., 'CONTOSO\User1'
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node localhost {

        # --- Enforce WinRM policy: AllowAutoConfig = 1 (Enabled) ---
        Registry WinRMPolicyEnable {
            Key       = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
            ValueName = 'AllowAutoConfig'
            ValueType = 'Dword'
            ValueData = 1
            Ensure    = 'Present'
            Force     = $true
        }

        # --- Ensure WinRM service is running and auto-start ---
        Service WinRMService {
            Name        = 'WinRM'
            StartupType = 'Automatic'
            State       = 'Running'
            DependsOn   = '[Registry]WinRMPolicyEnable'
        }

        # --- Enable Windows Firewall rules for WinRM ---
        Script WinRMFirewall {
            GetScript  = {
                $http  = Get-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)'  -ErrorAction SilentlyContinue
                $https = Get-NetFirewallRule -DisplayName 'Windows Remote Management (HTTPS-In)' -ErrorAction SilentlyContinue
                @{ HttpEnabled = ($http.Enabled -eq 'True'); HttpsEnabled = ($https.Enabled -eq 'True') }
            }
            SetScript  = {
                Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue
                Enable-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)'  -ErrorAction SilentlyContinue
                Enable-NetFirewallRule -DisplayName 'Windows Remote Management (HTTPS-In)' -ErrorAction SilentlyContinue
            }
            TestScript = {
                $http  = Get-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)'  -ErrorAction SilentlyContinue
                $https = Get-NetFirewallRule -DisplayName 'Windows Remote Management (HTTPS-In)' -ErrorAction SilentlyContinue
                return (($http.Enabled -eq 'True') -and ($https.Enabled -eq 'True'))
            }
            DependsOn = '[Service]WinRMService'
        }

        # --- Add the user to local groups ---
        Group RemoteDesktopUsers {
            GroupName        = 'Remote Desktop Users'
            Ensure           = 'Present'
            MembersToInclude = @($UserName)
            DependsOn        = '[Script]WinRMFirewall'
        }

        Group Administrators {
            GroupName        = 'Administrators'
            Ensure           = 'Present'
            MembersToInclude = @($UserName)
            DependsOn        = '[Script]WinRMFirewall'
        }
    }
}
