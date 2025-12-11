
# rdp_user.ps1 (DSC version )
configuration AddUserToGroups {
    param([string]$UserName)
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Node localhost {
        Group RemoteDesktopUsers {
            GroupName        = 'Remote Desktop Users'
            Ensure           = 'Present'
            MembersToInclude = @($UserName)
        }
        Group Administrators {
            GroupName        = 'Administrators'
            Ensure           = 'Present'
            MembersToInclude = @($UserName)
        }
    }
}
