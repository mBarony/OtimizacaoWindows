<#
.SYNOPSIS
  Desfaz o que Otimizar-Windows.ps1 aplicou e devolve os padroes do Windows.

.DESCRIPTION
  Restaura servicos, tarefas agendadas, telemetria, indexacao, memoria, energia,
  Defender, firewall e a interface. Auto-eleva.

  As listas vem de Listas.ps1, o mesmo arquivo que o otimizador le. E por isso que
  nenhum servico pode ficar sem reversao: $SvcPadrao guarda o tipo de inicializacao
  padrao de cada um, e este script percorre a lista inteira.

  A reversao das preferencias de usuario tem duas etapas, nesta ordem:
    1. apaga ou devolve ao padrao cada valor que o otimizador escreveu;
    2. reimporta os backups .reg, que restauram o que existia antes.
  Assim, valor que ja existia volta ao original, e valor que o otimizador criou
  do nada some -- que e o que "reverter" quer dizer.

  NAO reinstala os apps UWP removidos. Para reinstalar:
    - Microsoft Store, ou
    - Get-AppxPackage -AllUsers | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" }

.PARAMETER TodosUsuarios
  Reverte tambem o hive do usuario padrao. Use se tiver otimizado com a mesma opcao.

.EXAMPLE
  .\Reverter-Windows.ps1
  .\Reverter-Windows.ps1 -TodosUsuarios
#>
[CmdletBinding()]
param([switch]$TodosUsuarios)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  Write-Host "Elevando privilegios..." -ForegroundColor Yellow
  $argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath)
  if($TodosUsuarios){ $argv += '-TodosUsuarios' }
  try{ Start-Process powershell.exe -Verb RunAs -ArgumentList $argv | Out-Null }
  catch{ Write-Host "UAC recusado." -ForegroundColor Red; Read-Host "ENTER" }
  return
}

$ErrorActionPreference = 'Continue'
$Base = Split-Path -Parent $PSCommandPath
function S($p,$n,$v,$t='DWord'){ try{ if(-not(Test-Path $p)){New-Item $p -Force|Out-Null}; New-ItemProperty -Path $p -Name $n -Value $v -PropertyType $t -Force|Out-Null }catch{} }
function D($p,$n){ Remove-ItemProperty -Path $p -Name $n -Force -EA SilentlyContinue }

$listas = Join-Path $Base 'Listas.ps1'
if(-not (Test-Path $listas)){ Write-Host "Listas.ps1 nao encontrado em $Base" -ForegroundColor Red; Read-Host "ENTER"; return }
. $listas

$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber

Write-Host "== Servicos ==" -ForegroundColor Cyan
$okS=0
foreach($s in $SvcPadrao.Keys){
  if(-not (Get-Service -Name $s -EA SilentlyContinue)){ continue }
  try{ Set-Service $s -StartupType $SvcPadrao[$s] -EA Stop; $okS++ }catch{}
}
foreach($s in $SvcSobDemanda.Keys){
  if(-not (Get-Service -Name $s -EA SilentlyContinue)){ continue }
  try{ Set-Service $s -StartupType $SvcSobDemanda[$s] -EA Stop; $okS++ }catch{}
}
foreach($t in $SvcPorUsuario){
  $k="HKLM:\SYSTEM\CurrentControlSet\Services\$t"; if(Test-Path $k){ S $k 'Start' 2 }
}
Start-Service WSearch,SysMain,Spooler,DiagTrack -EA SilentlyContinue
Write-Host "  restaurados: $okS"

Write-Host "== Tarefas agendadas ==" -ForegroundColor Cyan
# So as tarefas desta lista. Habilitar "toda tarefa desabilitada da maquina"
# ligaria tambem as que ja vinham desligadas de fabrica ou pelo proprio usuario.
$okT=0
foreach($t in $Tarefas){
  $p = Split-Path $t -Parent; if($p -notmatch '\\$'){ $p += '\' }
  try{ Enable-ScheduledTask -TaskPath $p -TaskName (Split-Path $t -Leaf) -EA Stop | Out-Null; $okT++ }catch{}
}
Write-Host "  reabilitadas: $okT de $($Tarefas.Count)"

Write-Host "== Memoria / kernel / NTFS ==" -ForegroundColor Cyan
$mm='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
S "$mm\PrefetchParameters" 'EnablePrefetcher' 3
S "$mm\PrefetchParameters" 'EnableSuperfetch' 3
S $mm 'DisablePagingExecutive' 0
S $mm 'ClearPageFileAtShutdown' 0
S 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 2
S 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '5000' 'String'
D 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff'
# Ligar o gerenciamento automatico primeiro: o Windows descarta as instancias
# explicitas sozinho. So depois se remove o que por acaso tenha sobrado.
try{
  Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile=$true}
  Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue | Remove-CimInstance -EA SilentlyContinue
}catch{}
fsutil behavior set disablelastaccess 2 | Out-Null
fsutil behavior set disable8dot3 2      | Out-Null

