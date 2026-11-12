<#
    OptiWin 2.1  -  powered by CyberX, SVPNPA
    ---------------------------------------------------------------------------
    A point-and-click debloater and uninstaller for Windows 10 (1809 or later)
    and Windows 11.

    What it covers
      * Built-in apps, every removable Microsoft Store app (Microsoft or third
        party) and every desktop program installed on the PC
      * Microsoft Edge (WebView2 is kept) and OneDrive
      * Startup programs, Store app startup tasks and third-party scheduled tasks
      * Privacy, telemetry, ads and suggestions, Explorer and system settings
      * Optional services and optional Windows features
      * Clean-up of temporary files and update caches

    Safety
      * "Preview changes" shows exactly what would change. Nothing is touched
        until you press "Apply selected".
      * A System Restore point is made first (on by default).
      * Every setting, service, scheduled task, startup entry and Windows
        feature it changes is recorded in %ProgramData%\OptiWin\Backups, and
        "Undo a previous run" puts them back.
      * Removed apps and programs are not covered by Undo; reinstall them.

    Start it with "OptiWin.cmd", or from PowerShell:
        powershell -ExecutionPolicy Bypass -File .\OptiWin.ps1
    Build a single OptiWin.exe with Build-OptiWin-exe.ps1 (Windows only).
#>

$ErrorActionPreference = 'Continue'
$ToolName    = 'OptiWin'
$ToolVersion = '2.1'
$SelfPath    = $PSCommandPath

if ($env:OS -ne 'Windows_NT') { Write-Host 'This tool only runs on Windows.'; exit 1 }

