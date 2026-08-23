<#
.SYNOPSIS
  Desfaz o que Otimizar-Windows.ps1 aplicou e devolve os padroes do Windows.

.DESCRIPTION
  Restaura servicos, tarefas agendadas, telemetria, indexacao, memoria, energia,
  Defender e a interface. Auto-eleva.

  NAO reinstala os apps UWP removidos. Para reinstalar:
    - Microsoft Store, ou
    - Get-AppxPackage -AllUsers | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" }

.EXAMPLE
  .\Reverter-Windows.ps1
#>
[CmdletBinding()]
param()

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  Write-Host "Elevando privilegios..." -ForegroundColor Yellow
  try{ Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath) | Out-Null }
  catch{ Write-Host "UAC recusado." -ForegroundColor Red; Read-Host "ENTER" }
  return
}

$ErrorActionPreference = 'Continue'
$Base = Split-Path -Parent $PSCommandPath
function S($p,$n,$v,$t='DWord'){ try{ if(-not(Test-Path $p)){New-Item $p -Force|Out-Null}; New-ItemProperty -Path $p -Name $n -Value $v -PropertyType $t -Force|Out-Null }catch{} }
function D($p,$n){ Remove-ItemProperty -Path $p -Name $n -Force -EA SilentlyContinue }

Write-Host "== Servicos ==" -ForegroundColor Cyan
$auto = 'DiagTrack','SysMain','WSearch','Spooler','DoSvc','DusmSvc','DPS','TrkWks','PcaSvc',
        'LanmanServer','CDPSvc','edgeupdate',
        'wuauserv','UsoSvc','BITS','WerSvc'
foreach($s in $auto){ try{ Set-Service $s -StartupType Automatic -EA Stop }catch{} }

# Bloatware de fabricante: espelha a lista do Otimizar-Windows.ps1. Os que nao
# existirem nesta maquina falham em silencio no catch.
$oem = 'igfxCUIService2.0.0.0','WavesSysSvc','RtkAudioUniversalService','RtkAudioService',
       'NvTelemetryContainer',
       'DellClientManagementService','SupportAssistAgent','SupportAssistAppService',
       'DellDataVault','DDVDataCollector','DDVRulesProcessor','DDVCollectorSvcApi',
       'DellTechHub','DellCustomerConnect',
       'HPSupportSolutionsFrameworkService','HPTouchpointAnalyticsService','hpqwmiex',
       'HPAppHelperCap','HPDiagsCap','HPNetworkCap','HPSysInfoCap','HPPrintScanDoctorService',
       'LenovoVantageService','ImControllerService',
       'ASUSSoftwareManager','ASUSSystemAnalysis','ASUSSystemDiagnosis','ASUSLinkNear',
       'ASUSLinkRemote','ASUSSwitch',
       'GoogleChromeElevationService','AdobeARMservice','AdobeUpdateService','MozillaMaintenance'
foreach($s in $oem){ try{ Set-Service $s -StartupType Automatic -EA Stop }catch{} }

$manual = 'dmwappushservice','WdiServiceHost','WdiSystemHost','PrintNotify','SSDPSRV','upnphost',
          'lmhosts','RemoteRegistry','SharedAccess','AJRouter','ALG','TapiSrv','icssvc','NcaSvc',
          'WFDSProviderSvc','lfsvc','MapsBroker','WMPNetworkSvc','MixedRealityOpenXRSvc',
          'XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc','RetailDemo','WaaSMedicSvc',
          'Fax','PhoneSvc','WalletService','SEMgrSvc','seclogon','SCardSvr','ScDeviceEnum',
          'SCPolicySvc','SNMPTrap','StiSvc','WEPHOSTSVC','wisvc','workfolderssvc','autotimesvc',
          'SensrSvc','DisplayEnhancementService','edgeupdatem','MicrosoftEdgeElevationService',
          'VSInstallerElevationService','InstallService'
foreach($s in $manual){ try{ Set-Service $s -StartupType Manual -EA Stop }catch{} }

foreach($t in 'OneSyncSvc','PimIndexMaintenanceSvc','UnistoreSvc','UserDataSvc','MessagingService',
              'CDPUserSvc','BcastDVRUserService','CaptureService','DevicesFlowUserSvc','UdkUserSvc'){
  $k="HKLM:\SYSTEM\CurrentControlSet\Services\$t"; if(Test-Path $k){ S $k 'Start' 2 }
}
Start-Service WSearch,SysMain,Spooler,DiagTrack -EA SilentlyContinue

Write-Host "== Tarefas agendadas ==" -ForegroundColor Cyan
Get-ScheduledTask | Where-Object State -eq 'Disabled' | Enable-ScheduledTask -EA SilentlyContinue | Out-Null

Write-Host "== Autostart ==" -ForegroundColor Cyan
foreach($f in 'backup-Run-HKLM.reg','backup-Run-HKCU.reg'){
  $p = Join-Path $Base $f
  if(Test-Path $p){ reg import "$p" 2>&1 | Out-Null; Write-Host "  importado: $f" }
}