Write-Host "== Politicas ==" -ForegroundColor Cyan
foreach($k in $PoliticasApagar){ Remove-Item $k -Recurse -Force -EA SilentlyContinue }
Remove-Item 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Recurse -Force -EA SilentlyContinue
Remove-Item 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' -Recurse -Force -EA SilentlyContinue
Remove-Item 'HKCU:\Software\Policies\Microsoft\Windows\EdgeUI' -Recurse -Force -EA SilentlyContinue

# Valores soltos fora das chaves apagadas em bloco
S 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 0
S 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable' 1
S 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 1
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 1
D 'HKLM:\SOFTWARE\Policies\Microsoft' 'DisablePushToInstall'
D 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry'
D 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork'
D 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput' 'AllowLinguisticDataCollection'
D 'HKLM:\SOFTWARE\Microsoft\MdmCommon\SettingValues' 'LocationSyncEnabled'
D 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' 'Value'
D 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'Value'
D 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\features' 'WiFiSenseCredShared'
D 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\features' 'WiFiSenseOpen'
foreach($v in 'VSCommon\16.0','VSCommon\17.0'){ D "HKLM:\SOFTWARE\Microsoft\$v\SQM" 'OptIn' }
D 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2' 'OptInOrOutPreference'
foreach($v in 'DOTNET_CLI_TELEMETRY_OPTOUT','POWERSHELL_TELEMETRY_OPTOUT'){
  try{ [Environment]::SetEnvironmentVariable($v,$null,'Machine') }catch{}
}

# Permissoes de app para a maquina inteira
$csm='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
foreach($c in $Permissoes){ S "$csm\$c" 'Value' 'Allow' 'String' }

# VBS / Integridade de Memoria: apagar devolve o padrao do fabricante/edicao
D 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity'
D 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'