# =============================================================================
#  Startup: 64-bit Windows PowerShell 5.1, running as administrator
# =============================================================================
$winPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wrongBitness = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
if ($wrongBitness) { $winPS = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if ($PSVersionTable.PSEdition -eq 'Core' -or $wrongBitness -or -not $isAdmin) {
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $SelfPath
    try {
        # Hidden: the GUI is the only window the user needs to see.
        if ($isAdmin) { Start-Process -FilePath $winPS -ArgumentList $argLine -WindowStyle Hidden }
        else          { Start-Process -FilePath $winPS -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden }
    } catch {
        Write-Host 'The tool needs administrator rights to remove apps and change system settings.'
        Write-Host 'It did not start because the Windows permission prompt was declined.'
        Read-Host 'Press Enter to close'
    }
    exit
}

# Crisp text on high-DPI screens, and hide the console window behind the GUI.
try {
    Add-Type -Namespace DebloatTool -Name Native -ErrorAction Stop -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
    [void][DebloatTool.Native]::SetProcessDPIAware()
    [void][DebloatTool.Native]::ShowWindow([DebloatTool.Native]::GetConsoleWindow(), 0)
} catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$DataDir       = Join-Path $env:ProgramData 'OptiWin'
$BackupDir     = Join-Path $DataDir 'Backups'
$LogDir        = Join-Path $DataDir 'Logs'
$QuarantineDir = Join-Path $DataDir 'Quarantine'
$RegBackupDir  = Join-Path $DataDir 'RegBackups'
foreach ($d in @($BackupDir, $LogDir, $QuarantineDir, $RegBackupDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$LogFile = Join-Path $LogDir ('session-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

# =============================================================================
#  Catalog helpers
# =============================================================================
function RegVal([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    @{ Kind = 'Reg'; Path = $Path; Name = $Name; Value = $Value; Type = $Type }
}
function SvcStart([string]$Name, [string]$Start) {
    @{ Kind = 'Service'; Name = $Name; Start = $Start }
}
function TaskOff([string]$Path) {
    @{ Kind = 'Task'; Path = $Path }
}
function New-Tweak([string]$Tab, [string]$Group, [string]$Name, [string]$Desc, [object[]]$Actions) {
    @{ Type = 'Tweak'; Tab = $Tab; Group = $Group; Name = $Name; Desc = $Desc; Actions = $Actions; Skip = $false }
}
function New-App([string]$Group, [string]$Name, [string]$Desc, [string[]]$Patterns) {
    @{ Type = 'App'; Group = $Group; Name = $Name; Desc = $Desc; Patterns = $Patterns }
}
function New-Feature([string]$Group, [string]$Kind, [string]$Pattern, [string]$Name, [string]$Desc) {
    @{ Group = $Group; Kind = $Kind; Pattern = $Pattern; Name = $Name; Desc = $Desc }
}
function New-Cleanup([string]$Group, [string]$Id, [string]$Name, [string]$Desc) {
    @{ Type = 'Cleanup'; Group = $Group; Id = $Id; Name = $Name; Desc = $Desc }
}

$Adv  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$CDM  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$PolW = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'

# =============================================================================
#  Built-in apps
# =============================================================================
$AppCatalog = @(
    New-App Recommended 'Microsoft News' 'News feed app, also called Microsoft Start.' 'Microsoft.BingNews'
    New-App Recommended 'Weather' 'MSN Weather app.' 'Microsoft.BingWeather'
    New-App Recommended 'Old Bing apps' 'Finance, Sports, Travel, Food and Health apps left over from older Windows 10 installs.' @(
        'Microsoft.BingFinance', 'Microsoft.BingSports', 'Microsoft.BingTravel', 'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness')
    New-App Recommended 'Microsoft Bing' 'Bing search app added in recent Windows 11 builds.' 'Microsoft.BingSearch'
    New-App Recommended 'Get Help' "Microsoft's support chat app." 'Microsoft.GetHelp'
    New-App Recommended 'Tips' 'Windows tips app.' 'Microsoft.Getstarted'
    New-App Recommended 'Microsoft 365 (Office) hub' 'Launcher that advertises Microsoft 365. Installed Office apps such as Word are not affected.' 'Microsoft.MicrosoftOfficeHub'
    New-App Recommended 'Solitaire Collection' 'Ad-supported card games.' 'Microsoft.MicrosoftSolitaireCollection'
    New-App Recommended 'Feedback Hub' 'Sends feedback to Microsoft.' 'Microsoft.WindowsFeedbackHub'
    New-App Recommended 'Maps' 'Windows Maps (retired by Microsoft).' 'Microsoft.WindowsMaps'
    New-App Recommended 'Movies & TV' 'Video store and player.' 'Microsoft.ZuneVideo'
    New-App Recommended 'People' 'Old contacts app.' 'Microsoft.People'
    New-App Recommended 'Skype' 'Skype (retired by Microsoft in 2025).' 'Microsoft.SkypeApp'
    New-App Recommended 'Mixed Reality Portal' 'Only needed for Windows Mixed Reality headsets.' 'Microsoft.MixedReality.Portal'
    New-App Recommended '3D Viewer' 'Viewer for 3D models.' 'Microsoft.Microsoft3DViewer'
    New-App Recommended 'Paint 3D' 'Paint 3D. Classic Paint is kept.' 'Microsoft.MSPaint'
    New-App Recommended 'OneNote for Windows 10' 'Old Store version of OneNote. The OneNote that comes with Microsoft 365 is not affected.' 'Microsoft.Office.OneNote'
    New-App Recommended 'Clipchamp' 'Video editor.' 'Clipchamp.Clipchamp'
    New-App Recommended 'Cortana' 'Cortana app (retired by Microsoft).' 'Microsoft.549981C3F5F10'
    New-App Recommended 'Power Automate' 'Desktop automation app.' 'Microsoft.PowerAutomateDesktop'
    New-App Recommended 'Dev Home' 'Developer dashboard (retired by Microsoft).' 'Microsoft.Windows.DevHome'
    New-App Recommended 'Teams (personal, built in)' 'The free Teams chat built into early Windows 11. Work or school Teams is listed separately.' 'MicrosoftTeams'
    New-App Recommended 'Preinstalled games' 'Candy Crush and other promoted games.' @(
        '*CandyCrush*', '*BubbleWitch*', '*MarchofEmpires*', '*HiddenCity*', '*DisneyMagicKingdoms*',
        '*RoyalRevolt*', '*FarmVille*', '*Asphalt8*', '*DragonManiaLegends*', '*CookingFever*')
    New-App Recommended 'Preinstalled social apps' 'Promoted Facebook, Instagram, TikTok, X (Twitter) and LinkedIn apps.' @(
        '*Facebook*', '*Instagram*', '*TikTok*', '*Twitter*', '*LinkedIn*')
    New-App Optional 'Preinstalled streaming apps' 'Netflix, Prime Video, Disney+, Spotify and similar.' @(
        '*Netflix*', '*PrimeVideo*', '*Disney.*', '*SpotifyMusic*', '*Hulu*')
    New-App Optional 'Copilot' 'The Copilot app.' 'Microsoft.Copilot'
    New-App Optional 'Microsoft Teams (work or school)' 'The current Teams app. Keep it if you use Teams for work.' 'MSTeams'
    New-App Optional 'Xbox app' 'Xbox and PC Game Pass app.' @('Microsoft.XboxApp', 'Microsoft.GamingApp')
    New-App Optional 'Xbox Game Bar' 'Win+G overlay, also used for screen recording.' @(
        'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxSpeechToTextOverlay')
    New-App Optional 'Phone Link' 'Connects an Android phone or iPhone to the PC.' 'Microsoft.YourPhone'
    New-App Optional 'Mail and Calendar' 'Old Mail and Calendar apps, being replaced by the new Outlook.' 'microsoft.windowscommunicationsapps'
    New-App Optional 'Outlook (new)' 'The new Outlook for Windows app.' 'Microsoft.OutlookForWindows'
    New-App Optional 'Microsoft To Do' 'Task list app.' 'Microsoft.Todos'
    New-App Optional 'Sticky Notes' 'Desktop notes.' 'Microsoft.MicrosoftStickyNotes'
    New-App Optional 'Sound Recorder' 'Voice recorder app.' 'Microsoft.WindowsSoundRecorder'
    New-App Optional 'Clock' 'Alarms, timers and Focus sessions.' 'Microsoft.WindowsAlarms'
    New-App Optional 'Camera' 'Windows Camera app.' 'Microsoft.WindowsCamera'
    New-App Optional 'Media Player / Groove Music' 'On Windows 11 this is the Media Player app.' 'Microsoft.ZuneMusic'
    New-App Optional 'Quick Assist' 'Remote help tool. Often abused in tech-support scams; remove it if you never use it.' 'MicrosoftCorporationII.QuickAssist'
    New-App Optional 'Microsoft Family' 'Family Safety app.' 'MicrosoftCorporationII.MicrosoftFamily'
)

$OneDriveEntry = @{
    Type = 'OneDrive'; Group = 'Advanced'; Name = 'OneDrive'
    Desc = 'Uninstalls the OneDrive sync app. Files already downloaded stay in your OneDrive folder; online-only files will not open on this PC.'
}
$EdgeEntry = @{
    Type = 'Edge'; Group = 'Advanced'; Name = 'Microsoft Edge'
    Desc = 'Uninstalls the Edge browser and stops Windows Update reinstalling it. WebView2, which many apps rely on, is kept. Install another browser first.'
}
$DefenderEntry = @{
    Type = 'Defender'; Group = 'Advanced'; Name = 'Turn off Microsoft Defender Antivirus'
    Desc = 'Disables Defender real-time protection (it cannot be uninstalled on client Windows). Only for PCs with another antivirus, or isolated malware-analysis machines. You must turn off Tamper Protection in Windows Security first; the tool checks and will not bypass it. Leave this alone on an everyday PC.'
}

# Microsoft Defender disable: policy values, recorded so Undo reverses them. Needs Tamper Protection off.
$DefenderRegActions = @(
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiSpyware' 1
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiVirus' 1
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableRealtimeMonitoring' 1
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableBehaviorMonitoring' 1
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableOnAccessProtection' 1
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableScanOnRealtimeEnable' 1
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet' 'SpynetReporting' 0
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet' 'SubmitSamplesConsent' 2
)
# Non-driver Defender services only. Boot/filter drivers (WdBoot, WdFilter) are left alone so Windows still starts.
$DefenderServiceActions = @(
    SvcStart 'WinDefend' 'disabled'
    SvcStart 'WdNisSvc' 'disabled'
    SvcStart 'Sense' 'disabled'
)
$DefenderTaskPaths = @(
    '\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance'
    '\Microsoft\Windows\Windows Defender\Windows Defender Cleanup'
    '\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan'
    '\Microsoft\Windows\Windows Defender\Windows Defender Verification'
)

# Store apps tab: core parts that are never offered (removing them breaks Windows or the Store itself).
$NeverOffer = @(
    'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI',
    'Microsoft.VCLibs*', 'Microsoft.NET.*', 'Microsoft.UI.Xaml*', 'Microsoft.WindowsAppRuntime*', 'Microsoft.WindowsAppSDK*',
    'MicrosoftCorporationII.WinAppRuntime*', 'Microsoft.Services.Store.Engagement', 'Microsoft.Windows.*', 'MicrosoftWindows.*',
    'Windows.*', 'Microsoft.AAD.BrokerPlugin', 'Microsoft.AccountsControl', 'Microsoft.LockApp', 'Microsoft.Win32WebViewHost',
    'Microsoft.ECApp', 'Microsoft.CredDialogHost', 'Microsoft.AsyncTextService', 'Microsoft.BioEnrollment',
    'Microsoft.MicrosoftEdge*', 'Microsoft.Edge*', 'Microsoft.WidgetsPlatformRuntime',
    'Microsoft.ApplicationCompatibilityEnhancements', 'Microsoft.OneDriveSync', '*LanguageExperiencePack*', 'NcsiUwpApp',
    'Microsoft.StartExperiencesApp', 'Microsoft.Winget.*',
    'c5e2524a-ea46-4f67-841f-6a9465d9d515', 'E2A4F912-2574-4A75-9BB0-0D023378592B',
    'F46D4000-FD22-4DB4-AC8E-4E1DDDE828FE', '1527c705-839a-4832-9118-54d4Bd6a0c89'
)
# Store apps tab: offered, but in their own group with a warning. Checked before $NeverOffer.
$SystemAppPatterns = @(
    'Microsoft.Windows.Photos', 'Microsoft.WindowsCalculator', 'Microsoft.WindowsNotepad', 'Microsoft.Paint',
    'Microsoft.ScreenSketch', 'Microsoft.WindowsTerminal', 'Microsoft.PowerShell', 'Microsoft.*Extension*',
    'Microsoft.XboxIdentityProvider', 'Microsoft.Xbox.TCUI', 'Microsoft.GamingServices'
)

# Desktop programs tab
$ProgramExclusions = @('Microsoft Edge', 'Microsoft Edge Update', 'Microsoft Edge WebView2 Runtime', 'Microsoft OneDrive')
$RuntimePatterns = @(
    'Microsoft Visual C++*', 'Microsoft .NET*', 'Microsoft ASP.NET*', 'Microsoft Windows Desktop Runtime*', '*Redistributable*',
    '*Runtime*', '*Driver*', 'Intel(R)*', 'Intel *', 'NVIDIA*', 'AMD *', 'Realtek*', 'Microsoft Update Health Tools',
    'Microsoft GameInput', '*SDK*'
)
# Genuine bloatware only: factory-preinstalled OEM utilities, trial antivirus, toolbars and bundled adware/nag-ware.
# Highlighted on the Desktop programs tab so the user can review and remove; never auto-removed. Apps a
# person installs on purpose are deliberately NOT listed here.
$BloatProgramPatterns = @(
    # Trial / bundled antivirus and "web advisors" that ship preinstalled
    'McAfee*', '*WebAdvisor*', 'Norton*', 'Avast Free*', 'AVG Antivirus*', 'Avira*', '*Web Companion*', '*Total Adblock*',
    # OEM utilities and preloaded helpers (factory junk)
    'HP Support Assistant', 'HP JumpStart*', 'HP Documentation', 'HP Sure*', 'HP Connection Optimizer', 'HP Audio Center',
    'HP Smart', 'myHP', 'Dell Customer Connect', 'Dell Digital Delivery', 'Dell SupportAssist*', 'Dell Update*',
    'My Dell', 'Dell Mobile Connect', 'Lenovo Vantage*', 'Lenovo Now*', 'Lenovo Utility', 'Lenovo Smart*',
    'Lenovo Welcome', 'MyASUS', 'ASUS GiftBox*', 'ASUS Product Register*', 'Acer Jumpstart', 'Acer Care Center', 'Acer Collection',
    # Toolbars, coupon injectors, nag-ware and preinstalled game promos
    '*Toolbar*', '*Coupon*', 'WildTangent*', '*Booking.com*', 'ExpressFiles*', 'Wondershare Studio'
)

# Microsoft Edge removal: registry changes are recorded so Undo can reverse them.
$EdgeAllowActions = @(
    RegVal 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev' 'AllowUninstall' 1
    RegVal 'HKLM:\SOFTWARE\Microsoft\EdgeUpdateDev' 'AllowUninstall' 1
)
$EdgeBlockActions = @(
    RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0
    RegVal 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1
)

# =============================================================================
#  Settings and services
# =============================================================================
$Tweaks = @(
    # ------------------------------------------------------------ Privacy ----
    New-Tweak Privacy Recommended 'Reduce diagnostic data to the minimum' `
        'Sets diagnostic data to the lowest level your edition allows (Required on Home and Pro) and turns off the Connected User Experiences and Telemetry service.' @(
        RegVal "$PolW\DataCollection" 'AllowTelemetry' 0
        SvcStart 'DiagTrack' 'disabled'
    )
    New-Tweak Privacy Recommended 'Turn off telemetry scheduled tasks' `
        'Turns off the Compatibility Appraiser, Customer Experience Improvement Program, disk diagnostics and feedback tasks that collect and send usage data.' @(
        TaskOff '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
        TaskOff '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp'
        TaskOff '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
        TaskOff '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
        TaskOff '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
        TaskOff '\Microsoft\Windows\Autochk\Proxy'
        TaskOff '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
        TaskOff '\Microsoft\Windows\Feedback\Siuf\DmClient'
        TaskOff '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    )
    New-Tweak Privacy Recommended 'Turn off the advertising ID' `
        'Stops apps using your advertising ID to show personalised ads.' @(
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        RegVal "$PolW\AdvertisingInfo" 'DisabledByGroupPolicy' 1
    )
    New-Tweak Privacy Recommended 'Turn off tailored experiences' `
        'Stops Microsoft using your diagnostic data for personalised tips, ads and recommendations.' @(
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        RegVal 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
    )
    New-Tweak Privacy Recommended 'Turn off activity history' `
        'Stops Windows keeping and uploading a history of the apps, files and sites you use.' @(
        RegVal "$PolW\System" 'EnableActivityFeed' 0
        RegVal "$PolW\System" 'PublishUserActivities' 0
        RegVal "$PolW\System" 'UploadUserActivities' 0
    )
    New-Tweak Privacy Recommended 'Stop feedback requests' `
        'Stops Windows popping up questions asking you to rate it or send feedback.' @(
        RegVal 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
        RegVal "$PolW\DataCollection" 'DoNotShowFeedbackNotifications' 1
    )
    New-Tweak Privacy Recommended 'Turn off typing and inking personalisation' `
        'Stops Windows collecting what you type and handwrite to build a personal dictionary and send typing data to Microsoft.' @(
        RegVal 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
        RegVal 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
        RegVal 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
        RegVal 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
        RegVal 'HKCU:\Software\Microsoft\Input\TIPC' 'Enabled' 0
    )
    New-Tweak Privacy Recommended 'Stop websites reading your language list' `
        'Websites can no longer use your list of Windows languages to tailor content.' @(
        RegVal 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1
    )
    New-Tweak Privacy Recommended 'Turn off Recall snapshots (Copilot+ PCs)' `
        'Stops Recall saving screenshots of your activity. Makes no difference on PCs that do not have Recall.' @(
        RegVal 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
        RegVal "$PolW\WindowsAI" 'DisableAIDataAnalysis' 1
    )
    New-Tweak Privacy Optional 'Turn off online speech recognition' `
        'Stops sending your voice to Microsoft for recognition. Voice typing and other cloud speech features stop working.' @(
        RegVal 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
    )
    New-Tweak Privacy Optional 'Stop tracking which apps you open' `
        'Windows stops recording app launches. Start will no longer show a most-used list.' @(
        RegVal $Adv 'Start_TrackProgs' 0
    )

    # ---------------------------------------------- Start, taskbar & ads ----
    New-Tweak Start Recommended 'Stop auto-installed and suggested apps' `
        'Stops Windows quietly installing promoted apps such as games, and suggesting apps in Start.' @(
        RegVal $CDM 'SilentInstalledAppsEnabled' 0
        RegVal $CDM 'PreInstalledAppsEnabled' 0
        RegVal $CDM 'PreInstalledAppsEverEnabled' 0
        RegVal $CDM 'OemPreInstalledAppsEnabled' 0
        RegVal $CDM 'SystemPaneSuggestionsEnabled' 0
        RegVal $CDM 'SubscribedContent-338388Enabled' 0
        RegVal "$PolW\CloudContent" 'DisableWindowsConsumerFeatures' 1
    )
    New-Tweak Start Recommended 'Turn off tips and "get more out of Windows" prompts' `
        'Stops tip notifications, the welcome screen after updates and the "finish setting up your device" reminders.' @(
        RegVal $CDM 'SubscribedContent-338389Enabled' 0
        RegVal $CDM 'SubscribedContent-310093Enabled' 0
        RegVal $CDM 'SoftLandingEnabled' 0
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    )
    New-Tweak Start Recommended 'Turn off suggestions in the Settings app' `
        'Removes suggested content and promotions shown inside Settings.' @(
        RegVal $CDM 'SubscribedContent-338393Enabled' 0
        RegVal $CDM 'SubscribedContent-353694Enabled' 0
        RegVal $CDM 'SubscribedContent-353696Enabled' 0
    )
    New-Tweak Start Recommended 'Turn off lock screen tips and fun facts' `
        'Removes the tips, tricks and fun facts drawn over the lock screen picture.' @(
        RegVal $CDM 'RotatingLockScreenOverlayEnabled' 0
        RegVal $CDM 'SubscribedContent-338387Enabled' 0
    )
    New-Tweak Start Recommended 'Turn off Start menu promotions (Windows 11)' `
        'Removes promoted tips and new-app suggestions from the Recommended area of Start, and the Microsoft account reminders on your profile picture.' @(
        RegVal $Adv 'Start_IrisRecommendations' 0
        RegVal $Adv 'Start_AccountNotifications' 0
    )
    New-Tweak Start Recommended 'Remove web and Bing results from Start search' `
        'Stops Start search sending what you type to Bing over the internet. It then shows only apps, files and settings on this PC, with search highlights off.' @(
        RegVal 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsMSACloudSearchEnabled' 0
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsAADCloudSearchEnabled' 0
        RegVal "$PolW\Windows Search" 'DisableWebSearch' 1
        RegVal "$PolW\Windows Search" 'ConnectedSearchUseWeb' 0
        RegVal "$PolW\Windows Search" 'AllowCloudSearch' 0
        RegVal "$PolW\Windows Search" 'EnableDynamicContentInWSB' 0
    )
    New-Tweak Start Recommended 'Turn off Widgets / News and interests' `
        'Removes the news and weather feed from the taskbar.' @(
        RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        RegVal "$PolW\Windows Feeds" 'EnableFeeds' 0
    )
    New-Tweak Start Recommended 'Stop OneDrive and Microsoft 365 ads in File Explorer' `
        'Turns off the sync provider notifications shown at the top of File Explorer.' @(
        RegVal $Adv 'ShowSyncProviderNotifications' 0
    )
    New-Tweak Start Optional 'Hide the Task View button' `
        'Removes the Task View button from the taskbar. Win+Tab still works.' @(
        RegVal $Adv 'ShowTaskViewButton' 0
    )
    New-Tweak Start Optional 'Show search as an icon only' `
        'Shrinks the taskbar search box down to a magnifying-glass icon.' @(
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1
    )
    New-Tweak Start Optional 'Turn off Windows Copilot' `
        'Turns off the built-in Copilot sidebar and hides its taskbar button. To remove the Copilot app itself, tick it on the Built-in apps tab.' @(
        RegVal 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        RegVal "$PolW\WindowsCopilot" 'TurnOffWindowsCopilot' 1
        RegVal $Adv 'ShowCopilotButton' 0
    )
    New-Tweak Start Optional 'Stop Microsoft Edge running in the background' `
        'Edge stops preloading at sign-in and fully closes when you close it. Because this uses a policy, Edge will say it is managed by your organization.' @(
        RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
        RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
    )

    # --------------------------------------------------- Explorer & system ----
    New-Tweak System Recommended 'Show file name extensions' `
        'Shows the real file type, so a file named invoice.pdf.exe cannot pass itself off as a PDF.' @(
        RegVal $Adv 'HideFileExt' 0
    )
    New-Tweak System Recommended 'Turn off Cortana' `
        'Turns off Cortana through policy.' @(
        RegVal "$PolW\Windows Search" 'AllowCortana' 0
    )
    New-Tweak System Recommended 'Turn off Delivery Optimization (peer update sharing)' `
        'Delivery Optimization downloads updates from, and uploads them to, other PCs over your connection - the option that can use a large share of your bandwidth. This switches it to download only from Microsoft, so it stops sharing and using bandwidth for peers. It then shows as "managed by your organization" under Settings > Windows Update > Delivery Optimization.' @(
        RegVal "$PolW\DeliveryOptimization" 'DODownloadMode' 0
    )
    New-Tweak System Optional 'Free the bandwidth Windows reserves (QoS)' `
        'By default Windows lets system components reserve up to 20% of your connection for jobs such as updates. This sets that reserve to 0% so programs can use the full connection. Takes effect after a restart.' @(
        RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' 'NonBestEffortLimit' 0
    )
    New-Tweak System Optional 'Limit background Windows Update downloads' `
        'Caps how much of your connection Windows Update may use while downloading in the background, so updates do not crowd out your own traffic.' @(
        RegVal "$PolW\DeliveryOptimization" 'DOPercentageMaxBackgroundBandwidth' 25
    )
    New-Tweak System Optional 'Show hidden files' `
        'Shows hidden files and folders in File Explorer.' @(
        RegVal $Adv 'Hidden' 1
    )
    New-Tweak System Optional 'Classic right-click menu (Windows 11)' `
        'Brings back the full right-click menu without "Show more options". Appears after File Explorer restarts.' @(
        RegVal 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' '' 'String'
    )
    New-Tweak System Optional 'Open File Explorer to This PC' `
        'File Explorer opens on This PC (your drives) instead of Home / Quick access.' @(
        RegVal $Adv 'LaunchTo' 1
    )
    New-Tweak System Optional 'Turn off game clip recording (Game DVR)' `
        'Stops background gameplay recording, which can cost frame rate. Xbox Game Bar capture stops working.' @(
        RegVal 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        RegVal "$PolW\GameDVR" 'AllowGameDVR' 0
    )
    New-Tweak System Optional 'Stop background apps (Windows 10)' `
        'Store apps stop running in the background, so some of them may not show notifications.' @(
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
        RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
    )
    New-Tweak System Optional 'Turn off the Sticky Keys shortcut' `
        'Pressing Shift five times no longer pops up the Sticky Keys prompt.' @(
        RegVal 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
    )
    New-Tweak System Optional 'Turn off mouse acceleration' `
        'Turns off "Enhance pointer precision" so the same hand movement always moves the pointer the same distance. Takes effect after you sign out.' @(
        RegVal 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
        RegVal 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
        RegVal 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
    )

    # ----------------------------------------------------------- Services ----
    New-Tweak Services Recommended 'Retail Demo service' `
        'Only used by display PCs in shops.' @(
        SvcStart 'RetailDemo' 'disabled'
    )
    New-Tweak Services Recommended 'Downloaded Maps Manager' `
        'Keeps offline maps up to date for the retired Maps app.' @(
        SvcStart 'MapsBroker' 'disabled'
    )
    New-Tweak Services Recommended 'Windows Media Player network sharing' `
        'Shares your media library with other devices on the network.' @(
        SvcStart 'WMPNetworkSvc' 'disabled'
    )
    New-Tweak Services Recommended 'Remote Registry' `
        'Lets other computers edit this PC''s registry over the network. Already off on most PCs.' @(
        SvcStart 'RemoteRegistry' 'disabled'
    )
    New-Tweak Services Recommended 'Fax' `
        'Sends and receives faxes through a fax modem.' @(
        SvcStart 'Fax' 'disabled'
    )
    New-Tweak Services Optional 'Xbox services' `
        'Xbox sign-in, cloud saves, accessories and networking. The Xbox app, Game Pass games and some controller features stop working.' @(
        SvcStart 'XblAuthManager' 'disabled'
        SvcStart 'XblGameSave' 'disabled'
        SvcStart 'XboxGipSvc' 'disabled'
        SvcStart 'XboxNetApiSvc' 'disabled'
    )
    New-Tweak Services Optional 'Print Spooler' `
        'Only if you never print. Microsoft Print to PDF stops working too. Removes a service attackers have targeted (PrintNightmare).' @(
        SvcStart 'Spooler' 'disabled'
    )
    New-Tweak Services Optional 'Windows Search indexing' `
        'Saves disk activity, but searching files in Start, File Explorer and Outlook becomes much slower.' @(
        SvcStart 'WSearch' 'disabled'
    )
    New-Tweak Services Optional 'SysMain (Superfetch)' `
        'Preloads apps into memory. Turning it off can help on slow hard drives; little difference on SSDs.' @(
        SvcStart 'SysMain' 'disabled'
    )
    New-Tweak Services Optional 'Windows Error Reporting' `
        'Stops crash reports being collected and sent to Microsoft.' @(
        SvcStart 'WerSvc' 'disabled'
    )
    New-Tweak Services Optional 'Device management WAP push' `
        'Used by work or school device management (Intune). Leave it on if your PC is managed by an organisation.' @(
        SvcStart 'dmwappushservice' 'disabled'
    )
    New-Tweak Services Optional 'Geolocation service' `
        'Location stops working for every app, including maps, weather and Find my device.' @(
        SvcStart 'lfsvc' 'disabled'
    )
    New-Tweak Services Optional 'Distributed Link Tracking Client' `
        'Keeps shortcuts working when linked files move between NTFS drives on a network.' @(
        SvcStart 'TrkWks' 'disabled'
    )
    New-Tweak Services Optional 'Windows Insider service' `
        'Only needed if you join the Windows Insider preview programme.' @(
        SvcStart 'wisvc' 'disabled'
    )
)

# =============================================================================
#  Optional Windows features and capabilities
# =============================================================================
$FeatureCatalog = @(
    New-Feature Recommended OptionalFeature 'SMB1Protocol' 'SMB 1.0 file sharing' `
        'Old, insecure file-sharing protocol abused by worms such as WannaCry. Only very old NAS boxes and printers need it.'
    New-Feature Recommended OptionalFeature 'MicrosoftWindowsPowerShellV2Root' 'Windows PowerShell 2.0 engine' `
        'Legacy engine that attackers use to dodge modern PowerShell logging and AMSI. Almost nothing needs it.'
    New-Feature Recommended OptionalFeature 'Recall' 'Recall (Copilot+ PCs)' `
        'Removes the Recall component entirely, not just its snapshots.'
    New-Feature Recommended OptionalFeature 'Internet-Explorer-Optional-amd64' 'Internet Explorer 11' `
        'Retired browser. Edge has its own IE mode for old sites.'
    New-Feature Recommended Capability 'Browser.InternetExplorer~~~~*' 'Internet Explorer 11' `
        'Retired browser. Edge has its own IE mode for old sites.'
    New-Feature Recommended Capability 'App.StepsRecorder~~~~*' 'Steps Recorder' `
        'Retired screen-step recording tool.'
    New-Feature Recommended Capability 'MathRecognizer~~~~*' 'Math Input Panel' `
        'Handwriting recogniser for maths equations.'
    New-Feature Recommended Capability 'XPS.Viewer~~~~*' 'XPS Viewer' `
        'Viewer for the old XPS document format.'
    New-Feature Optional OptionalFeature 'WorkFolders-Client' 'Work Folders client' `
        'Syncs files with a Work Folders server at an organisation.'
    New-Feature Optional OptionalFeature 'Printing-XPSServices-Features' 'Microsoft XPS Document Writer' `
        'The XPS "printer" that saves documents as XPS files.'
    New-Feature Optional OptionalFeature 'FaxServicesClientPackage' 'Windows Fax and Scan' `
        'Fax and scanning app.'
    New-Feature Optional OptionalFeature 'WindowsMediaPlayer' 'Windows Media Player (legacy)' `
        'The classic Windows Media Player.'
    New-Feature Optional Capability 'Media.WindowsMediaPlayer~~~~*' 'Windows Media Player (legacy)' `
        'The classic Windows Media Player.'
    New-Feature Optional Capability 'Microsoft.Windows.WordPad~~~~*' 'WordPad' `
        'Basic word processor (retired by Microsoft).'
    New-Feature Optional Capability 'Microsoft.Windows.PowerShell.ISE~~~~*' 'Windows PowerShell ISE' `
        'Old PowerShell script editor. Keep it if you write scripts in it.'
    New-Feature Optional Capability 'Print.Fax.Scan~~~~*' 'Windows Fax and Scan' `
        'Fax and scanning app.'
    New-Feature Optional Capability 'App.Support.QuickAssist~~~~*' 'Quick Assist (Windows 10)' `
        'Remote help tool. Often abused in tech-support scams.'
)

# =============================================================================
#  Clean-up
# =============================================================================
$CleanupCatalog = @(
    New-Cleanup Recommended 'Temp' 'Temporary files' `
        'Deletes files older than a day from your Temp folder and the Windows Temp folder. Files in use are skipped.'
    New-Cleanup Recommended 'WUCache' 'Windows Update download cache' `
        'Deletes update files Windows has already downloaded. They are downloaded again if still needed.'
    New-Cleanup Recommended 'DOCache' 'Delivery Optimization cache' `
        'Deletes update pieces Windows keeps for sharing with other PCs.'
    New-Cleanup Optional 'DISM' 'Component store clean-up' `
        'Removes superseded versions of Windows components (DISM StartComponentCleanup). Can take 5 to 20 minutes.'
)
$StartupOffBytes = @(3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

# =============================================================================
#  Registry
# =============================================================================
function Split-RegPath([string]$Path) {
    if ($Path -match '^(HKLM|HKCU):\\(.+)$') {
        if ($Matches[1] -eq 'HKLM') { $hive = [Microsoft.Win32.RegistryHive]::LocalMachine }
        else                        { $hive = [Microsoft.Win32.RegistryHive]::CurrentUser }
        return @($hive, $Matches[2])
    }
    throw "Unsupported registry path: $Path"
}

function Open-RegBase($Hive) {
    [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, [Microsoft.Win32.RegistryView]::Registry64)
}

function Get-RegState([string]$Path, [string]$Name) {
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    try {
        $key = $base.OpenSubKey($sub, $false)
        if ($null -eq $key) { return @{ KeyExists = $false; Exists = $false } }
        try {
            if (@($key.GetValueNames()) -contains $Name) {
                return @{
                    KeyExists = $true; Exists = $true
                    Kind      = [string]$key.GetValueKind($Name)
                    Value     = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
            }
            return @{ KeyExists = $true; Exists = $false }
        } finally { $key.Close() }
    } finally { $base.Close() }
}

# All values of a key (environment variables expanded), as a hashtable.
function Get-RegValues([string]$Path) {
    $h = @{}
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    try {
        $key = $base.OpenSubKey($sub, $false)
        if ($null -ne $key) {
            try { foreach ($n in $key.GetValueNames()) { $h[$n] = $key.GetValue($n) } }
            finally { $key.Close() }
        }
    } finally { $base.Close() }
    return $h
}

function Get-RegSubKeyNames([string]$Path) {
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    try {
        $key = $base.OpenSubKey($sub, $false)
        if ($null -eq $key) { return }
        try { $key.GetSubKeyNames() } finally { $key.Close() }
    } finally { $base.Close() }
}

function Test-RegKey([string]$Path) {
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    try {
        $key = $base.OpenSubKey($sub, $false)
        if ($null -eq $key) { return $false }
        $key.Close()
        return $true
    } finally { $base.Close() }
}

function ConvertTo-RegData([string]$Kind, $Value) {
    switch ($Kind) {
        'DWord'       { return [int]$Value }
        'QWord'       { return [long]$Value }
        'Binary'      { return , ([byte[]]@($Value)) }
        'MultiString' { return , ([string[]]@($Value)) }
        default       { return [string]$Value }
    }
}

function Set-RegValue([string]$Path, [string]$Name, [string]$Kind, $Value) {
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    try {
        $key = $base.CreateSubKey($sub)
        try { $key.SetValue($Name, (ConvertTo-RegData $Kind $Value), [Microsoft.Win32.RegistryValueKind]$Kind) }
        finally { $key.Close() }
    } finally { $base.Close() }
}

function Remove-RegValue([string]$Path, [string]$Name) {
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    try {
        $key = $base.OpenSubKey($sub, $true)
        if ($null -ne $key) { try { $key.DeleteValue($Name, $false) } finally { $key.Close() } }
    } finally { $base.Close() }
}

# Keys that do not exist yet and would be created to reach $Path (outermost first).
function Get-MissingKeys([string]$Path) {
    $prefix = $Path.Substring(0, 5)
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    $missing = New-Object System.Collections.Generic.List[string]
    try {
        $cur = ''
        foreach ($part in $sub.Split('\')) {
            if ($cur) { $cur = "$cur\$part" } else { $cur = $part }
            if ($missing.Count -gt 0) { $missing.Add("$prefix\$cur"); continue }
            $k = $base.OpenSubKey($cur, $false)
            if ($null -eq $k) { $missing.Add("$prefix\$cur") } else { $k.Close() }
        }
    } finally { $base.Close() }
    return , $missing.ToArray()
}

function Remove-RegKeyIfEmpty([string]$Path) {
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    try {
        $k = $base.OpenSubKey($sub, $false)
        if ($null -eq $k) { return $true }
        $empty = ($k.SubKeyCount -eq 0 -and $k.ValueCount -eq 0)
        $k.Close()
        if ($empty) { $base.DeleteSubKey($sub, $false); return $true }
        return $false
    } finally { $base.Close() }
}

function Format-RegName([string]$Path, [string]$Name) {
    $n = $Name
    if ($n -eq '') { $n = '(Default)' }
    ("$Path\$n") -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU'
}

function Format-RegData($Value) {
    if ($null -eq $Value) { return '(not set)' }
    if ($Value -is [array]) { return ($Value -join ',') }
    if ($Value -is [string] -and $Value -eq '') { return '""' }
    return [string]$Value
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return ('{0:N0} bytes' -f $Bytes)
}

# =============================================================================
#  Services, scheduled tasks, generic actions
# =============================================================================
function Get-ServiceStart([string]$Name) {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $s = Get-RegState $p 'Start'
    if (-not $s.Exists) { return $null }
    $d = Get-RegState $p 'DelayedAutostart'
    switch ([int]$s.Value) {
        2       { if ($d.Exists -and [int]$d.Value -eq 1) { 'delayed-auto' } else { 'auto' } }
        3       { 'demand' }
        4       { 'disabled' }
        default { 'boot/system' }
    }
}

function Set-ServiceStart([string]$Name, [string]$Mode) {
    $out = & sc.exe config $Name start= $Mode 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("sc.exe: " + (($out | Out-String).Trim())) }
}

# 'Running', 'Stopped' or 'Absent' across one or more service names, for showing what is actually in use.
function Get-ServiceRunState([string[]]$Names) {
    $any = $false; $running = $false
    foreach ($n in $Names) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($s) { $any = $true; if ($s.Status -eq 'Running') { $running = $true } }
    }
    if (-not $any) { return 'Absent' }
    if ($running) { return 'Running' }
    return 'Stopped'
}

function Split-TaskPath([string]$Full) {
    $i = $Full.LastIndexOf('\')
    return @($Full.Substring(0, $i + 1), $Full.Substring($i + 1))
}

function Get-TaskState([string]$Full) {
    $tp, $tn = Split-TaskPath $Full
    $t = Get-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction SilentlyContinue
    if ($null -eq $t) { return $null }
    return [string]$t.State
}

# What one action would do right now, without changing anything.
function Get-ActionPlan($a) {
    switch ($a.Kind) {
        'Reg' {
            $label = Format-RegName $a.Path $a.Name
            $target = Format-RegData (ConvertTo-RegData $a.Type $a.Value)
            try {
                $st = Get-RegState $a.Path $a.Name
                if ($st.Exists) { $cur = Format-RegData $st.Value } else { $cur = '(not set)' }
                $done = $st.Exists -and ($st.Kind -eq $a.Type) -and ($cur -eq $target)
                return @{ Label = $label; Current = $cur; Target = $target; Done = $done; Missing = $false }
            } catch {
                return @{ Label = $label; Current = '(unreadable)'; Target = $target; Done = $false; Missing = $false }
            }
        }
        'Service' {
            $cur = Get-ServiceStart $a.Name
            if ($null -eq $cur) { return @{ Label = "Service $($a.Name)"; Missing = $true; Done = $true } }
            return @{ Label = "Service $($a.Name) startup"; Current = $cur; Target = $a.Start; Done = ($cur -eq $a.Start); Missing = $false }
        }
        'Task' {
            $cur = Get-TaskState $a.Path
            if ($null -eq $cur) { return @{ Label = "Task $($a.Path)"; Missing = $true; Done = $true } }
            return @{ Label = "Task $($a.Path)"; Current = $cur; Target = 'Disabled'; Done = ($cur -eq 'Disabled'); Missing = $false }
        }
    }
}

# Applies one action and returns the record needed to undo it.
function Invoke-Action($a) {
    switch ($a.Kind) {
        'Reg' {
            $st = Get-RegState $a.Path $a.Name
            $created = Get-MissingKeys $a.Path
            Set-RegValue $a.Path $a.Name $a.Type $a.Value
            return @{
                Kind = 'Reg'; Path = $a.Path; Name = $a.Name; Existed = [bool]$st.Exists
                OldKind = $st.Kind; OldValue = $st.Value; CreatedKeys = $created
            }
        }
        'Service' {
            $old = Get-ServiceStart $a.Name
            $svc = Get-Service -Name $a.Name -ErrorAction SilentlyContinue
            $wasRunning = [bool]($svc -and $svc.Status -eq 'Running')
            if ($a.Start -eq 'disabled' -and $wasRunning) { Stop-Service -Name $a.Name -Force -ErrorAction SilentlyContinue }
            Set-ServiceStart $a.Name $a.Start
            return @{ Kind = 'Service'; Name = $a.Name; OldStart = $old; WasRunning = $wasRunning }
        }
        'Task' {
            $tp, $tn = Split-TaskPath $a.Path
            Disable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null
            return @{ Kind = 'Task'; Path = $a.Path }
        }
    }
}

# Reverses one record from a backup file. Returns a line for the log.
function Undo-Record($r) {
    switch ($r.Kind) {
        'Reg' {
            $label = Format-RegName $r.Path $r.Name
            if ($r.Existed) {
                Set-RegValue $r.Path $r.Name $r.OldKind $r.OldValue
                return "$label restored to $(Format-RegData $r.OldValue)"
            }
            Remove-RegValue $r.Path $r.Name
            $keys = @($r.CreatedKeys | Where-Object { $_ })
            for ($i = $keys.Count - 1; $i -ge 0; $i--) {
                if (-not (Remove-RegKeyIfEmpty $keys[$i])) { break }
            }
            return "$label removed (it was not set before)"
        }
        'Service' {
            if ($r.OldStart -and $r.OldStart -ne 'boot/system') { Set-ServiceStart $r.Name $r.OldStart }
            if ($r.WasRunning) { Start-Service -Name $r.Name -ErrorAction SilentlyContinue }
            return "Service $($r.Name) startup restored to $($r.OldStart)"
        }
        'Task' {
            $tp, $tn = Split-TaskPath $r.Path
            Enable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null
            return "Task $($r.Path) re-enabled"
        }
        'Feature' {
            if ($r.FeatureType -eq 'Capability') {
                [void](Invoke-InBackground { param($n) Add-WindowsCapability -Online -Name $n -ErrorAction Stop | Out-Null } @($r.Name))
                return "Windows capability $($r.Name) added back"
            }
            [void](Invoke-InBackground { param($n) Enable-WindowsOptionalFeature -Online -FeatureName $n -All -NoRestart -ErrorAction Stop | Out-Null } @($r.Name))
            return "Windows feature $($r.Name) turned back on"
        }
        'Quarantine' {
            $parent = Split-Path $r.From -Parent
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Move-Item -LiteralPath $r.To -Destination $r.From -Force -ErrorAction Stop
            return "restored $($r.From)"
        }
        'RegKeyDelete' {
            Import-RegFileBackup $r.Backup
            if ($r.Service) { return "service $($r.Service) registry restored (restart to bring it back)" }
            return "registry key $(Convert-RegExePath $r.Path) restored"
        }
        'TaskDelete' {
            $xml = Get-Content -Raw -Path $r.Backup
            $tp, $tn = Split-TaskPath $r.Path
            [void](Invoke-InBackground { param($p, $n2, $x) Register-ScheduledTask -TaskPath $p -TaskName $n2 -Xml $x -Force -ErrorAction Stop | Out-Null } @($tp, $tn, $xml))
            return "scheduled task $($r.Path) restored"
        }
        'MpPref' {
            [void](Invoke-InBackground { param($n, $v) $h = @{}; $h[$n] = $v; Set-MpPreference @h -ErrorAction Stop } @($r.Name, $r.Restore))
            return "Defender setting $($r.Name) restored to $($r.Restore)"
        }
    }
}

# =============================================================================
#  Microsoft Defender helpers
# =============================================================================
# $true = Tamper Protection on, $false = off, $null = could not read it.
# The Features\TamperProtection registry value is obfuscated by Windows and often
# wrong, so ask Defender itself first (Get-MpComputerStatus.IsTamperProtected).
function Get-TamperProtection {
    try {
        $r = Invoke-InBackground { (Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected }
        $v = $r.Output | Select-Object -Last 1
        if ($v -is [bool]) { return [bool]$v }
        if ("$v" -eq 'True')  { return $true }
        if ("$v" -eq 'False') { return $false }
    } catch { }
    try {
        $st = Get-RegState 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' 'TamperProtection'
        if ($st.Exists) { return ([int]$st.Value -ge 5) }
    } catch { }
    return $null
}

# $true if Defender still has real-time protection on, $false if off, $null if unknown.
function Get-DefenderRealtime {
    try {
        $r = Invoke-InBackground { (Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled }
        $v = $r.Output | Select-Object -Last 1
        if ($v -is [bool]) { return [bool]$v }
        if ("$v" -eq 'True')  { return $true }
        if ("$v" -eq 'False') { return $false }
    } catch { }
    return $null
}

function Get-OtherAntivirus {
    $r = Invoke-InBackground {
        Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
            Where-Object { $_.displayName -and $_.displayName -notmatch 'Windows Defender|Microsoft Defender' } |
            ForEach-Object { $_.displayName }
    }
    return @($r.Output | Where-Object { $_ } | Select-Object -Unique)
}

function Invoke-DefenderDisable {
    foreach ($a in $script:DefenderRegActions) { Invoke-LoggedAction $a }
    foreach ($t in $script:DefenderTaskPaths) { Invoke-LoggedAction (TaskOff $t) }
    foreach ($s in $script:DefenderServiceActions) { Invoke-LoggedAction $s }

    # Defender's own settings, via its supported cmdlet. These apply only while Tamper
    # Protection is off; with it on, Set-MpPreference is ignored or errors (logged, not forced).
    $targets = @(
        @{ Name = 'DisableRealtimeMonitoring'; Value = $true; Restore = $false }
        @{ Name = 'DisableBehaviorMonitoring'; Value = $true; Restore = $false }
        @{ Name = 'DisableIOAVProtection';     Value = $true; Restore = $false }
        @{ Name = 'DisableScriptScanning';     Value = $true; Restore = $false }
        @{ Name = 'MAPSReporting';             Value = 0;     Restore = 2 }
        @{ Name = 'SubmitSamplesConsent';      Value = 2;     Restore = 1 }
    )
    $cur = $null
    try { $cur = (Invoke-InBackground { Get-MpPreference -ErrorAction Stop }).Output | Select-Object -Last 1 } catch { }
    foreach ($p in $targets) {
        $restore = $p.Restore
        if ($cur -and $null -ne $cur.($p.Name)) { $restore = $cur.($p.Name) }
        try {
            [void](Invoke-InBackground { param($n, $v) $h = @{}; $h[$n] = $v; Set-MpPreference @h -ErrorAction Stop } @($p.Name, $p.Value))
            Add-RunRecord @{ Kind = 'MpPref'; Name = $p.Name; Restore = $restore }
            Write-Log "    Set-MpPreference $($p.Name) = $($p.Value)"
            $script:Stats.Changed++
        } catch {
            Write-Log "    Set-MpPreference $($p.Name) not applied (Tamper Protection likely on): $($_.Exception.Message)"
        }
    }
}

# =============================================================================
#  Background work and processes
# =============================================================================
# Runs slow cmdlets on a second runspace so the window keeps responding.
function Invoke-InBackground([scriptblock]$Script, [object[]]$Arguments = @()) {
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddScript($Script.ToString())
        foreach ($arg in $Arguments) { [void]$ps.AddArgument($arg) }
        $h = $ps.BeginInvoke()
        while (-not $h.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 80
        }
        try { $out = $ps.EndInvoke($h) }
        catch {
            $e = $_.Exception
            if ($e.InnerException) { $e = $e.InnerException }
            throw $e.Message
        }
        return @{ Output = @($out); Errors = @($ps.Streams.Error) }
    } finally { $ps.Dispose() }
}

function Start-Tracked([string]$File, [string]$Arguments, [bool]$Hidden) {
    $sp = @{ FilePath = $File; PassThru = $true; ErrorAction = 'Stop' }
    if ($Arguments) { $sp['ArgumentList'] = $Arguments }
    if ($Hidden) { $sp['WindowStyle'] = 'Hidden' }
    $proc = Start-Process @sp
    $null = $proc.Handle   # keeps ExitCode readable after the process ends
    return $proc
}

function Wait-Tracked($Proc, [double]$TimeoutMinutes) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $Proc.HasExited -and $sw.Elapsed.TotalMinutes -lt $TimeoutMinutes) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }
    return $Proc.HasExited
}

# =============================================================================
#  Store apps
# =============================================================================
$InstalledPkgs   = @()
$ProvisionedPkgs = @()

function Update-PackageCache {
    $r = Invoke-InBackground {
        $inst = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
        if ($inst.Count -eq 0) { $inst = @(Get-AppxPackage -ErrorAction SilentlyContinue) }
        $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
        [pscustomobject]@{ Installed = $inst; Provisioned = $prov }
    }
    $res = $r.Output | Select-Object -First 1
    $script:InstalledPkgs   = @($res.Installed | Where-Object { $_ })
    $script:ProvisionedPkgs = @($res.Provisioned | Where-Object { $_ })
}

function Test-NameMatches([string]$Name, [string[]]$Patterns) {
    foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
    return $false
}

function Get-AppMatches($Entry) {
    $inst = @($script:InstalledPkgs | Where-Object { Test-NameMatches $_.Name $Entry.Patterns } |
              Sort-Object PackageFullName -Unique)
    $prov = @($script:ProvisionedPkgs | Where-Object { Test-NameMatches $_.DisplayName $Entry.Patterns } |
              Sort-Object PackageName -Unique)
    return @{ Installed = $inst; Provisioned = $prov }
}

function Get-PublisherName([string]$Publisher) {
    if ($Publisher -match 'CN=([^,]+)') { return $Matches[1].Trim('"') }
    return $Publisher
}

function Get-SourceName([string]$SignatureKind) {
    switch ($SignatureKind) {
        'Store'      { 'Microsoft Store' }
        'Developer'  { 'sideloaded' }
        'Enterprise' { 'installed by an organisation' }
        default      { 'other source' }
    }
}

$RemoveAppScript = {
    param($FullName)
    try { Remove-AppxPackage -Package $FullName -AllUsers -ErrorAction Stop; 'all users' }
    catch { Remove-AppxPackage -Package $FullName -ErrorAction Stop; 'current user only' }
}
$RemoveProvisionedScript = {
    param($PackageName)
    Remove-AppxProvisionedPackage -Online -PackageName $PackageName -ErrorAction Stop | Out-Null
}

# Removes every installed and provisioned package of one app entry. Returns the names removed.
function Remove-AppEntry($App) {
    $m = Get-AppMatches $App
    $gone = @()
    foreach ($p in $m.Installed) {
        try {
            $how = (Invoke-InBackground $script:RemoveAppScript @($p.PackageFullName)).Output | Select-Object -Last 1
            Write-Log "    removed $($p.PackageFullName) ($how)"
            $gone += $p.Name
        } catch {
            Write-Log "    FAILED $($p.PackageFullName): $($_.Exception.Message)"
            $script:Stats.Failed++
        }
    }
    foreach ($p in $m.Provisioned) {
        try {
            [void](Invoke-InBackground $script:RemoveProvisionedScript @($p.PackageName))
            Write-Log "    removed provisioned copy $($p.PackageName) (new accounts will not get it)"
            $gone += $p.DisplayName
        } catch {
            Write-Log "    FAILED provisioned $($p.PackageName): $($_.Exception.Message)"
            $script:Stats.Failed++
        }
    }
    return , @($gone | Select-Object -Unique)
}

# =============================================================================
#  Desktop programs
# =============================================================================
function Get-Win32Programs {
    $roots = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'All users' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'All users, 32-bit' },
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Current user' }
    )
    $list = New-Object System.Collections.ArrayList
    foreach ($root in $roots) {
        foreach ($sub in @(Get-RegSubKeyNames $root.Path)) {
            try {
                $key = "$($root.Path)\$sub"
                $v = Get-RegValues $key
                $name = ([string]$v['DisplayName']).Trim()
                if (-not $name) { continue }
                if ("$($v['SystemComponent'])" -eq '1' -or "$($v['NoRemove'])" -eq '1') { continue }
                if ($v['ParentKeyName'] -or $v['ParentDisplayName']) { continue }
                if ([string]$v['ReleaseType'] -match 'Update|Hotfix') { continue }
                if (Test-NameMatches $name $script:ProgramExclusions) { continue }
                $uninst = ([string]$v['UninstallString']).Trim()
                $quiet  = ([string]$v['QuietUninstallString']).Trim()
                if (-not $uninst -and -not $quiet) { continue }

                $code = $null
                if ($sub -match '^\{[0-9A-Fa-f-]{36}\}$' -and ("$($v['WindowsInstaller'])" -eq '1' -or $uninst -match '(?i)msiexec')) { $code = $sub }
                elseif ($uninst -match '(?i)msiexec.*?(\{[0-9A-Fa-f-]{36}\})') { $code = $Matches[1] }

                $date = [string]$v['InstallDate']
                if ($date -match '^(\d{4})(\d{2})(\d{2})$') { $date = "$($Matches[1])-$($Matches[2])-$($Matches[3])" } else { $date = '' }
                $size = 0
                if ($v['EstimatedSize']) { $size = [double]$v['EstimatedSize'] * 1KB }
                $group = 'Optional'
                if (Test-NameMatches $name $script:RuntimePatterns) { $group = 'Runtime' }

                [void]$list.Add(@{
                    Type = 'Win32'; Group = $group; Name = $name; Key = $key; Scope = $root.Scope
                    Publisher = ([string]$v['Publisher']).Trim(); Version = [string]$v['DisplayVersion']
                    Uninstall = $uninst; Quiet = $quiet; ProductCode = $code; Size = $size; Date = $date
                    InstallLocation = ([string]$v['InstallLocation']).Trim().TrimEnd('\')
                })
            } catch { }
        }
    }
    $list | Sort-Object { $_.Name }
}

# Splits a command line into program and arguments.
function Split-CommandLine([string]$Command) {
    $c = $Command.Trim()
    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 1) { return @{ File = $c.Substring(1, $end - 1); Args = $c.Substring($end + 1).Trim() } }
    }
    $m = [regex]::Match($c, '(?i)^(.+?\.exe)(\s+(.*))?$')
    if ($m.Success) { return @{ File = $m.Groups[1].Value; Args = $m.Groups[3].Value.Trim() } }
    return @{ File = 'cmd.exe'; Args = '/c "' + $c + '"' }
}

# Picks the uninstall command for a program: silent where the program supports it.
function Get-UninstallCommand($Program, [bool]$PreferSilent) {
    if ($PreferSilent -and $Program.Quiet) {
        $c = Split-CommandLine $Program.Quiet
        $c.Silent = $true
        return $c
    }
    if ($Program.ProductCode) {
        if ($PreferSilent) { return @{ File = 'msiexec.exe'; Args = "/x $($Program.ProductCode) /qn /norestart"; Silent = $true } }
        return @{ File = 'msiexec.exe'; Args = "/x $($Program.ProductCode) /norestart"; Silent = $false }
    }
    if ($Program.Uninstall) {
        $c = Split-CommandLine $Program.Uninstall
        $c.Silent = $false
        if ($PreferSilent -and $c.File -match '(?i)(^|\\)unins\d{3}\.exe$') {
            # Inno Setup uninstaller
            $c.Args = ("$($c.Args) /VERYSILENT /SUPPRESSMSGBOXES /NORESTART").Trim()
            $c.Silent = $true
        }
        return $c
    }
    if ($Program.Quiet) {
        $c = Split-CommandLine $Program.Quiet
        $c.Silent = $true
        return $c
    }
    return $null
}

function Uninstall-Win32($Program, [bool]$PreferSilent) {
    $cmd = Get-UninstallCommand $Program $PreferSilent
    if (-not $cmd) { throw 'No uninstall command is registered for this program.' }
    $file = [Environment]::ExpandEnvironmentVariables($cmd.File)
    if ($file -match '\\' -and -not (Test-Path -LiteralPath $file)) {
        throw "The uninstaller is missing ($file). The program may already be gone and only its entry is left."
    }
    if ($cmd.Silent) { Write-Log "    running silently: $file $($cmd.Args)" }
    else { Write-Log "    opening the program's own uninstaller; finish it in its window: $file $($cmd.Args)" }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Tracked $file $cmd.Args $cmd.Silent
    $limit = 60
    if ($cmd.Silent) { $limit = 30 }
    $exited = Wait-Tracked $proc $limit
    $code = $null
    if ($exited) { $code = $proc.ExitCode }

    # Some uninstallers hand over to a copy of themselves and exit at once; give those time to finish.
    $grace = 5
    if ($exited -and $sw.Elapsed.TotalSeconds -lt 15) { $grace = 120 }
    $wait = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-RegKey $Program.Key) -and $wait.Elapsed.TotalSeconds -lt $grace) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 500
    }

    $gone = -not (Test-RegKey $Program.Key)
    $reboot = ($code -eq 3010 -or $code -eq 1641)
    if ($gone) {
        $msg = 'uninstalled'
        if ($reboot) { $msg += ' (restart the PC to finish)' }
    } elseif (-not $exited) {
        $msg = "the uninstaller is still running after $limit minutes; check its window"
    } elseif ($code -eq 1602) {
        $msg = 'cancelled in the uninstaller'
    } else {
        $msg = "still installed (exit code $code). The uninstaller may have been cancelled, failed, or need a restart."
    }
    return @{ Gone = $gone; Reboot = $reboot; Message = $msg }
}