Write-Host "== Memoria / kernel / NTFS ==" -ForegroundColor Cyan
$mm='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
S "$mm\PrefetchParameters" 'EnablePrefetcher' 3
S "$mm\PrefetchParameters" 'EnableSuperfetch' 3
S $mm 'DisablePagingExecutive' 0
S 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 2
S 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '5000' 'String'
D 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff'
try{ Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile=$true} }catch{}
fsutil behavior set disablelastaccess 2 | Out-Null
fsutil behavior set disable8dot3 2      | Out-Null

Write-Host "== Politicas ==" -ForegroundColor Cyan
foreach($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds',
              'HKLM:\SOFTWARE\Policies\Microsoft\Dsh',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender',
              'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
              'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo',
              'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization',
              'HKLM:\SOFTWARE\Policies\Microsoft\Speech',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync',
              'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messenger',
              'HKLM:\SOFTWARE\Policies\Microsoft\office'){
  Remove-Item $k -Recurse -Force -EA SilentlyContinue
}
S 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 0
S 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable' 1
D 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' 'Value'
D 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'Value'
foreach($v in 'VSCommon\16.0','VSCommon\17.0'){ D "HKLM:\SOFTWARE\Microsoft\$v\SQM" 'OptIn' }
D 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2' 'OptInOrOutPreference'
foreach($v in 'DOTNET_CLI_TELEMETRY_OPTOUT','POWERSHELL_TELEMETRY_OPTOUT'){
  try{ [Environment]::SetEnvironmentVariable($v,$null,'Machine') }catch{}
}

Write-Host "== Sessoes de rastreamento ETW ==" -ForegroundColor Cyan
foreach($al in 'AutoLogger-Diagtrack-Listener','SQMLogger','Diagtrack-Listener','WiFiSession',
               'DiagLog','CloudExperienceHostOobe','Circular Kernel Context Logger'){
  $k = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$al"
  if(Test-Path $k){ S $k 'Start' 1; S $k 'Enabled' 1 }
}

Write-Host "== Defender ==" -ForegroundColor Cyan
if(Get-Command Set-MpPreference -EA SilentlyContinue){
  try{
    Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false `
      -DisableIOAVProtection $false -DisableScriptScanning $false -DisableArchiveScanning $false `
      -DisableScanningNetworkFiles $false -DisableRemovableDriveScanning $false `
      -DisableCatchupFullScan $false -DisableCatchupQuickScan $false `
      -ScanAvgCPULoadFactor 50 -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples `
      -EnableNetworkProtection Enabled -PUAProtection Enabled -EA Stop
    $mp = Get-MpPreference
    $mp.ExclusionPath    | Where-Object {$_ -and $_ -notmatch '^N/A'} | ForEach-Object { Remove-MpPreference -ExclusionPath $_ -EA SilentlyContinue }
    $mp.ExclusionProcess | Where-Object {$_ -and $_ -notmatch '^N/A'} | ForEach-Object { Remove-MpPreference -ExclusionProcess $_ -EA SilentlyContinue }
    Write-Host "  restaurado"
  }catch{ Write-Host "  parcial: $($_.Exception.Message)" -ForegroundColor Yellow }
}

Write-Host "== Energia / indexacao / recursos ==" -ForegroundColor Cyan
powercfg -setactive SCHEME_BALANCED 2>&1 | Out-Null
powercfg -h on 2>&1 | Out-Null
try{ Get-CimInstance Win32_Volume -Filter "DriveLetter='$($env:SystemDrive)'" | Set-CimInstance -Property @{IndexingEnabled=$true} }catch{}
foreach($f in 'MicrosoftWindowsPowerShellV2Root','MediaPlayback'){
  try{ Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -EA Stop | Out-Null }catch{}
}

Write-Host "== Interface ==" -ForegroundColor Cyan
$adv='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
foreach($n in 'TaskbarDa','TaskbarMn','TaskbarAnimations','ListviewAlphaSelect','ListviewShadow',
              'ShowTaskViewButton','Start_TrackDocs','Start_TrackProgs'){ S $adv $n 1 }
S $adv 'IconsOnly' 0
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 2
S 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 0
S 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1' 'String'
S 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '400' 'String'
S 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '1' 'String'
S 'HKCU:\Control Panel\Desktop' 'AutoEndTasks' '0' 'String'
D 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask'
S 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1
S 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 1
S 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 0
S 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 0
S 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 1
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 1
S 'HKCU:\Software\Microsoft\MediaPlayer\Preferences' 'UsageTracking' 1
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Allow' 'String'
D 'HKCU:\Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds'
$cdm='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach($n in 'ContentDeliveryAllowed','SubscribedContentEnabled','SystemPaneSuggestionsEnabled',
              'RotatingLockScreenEnabled','SoftLandingEnabled'){ S $cdm $n 1 }

Write-Host ""
Write-Host "REVERTIDO. Reinicie o Windows." -ForegroundColor Green
Write-Host "Apps UWP removidos nao voltam automaticamente - use a Microsoft Store." -ForegroundColor Yellow
Read-Host "Pressione ENTER para fechar"
