# Send a Windows Notification to show what status are we running now
# This function notifies when a profile has been set
# from here: https://den.dev/blog/powershell-windows-notification/
function Show-Notification {
    [cmdletbinding()]
    Param (
        [string]
        $ToastTitle,
        [string]
        [parameter(ValueFromPipeline)]
        $ToastText
    )

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    $Template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)

    $RawXml = [xml] $Template.GetXml()
    ($RawXml.toast.visual.binding.text | Where-Object { $_.id -eq "1" }).AppendChild($RawXml.CreateTextNode($ToastTitle)) > $null
    ($RawXml.toast.visual.binding.text | Where-Object { $_.id -eq "2" }).AppendChild($RawXml.CreateTextNode($ToastText)) > $null

    $SerializedXml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $SerializedXml.LoadXml($RawXml.OuterXml)

    $Toast = [Windows.UI.Notifications.ToastNotification]::new($SerializedXml)
    $Toast.Tag = "PowerShell"
    $Toast.Group = "PowerShell"
    $Toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(1)

    $Notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("PowerShell")
    $Notifier.Show($Toast);
}

function Set-Svc {
    param([string]$svc_name, [string]$action)
    If ($action -eq 'start') {
        Get-Service $svc_name | Set-Service -StartupType Automatic -PassThru | Start-Service 
    }
    elseif ($action -eq 'stop') {
        Get-Service $svc_name | Stop-Service -PassThru | Set-Service -StartupType Disabled
    }
    else {
        Write-Host ("Not a valid action")
    }
}

function Start-Program-If-Not-Running {
    Param (
        [string]
        $folderPath,
        [string]
        $programName
    )

    $isRunning = (Get-Process | Where-Object { $_.Name -eq $programName }).Count -gt 0
    if ($isRunning) {
        Write-Host "Already running..."
    }
    else {
        Write-Host "Starting $programName..."
        Start-Process -WindowStyle Minimized "$folderPath\$programName.exe"
    }
}

function Assert-Power-Plan-Battery-Mode {
    # List power consumption profile schemes
    $powerConstants = @{}
    PowerCfg.exe -ALIASES | Where-Object { $_ -match 'SCHEME_' } | ForEach-Object {
        $guid,$alias = ($_ -split '\s+', 2).Trim()
        $powerConstants[$alias] = $guid 
    }
    
    # Get a list of power schemes and check the one that is active
    $powerSchemes = PowerCfg.exe -LIST | Where-Object { $_ -match '^GUID' } | ForEach-Object {
        $guid = $_ -replace '.*GUID:\s*([-a-f0-9]+).*', '$1'
        [PsCustomObject]@{
            Name     = $_.Trim("* ") -replace '.*\(([^)]+)\)$', '$1'          # LOCALIZED !
            Alias    = $powerConstants[$guid]
            Guid     = $guid
            IsActive = $_ -match '\*$'
        }
    }

    # Set a variable for each of the power schemes (just to make it more readable)
    $highPerformance = $powerConstants['SCHEME_MIN']
    $balanced = $powerConstants['SCHEME_BALANCED']

    # Get current active power plan
    $setPowerPlan = $powerSchemes | Where-Object { $_.IsActive }
    $setPowerPlan = $setPowerPlan.Guid

    # Regex to get the GUID
    if ($setPowerPlan -match '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}') {
        $setPowerPlan = $matches[0]
    }
    else {
        $setPowerPlan = $null
    }

    # Change the power plan based on what power plan is active right now
    if (($setPowerPlan -eq $balanced) -or ($setPowerPlan -eq $highPerformance)) {
        return $false
    } 
    else {
        return $true
    }
}