# =============================================================================
#  Leftovers (files, registry keys, services and tasks an uninstaller leaves)
# =============================================================================
$ServicePathCache = $null
$TaskPathCache    = $null

function Convert-RegExePath([string]$Path) {
    $Path -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU' -replace '^HKCR:', 'HKCR' -replace '^HKU:', 'HKU'
}

function Export-RegKeyBackup([string]$Path, [string]$File) {
    $out = & reg.exe export (Convert-RegExePath $Path) $File /y 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('reg export: ' + (($out | Out-String).Trim())) }
}

function Import-RegFileBackup([string]$File) {
    $out = & reg.exe import $File 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('reg import: ' + (($out | Out-String).Trim())) }
}

function Remove-RegTree([string]$Path) {
    $hive, $sub = Split-RegPath $Path
    $base = Open-RegBase $hive
    try { $base.DeleteSubKeyTree($sub, $false) } finally { $base.Close() }
}

# Refuses drive roots, Windows, and the bare Program Files / AppData / ProgramData roots;
# a folder must sit at least one level under one of those bases to be touchable.
function Test-SafeFolder([string]$Path) {
    if (-not $Path) { return $false }
    try { $full = ([IO.Path]::GetFullPath($Path)).TrimEnd('\') } catch { return $false }
    if ($full.Length -lt 4 -or $full -match '^[A-Za-z]:\\?$') { return $false }
    $win = ($env:SystemRoot + '').TrimEnd('\')
    $roots = @($win, "$win\System32", "$win\SysWOW64",
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE, $env:PUBLIC,
        $env:APPDATA, $env:LOCALAPPDATA, "$env:LOCALAPPDATA\Programs") |
        Where-Object { $_ } | ForEach-Object { ($_ + '').TrimEnd('\') }
    foreach ($r in $roots) { if ($full -ieq $r) { return $false } }
    if ($win -and $full -like "$win\*") { return $false }
    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA) |
        Where-Object { $_ } | ForEach-Object { ($_ + '').TrimEnd('\') }
    foreach ($b in $bases) { if ($full -like "$b\*") { return $true } }
    return $false
}

# Turns a publisher or product name into a plausible folder name, or '' if it is too generic to match on.
function Get-SafeNameFragment([string]$Text) {
    $t = ($Text + '').Trim()
    if (-not $t) { return '' }
    $t = $t -replace '\s*\(.*?\)\s*', ' '
    $t = $t -replace '(?i)\s+(x64|x86|64-bit|32-bit|amd64)\b.*$', ''
    $t = $t -replace '\s+\d+(\.\d+)+.*$', ''
    $t = $t.Trim()
    if ($t.Length -lt 3 -or $t -match '[\\/:*?"<>|]') { return '' }
    if ($t -in @('Microsoft', 'Common Files', 'Common', 'Windows', 'Temp', 'Application', 'Programs')) { return '' }
    return $t
}

function Get-LeftoverServiceCache {
    if ($null -eq $script:ServicePathCache) {
        $r = Invoke-InBackground {
            Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; PathName = $_.PathName }
            }
        }
        $script:ServicePathCache = @(foreach ($s in $r.Output) {
            $pn = ($s.PathName + '').Trim(); $exe = $pn
            if ($pn.StartsWith('"')) { $e = $pn.IndexOf('"', 1); if ($e -gt 1) { $exe = $pn.Substring(1, $e - 1) } }
            elseif ($pn -match '(?i)^(.+?\.exe)\b') { $exe = $Matches[1] }
            [pscustomobject]@{ Name = $s.Name; Path = [Environment]::ExpandEnvironmentVariables($exe) }
        })
    }
    return $script:ServicePathCache
}

function Get-LeftoverTaskCache {
    if ($null -eq $script:TaskPathCache) {
        $script:TaskPathCache = @(Get-ThirdPartyTasks | ForEach-Object {
            [pscustomobject]@{ Full = "$($_.Path)$($_.Name)"; Exec = [Environment]::ExpandEnvironmentVariables(($_.Exec + '')) }
        })
    }
    return $script:TaskPathCache
}

function Reset-LeftoverCaches { $script:ServicePathCache = $null; $script:TaskPathCache = $null }

function Test-PathInsideAny([string]$Path, [string[]]$Folders) {
    if (-not $Path) { return $false }
    foreach ($f in $Folders) { if ($Path.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true } }
    return $false
}

# Finds what an uninstalled program left behind. Run AFTER the uninstaller, so the install folder here is a genuine leftover.
function Get-ProgramLeftovers($Program) {
    $found = New-Object System.Collections.ArrayList
    $folders = New-Object System.Collections.ArrayList

    if ((Test-SafeFolder $Program.InstallLocation) -and (Test-Path -LiteralPath $Program.InstallLocation)) {
        [void]$folders.Add(([IO.Path]::GetFullPath($Program.InstallLocation)).TrimEnd('\'))
    }
    if ($Program.Uninstall) {
        $uf = [Environment]::ExpandEnvironmentVariables((Split-CommandLine $Program.Uninstall).File)
        if ($uf -match '\\') {
            $d = Split-Path $uf -Parent
            if ((Test-SafeFolder $d) -and (Test-Path -LiteralPath $d)) { [void]$folders.Add(([IO.Path]::GetFullPath($d)).TrimEnd('\')) }
        }
    }
    foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA, $env:ProgramData)) {
        foreach ($frag in @((Get-SafeNameFragment $Program.Publisher), (Get-SafeNameFragment $Program.Name))) {
            if (-not $frag) { continue }
            $cand = Join-Path $base $frag
            if ((Test-SafeFolder $cand) -and (Test-Path -LiteralPath $cand)) { [void]$folders.Add(([IO.Path]::GetFullPath($cand)).TrimEnd('\')) }
        }
    }

    $kept = New-Object System.Collections.ArrayList
    foreach ($f in ($folders | Sort-Object -Unique)) {
        $inside = $false
        foreach ($g in $kept) { if ($f -ieq $g -or $f -like "$g\*") { $inside = $true; break } }
        if (-not $inside) { [void]$kept.Add($f); [void]$found.Add(@{ Kind = 'File'; Path = $f; Display = "Folder: $f" }) }
    }

    foreach ($soft in @('HKCU:\Software', 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node')) {
        foreach ($frag in @($Program.Publisher, $Program.Name)) {
            $fr = ($frag + '').Trim()
            if (-not $fr -or $fr -match '[\\/]' -or $fr.Length -lt 3) { continue }
            if ((Get-SafeNameFragment $fr) -eq '') { continue }
            $cand = "$soft\$fr"
            if (Test-RegKey $cand) { [void]$found.Add(@{ Kind = 'RegKey'; Path = $cand; Display = "Registry: $(Convert-RegExePath $cand)" }) }
        }
    }

    if ($kept.Count) {
        foreach ($svc in (Get-LeftoverServiceCache)) {
            if (Test-PathInsideAny $svc.Path $kept) {
                [void]$found.Add(@{ Kind = 'Service'; Path = $svc.Name; RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"; Display = "Service: $($svc.Name)" })
            }
        }
        foreach ($tk in (Get-LeftoverTaskCache)) {
            if (Test-PathInsideAny $tk.Exec $kept) { [void]$found.Add(@{ Kind = 'Task'; Path = $tk.Full; Display = "Scheduled task: $($tk.Full)" }) }
        }
    }
    return $found
}

# Removes leftovers reversibly: files to quarantine, registry keys and services to .reg backups, tasks to .xml.
function Remove-Leftovers($Items, [string]$Stamp) {
    $qdir = Join-Path $script:QuarantineDir $Stamp
    $rdir = Join-Path $script:RegBackupDir $Stamp
    $n = 0
    foreach ($item in $Items) {
        try {
            switch ($item.Kind) {
                'File' {
                    if (-not (Test-Path -LiteralPath $item.Path) -or -not (Test-SafeFolder $item.Path)) { continue }
                    if (-not (Test-Path $qdir)) { New-Item -ItemType Directory -Path $qdir -Force | Out-Null }
                    $dest = Join-Path $qdir ('{0:D3}_{1}' -f $n, (Split-Path $item.Path -Leaf))
                    Move-Item -LiteralPath $item.Path -Destination $dest -Force -ErrorAction Stop
                    Add-RunRecord @{ Kind = 'Quarantine'; From = $item.Path; To = $dest }
                    Write-Log "    quarantined $($item.Path)"; $n++
                }
                'RegKey' {
                    if (-not (Test-RegKey $item.Path)) { continue }
                    if (-not (Test-Path $rdir)) { New-Item -ItemType Directory -Path $rdir -Force | Out-Null }
                    $bak = Join-Path $rdir ('{0:D3}.reg' -f $n)
                    Export-RegKeyBackup $item.Path $bak
                    Remove-RegTree $item.Path
                    Add-RunRecord @{ Kind = 'RegKeyDelete'; Path = $item.Path; Backup = $bak }
                    Write-Log "    removed registry key $(Convert-RegExePath $item.Path)"; $n++
                }
                'Service' {
                    if (-not (Test-RegKey $item.RegPath)) { continue }
                    if (-not (Test-Path $rdir)) { New-Item -ItemType Directory -Path $rdir -Force | Out-Null }
                    $bak = Join-Path $rdir ('{0:D3}_svc.reg' -f $n)
                    Export-RegKeyBackup $item.RegPath $bak
                    Stop-Service -Name $item.Path -Force -ErrorAction SilentlyContinue
                    $null = & sc.exe delete $item.Path 2>&1
                    Add-RunRecord @{ Kind = 'RegKeyDelete'; Path = $item.RegPath; Backup = $bak; Service = $item.Path }
                    Write-Log "    deleted service $($item.Path)"; $n++
                }
                'Task' {
                    $tp, $tn = Split-TaskPath $item.Path
                    $xml = (Invoke-InBackground { param($p, $n2) Get-ScheduledTask -TaskPath $p -TaskName $n2 -ErrorAction Stop | Export-ScheduledTask } @($tp, $tn)).Output | Select-Object -Last 1
                    if ($xml) {
                        if (-not (Test-Path $rdir)) { New-Item -ItemType Directory -Path $rdir -Force | Out-Null }
                        $bak = Join-Path $rdir ('{0:D3}_task.xml' -f $n)
                        Set-Content -Path $bak -Value $xml -Encoding Unicode
                        [void](Invoke-InBackground { param($p, $n2) Unregister-ScheduledTask -TaskPath $p -TaskName $n2 -Confirm:$false -ErrorAction Stop } @($tp, $tn))
                        Add-RunRecord @{ Kind = 'TaskDelete'; Path = $item.Path; Backup = $bak }
                        Write-Log "    deleted scheduled task $($item.Path)"; $n++
                    }
                }
            }
        } catch { Write-Log "    FAILED to remove $($item.Path): $($_.Exception.Message)" }
    }
    return $n
}

# =============================================================================
#  Python packages
# =============================================================================
# pip itself and its install helpers - never offered for removal (removing them breaks pip).
$PyCorePackages = @('pip', 'setuptools', 'wheel', 'pkg-resources', 'pip-tools')

# Every Python interpreter the tool can find: py launcher, PATH, registry and the usual folders.
function Get-PythonEnvs {
    $cands = New-Object System.Collections.Generic.List[string]
    try {
        if (Get-Command py.exe -ErrorAction SilentlyContinue) {
            foreach ($line in @(& py.exe -0p 2>$null)) {
                if ("$line" -match '([A-Za-z]:\\[^\r\n*]+?python\.exe)') { $cands.Add($Matches[1].Trim()) }
            }
        }
    } catch { }
    foreach ($c in @(Get-Command python.exe -All -ErrorAction SilentlyContinue)) { if ($c.Source) { $cands.Add($c.Source) } }
    foreach ($root in @('HKLM:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore', 'HKCU:\Software\Python\PythonCore')) {
        foreach ($ver in @(Get-RegSubKeyNames $root)) {
            $ip = Get-RegState "$root\$ver\InstallPath" ''
            if ($ip.Exists -and $ip.Value) { $cands.Add((Join-Path ([string]$ip.Value) 'python.exe')) }
        }
    }
    foreach ($b in @("$env:LOCALAPPDATA\Programs\Python", $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($b -and (Test-Path -LiteralPath $b)) {
            foreach ($d in @(Get-ChildItem -LiteralPath $b -Directory -Filter 'Python*' -ErrorAction SilentlyContinue)) {
                $p = Join-Path $d.FullName 'python.exe'; if (Test-Path -LiteralPath $p) { $cands.Add($p) }
            }
        }
    }
    $envs = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($p in $cands) {
        if (-not $p) { continue }
        try { $full = (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path } catch { continue }
        $key = $full.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $ver = ''
        try { $ver = (Invoke-InBackground { param($e) & $e --version 2>&1 } @($full)).Output | Select-Object -Last 1 } catch { }
        [void]$envs.Add(@{ Exe = $full; Version = (("$ver") -replace 'Python\s*', '').Trim() })
    }
    return $envs
}

function Get-PythonPackages([string]$Exe) {
    $pkgs = @()
    try {
        $r = Invoke-InBackground { param($e) & $e -m pip list --format=freeze --disable-pip-version-check 2>$null } @($Exe)
        foreach ($line in $r.Output) {
            if ("$line" -match '^([A-Za-z0-9][A-Za-z0-9._-]*)==(.+)$') { $pkgs += @{ Name = $Matches[1]; Version = $Matches[2].Trim() } }
        }
    } catch { }
    return $pkgs
}

# =============================================================================
#  Startup items
# =============================================================================
$ApprovedBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$StoreStartupRoot = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'

function New-StartupTag([string]$Display, [string]$Group, [string]$Status, [string]$Desc, [bool]$Off, [object[]]$Actions) {
    @{
        Type = 'Tweak'; Tab = 'Startup'; Group = $Group; Name = "Startup: $Display"; Display = $Display
        StatusText = $Status; Desc = $Desc; Skip = $Off; Actions = $Actions
    }
}

function Get-StartupEntries([object[]]$ThirdPartyTasks) {
    $out = New-Object System.Collections.ArrayList
    $sources = @(
        @{ Kind = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKCU:\$ApprovedBase\Run"; Scope = 'current user' },
        @{ Kind = 'Reg'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$ApprovedBase\Run"; Scope = 'all users' },
        @{ Kind = 'Reg'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$ApprovedBase\Run32"; Scope = 'all users, 32-bit' },
        @{ Kind = 'Folder'; Path = [Environment]::GetFolderPath('Startup'); Approved = "HKCU:\$ApprovedBase\StartupFolder"; Scope = 'your Startup folder' },
        @{ Kind = 'Folder'; Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$ApprovedBase\StartupFolder"; Scope = 'all users Startup folder' }
    )
    foreach ($src in $sources) {
        $items = @()
        try {
            if ($src.Kind -eq 'Reg') {
                $vals = Get-RegValues $src.Path
                foreach ($n in $vals.Keys) { if ($n) { $items += @{ Name = $n; Command = [string]$vals[$n] } } }
            } elseif ($src.Path -and (Test-Path -LiteralPath $src.Path)) {
                foreach ($f in Get-ChildItem -LiteralPath $src.Path -File -Force -ErrorAction SilentlyContinue) {
                    if ($f.Name -ne 'desktop.ini') { $items += @{ Name = $f.Name; Command = $f.FullName } }
                }
            }
        } catch { }
        foreach ($i in $items) {
            $off = $false
            try {
                $st = Get-RegState $src.Approved $i.Name
                $off = $st.Exists -and ($st.Value -is [byte[]]) -and $st.Value.Length -gt 0 -and (($st.Value[0] -band 1) -eq 1)
            } catch { }
            if ($off) { $grp = 'Disabled'; $status = 'Disabled' } else { $grp = 'Optional'; $status = 'Enabled' }
            $act = RegVal $src.Approved $i.Name $script:StartupOffBytes 'Binary'
            [void]$out.Add((New-StartupTag $i.Name $grp $status "$($i.Command)   ($($src.Scope))" $off @($act)))
        }
    }

    # Store app startup tasks
    foreach ($fam in @(Get-RegSubKeyNames $StoreStartupRoot)) {
        try {
            foreach ($task in @(Get-RegSubKeyNames "$StoreStartupRoot\$fam")) {
                $path = "$StoreStartupRoot\$fam\$task"
                $st = Get-RegState $path 'State'
                if (-not $st.Exists -or $st.Kind -ne 'DWord' -or [int]$st.Value -gt 4) { continue }
                $on = ([int]$st.Value -eq 2 -or [int]$st.Value -eq 4)
                if ($on) { $grp = 'Optional'; $status = 'Enabled' } else { $grp = 'Disabled'; $status = 'Disabled' }
                $display = ($fam -split '_')[0] + ' (Store app)'
                $act = RegVal $path 'State' 1
                [void]$out.Add((New-StartupTag $display $grp $status "Store app startup task $task" (-not $on) @($act)))
            }
        } catch { }
    }

    # Third-party scheduled tasks (updaters and background jobs)
    foreach ($t in $ThirdPartyTasks) {
        $full = "$($t.Path)$($t.Name)"
        $off = ($t.State -eq 'Disabled')
        if ($off) { $grp = 'Disabled' } else { $grp = 'Tasks' }
        $desc = "Scheduled task $full. Runs: $($t.Exec)"
        if ($t.Name -like 'MicrosoftEdgeUpdate*') { $desc = "Also keeps WebView2 updated; leave it on even if you remove Edge. $desc" }
        [void]$out.Add((New-StartupTag "Task: $($t.Name)" $grp $t.State $desc $off @(TaskOff $full)))
    }
    return $out
}

function Get-ThirdPartyTasks {
    $r = Invoke-InBackground {
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
            [pscustomobject]@{
                Path  = $_.TaskPath; Name = $_.TaskName; State = [string]$_.State
                Exec  = (@($_.Actions | ForEach-Object { $_.Execute } | Where-Object { $_ }) -join '; ')
            }
        }
    }
    return $r.Output
}

# =============================================================================
#  Windows features
# =============================================================================
$EnabledFeatures = @()
$InstalledCaps   = @()

function Update-FeatureCache {
    $r = Invoke-InBackground {
        $f = @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
               Where-Object { [string]$_.State -eq 'Enabled' } | ForEach-Object { $_.FeatureName })
        $c = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
               Where-Object { [string]$_.State -eq 'Installed' } | ForEach-Object { $_.Name })
        [pscustomobject]@{ Features = $f; Capabilities = $c }
    }
    $res = $r.Output | Select-Object -First 1
    $script:EnabledFeatures = @($res.Features | Where-Object { $_ })
    $script:InstalledCaps   = @($res.Capabilities | Where-Object { $_ })
}

# =============================================================================
#  OneDrive
# =============================================================================
function Get-OneDriveExe {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')
    )
    if (${env:ProgramFiles(x86)}) { $paths += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe') }
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    return $null
}

function Find-OneDriveSetup {
    $c = @()
    $c += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\*\OneDriveSetup.exe') -ErrorAction SilentlyContinue)
    $c += @(Get-ChildItem (Join-Path $env:ProgramFiles 'Microsoft OneDrive\*\OneDriveSetup.exe') -ErrorAction SilentlyContinue)
    if (${env:ProgramFiles(x86)}) {
        $c += @(Get-ChildItem (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\*\OneDriveSetup.exe') -ErrorAction SilentlyContinue)
    }
    foreach ($p in @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")) {
        if (Test-Path $p) { $c += Get-Item $p }
    }
    return ($c | Where-Object { $_ } | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Uninstall-OneDrive {
    $exe = Get-OneDriveExe
    $setup = Find-OneDriveSetup
    if (-not $setup) { throw 'Could not find OneDriveSetup.exe.' }
    $odArgs = '/uninstall'
    if ($exe -and $exe -like "$env:ProgramFiles*") { $odArgs = '/uninstall /allusers' }
    Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $proc = Start-Tracked $setup.FullName $odArgs $false
    if (-not (Wait-Tracked $proc 5)) { return 'the uninstaller is still running and will finish on its own' }
    return "uninstaller finished with exit code $($proc.ExitCode)"
}

# =============================================================================
#  Microsoft Edge
# =============================================================================
function Get-EdgeInstalls {
    $roots = @()
    if (${env:ProgramFiles(x86)}) { $roots += @{ Dir = (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'); System = $true } }
    $roots += @{ Dir = (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application'); System = $true }
    $roots += @{ Dir = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application'); System = $false }
    foreach ($root in $roots) {
        $exe = Join-Path $root.Dir 'msedge.exe'
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        $setup = Get-ChildItem (Join-Path $root.Dir '*\Installer\setup.exe') -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $ver = ''
        try { $ver = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion } catch { }
        @{ Exe = $exe; Setup = $setup; System = $root.System; Version = $ver }
    }
}

# Browsers registered with Windows, other than Edge and Internet Explorer.
function Get-OtherBrowsers {
    $names = @()
    foreach ($p in @('HKLM:\SOFTWARE\Clients\StartMenuInternet', 'HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet',
                     'HKCU:\Software\Clients\StartMenuInternet')) {
        foreach ($k in @(Get-RegSubKeyNames $p)) {
            if ($k -like 'Microsoft Edge*' -or $k -like '*MSEdge*' -or $k -eq 'IEXPLORE.EXE') { continue }
            $display = $k
            try { $st = Get-RegState "$p\$k" ''; if ($st.Exists -and $st.Value) { $display = [string]$st.Value } } catch { }
            $names += $display
        }
    }
    return ($names | Select-Object -Unique)
}

function Remove-Edge([bool]$DeleteProfile) {
    $installs = @(Get-EdgeInstalls)
    if ($installs.Count -eq 0) { Write-Log '    Edge is not installed.'; return $true }

    # 1. Allow the official uninstaller to run (recorded, Undo removes it).
    foreach ($a in $script:EdgeAllowActions) { Invoke-LoggedAction $a }

    # 2. The uninstaller refuses outside the EEA unless the legacy Edge stub exists. Create an empty one for the run.
    $legacyDir = Join-Path $env:SystemRoot 'SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe'
    $stub = Join-Path $legacyDir 'MicrosoftEdge.exe'
    $madeStub = $false
    $madeDir = $false
    if (-not (Test-Path -LiteralPath $stub)) {
        try {
            if (-not (Test-Path -LiteralPath $legacyDir)) {
                New-Item -ItemType Directory -Path $legacyDir -Force -ErrorAction Stop | Out-Null
                $madeDir = $true
            }
            New-Item -ItemType File -Path $stub -Force -ErrorAction Stop | Out-Null
            $madeStub = $true
        } catch { Write-Log "    note: could not create the unlock file ($($_.Exception.Message)); trying anyway" }
    }

    # 3. Run Edge's own uninstaller.
    Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($i in $installs) {
        if (-not $i.Setup) { Write-Log "    no uninstaller found next to $($i.Exe)"; continue }
        $edgeArgs = '--uninstall --force-uninstall --verbose-logging'
        if ($i.System) { $edgeArgs += ' --system-level' }
        if ($DeleteProfile) { $edgeArgs += ' --delete-profile' }
        Write-Log "    running $($i.Setup.FullName) $edgeArgs"
        try {
            $proc = Start-Tracked $i.Setup.FullName $edgeArgs $true
            if (Wait-Tracked $proc 10) { Write-Log "    uninstaller exit code $($proc.ExitCode)" }
            else { Write-Log '    the uninstaller is still running after 10 minutes' }
        } catch { Write-Log "    FAILED to start the uninstaller: $($_.Exception.Message)" }
    }
    if ($madeStub) { Remove-Item -LiteralPath $stub -Force -ErrorAction SilentlyContinue }
    if ($madeDir -and -not (Get-ChildItem -LiteralPath $legacyDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $legacyDir -Force -ErrorAction SilentlyContinue
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (@(Get-EdgeInstalls).Count -gt 0 -and $sw.Elapsed.TotalSeconds -lt 30) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 500
    }
    if (@(Get-EdgeInstalls).Count -gt 0) {
        Write-Log '    Edge is still installed. Microsoft blocked the uninstaller on this Windows build.'
        Write-Log '    Only the uninstall permission was changed; "Undo a previous run" removes it.'
        return $false
    }
    Write-Log '    Edge browser removed.'

    # 4. Leftovers: the Store registration and shortcuts.
    $stubApp = @{ Name = 'Edge Store registration'; Patterns = @('Microsoft.MicrosoftEdge.Stable') }
    if ((Get-AppMatches $stubApp).Installed.Count -gt 0) { [void](Remove-AppEntry $stubApp) }
    $links = @(
        (Join-Path $env:PUBLIC 'Desktop\Microsoft Edge.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Microsoft Edge.lnk'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk')
    )
    foreach ($l in $links) {
        if (Test-Path -LiteralPath $l) { Remove-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue; Write-Log "    removed shortcut $l" }
    }

    # 5. Tell Edge Update not to put it back (recorded, Undo removes it). WebView2 updates are untouched.
    foreach ($a in $script:EdgeBlockActions) { Invoke-LoggedAction $a }
    return $true
}

# =============================================================================
#  Clean-up
# =============================================================================
function Get-TempPaths {
    @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) -and ((Split-Path $_ -Leaf) -match '^(Temp|Tmp)$') } |
        ForEach-Object { [IO.Path]::GetFullPath($_) } | Select-Object -Unique
}

# Shared by the clean-up scripts: lists files or folders without following junctions or symbolic links.
$FileWalker = @'
function Get-PlainItems([string]$Root, [switch]$Dirs) {
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($i in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue) {
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($i.PSIsContainer) { $stack.Push($i.FullName); if ($Dirs) { $i } }
            elseif (-not $Dirs) { $i }
        }
    }
}
function Get-PlainFiles([string]$Root) { Get-PlainItems $Root }
'@

# Runs a clean-up script with the file walker available. $ParamLine must come first in a script.
function Invoke-WithWalker([string]$ParamLine, [string]$Body, [object[]]$Arguments) {
    $text = $ParamLine + "`n" + $script:FileWalker + "`n" + $Body
    Invoke-InBackground ([scriptblock]::Create($text)) $Arguments
}

function Get-CleanupSizes {
    $body = @'
$cut = (Get-Date).AddDays(-1)
$t = 0
foreach ($p in $TempPaths) { foreach ($f in Get-PlainFiles $p) { if ($f.LastWriteTime -lt $cut) { $t += $f.Length } } }
$w = 0
if (Test-Path -LiteralPath $WuPath) { foreach ($f in Get-PlainFiles $WuPath) { $w += $f.Length } }
[pscustomobject]@{ Temp = $t; WU = $w }
'@
    $argv = @($null, (Join-Path $env:SystemRoot 'SoftwareDistribution\Download'))
    $argv[0] = [object[]]@(Get-TempPaths)
    $r = Invoke-WithWalker 'param($TempPaths, $WuPath)' $body $argv
    return ($r.Output | Select-Object -First 1)
}

function Invoke-Cleanup($Item) {
    switch ($Item.Id) {
        'Temp' {
            $body = @'
$cut = (Get-Date).AddDays(-1)
$freed = 0
foreach ($p in $TempPaths) {
    # Old folders are noted before any file is deleted, because deleting files updates a folder's date.
    $oldDirs = @(Get-PlainItems $p -Dirs | Where-Object { $_.LastWriteTime -lt $cut } | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($f in Get-PlainFiles $p) {
        if ($f.LastWriteTime -lt $cut) {
            try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len } catch { }
        }
    }
    # Remove old folders that are now empty, deepest first. Junctions are never entered or removed.
    foreach ($d in $oldDirs) {
        if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}
$freed
'@
            $argv = @($null)
            $argv[0] = [object[]]@(Get-TempPaths)
            $r = Invoke-WithWalker 'param($TempPaths)' $body $argv
            return "freed $(Format-Size ([double]($r.Output | Select-Object -Last 1)))"
        }
        'WUCache' {
            $body = @'
$svcs = @('wuauserv', 'bits')
$was = @{}
foreach ($s in $svcs) { $was[$s] = ((Get-Service -Name $s -ErrorAction SilentlyContinue).Status -eq 'Running') }
Stop-Service -Name $svcs -Force -ErrorAction SilentlyContinue
$before = 0; foreach ($f in Get-PlainFiles $Dl) { $before += $f.Length }
Get-ChildItem -LiteralPath $Dl -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$after = 0; foreach ($f in Get-PlainFiles $Dl) { $after += $f.Length }
foreach ($s in $svcs) { if ($was[$s]) { Start-Service -Name $s -ErrorAction SilentlyContinue } }
$before - $after
'@
            $r = Invoke-WithWalker 'param($Dl)' $body @((Join-Path $env:SystemRoot 'SoftwareDistribution\Download'))
            return "freed $(Format-Size ([double]($r.Output | Select-Object -Last 1)))"
        }
        'DOCache' {
            [void](Invoke-InBackground {
                if (-not (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) {
                    throw 'This version of Windows has no Delivery Optimization clean-up command.'
                }
                Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
            })
            return 'cache cleared'
        }
        'DISM' {
            $r = Invoke-InBackground {
                $out = & dism.exe /Online /Cleanup-Image /StartComponentCleanup /English 2>&1
                if ($LASTEXITCODE -ne 0) { throw ("DISM failed with exit code $LASTEXITCODE. " + (($out | Select-Object -Last 3) -join ' ')) }
                'component store cleaned'
            }
            return ($r.Output | Select-Object -Last 1)
        }
    }
}

# =============================================================================
#  Logging, restore point, backups
# =============================================================================
function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
        $script:LogBox.AppendText($line + "`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
    try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 } catch { }
}

function Show-Message([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    return [System.Windows.Forms.MessageBox]::Show($script:Form, $Text, "$script:ToolName - Windows debloater",
        [System.Windows.Forms.MessageBoxButtons]$Buttons, [System.Windows.Forms.MessageBoxIcon]$Icon)
}

function New-RestorePoint {
    $desc = "Before $ToolName " + (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $freqKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqName = 'SystemRestorePointCreationFrequency'
    while ($true) {
        Write-Log 'Creating a System Restore point. This can take a minute...'
        $ok = $false; $err = ''
        $old = Get-RegState $freqKey $freqName
        try {
            # Windows normally allows one restore point per 24 hours; lift that for this one.
            Set-RegValue $freqKey $freqName 'DWord' 0
            $r = Invoke-InBackground {
                param($d)
                Checkpoint-Computer -Description $d -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                [bool](Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq $d })
            } @($desc)
            $last = $r.Output | Select-Object -Last 1
            $ok = ("$last" -eq 'True')
            if (-not $ok) { $err = 'Windows did not record the restore point.' }
        } catch {
            $err = $_.Exception.Message
        } finally {
            try {
                if ($old.Exists) { Set-RegValue $freqKey $freqName $old.Kind $old.Value }
                else { Remove-RegValue $freqKey $freqName }
            } catch { }
        }
        if ($ok) { Write-Log "Restore point created: $desc"; return $true }

        Write-Log "Restore point failed: $err"
        $q = "Could not create a restore point.`n`n$err`n`nSystem Restore may be turned off on this PC.`n`n" +
             "Yes: turn System Restore on for drive $env:SystemDrive and try again`n" +
             "No: continue without a restore point`n" +
             "Cancel: stop here and change nothing"
        $ans = Show-Message $q 'YesNoCancel' 'Warning'
        if ($ans -eq 'Yes') {
            try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop; Write-Log "System Restore turned on for $env:SystemDrive." }
            catch { Write-Log "Could not turn on System Restore: $($_.Exception.Message)" }
        } elseif ($ans -eq 'No') {
            Write-Log 'Continuing without a restore point.'
            return $true
        } else {
            return $false
        }
    }
}

function New-RunBackup {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:RunStamp = $stamp
    $script:Run = [ordered]@{
        Tool     = $ToolName
        Version  = $ToolVersion
        Created  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Computer = $env:COMPUTERNAME
        User     = "$env:USERDOMAIN\$env:USERNAME"
        Changes  = (New-Object System.Collections.ArrayList)
    }
    $script:RunFile = Join-Path $BackupDir "run-$stamp.json"
    Reset-LeftoverCaches
}

function Add-RunRecord($Record) {
    [void]$script:Run.Changes.Add($Record)
    $script:Run | ConvertTo-Json -Depth 8 | Set-Content -Path $script:RunFile -Encoding UTF8
}

# Applies one action if needed, records it for Undo and logs the result.
function Invoke-LoggedAction($a) {
    $p = Get-ActionPlan $a
    if ($p.Missing) { Write-Log "    $($p.Label): not on this PC, skipped"; return }
    if ($p.Done)    { Write-Log "    $($p.Label): already $($p.Target)"; return }
    try {
        Add-RunRecord (Invoke-Action $a)
        Write-Log "    $($p.Label): $($p.Current) -> $($p.Target)"
        $script:Stats.Changed++
    } catch {
        Write-Log "    FAILED $($p.Label): $($_.Exception.Message)"
        $script:Stats.Failed++
    }
}

function Request-Restart([bool]$Reboot) {
    $q = 'Done. Some changes only show up after File Explorer restarts.'
    if ($Reboot) { $q += "`n`nRestart the PC when you can: some Windows features, services, policies or uninstallers only finish after a restart." }
    $q += "`n`nRestart File Explorer now? Open File Explorer windows will close."
    if ((Show-Message $q 'YesNo' 'Question') -ne 'Yes') { return }
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { Write-Log 'File Explorer restarted.'; return }
    }
    Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe')
    Write-Log 'File Explorer restarted.'
}

# =============================================================================
#  Window
# =============================================================================
$g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$Scale = $g.DpiX / 96.0
$g.Dispose()
function Px([double]$v) { [int][Math]::Round($v * $script:Scale) }

$Busy = $false
$Populating = $false
$Stats = @{ Changed = 0; Removed = 0; Failed = 0; Reboot = $false }

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "$ToolName $ToolVersion"
$Form.StartPosition = 'CenterScreen'
$Form.AutoScaleMode = 'None'
$Form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$Form.ClientSize = New-Object System.Drawing.Size(
    [Math]::Min((Px 1100), $work.Width - 40), [Math]::Min((Px 780), $work.Height - 60))
$Form.MinimumSize = New-Object System.Drawing.Size(
    [Math]::Min((Px 860), $work.Width - 20), [Math]::Min((Px 580), $work.Height - 20))

# Logo card (CyberX + SVPNPA in one seamless panel), embedded so the single file stays self-contained.
$LogoCard = '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'

function New-LogoPicture([string]$B64, [int]$DisplayHeight) {
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.SizeMode = 'Zoom'
    $pb.Height = $DisplayHeight
    $pb.Margin = New-Object System.Windows.Forms.Padding((Px 10), (Px 2), (Px 2), (Px 2))
    try {
        $bytes = [Convert]::FromBase64String($B64)
        $img = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream (, $bytes)))
        $pb.Image = $img
        $pb.Width = [int]($img.Width * $DisplayHeight / $img.Height)
    } catch { $pb.Width = 0 }
    return $pb
}

# Header: title and tagline on the left, the CyberX + SVPNPA logo card on the right.
$header = New-Object System.Windows.Forms.TableLayoutPanel
$header.Dock = 'Top'
$header.AutoSize = $true
$header.ColumnCount = 2
$header.RowCount = 1
[void]$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
[void]$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$header.Padding = New-Object System.Windows.Forms.Padding((Px 10), (Px 8), (Px 10), (Px 6))

$titleFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$titleFlow.FlowDirection = 'TopDown'
$titleFlow.WrapContents = $false
$titleFlow.AutoSize = $true
$titleFlow.Anchor = 'Left'
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = $ToolName
$lblTitle.AutoSize = $true
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.AutoSize = $true
$lblSub.ForeColor = [System.Drawing.SystemColors]::GrayText
$lblSub.Text = 'Debloat Windows 10 & 11 - apps, services, telemetry and bloat. Preview first; most changes can be undone.'
$titleFlow.Controls.AddRange([System.Windows.Forms.Control[]]@($lblTitle, $lblSub))

$logoFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$logoFlow.FlowDirection = 'LeftToRight'
$logoFlow.WrapContents = $false
$logoFlow.AutoSize = $true
$logoFlow.Anchor = 'Right'
$logoFlow.Controls.Add((New-LogoPicture $LogoCard (Px 50)))

$header.Controls.Add($titleFlow, 0, 0)
$header.Controls.Add($logoFlow, 1, 0)

# Filter row
$filterRow = New-Object System.Windows.Forms.FlowLayoutPanel
$filterRow.Dock = 'Top'
$filterRow.AutoSize = $true
$filterRow.WrapContents = $false
$filterRow.Padding = New-Object System.Windows.Forms.Padding(0, (Px 2), 0, (Px 4))
$lblFind = New-Object System.Windows.Forms.Label
$lblFind.Text = 'Find:'
$lblFind.AutoSize = $true
$lblFind.Margin = New-Object System.Windows.Forms.Padding((Px 2), (Px 6), (Px 4), 0)
$FilterBox = New-Object System.Windows.Forms.TextBox
$FilterBox.Width = (Px 300)
$lblFindHint = New-Object System.Windows.Forms.Label
$lblFindHint.Text = 'Filters every tab. Right-click a list to tick or untick everything shown.'
$lblFindHint.AutoSize = $true
$lblFindHint.ForeColor = [System.Drawing.SystemColors]::GrayText
$lblFindHint.Margin = New-Object System.Windows.Forms.Padding((Px 8), (Px 6), 0, 0)
$filterRow.Controls.AddRange([System.Windows.Forms.Control[]]@($lblFind, $FilterBox, $lblFindHint))

# Shared right-click menu for the lists
$ListMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miTickAll = $ListMenu.Items.Add('Tick all shown')
$miTickAll.Add_Click({ Invoke-Safely { Set-ShownChecks $script:ListMenu.SourceControl $true } })
$miUntickAll = $ListMenu.Items.Add('Untick all shown')
$miUntickAll.Add_Click({ Invoke-Safely { Set-ShownChecks $script:ListMenu.SourceControl $false } })

# Tabs
$Tabs = New-Object System.Windows.Forms.TabControl
$Tabs.Dock = 'Fill'
$Tabs.Multiline = $true

function Set-LastColumnWidth($lv) {
    if ($lv.Columns.Count -lt 3) { return }
    $w = $lv.ClientSize.Width - $lv.Columns[0].Width - $lv.Columns[1].Width - (Px 4)
    if ($w -gt (Px 120)) { $lv.Columns[2].Width = $w }
}

function New-ListTab([string]$Title, [string]$Intro, [string]$FirstColumn, $Groups) {
    $page = New-Object System.Windows.Forms.TabPage
    $page.Text = $Title
    $page.Padding = New-Object System.Windows.Forms.Padding((Px 6))
    $page.UseVisualStyleBackColor = $true

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.HeaderStyle = 'Nonclickable'
    $lv.ShowItemToolTips = $true
    $lv.Dock = 'Fill'
    $lv.ContextMenuStrip = $script:ListMenu
    $lv.Tag = New-Object System.Collections.ArrayList
    [void]$lv.Columns.Add($FirstColumn, (Px 300))
    [void]$lv.Columns.Add('Status', (Px 140))
    [void]$lv.Columns.Add('Details', (Px 500))
    foreach ($k in $Groups.Keys) { [void]$lv.Groups.Add($k, $Groups[$k]) }
    $lv.Add_Resize({ param($s, $e) Set-LastColumnWidth $s })
    $lv.Add_ItemChecked({ Update-SelectionCount })

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Intro
    $lbl.Dock = 'Top'
    $lbl.Height = (Px 26)
    $lbl.TextAlign = 'MiddleLeft'

    $page.Controls.Add($lv)
    $page.Controls.Add($lbl)
    $lv.BringToFront()
    [void]$script:Tabs.TabPages.Add($page)
    return $lv
}

$TweakGroups = [ordered]@{ Recommended = 'Recommended'; Optional = 'Optional - changes some people want and some do not' }

$LvApps = New-ListTab 'Built-in apps' `
    'Apps that came with Windows. Only apps found on this PC are listed. Hover over a row for details.' 'App' `
    ([ordered]@{ Recommended = 'Recommended'; Optional = 'Optional - you may use these; tick only what you do not need'
                 Advanced = 'Advanced - read the details before ticking' })
$LvStore = New-ListTab 'Store apps' `
    'Every Microsoft Store app on this PC, from Microsoft or anyone else. Nothing is ticked. The Store and core Windows parts are not listed.' 'Package' `
    ([ordered]@{ Optional = 'Removable apps'; System = 'Windows system apps - removing these can break things like opening photos or playing video' })
$LvPrograms = New-ListTab 'Desktop programs' `
    'Every program installed with its own installer, as in Settings > Apps. Nothing is ticked.' 'Program' `
    ([ordered]@{ Bloat = 'Bloatware - factory OEM utilities, trial antivirus, toolbars and bundled junk (safe to remove)'
                 Optional = 'Installed programs'
                 Runtime = 'Runtimes, drivers and components - other software may depend on these' })
$LvPython = New-ListTab 'Python packages' `
    'pip packages found in each Python on this PC. Nothing is ticked. pip, setuptools and wheel are not listed (they are needed).' 'Package' `
    ([ordered]@{ Packages = 'Installed pip packages (tick to uninstall)' })
$LvStartup = New-ListTab 'Startup' `
    'Programs that start when you sign in, Store app startup tasks and third-party scheduled tasks. Disabling keeps them installed.' 'Item' `
    ([ordered]@{ Optional = 'Starts when you sign in'; Tasks = 'Third-party scheduled tasks (updaters and background jobs)'; Disabled = 'Already disabled' })
$LvPrivacy = New-ListTab 'Privacy' 'Diagnostic data, advertising and activity tracking.' 'Setting' $TweakGroups
$LvStart = New-ListTab 'Start & taskbar' 'Suggestions, promotions and clutter in Start, the taskbar, lock screen and Settings.' 'Setting' $TweakGroups
$LvSystem = New-ListTab 'Explorer & system' 'File Explorer and general system behaviour.' 'Setting' $TweakGroups
$LvServices = New-ListTab 'Services' 'Background services, with each one''s live state. Only non-essential services are listed; disabling sets startup to Disabled (not removal) and Undo puts it back.' 'Service' `
    ([ordered]@{ Recommended = 'Safe to disable on almost any PC'
                 Optional = 'Needs care - affects printing, search, location or Xbox (shown only when the box below is ticked)' })
$LvFeatures = New-ListTab 'Windows features' 'Optional Windows components. Most need a restart to finish; Undo can add them back (some need internet).' 'Feature' $TweakGroups
$LvCleanup = New-ListTab 'Clean up' 'Frees disk space. Clean-ups cannot be undone.' 'Task' $TweakGroups
$TweakLists = [ordered]@{ Privacy = $LvPrivacy; Start = $LvStart; System = $LvSystem; Services = $LvServices }

# Log
$LogBox = New-Object System.Windows.Forms.TextBox
$LogBox.Multiline = $true
$LogBox.ReadOnly = $true
$LogBox.ScrollBars = 'Vertical'
$LogBox.MaxLength = [int]::MaxValue
$LogBox.Dock = 'Fill'
$LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$LogBox.BackColor = [System.Drawing.SystemColors]::Window
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Log'
$lblLog.Dock = 'Top'
$lblLog.Height = (Px 22)
$lblLog.TextAlign = 'BottomLeft'

$Split = New-Object System.Windows.Forms.SplitContainer
$Split.Orientation = 'Horizontal'
$Split.Dock = 'Fill'
$Split.Panel1.Padding = New-Object System.Windows.Forms.Padding((Px 8), 0, (Px 8), 0)
$Split.Panel2.Padding = New-Object System.Windows.Forms.Padding((Px 8), 0, (Px 8), 0)
$Split.Panel1.Controls.Add($Tabs)
$Split.Panel1.Controls.Add($filterRow)
$Tabs.BringToFront()
$Split.Panel2.Controls.Add($LogBox)
$Split.Panel2.Controls.Add($lblLog)
$LogBox.BringToFront()

# Buttons and options
$bar = New-Object System.Windows.Forms.FlowLayoutPanel
$bar.Dock = 'Bottom'
$bar.AutoSize = $true
$bar.AutoSizeMode = 'GrowAndShrink'
$bar.WrapContents = $true
$bar.Padding = New-Object System.Windows.Forms.Padding((Px 8), (Px 6), (Px 8), (Px 6))

function New-Button([string]$Text, [scriptblock]$OnClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.AutoSize = $true
    $b.AutoSizeMode = 'GrowAndShrink'
    $b.Padding = New-Object System.Windows.Forms.Padding((Px 8), (Px 3), (Px 8), (Px 3))
    $b.Add_Click($OnClick)
    $script:bar.Controls.Add($b)
    return $b
}

function New-Option([string]$Text, [bool]$Checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Checked = $Checked
    $c.AutoSize = $true
    $c.Margin = New-Object System.Windows.Forms.Padding((Px 10), (Px 8), (Px 6), (Px 3))
    $script:bar.Controls.Add($c)
    return $c
}

function Invoke-Safely([scriptblock]$Body) {
    try { & $Body }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        Set-Busy $false
    }
}

$btnRecommended = New-Button 'Select recommended' { Invoke-Safely { Select-Recommended } }
$btnClear       = New-Button 'Clear all'          { Invoke-Safely { Clear-AllChecks } }
$ChkRestore = New-Option 'Create a restore point first' $true
$ChkSilent  = New-Option 'Uninstall silently when possible' $true
$ChkLeftovers = New-Option 'Remove leftover files and registry entries' $true
$ChkServiceCare = New-Option 'Show services that need care' $false
$btnPreview = New-Button 'Preview changes'        { Invoke-Safely { Show-Preview } }
$btnApply   = New-Button 'Apply selected'         { Invoke-Safely { Invoke-Apply } }
$btnApply.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnUndo    = New-Button 'Restore / roll back...' { Invoke-Safely { Invoke-Undo } }
$btnFolder  = New-Button 'Open backups folder'    { Invoke-Safely { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$BackupDir`"" } }
$ActionButtons = @($btnRecommended, $btnClear, $btnPreview, $btnApply, $btnUndo, $btnFolder)
$Options = @($ChkRestore, $ChkSilent, $ChkLeftovers, $ChkServiceCare)
$ChkServiceCare.Add_CheckedChanged({ Invoke-Safely { Show-ListItems $script:LvServices; Update-SelectionCount } })

# Status bar
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$StatusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$StatusLabel.Spring = $true
$StatusLabel.TextAlign = 'MiddleLeft'
[void]$statusStrip.Items.Add($StatusLabel)
$FooterLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$FooterLabel.Text = 'Powered by CyberX, SVPNPA'
$FooterLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$FooterLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, (Px 8), 0)
[void]$statusStrip.Items.Add($FooterLabel)

$Form.Controls.Add($Split)
$Form.Controls.Add($header)
$Form.Controls.Add($bar)
$Form.Controls.Add($statusStrip)
$bar.SendToBack()
$statusStrip.SendToBack()
$Split.BringToFront()

# =============================================================================
#  Lists
# =============================================================================
function Set-Busy([bool]$On, [bool]$LockLists = $true) {
    $script:Busy = $On
    foreach ($b in $script:ActionButtons) { $b.Enabled = -not $On }
    foreach ($c in $script:Options) { $c.Enabled = -not $On }
    $script:FilterBox.Enabled = -not $On
    if ($LockLists -or -not $On) { $script:Tabs.Enabled = -not $On }
    if ($On) { $script:Form.Cursor = [System.Windows.Forms.Cursors]::AppStarting }
    else     { $script:Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-AllLists {
    @($script:LvApps, $script:LvStore, $script:LvPrograms, $script:LvPython, $script:LvStartup, $script:LvPrivacy,
      $script:LvStart, $script:LvSystem, $script:LvServices, $script:LvFeatures, $script:LvCleanup)
}

function Update-SelectionCount {
    if ($script:Populating) { return }
    $n = 0
    foreach ($lv in Get-AllLists) { foreach ($it in $lv.Tag) { if ($it.Checked) { $n++ } } }
    $script:StatusLabel.Text = "$n item(s) selected    |    Backups and logs: $DataDir"
}

# Each list keeps all its items in .Tag; the find box decides which are shown.
function Reset-List($List) { $List.Tag = New-Object System.Collections.ArrayList }

function Add-StoreItem($List, [string]$Text, [string]$Status, [string]$Details, $Tag, [string]$GroupKey, [bool]$Checked, [bool]$Dim) {
    $it = New-Object System.Windows.Forms.ListViewItem($Text)
    [void]$it.SubItems.Add($Status)
    [void]$it.SubItems.Add($Details)
    $it.Name = $GroupKey
    $it.Tag = $Tag
    $it.Checked = $Checked
    $it.ToolTipText = $Details
    if ($Dim) { $it.ForeColor = [System.Drawing.SystemColors]::GrayText }
    [void]$List.Tag.Add($it)
}

function Test-ItemMatches($Item, [string]$Query) {
    foreach ($s in $Item.SubItems) {
        if ($s.Text.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Show-ListItems($List) {
    $q = $script:FilterBox.Text.Trim()
    $script:Populating = $true
    $List.BeginUpdate()
    try {
        $saved = @{}
        foreach ($it in @($List.Items)) { $saved[$it] = $it.Checked }
        $List.Items.Clear()
        foreach ($k in @($saved.Keys)) { $k.Checked = $saved[$k] }
        $hideCare = ($List -eq $script:LvServices -and -not $script:ChkServiceCare.Checked)
        foreach ($it in $List.Tag) {
            if ($q -and -not (Test-ItemMatches $it $q)) { continue }
            # A hidden "needs care" service must not stay ticked, or it would be acted on unseen.
            if ($hideCare -and $it.Name -eq 'Optional') { $it.Checked = $false; continue }
            $it.Group = $List.Groups[$it.Name]
            [void]$List.Items.Add($it)
        }
        Set-LastColumnWidth $List
    } finally {
        $List.EndUpdate()
        $script:Populating = $false
    }
}

function Update-Filter {
    foreach ($lv in Get-AllLists) { Show-ListItems $lv }
    Update-SelectionCount
}

function Set-ShownChecks($List, [bool]$State) {
    if ($null -eq $List) { return }
    $script:Populating = $true
    foreach ($it in $List.Items) { $it.Checked = $State }
    $script:Populating = $false
    Update-SelectionCount
}

function Update-AppLists {
    $edge = @(Get-EdgeInstalls)
    $lv = $script:LvApps
    Reset-List $lv
    foreach ($app in $script:AppCatalog) {
        $m = Get-AppMatches $app
        if ($m.Installed.Count -eq 0 -and $m.Provisioned.Count -eq 0) { continue }
        if ($m.Installed.Count -gt 0) { $st = 'Installed' } else { $st = 'Provisioned only' }
        Add-StoreItem $lv $app.Name $st $app.Desc $app $app.Group ($app.Group -eq 'Recommended') $false
    }
    if (Get-OneDriveExe) {
        Add-StoreItem $lv 'OneDrive' 'Installed' $script:OneDriveEntry.Desc $script:OneDriveEntry 'Advanced' $false $false
    }
    if ($edge.Count -gt 0) {
        Add-StoreItem $lv 'Microsoft Edge' ("Installed $($edge[0].Version)").Trim() $script:EdgeEntry.Desc $script:EdgeEntry 'Advanced' $false $false
    }
    if ((Get-ServiceRunState @('WinDefend')) -ne 'Absent') {
        if ((Get-TamperProtection) -eq $true) { $dst = 'On (Tamper Protection on)' } else { $dst = 'On' }
        Add-StoreItem $lv $script:DefenderEntry.Name $dst $script:DefenderEntry.Desc $script:DefenderEntry 'Advanced' $false $false
    }
    Show-ListItems $lv

    $known = @($script:AppCatalog | ForEach-Object { $_.Patterns })
    $pkgs = @($script:InstalledPkgs | Where-Object {
            -not $_.IsFramework -and -not $_.IsResourcePackage -and
            [string]$_.SignatureKind -ne 'System' -and
            -not ($_.PSObject.Properties['NonRemovable'] -and $_.NonRemovable) -and
            -not (Test-NameMatches $_.Name $known)
        } | Sort-Object Name -Unique)
    $lv = $script:LvStore
    Reset-List $lv
    foreach ($p in $pkgs) {
        if (Test-NameMatches $p.Name $script:SystemAppPatterns) { $grp = 'System' }
        elseif (Test-NameMatches $p.Name $script:NeverOffer) { continue }
        else { $grp = 'Optional' }
        $tag = @{ Type = 'App'; Group = $grp; Name = $p.Name; Desc = ''; Patterns = @($p.Name) }
        $det = '{0}    version {1}    from {2}' -f (Get-PublisherName $p.Publisher), $p.Version, (Get-SourceName ([string]$p.SignatureKind))
        Add-StoreItem $lv $p.Name 'Installed' $det $tag $grp $false $false
    }
    Show-ListItems $lv
}

function Update-ProgramList {
    $programs = @(Get-Win32Programs)
    $lv = $script:LvPrograms
    Reset-List $lv
    foreach ($p in $programs) {
        $cmd = Get-UninstallCommand $p $true
        if ($cmd -and $cmd.Silent) { $st = 'Silent uninstall' } else { $st = 'Opens uninstaller' }
        # Genuine bloatware floats to its own group, above everything else.
        $grp = $p.Group
        if (Test-NameMatches $p.Name $script:BloatProgramPatterns) { $grp = 'Bloat'; $st = 'Bloatware - ' + $st.ToLower() }
        $bits = @()
        if ($p.Publisher) { $bits += $p.Publisher }
        if ($p.Version)   { $bits += "version $($p.Version)" }
        if ($p.Size -gt 0) { $bits += (Format-Size $p.Size) }
        if ($p.Date)      { $bits += "installed $($p.Date)" }
        $bits += $p.Scope
        Add-StoreItem $lv $p.Name $st ($bits -join '    ') $p $grp $false $false
    }
    Show-ListItems $lv
}

function Update-PythonList {
    $lv = $script:LvPython
    Reset-List $lv
    foreach ($envp in @(Get-PythonEnvs)) {
        $label = "Python $($envp.Version)".Trim()
        foreach ($pkg in (Get-PythonPackages $envp.Exe)) {
            if ($script:PyCorePackages -contains $pkg.Name.ToLower()) { continue }
            $tag = @{ Type = 'PyPkg'; Env = $envp.Exe; Name = $pkg.Name; Version = $pkg.Version; Display = $pkg.Name }
            Add-StoreItem $lv $pkg.Name "v$($pkg.Version)" "$label    $($envp.Exe)" $tag 'Packages' $false $false
        }
    }
    Show-ListItems $lv
}

function Update-StartupList {
    $tasks = @(Get-ThirdPartyTasks)
    $entries = @(Get-StartupEntries $tasks)
    $lv = $script:LvStartup
    Reset-List $lv
    foreach ($e in ($entries | Sort-Object { $_.Display })) {
        Add-StoreItem $lv $e.Display $e.StatusText $e.Desc $e $e.Group $false $e.Skip
    }
    Show-ListItems $lv
}

function Update-TweakLists {
    foreach ($tab in $script:TweakLists.Keys) {
        $lv = $script:TweakLists[$tab]
        Reset-List $lv
        foreach ($t in @($script:Tweaks | Where-Object { $_.Tab -eq $tab })) {
            $plans = @(foreach ($a in $t.Actions) { Get-ActionPlan $a })
            $relevant = @($plans | Where-Object { -not $_.Missing })
            $notDone = @($relevant | Where-Object { -not $_.Done })
            if ($relevant.Count -eq 0)                  { $st = 'Not on this PC';  $skip = $true }
            elseif ($notDone.Count -eq 0)               { $st = 'Already applied'; $skip = $true }
            elseif ($notDone.Count -lt $relevant.Count) { $st = 'Partly applied';  $skip = $false }
            else                                        { $st = 'Not applied';     $skip = $false }
            # For services, lead with what is actually in use right now.
            if ($tab -eq 'Services' -and -not $skip) {
                $run = Get-ServiceRunState @($t.Actions | Where-Object { $_.Kind -eq 'Service' } | ForEach-Object { $_.Name })
                if ($run -eq 'Running') { $st = 'Running now' } elseif ($run -eq 'Stopped') { $st = 'Stopped (startup not disabled)' }
            }
            $t.Skip = $skip
            Add-StoreItem $lv $t.Name $st $t.Desc $t $t.Group (($t.Group -eq 'Recommended') -and -not $skip) $skip
        }
        Show-ListItems $lv
    }
}

function Update-FeatureList {
    $lv = $script:LvFeatures
    Reset-List $lv
    foreach ($f in $script:FeatureCatalog) {
        if ($f.Kind -eq 'OptionalFeature') { $hits = @($script:EnabledFeatures | Where-Object { $_ -eq $f.Pattern }); $st = 'Enabled' }
        else { $hits = @($script:InstalledCaps | Where-Object { $_ -like $f.Pattern }); $st = 'Installed' }
        foreach ($h in $hits) {
            $tag = @{ Type = 'Feature'; FeatureType = $f.Kind; Group = $f.Group; Name = $f.Name; Target = $h; Desc = $f.Desc }
            Add-StoreItem $lv $f.Name $st "$($f.Desc)    [$h]" $tag $f.Group ($f.Group -eq 'Recommended') $false
        }
    }
    Show-ListItems $lv
}

function Update-CleanupList {
    $sizes = $null
    try { $sizes = Get-CleanupSizes } catch { }
    $lv = $script:LvCleanup
    Reset-List $lv
    foreach ($c in $script:CleanupCatalog) {
        $st = 'Ready'
        if ($sizes -and $c.Id -eq 'Temp') { $st = 'About ' + (Format-Size ([double]$sizes.Temp)) }
        if ($sizes -and $c.Id -eq 'WUCache') { $st = 'About ' + (Format-Size ([double]$sizes.WU)) }
        Add-StoreItem $lv $c.Name $st $c.Desc $c $c.Group ($c.Group -eq 'Recommended') $false
    }
    Show-ListItems $lv
}

# One scan step; a failure is logged and the remaining steps still run.
function Invoke-ScanStep([string]$Label, [scriptblock]$Body) {
    $script:StatusLabel.Text = $Label
    try { & $Body }
    catch { Write-Log "Could not finish '$Label': $($_.Exception.Message)" }
}

function Update-AllLists {
    Set-Busy $true $false
    try {
        Invoke-ScanStep 'Scanning apps...' { Update-PackageCache; Update-AppLists }
        Invoke-ScanStep 'Scanning desktop programs...' { Update-ProgramList }
        Invoke-ScanStep 'Scanning Python packages...' { Update-PythonList }
        Invoke-ScanStep 'Scanning startup items...' { Update-StartupList }
        Invoke-ScanStep 'Checking current settings and services...' { Update-TweakLists }
        Invoke-ScanStep 'Checking Windows features (this can take a moment)...' { Update-FeatureCache; Update-FeatureList }
        Invoke-ScanStep 'Measuring clean-up sizes...' { Update-CleanupList }
    } finally {
        Set-Busy $false
        Update-SelectionCount
    }
}

function Select-Recommended {
    $script:Populating = $true
    foreach ($lv in Get-AllLists) {
        foreach ($it in $lv.Tag) { $it.Checked = ($it.Tag.Group -eq 'Recommended') -and -not $it.Tag.Skip }
    }
    $script:Populating = $false
    Update-SelectionCount
}

function Clear-AllChecks {
    $script:Populating = $true
    foreach ($lv in Get-AllLists) { foreach ($it in $lv.Tag) { $it.Checked = $false } }
    $script:Populating = $false
    Update-SelectionCount
}

function Get-Selection {
    $s = @{ Tweaks = @(); Apps = @(); Programs = @(); PyPkgs = @(); Features = @(); Cleanups = @(); OneDrive = $false; Edge = $false; Defender = $false }
    foreach ($lv in Get-AllLists) {
        foreach ($it in $lv.Tag) {
            if (-not $it.Checked) { continue }
            $tag = $it.Tag
            switch ($tag.Type) {
                'Tweak'    { $s.Tweaks += $tag }
                'App'      { $s.Apps += $tag }
                'Win32'    { $s.Programs += $tag }
                'PyPkg'    { $s.PyPkgs += $tag }
                'Feature'  { $s.Features += $tag }
                'Cleanup'  { $s.Cleanups += $tag }
                'OneDrive' { $s.OneDrive = $true }
                'Edge'     { $s.Edge = $true }
                'Defender' { $s.Defender = $true }
            }
        }
    }
    return $s
}

function Get-SelectionTotal($Sel) {
    $Sel.Tweaks.Count + $Sel.Apps.Count + $Sel.Programs.Count + $Sel.PyPkgs.Count + $Sel.Features.Count + $Sel.Cleanups.Count +
        [int]$Sel.OneDrive + [int]$Sel.Edge + [int]$Sel.Defender
}

function Show-Preview {
    $sel = Get-Selection
    if ((Get-SelectionTotal $sel) -eq 0) { [void](Show-Message 'Nothing is ticked yet.'); return }
    Write-Log '=== Preview: nothing is changed ==='
    foreach ($t in $sel.Tweaks) {
        Write-Log "[Setting] $($t.Name)"
        foreach ($a in $t.Actions) {
            $p = Get-ActionPlan $a
            if ($p.Missing)   { Write-Log "    $($p.Label): not on this PC, skipped" }
            elseif ($p.Done)  { Write-Log "    $($p.Label): already $($p.Target)" }
            else              { Write-Log "    $($p.Label): $($p.Current) -> $($p.Target)" }
        }
    }
    foreach ($f in $sel.Features) {
        Write-Log "[Turn off Windows feature] $($f.Name): $($f.Target)"
    }
    foreach ($app in $sel.Apps) {
        $m = Get-AppMatches $app
        Write-Log "[Remove app] $($app.Name)"
        foreach ($p in $m.Installed)   { Write-Log "    $($p.PackageFullName)" }
        foreach ($p in $m.Provisioned) { Write-Log "    provisioned for new accounts: $($p.PackageName)" }
    }
    foreach ($p in $sel.Programs) {
        $c = Get-UninstallCommand $p $script:ChkSilent.Checked
        if ($c -and $c.Silent) { $mode = 'silent' } else { $mode = 'opens its uninstaller' }
        Write-Log "[Uninstall program] $($p.Name) ($mode)"
        if ($c) { Write-Log "    $($c.File) $($c.Args)" }
        if ($script:ChkLeftovers.Checked) { Write-Log '    then scan for leftover files, registry keys, services and tasks (you confirm before any are removed)' }
    }
    foreach ($g in ($sel.PyPkgs | Group-Object { $_.Env })) {
        Write-Log "[Python] $($g.Name)"
        Write-Log "    pip uninstall: $((@($g.Group | ForEach-Object { $_.Name })) -join ', ')"
    }
    if ($sel.Defender) {
        Write-Log '[Turn off] Microsoft Defender Antivirus'
        $tp = Get-TamperProtection
        if ($tp -eq $true) { Write-Log '    Tamper Protection is ON - this is skipped until you turn it off in Windows Security' }
        elseif ($null -eq $tp) { Write-Log '    Tamper Protection state could not be read - make sure it is off first' }
        else { Write-Log '    Tamper Protection is off' }
        foreach ($a in $script:DefenderRegActions) { $pp = Get-ActionPlan $a; Write-Log "    $($pp.Label): $($pp.Current) -> $($pp.Target)" }
        foreach ($t in $script:DefenderTaskPaths) { Write-Log "    disable scheduled task $t" }
        foreach ($s in $script:DefenderServiceActions) { Write-Log "    service $($s.Name) -> disabled (may be blocked while Defender is protected)" }
    }
    if ($sel.OneDrive) { Write-Log '[Uninstall] OneDrive (files already on this PC stay where they are)' }
    if ($sel.Edge) {
        Write-Log '[Remove] Microsoft Edge'
        foreach ($i in @(Get-EdgeInstalls)) { Write-Log "    $($i.Exe) $($i.Version)" }
        foreach ($a in $script:EdgeAllowActions + $script:EdgeBlockActions) {
            $p = Get-ActionPlan $a
            Write-Log "    $($p.Label): $($p.Current) -> $($p.Target)"
        }
        $b = @(Get-OtherBrowsers)
        if ($b.Count) { Write-Log "    other browsers found: $($b -join ', ')" } else { Write-Log '    WARNING: no other browser found' }
        Write-Log '    WebView2 is kept.'
    }
    foreach ($c in $sel.Cleanups) { Write-Log "[Clean up] $($c.Name)" }
    Write-Log ("=== End of preview: {0} item(s) ===" -f (Get-SelectionTotal $sel))
}

function Invoke-Apply {
    $sel = Get-Selection
    if ((Get-SelectionTotal $sel) -eq 0) { [void](Show-Message 'Nothing is ticked yet.'); return }

    $lines = @()
    if ($sel.Tweaks.Count)   { $lines += "-  change $($sel.Tweaks.Count) setting, service or startup item(s)" }
    if ($sel.Features.Count) { $lines += "-  turn off $($sel.Features.Count) Windows feature(s)" }
    $nApps = $sel.Apps.Count + [int]$sel.OneDrive
    if ($nApps)              { $lines += "-  remove $nApps app(s)" }
    if ($sel.Programs.Count) { $lines += "-  uninstall $($sel.Programs.Count) desktop program(s)" }
    if ($sel.PyPkgs.Count)   { $lines += "-  uninstall $($sel.PyPkgs.Count) Python package(s) with pip" }
    if ($sel.Edge)           { $lines += '-  remove Microsoft Edge' }
    if ($sel.Defender)       { $lines += '-  turn off Microsoft Defender' }
    if ($sel.Cleanups.Count) { $lines += "-  run $($sel.Cleanups.Count) clean-up task(s)" }
    $q = "About to:`n" + ($lines -join "`n") + "`n`n"
    $interactive = @($sel.Programs | Where-Object { $c = Get-UninstallCommand $_ $script:ChkSilent.Checked; -not ($c -and $c.Silent) }).Count
    if ($interactive) { $q += "$interactive program(s) have no silent uninstaller. Their own uninstall windows will open; finish each one to continue.`n`n" }
    $q += "Settings, services, startup items, Windows features and any removed leftover files or registry keys can be put back with 'Undo a previous run'. " +
          "Apps and programs themselves have to be reinstalled, and clean-ups cannot be undone.`n`nContinue?"
    if ((Show-Message $q 'YesNo' 'Question') -ne 'Yes') { return }

    $deleteEdgeProfile = $false
    if ($sel.Edge) {
        $others = @(Get-OtherBrowsers)
        if ($others.Count) { $b = 'Other browsers found: ' + ($others -join ', ') + '.' }
        else { $b = 'No other browser was found on this PC. Without one you will need another way to get a browser, for example from a terminal: winget install Mozilla.Firefox' }
        $q2 = "Remove Microsoft Edge?`n`n$b`n`nWebView2, which Teams, Outlook, Widgets and many other apps need, is kept. " +
              "Windows Update is told not to reinstall Edge, but a Windows feature update may still bring it back."
        if ((Show-Message $q2 'YesNo' 'Warning') -ne 'Yes') { $sel.Edge = $false; Write-Log 'Microsoft Edge will be kept.' }
        else {
            $q3 = "Also delete your Edge profile data (favorites, saved passwords, history) for this account?`n`nChoose No to leave it on disk."
            $deleteEdgeProfile = ((Show-Message $q3 'YesNo' 'Question') -eq 'Yes')
        }
    }
    if ($sel.OneDrive) {
        $where = 'your OneDrive folder'
        if ($env:OneDrive) { $where = $env:OneDrive }
        $q4 = "OneDrive will be uninstalled.`n`nFiles already downloaded stay in $where, but files marked online-only (cloud icon) will not open on this PC afterwards. " +
              "Make sure anything you need is downloaded first.`n`nUninstall OneDrive?"
        if ((Show-Message $q4 'YesNo' 'Warning') -ne 'Yes') { $sel.OneDrive = $false; Write-Log 'OneDrive will be kept.' }
    }
    if ($sel.Defender) {
        $tp = Get-TamperProtection
        if ($tp -eq $true) {
            $ans = Show-Message ("Microsoft Defender cannot be turned off while Tamper Protection is on. " +
                "Windows only lets a person change that toggle, in the Windows Security app.`n`n" +
                "Open Windows Security at that setting now? Switch Tamper Protection off there (Manage settings > Tamper Protection), " +
                "then run OptiWin again.`n`nDefender will be left on for now.") 'YesNo' 'Warning'
            if ($ans -eq 'Yes') {
                try { Start-Process 'windowsdefender://threatsettings' }
                catch { try { Start-Process 'windowsdefender:' } catch { Write-Log "    could not open Windows Security: $($_.Exception.Message)" } }
                Write-Log 'Opened Windows Security to the Tamper Protection setting.'
            }
            $sel.Defender = $false; Write-Log 'Defender left on (Tamper Protection is on).'
        } else {
            $av = @(Get-OtherAntivirus)
            if ($av.Count) { $note = "Another antivirus is registered: $($av -join ', '). " }
            else { $note = 'No other antivirus was detected, so this PC may be left with no real-time protection. ' }
            if ($null -eq $tp) { $note += 'The tool could not read Tamper Protection; make sure it is off or the changes will not stick. ' }
            $q5 = "Turn off Microsoft Defender Antivirus?`n`n$note`nThis disables real-time protection through policy, services and scheduled tasks. " +
                  "It is undoable, but a Windows security update may switch parts back on. Only do this on a PC with another antivirus or an isolated analysis machine.`n`nContinue?"
            if ((Show-Message $q5 'YesNo' 'Warning') -ne 'Yes') { $sel.Defender = $false; Write-Log 'Defender left on.' }
        }
    }

    $script:Stats = @{ Changed = 0; Removed = 0; Failed = 0; Reboot = $false }
    Set-Busy $true
    try {
        Write-Log '=== Apply ==='
        if ($script:ChkRestore.Checked) {
            if (-not (New-RestorePoint)) { Write-Log 'Stopped before making any changes.'; return }
        } else {
            Write-Log 'No restore point (option unticked).'
        }
        New-RunBackup

        foreach ($t in $sel.Tweaks) {
            Write-Log "[Setting] $($t.Name)"
            foreach ($a in $t.Actions) { Invoke-LoggedAction $a }
        }

        foreach ($f in $sel.Features) {
            Write-Log "[Turn off Windows feature] $($f.Name): $($f.Target)"
            $script:StatusLabel.Text = "Turning off $($f.Name)..."
            try {
                if ($f.FeatureType -eq 'Capability') {
                    $r = Invoke-InBackground { param($n) [string](Remove-WindowsCapability -Online -Name $n -ErrorAction Stop).RestartNeeded } @($f.Target)
                } else {
                    $r = Invoke-InBackground { param($n) [string](Disable-WindowsOptionalFeature -Online -FeatureName $n -NoRestart -ErrorAction Stop).RestartNeeded } @($f.Target)
                }
                Add-RunRecord @{ Kind = 'Feature'; FeatureType = $f.FeatureType; Name = $f.Target; Display = $f.Name }
                $script:Stats.Changed++
                if ("$($r.Output | Select-Object -Last 1)" -eq 'True') { $script:Stats.Reboot = $true; Write-Log '    done (restart needed)' }
                else { Write-Log '    done' }
            } catch {
                Write-Log "    FAILED: $($_.Exception.Message)"
                $script:Stats.Failed++
            }
        }

        foreach ($app in $sel.Apps) {
            Write-Log "[Remove app] $($app.Name)"
            $script:StatusLabel.Text = "Removing $($app.Name)..."
            $gone = Remove-AppEntry $app
            if ($gone.Count -gt 0) {
                $script:Stats.Removed++
                Add-RunRecord @{ Kind = 'App'; Name = $app.Name; Packages = $gone }
            }
        }

        foreach ($p in $sel.Programs) {
            Write-Log "[Uninstall program] $($p.Name)"
            $script:StatusLabel.Text = "Uninstalling $($p.Name)..."
            try {
                $res = Uninstall-Win32 $p $script:ChkSilent.Checked
                Write-Log "    $($res.Message)"
                if ($res.Reboot) { $script:Stats.Reboot = $true }
                if ($res.Gone) {
                    $script:Stats.Removed++
                    Add-RunRecord @{ Kind = 'App'; Name = "$($p.Name) (desktop program)"; Packages = @($p.Name) }
                    if ($script:ChkLeftovers.Checked) {
                        $left = @(Get-ProgramLeftovers $p)
                        if ($left.Count) {
                            $show = ($left | Select-Object -First 15 | ForEach-Object { "- $($_.Display)" }) -join "`n"
                            if ($left.Count -gt 15) { $show += "`n- ... and $($left.Count - 15) more" }
                            $ans = Show-Message ("Leftovers found for $($p.Name):`n`n$show`n`nRemove these as well? Files go to a quarantine folder and registry keys are backed up, so 'Undo a previous run' can restore them.") 'YesNo' 'Question'
                            if ($ans -eq 'Yes') { Write-Log "    leftovers removed: $(Remove-Leftovers $left $script:RunStamp) item(s)" }
                            else { Write-Log '    leftovers kept.' }
                        } else { Write-Log '    no leftovers found.' }
                    }
                } else { $script:Stats.Failed++ }
            } catch {
                Write-Log "    FAILED: $($_.Exception.Message)"
                $script:Stats.Failed++
            }
        }

        if ($sel.OneDrive) {
            Write-Log '[Uninstall] OneDrive'
            $script:StatusLabel.Text = 'Uninstalling OneDrive...'
            try {
                Write-Log "    $(Uninstall-OneDrive)"
                $script:Stats.Removed++
                Add-RunRecord @{ Kind = 'App'; Name = 'OneDrive'; Packages = @('OneDrive (reinstall from microsoft.com/onedrive)') }
            } catch {
                Write-Log "    FAILED: $($_.Exception.Message)"
                $script:Stats.Failed++
            }
        }

        foreach ($g in ($sel.PyPkgs | Group-Object { $_.Env })) {
            $exe = $g.Name
            $names = @($g.Group | ForEach-Object { $_.Name })
            Write-Log "[Python] uninstall from $exe"
            $script:StatusLabel.Text = "Uninstalling Python packages ($($names.Count))..."
            try {
                $r = Invoke-InBackground { param($e, $ns) & $e -m pip uninstall -y --disable-pip-version-check @ns 2>&1 } @($exe, $names)
                foreach ($l in $r.Output) { if ("$l".Trim()) { Write-Log "    $l" } }
                $script:Stats.Removed += $names.Count
                Add-RunRecord @{ Kind = 'App'; Name = "Python packages ($([IO.Path]::GetFileName($exe)))"; Packages = @($names | ForEach-Object { "$_ (reinstall with pip install)" }) }
            } catch {
                Write-Log "    FAILED: $($_.Exception.Message)"
                $script:Stats.Failed++
            }
        }

        if ($sel.Edge) {
            Write-Log '[Remove] Microsoft Edge'
            $script:StatusLabel.Text = 'Removing Microsoft Edge...'
            try {
                if (Remove-Edge $deleteEdgeProfile) {
                    $script:Stats.Removed++
                    $script:Stats.Reboot = $true
                    Add-RunRecord @{ Kind = 'App'; Name = 'Microsoft Edge'; Packages = @('Microsoft Edge (run Undo first to lift the reinstall block, then install from microsoft.com/edge)') }
                } else { $script:Stats.Failed++ }
            } catch {
                Write-Log "    FAILED: $($_.Exception.Message)"
                $script:Stats.Failed++
            }
        }

        if ($sel.Defender) {
            Write-Log '[Turn off] Microsoft Defender Antivirus'
            $script:StatusLabel.Text = 'Turning off Microsoft Defender...'
            Invoke-DefenderDisable
            $script:Stats.Reboot = $true
            # Check whether it actually took: real-time protection cannot turn off while Tamper Protection is on.
            $rt = Get-DefenderRealtime
            if ($rt -eq $true) {
                Write-Log '    WARNING: real-time protection is still ON. Tamper Protection is almost certainly still enabled.'
                Write-Log '    Turn Tamper Protection OFF in Windows Security > Virus & threat protection > Manage settings, then run this again.'
            } elseif ($rt -eq $false) {
                Write-Log '    real-time protection now reports OFF.'
            }
            Write-Log '    applied. Restart the PC to finish. Undo this run to re-enable.'
        }

        foreach ($c in $sel.Cleanups) {
            Write-Log "[Clean up] $($c.Name)"
            $script:StatusLabel.Text = "Cleaning up: $($c.Name)..."
            try { Write-Log "    $(Invoke-Cleanup $c)" }
            catch { Write-Log "    FAILED: $($_.Exception.Message)"; $script:Stats.Failed++ }
        }

        Write-Log ("=== Done: {0} change(s), {1} app(s) or program(s) removed, {2} failure(s) ===" -f
            $script:Stats.Changed, $script:Stats.Removed, $script:Stats.Failed)
        if ($script:Run.Changes.Count -gt 0) { Write-Log "Undo file: $($script:RunFile)" }
    } finally {
        Set-Busy $false
    }

    Update-AllLists
    if ($script:Stats.Changed -gt 0 -or $script:Stats.Removed -gt 0) { Request-Restart $script:Stats.Reboot }
}

# All kept backup points (run-*.json, newest first). Undone ones are archived as .undone and not listed.
function Get-RunBackups {
    $list = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -Path $script:BackupDir -Filter 'run-*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -match '^run-(\d{8}-\d{6})\.json$') { $stamp = $Matches[1] } else { continue }
        try { $d = Get-Content -Raw -Path $f.FullName | ConvertFrom-Json } catch { continue }
        $ch = @($d.Changes | Where-Object { $_ })
        [void]$list.Add([pscustomobject]@{
            File = $f.FullName; Stamp = $stamp; Created = [string]$d.Created
            Changes = @($ch | Where-Object { $_.Kind -ne 'App' }).Count
            Apps = @($ch | Where-Object { $_.Kind -eq 'App' }).Count
        })
    }
    return @($list | Sort-Object Stamp -Descending)
}

# Reverses one backup file's changes. Returns restored/failed counts, whether a reboot is wanted, and removed app names.
function Undo-OneFile([string]$File) {
    $res = @{ Restored = 0; Failed = 0; Reboot = $false; Apps = @() }
    try { $data = Get-Content -Raw -Path $File | ConvertFrom-Json }
    catch { Write-Log "    cannot read $([IO.Path]::GetFileName($File)): $($_.Exception.Message)"; $res.Failed++; return $res }
    $changes = @($data.Changes | Where-Object { $_ })
    Write-Log "=== Undo: $([IO.Path]::GetFileName($File))  ($($data.Created)) ==="
    for ($i = $changes.Count - 1; $i -ge 0; $i--) {
        $r = $changes[$i]
        if ($r.Kind -eq 'App') { $res.Apps += $r.Name; continue }
        try {
            Write-Log ('    ' + (Undo-Record $r))
            $res.Restored++
            if ($r.Kind -in @('Feature', 'Service') -or ($r.Kind -eq 'RegKeyDelete' -and $r.Service)) { $res.Reboot = $true }
        } catch {
            Write-Log "    FAILED: $($_.Exception.Message)"; $res.Failed++
        }
    }
    if ($res.Failed -eq 0) {
        try { Rename-Item -Path $File -NewName ([IO.Path]::GetFileName($File) + '.undone') -ErrorAction Stop } catch { }
    }
    return $res
}

# Lists kept backup points and lets the user undo one run, or roll the PC back to an earlier point.
function Show-RestoreDialog {
    $backups = @(Get-RunBackups)
    if ($backups.Count -eq 0) { [void](Show-Message 'No backup points yet. One is saved automatically each time you Apply changes.'); return $null }
    $script:RestoreChoice = $null

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$script:ToolName - Restore / roll back"
    $dlg.StartPosition = 'CenterParent'; $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false
    $dlg.Font = $script:Form.Font
    $dlg.ClientSize = New-Object System.Drawing.Size((Px 660), (Px 430))

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Dock = 'Top'; $lbl.Height = (Px 54)
    $lbl.Padding = New-Object System.Windows.Forms.Padding((Px 10), (Px 8), (Px 10), 0)
    $lbl.Text = 'Every Apply saves a backup point, and they are all kept. Pick one, then either undo just that run, or roll the PC back to how it was before that point (undoing it and everything applied after it).'

    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Bottom'; $bar.FlowDirection = 'RightToLeft'; $bar.AutoSize = $true
    $bar.Padding = New-Object System.Windows.Forms.Padding((Px 8))

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false
    $lv.HeaderStyle = 'Nonclickable'
    [void]$lv.Columns.Add('Backup point (when Applied)', (Px 230))
    [void]$lv.Columns.Add('Settings', (Px 120))
    [void]$lv.Columns.Add('Apps removed (reinstall only)', (Px 270))
    foreach ($b in $backups) {
        $when = $b.Created; if (-not $when) { $when = $b.Stamp }
        $it = New-Object System.Windows.Forms.ListViewItem($when)
        [void]$it.SubItems.Add([string]$b.Changes)
        [void]$it.SubItems.Add([string]$b.Apps)
        $it.Tag = $b
        [void]$lv.Items.Add($it)
    }
    if ($lv.Items.Count) { $lv.Items[0].Selected = $true }

    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = 'Cancel'; $btnCancel.AutoSize = $true
    $btnCancel.Margin = New-Object System.Windows.Forms.Padding((Px 4), (Px 2), (Px 4), (Px 2))
    $btnCancel.Add_Click({ $dlg.Close() })
    $btnOne = New-Object System.Windows.Forms.Button; $btnOne.Text = 'Undo this run only'; $btnOne.AutoSize = $true
    $btnOne.Margin = New-Object System.Windows.Forms.Padding((Px 4), (Px 2), (Px 4), (Px 2))
    $btnOne.Add_Click({
        if ($lv.SelectedItems.Count) { $script:RestoreChoice = @{ File = $lv.SelectedItems[0].Tag.File; Mode = 'single' }; $dlg.Close() }
    })
    $btnRoll = New-Object System.Windows.Forms.Button; $btnRoll.Text = 'Roll back to before this point'; $btnRoll.AutoSize = $true
    $btnRoll.Margin = New-Object System.Windows.Forms.Padding((Px 4), (Px 2), (Px 4), (Px 2))
    $btnRoll.Font = New-Object System.Drawing.Font($dlg.Font, [System.Drawing.FontStyle]::Bold)
    $btnRoll.Add_Click({
        if ($lv.SelectedItems.Count) {
            $t = $lv.SelectedItems[0].Tag
            $script:RestoreChoice = @{ File = $t.File; Mode = 'rollback'; Stamp = $t.Stamp; When = $t.Created }; $dlg.Close()
        }
    })
    $bar.Controls.AddRange([System.Windows.Forms.Control[]]@($btnCancel, $btnOne, $btnRoll))

    $dlg.Controls.Add($lv)
    $dlg.Controls.Add($bar)
    $dlg.Controls.Add($lbl)
    [void]$dlg.ShowDialog($script:Form)
    return $script:RestoreChoice
}

function Invoke-Undo {
    $sel = Show-RestoreDialog
    if (-not $sel) { return }

    if ($sel.Mode -eq 'single') {
        $targets = @($sel.File)
        $confirm = "Undo this one run?`n`nIts settings, services, startup items, features and quarantined leftovers go back to how they were. Any apps or programs removed in that run must be reinstalled."
    } else {
        $all = @(Get-RunBackups)
        $targets = @($all | Where-Object { $_.Stamp -ge $sel.Stamp } | Sort-Object Stamp -Descending | ForEach-Object { $_.File })
        $when = $sel.When; if (-not $when) { $when = $sel.Stamp }
        $confirm = "Roll back to before $when?`n`nThis undoes that run and the $($targets.Count - 1) run(s) applied after it, returning the PC to how it was just before that point. Apps or programs removed along the way must be reinstalled."
    }
    if ((Show-Message $confirm 'YesNo' 'Question') -ne 'Yes') { return }

    Set-Busy $true
    $tot = @{ R = 0; F = 0; Reboot = $false; Apps = @() }
    try {
        Write-Log "=== Restore ($($sel.Mode)) ==="
        foreach ($f in $targets) {
            $r = Undo-OneFile $f
            $tot.R += $r.Restored; $tot.F += $r.Failed; if ($r.Reboot) { $tot.Reboot = $true }; $tot.Apps += $r.Apps
        }
        if ($tot.Apps.Count) {
            Write-Log 'Apps and programs removed in the undone run(s) (reinstall any you want):'
            foreach ($a in @($tot.Apps | Select-Object -Unique)) { Write-Log "    $a" }
        }
        Write-Log ("=== Restore finished: {0} change(s) put back, {1} failure(s) ===" -f $tot.R, $tot.F)
    } finally {
        Set-Busy $false
    }
    Update-AllLists
    if ($tot.R -gt 0) { Request-Restart $tot.Reboot }
}

# =============================================================================
#  Events and start
# =============================================================================
$FilterBox.Add_TextChanged({ Invoke-Safely { Update-Filter } })

$Form.Add_Load({
    try {
        $Split.Panel1MinSize = (Px 180)
        $Split.Panel2MinSize = (Px 90)
        $Split.SplitterDistance = [int]($Split.Height * 0.66)
    } catch { }
})

$Form.Add_Shown({
    Invoke-Safely {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) { Write-Log ("{0} (build {1})" -f $os.Caption, $os.BuildNumber) }
        Write-Log "Per-user settings will apply to the account $env:USERDOMAIN\$env:USERNAME."
        Write-Log "Backups and logs are kept in $DataDir"
        Update-AllLists
        Write-Log 'Ready. Nothing has been changed yet.'
    }
})

$Form.Add_FormClosing({
    param($s, $e)
    if ($script:Busy) {
        $e.Cancel = $true
        [void](Show-Message 'Please wait until the current task finishes.')
    }
})

Add-Content -Path $LogFile -Value ("$ToolName {0} (powered by CyberX, SVPNPA) started {1}" -f $ToolVersion, (Get-Date)) -Encoding UTF8 -ErrorAction SilentlyContinue
try {
    [void]$Form.ShowDialog()
} catch {
    [void][System.Windows.Forms.MessageBox]::Show("The tool hit an unexpected error:`n`n$($_.Exception.Message)`n`nLog: $LogFile",
        $ToolName, 'OK', 'Error')
}