Write-Host "== Sessoes de rastreamento ETW ==" -ForegroundColor Cyan
foreach($al in $Autologgers){
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

Write-Host "== Energia / indexacao / recursos / firewall ==" -ForegroundColor Cyan
powercfg -setactive SCHEME_BALANCED 2>&1 | Out-Null
powercfg -h on 2>&1 | Out-Null
try{ Get-CimInstance Win32_Volume -Filter "DriveLetter='$($env:SystemDrive)'" | Set-CimInstance -Property @{IndexingEnabled=$true} }catch{}
foreach($f in $RecursosRestaurar){
  try{ Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -EA Stop | Out-Null }catch{}
}
foreach($g in $FirewallGrupos){
  Get-NetFirewallRule -Group $g -EA SilentlyContinue | Enable-NetFirewallRule -EA SilentlyContinue
}
if(Get-Command Set-WindowsReservedStorageState -EA SilentlyContinue){
  try{ Set-WindowsReservedStorageState -State Enabled -EA Stop }catch{}
}

# =====================================================================
# Preferencias do usuario
# =====================================================================
function Reverter-Usuario($raiz){
  $adv = "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
  $cdm = "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
  $pex = "$raiz\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
  $bsc = "$raiz\Software\Microsoft\Windows\CurrentVersion\Search"

  # --- valores cujo padrao e um valor ---
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" 'VisualFXSetting' 0
  S "$raiz\Control Panel\Desktop\WindowMetrics" 'MinAnimate' '1' 'String'
  S "$raiz\Control Panel\Desktop" 'MenuShowDelay' '400' 'String'
  S "$raiz\Control Panel\Desktop" 'DragFullWindows' '1' 'String'
  S "$raiz\Control Panel\Desktop" 'AutoEndTasks' '0' 'String'
  S "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'EnableTransparency' 1
  S "$raiz\SOFTWARE\Microsoft\Windows\DWM" 'EnableAeroPeek' 1
  S "$raiz\SOFTWARE\Microsoft\Windows\DWM" 'AlwaysHibernateThumbnails' 1
  foreach($n in 'TaskbarAnimations','ListviewAlphaSelect','ListviewShadow','ShowTaskViewButton',
                'Start_TrackDocs','Start_TrackProgs','ShowSyncProviderNotifications',
                'ShowInfoTip','FolderContentsInfoTip','ShowPreviewHandlers'){ S $adv $n 1 }
  S $adv 'IconsOnly' 0
  S $bsc 'SearchboxTaskbarMode' 2
  S $bsc 'BingSearchEnabled' 1
  S $bsc 'BackgroundAppGlobalToggle' 1
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" 'GlobalUserDisabled' 0
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\SearchSettings" 'IsDeviceSearchHistoryEnabled' 1
  S "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" 'Enabled' 1
  S "$raiz\Software\Microsoft\InputPersonalization" 'RestrictImplicitTextCollection' 0
  S "$raiz\Software\Microsoft\InputPersonalization" 'RestrictImplicitInkCollection' 0
  S "$raiz\Software\Microsoft\InputPersonalization\TrainedDataStore" 'HarvestContacts' 1
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\Privacy" 'TailoredExperiencesWithDiagnosticDataEnabled' 1
  S "$raiz\Software\Microsoft\MediaPlayer\Preferences" 'UsageTracking' 1
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" 'Value' 'Allow' 'String'
  S "$raiz\System\GameConfigStore" 'GameDVR_Enabled' 1
  S "$raiz\System\GameConfigStore" 'GameDVR_FSEBehaviorMode' 2
  S "$raiz\Software\Microsoft\GameBar" 'AutoGameModeEnabled' 1
  S "$raiz\Software\Microsoft\GameBar" 'ShowStartupPanel' 1
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" 'ScoobeSystemSettingEnabled' 1
  foreach($n in 'ContentDeliveryAllowed','FeatureManagementEnabled','OemPreInstalledAppsEnabled',
   'PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled',
   'SubscribedContentEnabled','SystemPaneSuggestionsEnabled','RotatingLockScreenEnabled',
   'RotatingLockScreenOverlayEnabled'){ S $cdm $n 1 }

  # --- valores cujo padrao e a ausencia: apagar ---
  D "$raiz\Control Panel\Desktop" 'UserPreferencesMask'
  D "$raiz\Control Panel\Desktop" 'HungAppTimeout'
  D "$raiz\Control Panel\Desktop" 'WaitToKillAppTimeout'
  D $bsc 'CortanaConsent'
  D $pex 'DisableThumbnails'
  D $pex 'NoResolveSearch'
  D $pex 'NoResolveTrack'
  D $pex 'LinkResolveIgnoreLinkInfo'
  D "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" 'StartupDelayInMSec'
  D "$raiz\Software\Microsoft\Siuf\Rules" 'NumberOfSIUFInPeriod'
  D "$raiz\Software\Microsoft\Siuf\Rules" 'PeriodInNanoSeconds'
  D "$raiz\Software\Microsoft\Personalization\Settings" 'AcceptedPrivacyPolicy'
  D "$raiz\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" 'HasAccepted'
  foreach($n in 'SubscribedContent-310093Enabled','SubscribedContent-338388Enabled',
   'SubscribedContent-338389Enabled','SubscribedContent-338393Enabled','SubscribedContent-353694Enabled',
   'SubscribedContent-353696Enabled','SubscribedContent-338387Enabled','SubscribedContent-88000326Enabled'){ D $cdm $n }
  if($build -ge 22000){
    foreach($n in 'TaskbarDa','TaskbarMn','ShowCopilotButton','Start_IrisRecommendations',
                  'Start_AccountNotifications'){ D $adv $n }
  }
}

Write-Host "== Interface ==" -ForegroundColor Cyan
Reverter-Usuario 'HKCU:'

if($TodosUsuarios){
  $ntuser = "$env:SystemDrive\Users\Default\NTUSER.DAT"
  if(Test-Path $ntuser){
    if(-not (Get-PSDrive -Name HKU -EA SilentlyContinue)){
      New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -Scope Script | Out-Null
    }
    reg load 'HKU\PadraoOtim' "$ntuser" 2>&1 | Out-Null
    if(Test-Path 'HKU:\PadraoOtim'){
      Reverter-Usuario 'HKU:\PadraoOtim'
      [gc]::Collect(); [gc]::WaitForPendingFinalizers()
      reg unload 'HKU\PadraoOtim' 2>&1 | Out-Null
      Write-Host "  hive do usuario padrao revertido"
    }
  }
}

# Os backups vem DEPOIS: eles devolvem o valor original das chaves que ja tinham
# um. O que o otimizador criou do nada ja foi apagado acima e continua apagado.
Write-Host "== Backups ==" -ForegroundColor Cyan
foreach($f in 'backup-Run-HKLM.reg','backup-Run-HKCU.reg','backup-Explorer-Advanced.reg',
              'backup-ContentDelivery.reg','backup-ControlPanel-Desktop.reg','backup-Search.reg'){
  $p = Join-Path $Base $f
  if(Test-Path $p){ reg import "$p" 2>&1 | Out-Null; Write-Host "  importado: $f" }
  else            { Write-Host "  ausente:   $f" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "REVERTIDO. Reinicie o Windows." -ForegroundColor Green
Write-Host "Apps UWP removidos nao voltam automaticamente - use a Microsoft Store." -ForegroundColor Yellow
Write-Host "SMB1, WorkFolders e XPS continuam desligados de proposito." -ForegroundColor Yellow
Read-Host "Pressione ENTER para fechar"
