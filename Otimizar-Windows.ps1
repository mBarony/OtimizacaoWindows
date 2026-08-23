<#
.SYNOPSIS
  Otimizacao agressiva de Windows 10/11 para maquinas fracas.
  Alvo: deixar o sistema o mais leve possivel para rodar Claude Code / Claude Desktop.

.DESCRIPTION
  Desabilita servicos, tarefas agendadas, telemetria, indexacao, autostart e apps UWP
  que nao sao necessarios. Ajusta memoria, pagefile, energia e Defender.

  PRESERVA DE PROPOSITO (nao mexe):
    - Bluetooth  ....... se houver teclado/mouse Bluetooth, desabilitar te deixa sem input
    - esifsvc / DPTF ... gestao termica Intel (notebooks/tablets sem ventoinha)
    - Audio ............ Audiosrv, AudioEndpointBuilder, codec do fabricante
    - Rede ............. Dhcp, Dnscache, WlanSvc, nsi, netprofm, Wcmsvc, BFE, firewall
    - Seguranca base ... CryptSvc, RpcSs, DcomLaunch, SamSs, gpsvc, BitLocker
    - Claude ........... CoworkVMService, AppXSvc, ClipSVC, StateRepository, TokenBroker

.PARAMETER SemDefender
  Tambem tenta desligar a protecao em tempo real do Defender.
  So funciona se a Protecao contra Adulteracao (Tamper Protection) estiver DESLIGADA:
  Seguranca do Windows > Protecao contra virus e ameacas > Gerenciar configuracoes.

.PARAMETER SemRemoverApps
  Nao remove nenhum app UWP.

.PARAMETER SemLimpeza
  Pula a limpeza de disco (temp, prefetch, WER, DISM).

.EXAMPLE
  .\Otimizar-Windows.ps1
  .\Otimizar-Windows.ps1 -SemDefender
  .\Otimizar-Windows.ps1 -SemRemoverApps -SemLimpeza

.NOTES
  Reversao: Reverter-Windows.ps1 (mesma pasta).
  Reinicie o Windows ao final.
#>
[CmdletBinding()]
param(
  [switch]$SemDefender,
  [switch]$SemRemoverApps,
  [switch]$SemLimpeza
)

# ---------------------------------------------------------------------
# Auto-elevacao
# ---------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  Write-Host "Elevando privilegios..." -ForegroundColor Yellow
  $argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
  if($SemDefender)    { $argv += '-SemDefender' }
  if($SemRemoverApps) { $argv += '-SemRemoverApps' }
  if($SemLimpeza)     { $argv += '-SemLimpeza' }
  try{ Start-Process powershell.exe -Verb RunAs -ArgumentList $argv | Out-Null }
  catch{ Write-Host "UAC recusado. Execute como Administrador." -ForegroundColor Red; Read-Host "ENTER" }
  return
}

$ErrorActionPreference = 'Continue'
$Base = Split-Path -Parent $PSCommandPath
$log  = Join-Path $Base ("otimizacao-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function L($m){ $m | Tee-Object -FilePath $log -Append }
function S($p,$n,$v,$t='DWord'){
  try{ if(-not(Test-Path $p)){ New-Item $p -Force | Out-Null }
       New-ItemProperty -Path $p -Name $n -Value $v -PropertyType $t -Force | Out-Null }catch{}
}

$cs    = Get-CimInstance Win32_ComputerSystem
$ramGB = [math]::Round($cs.TotalPhysicalMemory/1GB,2)
L "===== OTIMIZACAO WINDOWS - $(Get-Date) ====="
L "Maquina : $($cs.Manufacturer) $($cs.Model)"
L "SO      : $((Get-CimInstance Win32_OperatingSystem).Caption) build $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
L "RAM     : $ramGB GB"
L "Opcoes  : SemDefender=$SemDefender SemRemoverApps=$SemRemoverApps SemLimpeza=$SemLimpeza"

# Instalador pesado em andamento? Nao mexer em %TEMP% nem no DISM.
$busy = [bool](Get-Process -Name 'vs_BuildTools','vs_setup_bootstrapper','setup','winsdksetup','msiexec','TiWorker','TrustedInstaller' -EA SilentlyContinue)
if($busy){ L "[!] Instalador/servicing ATIVO - %TEMP%, SoftwareDistribution e DISM serao preservados" }

# =====================================================================
# 1. SERVICOS
# =====================================================================
$off = @(
 # telemetria e diagnostico
 'DiagTrack','dmwappushservice','DPS','WdiServiceHost','WdiSystemHost','WerSvc','PcaSvc',
 # cache/pre-carregamento inutil em SSD com pouca RAM
 'SysMain',
 # busca e indexacao
 'WSearch',
 # impressao
 'Spooler','PrintNotify',
 # rede secundaria / descoberta / compartilhamento
 'DoSvc','DusmSvc','SSDPSRV','upnphost','lmhosts','LanmanServer','RemoteRegistry',
 'SharedAccess','AJRouter','ALG','TapiSrv','icssvc','NcaSvc','WFDSProviderSvc',
 # rastreamento / localizacao / midia
 'TrkWks','lfsvc','MapsBroker','WMPNetworkSvc','MixedRealityOpenXRSvc',
 # Xbox
 'XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc',
 # diversos sem uso
 'RetailDemo','WaaSMedicSvc','Fax','PhoneSvc','WalletService','SEMgrSvc','seclogon',
 'SCardSvr','ScDeviceEnum','SCPolicySvc','SNMPTrap','StiSvc','WEPHOSTSVC','wisvc',
 'workfolderssvc','autotimesvc','CDPSvc',
 # sensores de brilho adaptativo (mantem SensorService p/ rotacao de tela)
 'SensrSvc','DisplayEnhancementService',
 # --- bloatware de fabricante -------------------------------------------------
 # Servicos que nao existirem na maquina sao ignorados pelo laco abaixo, entao a
 # lista cobre varios fabricantes sem risco para quem tem so um deles.
 # NAO entram aqui, de proposito: gestao termica (esifsvc / DPTF / Dell Power
 # Manager), pilhas Bluetooth (RtkBtManServ), drivers de audio e servicos de
 # teclas de funcao -- desabilitar qualquer um deles quebra hardware basico.
 # efeitos de audio e utilitarios de video
 'igfxCUIService2.0.0.0','WavesSysSvc','RtkAudioUniversalService','RtkAudioService',
 'NvTelemetryContainer',
 # Dell
 'DellClientManagementService','SupportAssistAgent','SupportAssistAppService',
 'DellDataVault','DDVDataCollector','DDVRulesProcessor','DDVCollectorSvcApi',
 'DellTechHub','DellCustomerConnect',
 # HP
 'HPSupportSolutionsFrameworkService','HPTouchpointAnalyticsService','hpqwmiex',
 'HPAppHelperCap','HPDiagsCap','HPNetworkCap','HPSysInfoCap','HPPrintScanDoctorService',
 # Lenovo (ImControllerService tambem cuida do Lenovo System Update)
 'LenovoVantageService','ImControllerService',
 # Asus
 'ASUSSoftwareManager','ASUSSystemAnalysis','ASUSSystemDiagnosis','ASUSLinkNear',
 'ASUSLinkRemote','ASUSSwitch',
 # updaters de terceiros
 'edgeupdate','edgeupdatem','MicrosoftEdgeElevationService','gupdate','gupdatem',
 'GoogleChromeElevationService','VSInstallerElevationService','brave','BraveElevationService',
 'AdobeARMservice','AdobeUpdateService','MozillaMaintenance'
)
if($busy){ $off = $off | Where-Object { $_ -ne 'VSInstallerElevationService' } }

L "`n--- Servicos desabilitados ---"
$okS=0
foreach($s in $off){
  if(Get-Service -Name $s -EA SilentlyContinue){
    try{ Stop-Service $s -Force -EA SilentlyContinue
         Set-Service  $s -StartupType Disabled -EA Stop
         $okS++; L ("  OK      $s") }
    catch{
      # Alguns servicos (DoSvc, WaaSMedicSvc) negam acesso pelo Service Control Manager
      # mesmo para Admin. A chave do registro normalmente ainda aceita a escrita.
      S "HKLM:\SYSTEM\CurrentControlSet\Services\$s" 'Start' 4
      if((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$s" -EA SilentlyContinue).Start -eq 4){
        $okS++; L ("  OK      $s  (via registro)")
      }else{ L ("  FALHOU  $s : " + $_.Exception.Message) }
    }
  }
}
L "  total: $okS"

L "`n--- Windows Update -> sob demanda (Manual) ---"
foreach($s in 'wuauserv','UsoSvc','BITS','InstallService'){
  try{ Set-Service $s -StartupType Manual -EA Stop; L "  OK      $s" }catch{ L "  FALHOU  $s" }
}

# Servicos por-usuario tem sufixo aleatorio: desabilitar pelo template em HKLM
L "`n--- Servicos por-usuario (template HKLM) ---"
foreach($t in 'OneSyncSvc','PimIndexMaintenanceSvc','UnistoreSvc','UserDataSvc','MessagingService',
              'CDPUserSvc','BcastDVRUserService','CaptureService','DevicesFlowUserSvc','UdkUserSvc'){
  $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$t"
  if(Test-Path $k){ S $k 'Start' 4; L "  OK      $t" }
}

# =====================================================================
# 2. TAREFAS AGENDADAS
# =====================================================================
$tasks = @(
 '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
 '\Microsoft\Windows\Application Experience\MareBackup'
 '\Microsoft\Windows\Application Experience\PcaPatchDbTask'
 '\Microsoft\Windows\Application Experience\PcaWallpaperAppDetect'
 '\Microsoft\Windows\Application Experience\SdbinstMergeDbTask'
 '\Microsoft\Windows\Application Experience\StartupAppTask'
 '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
 '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
 '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
 '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask'
 '\Microsoft\Windows\Feedback\Siuf\DmClient'
 '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
 '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
 '\Microsoft\Windows\Autochk\Proxy'
 '\Microsoft\Windows\Maps\MapsToastTask'
 '\Microsoft\Windows\Maps\MapsUpdateTask'
 '\Microsoft\Windows\Data Integrity Scan\Data Integrity Check And Scan'
 '\Microsoft\Windows\Data Integrity Scan\Data Integrity Scan'
 '\Microsoft\Windows\Data Integrity Scan\Data Integrity Scan for Crash Recovery'
 '\Microsoft\Windows\SpacePort\SpaceAgentTask'
 '\Microsoft\Windows\SpacePort\SpaceManagerTask'
 '\Microsoft\Windows\Storage Tiers Management\Storage Tiers Management Initialization'
 '\Microsoft\Windows\Shell\FamilySafetyMonitor'
 '\Microsoft\Windows\Shell\FamilySafetyRefreshTask'
 '\Microsoft\Windows\Shell\ThemesSyncedImageDownload'
 '\Microsoft\Windows\Shell\IndexerAutomaticMaintenance'
 '\Microsoft\XblGameSave\XblGameSaveTask'
 '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem'
 '\Microsoft\Windows\Diagnosis\Scheduled'
 '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner'
 '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
 '\Microsoft\Windows\Registry\RegIdleBackup'
 '\Microsoft\Windows\WindowsUpdate\Scheduled Start'
 '\Microsoft\Windows\InstallService\ScanForUpdates'
 '\Microsoft\Windows\InstallService\ScanForUpdatesAsUser'
 '\Microsoft\Windows\CloudRestore\Backup'
 '\Microsoft\Windows\CloudRestore\Restore'
 '\Microsoft\Windows\AppListBackup\Backup'
 '\Microsoft\Windows\AppListBackup\BackupNonMaintenance'
 '\Microsoft\Windows\Device Information\Device'
 '\Microsoft\Windows\Device Information\Device User'
 '\Microsoft\Windows\DUSM\dusmtask'
 '\Microsoft\Windows\Flighting\FeatureConfig\ReconcileConfigs'
 '\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures'
 '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing'
 '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver'
 '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting'
 '\Microsoft\Windows\Flighting\OneSettings\RefreshCache'
 '\Microsoft\Windows\Maintenance\WinSAT'
 '\Microsoft\Windows\MemoryDiagnostic\ProcessMemoryDiagnosticEvents'
 '\Microsoft\Windows\DirectX\DirectXDatabaseUpdater'
 '\Microsoft\Windows\Printing\EduPrintProv'
 '\Microsoft\Windows\Printing\PrinterCleanupTask'
 '\Microsoft\Windows\SystemRestore\SR'
 '\Microsoft\Windows\BitLocker\BitLocker Encrypt All Drives'
 '\Microsoft\Windows\BitLocker\BitLocker MDM policy Refresh'
 '\Microsoft\Windows\WwanSvc\NotificationTask'
 '\Microsoft\Windows\WwanSvc\OobeDiscovery'
 '\Microsoft\Windows\UPnP\UPnPHostConfig'
 '\Microsoft\Windows\Location\Notifications'
 '\Microsoft\Windows\Subscription\EnableLicenseAcquisition'
 '\Microsoft\Windows\International\Synchronize Language Settings'
 '\Microsoft\Windows\FileHistory\File History (maintenance mode)'
 '\Microsoft\Windows\DiskFootprint\Diagnostics'
 '\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance'
 '\Microsoft\Windows\Windows Defender\Windows Defender Cleanup'
 '\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan'
 '\Microsoft\Windows\Windows Defender\Windows Defender Verification'
 '\Git for Windows Updater'
 '\GoogleUpdateTaskMachineCore'
 '\GoogleUpdateTaskMachineUA'
 '\MicrosoftEdgeUpdateTaskMachineCore'
 '\MicrosoftEdgeUpdateTaskMachineUA'
)
L "`n--- Tarefas agendadas ---"
$okT=0
foreach($t in $tasks){
  $p = Split-Path $t -Parent; if($p -notmatch '\\$'){ $p += '\' }
  try{ Disable-ScheduledTask -TaskPath $p -TaskName (Split-Path $t -Leaf) -EA Stop | Out-Null; $okT++ }catch{}
}
L "  desabilitadas: $okT de $($tasks.Count) (as demais nao existem nesta instalacao)"

# =====================================================================
# 3. AUTOSTART
# =====================================================================
L "`n--- Autostart ---"
$runHKLM = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$runHKCU = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" (Join-Path $Base 'backup-Run-HKLM.reg') /y 2>&1 | Out-Null
reg export "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" (Join-Path $Base 'backup-Run-HKCU.reg') /y 2>&1 | Out-Null

# Padroes de autostart dispensavel (efeitos de audio, updaters, assistentes de fabricante)
$lixo = 'RtkNGui|RtI2SBgProc|WavesSvc|RtHDVCpl|Realtek|Nahimic|SecurityHealth|Logi.*Download|LogiLDA|' +
        'EdgeAutoLaunch|OneDrive|Skype|Spotify|Steam|EpicGames|Discord|Adobe|Acrobat|iTunes|' +
        'CCleaner|Dropbox|Teams|GoogleDriveFS|QuickTime|Java|jusched|NvBackend|' +
        # assistentes e updaters de fabricante
        'Dell.*Update|SupportAssist|HP.*Update|HPSupport|Lenovo.*Update|Vantage|' +
        'ASUS.*Update|ArmouryCrate|Acer.*Update|MSI.*Update'
foreach($k in $runHKLM,$runHKCU){
  if(Test-Path $k){
    (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
      if($_.Name -match $lixo -or $_.Value -match $lixo){
        Remove-ItemProperty $k -Name $_.Name -Force -EA SilentlyContinue
        L ("  removido: " + $_.Name)
      }
    }
  }
}

# =====================================================================
# 4. MEMORIA / KERNEL / NTFS
# =====================================================================
L "`n--- Memoria e kernel ---"
$mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
S $mm 'ClearPageFileAtShutdown' 0
S $mm 'DisablePagingExecutive' $(if($ramGB -ge 8){1}else{0})   # so trava o kernel na RAM se sobrar RAM
S "$mm\PrefetchParameters" 'EnablePrefetcher' 0
S "$mm\PrefetchParameters" 'EnableSuperfetch' 0
S 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 26
S 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000' 'String'
S 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
L "  prefetch/superfetch OFF | prioridade p/ foreground | power throttling OFF"

# Pagefile fixo dimensionado pela RAM: em maquinas com pouca RAM evita OOM
$ini = [int]([math]::Max(2048, $ramGB*1024))
$max = $ini*2
try{
  if($cs.AutomaticManagedPagefile){ $cs | Set-CimInstance -Property @{AutomaticManagedPagefile=$false} }
  $pf = Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue | Select-Object -First 1
  if($pf){ $pf | Set-CimInstance -Property @{InitialSize=$ini; MaximumSize=$max} }
  else   { New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name="$env:SystemDrive\pagefile.sys";InitialSize=$ini;MaximumSize=$max} | Out-Null }
  L "  pagefile fixo ${ini}-${max} MB (efetivo apos reiniciar)"
}catch{ L ("  pagefile FALHOU: " + $_.Exception.Message) }

fsutil behavior set disablelastaccess 1 | Out-Null
fsutil behavior set disable8dot3 1      | Out-Null
L "  NTFS: last-access OFF | nomes 8.3 OFF"

# =====================================================================
# 5. INDEXACAO
# =====================================================================
L "`n--- Indexacao ---"
$ws = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
S $ws 'AllowCortana' 0; S $ws 'DisableWebSearch' 1; S $ws 'ConnectedSearchUseWeb' 0
S $ws 'AllowIndexingEncryptedStoresOrItems' 0; S $ws 'AllowSearchToUseLocation' 0
$idx = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"
if(Test-Path $idx){
  $sz = (Get-ChildItem $idx -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum
  Remove-Item "$idx\*" -Recurse -Force -EA SilentlyContinue
  L ("  indice apagado: " + [math]::Round($sz/1MB,1) + " MB")
}
try{ Get-CimInstance Win32_Volume -Filter "DriveLetter='$($env:SystemDrive)'" |
       Set-CimInstance -Property @{IndexingEnabled=$false}
     L "  atributo de indexacao removido de $env:SystemDrive" }catch{ L "  atributo de indexacao: nao aplicado" }

# =====================================================================
# 6. TELEMETRIA / NUVEM / POLITICAS
# =====================================================================
L "`n--- Telemetria e politicas (HKLM) ---"
$dc='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
S $dc 'AllowTelemetry' 0; S $dc 'DoNotShowFeedbackNotifications' 1
S $dc 'AllowDeviceNameInTelemetry' 0; S $dc 'LimitDiagnosticLogCollection' 1
S $dc 'LimitDumpCollection' 1; S $dc 'DisableOneSettingsDownloads' 1
$ac='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
S $ac 'AITEnable' 0; S $ac 'DisableInventory' 1; S $ac 'DisableUAR' 1; S $ac 'DisablePCA' 1
$cc='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
S $cc 'DisableWindowsConsumerFeatures' 1; S $cc 'DisableSoftLanding' 1; S $cc 'DisableCloudOptimizedContent' 1
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
S 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
S 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0

# --- CEIP / SQM ---
S 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messenger\Client' 'CEIP' 2
S 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable' 0

# --- relatorio de erros (WER) ---
$wer='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
S $wer 'Disabled' 1; S $wer 'DontSendAdditionalData' 1; S $wer 'AutoApproveOSDumps' 0
S $wer 'LoggingDisabled' 1

# --- linha do tempo / historico de atividades ---
$sys='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
S $sys 'EnableActivityFeed' 0; S $sys 'PublishUserActivities' 0; S $sys 'UploadUserActivities' 0
# so a area de transferencia entre dispositivos, que sobe para a nuvem.
# O historico local (Win+V) continua funcionando.
S $sys 'AllowCrossDeviceClipboard' 0

# --- ID de publicidade ---
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1

# --- voz, escrita e personalizacao de entrada ---
S 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Speech' 'AllowSpeechModelUpdate' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' 'PreventHandwritingErrorReports' 1
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1

# --- busca na nuvem / Cortana ---
$ws='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
S $ws 'AllowCortana' 0; S $ws 'AllowCloudSearch' 0; S $ws 'ConnectedSearchUseWeb' 0
S $ws 'DisableWebSearch' 1; S $ws 'AllowSearchToUseLocation' 0

# --- sincronizacao de configuracoes e WiFi Sense ---
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSync' 2
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSyncUserOverride' 1
S 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' 'Value' 0
S 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'Value' 0

# --- telemetria do Edge ---
$ed='HKLM:\SOFTWARE\Policies\Microsoft\Edge'
S $ed 'MetricsReportingEnabled' 0; S $ed 'SendSiteInfoToImproveServices' 0
S $ed 'PersonalizationReportingEnabled' 0; S $ed 'UserFeedbackAllowed' 0
S $ed 'DiagnosticData' 0; S $ed 'SpotlightExperiencesAndRecommendationsEnabled' 0

# --- telemetria de terceiros presentes numa maquina de desenvolvimento ---
S 'HKLM:\SOFTWARE\Policies\Microsoft\office\common\clienttelemetry' 'sendtelemetry' 3
S 'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common' 'sendcustomerdata' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\clienttelemetry' 'DisableTelemetry' 1
S 'HKLM:\SOFTWARE\Microsoft\VSCommon\16.0\SQM' 'OptIn' 0
S 'HKLM:\SOFTWARE\Microsoft\VSCommon\17.0\SQM' 'OptIn' 0
S 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2' 'OptInOrOutPreference' 0
foreach($v in 'DOTNET_CLI_TELEMETRY_OPTOUT','POWERSHELL_TELEMETRY_OPTOUT'){
  try{ [Environment]::SetEnvironmentVariable($v,'1','Machine') }catch{}
}
L "  aplicado"

# --- sessoes de rastreamento ETW (autologger) ---
# Nao mexemos no arquivo hosts: bloquear dominios da Microsoft por ali quebra
# Windows Update e Store, e volta a valer a cada atualizacao de recurso.
L "`n--- Sessoes de rastreamento ETW ---"
$okE=0
foreach($al in 'AutoLogger-Diagtrack-Listener','SQMLogger','Diagtrack-Listener','WiFiSession',
               'DiagLog','CloudExperienceHostOobe','Circular Kernel Context Logger'){
  $k = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$al"
  if(Test-Path $k){ S $k 'Start' 0; S $k 'Enabled' 0; $okE++; L "  OK      $al" }
}
L "  total: $okE"

# =====================================================================
# 7. PREFERENCIAS DO USUARIO (HKCU)
# =====================================================================
L "`n--- Interface (HKCU) ---"
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
S 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
S 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
S 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' 'String'
S 'HKCU:\Control Panel\Desktop' 'AutoEndTasks' '1' 'String'
S 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '2000' 'String'
S 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '2000' 'String'
New-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' `
  -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -PropertyType Binary -Force | Out-Null
S 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
S 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
S 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'AlwaysHibernateThumbnails' 0
$adv='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
foreach($n in 'TaskbarDa','TaskbarMn','ShowCopilotButton','TaskbarAnimations','ListviewAlphaSelect',
              'ListviewShadow','ShowTaskViewButton','Start_TrackDocs','Start_TrackProgs',
              'ShowSyncProviderNotifications'){ S $adv $n 0 }
S $adv 'IconsOnly' 1
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0
$cdm='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach($n in 'ContentDeliveryAllowed','FeatureManagementEnabled','OemPreInstalledAppsEnabled',
 'PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled',
 'SubscribedContentEnabled','SubscribedContent-310093Enabled','SubscribedContent-338388Enabled',
 'SubscribedContent-338389Enabled','SubscribedContent-338393Enabled','SubscribedContent-353694Enabled',
 'SubscribedContent-353696Enabled','SubscribedContent-338387Enabled','SubscribedContent-88000326Enabled',
 'SystemPaneSuggestionsEnabled','RotatingLockScreenEnabled','RotatingLockScreenOverlayEnabled'){ S $cdm $n 0 }
S 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
S 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
S 'HKCU:\Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0
S 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
S 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
S 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
S 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
# "experiencias personalizadas com dados de diagnostico"
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
# reconhecimento de voz online
S 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
S 'HKCU:\Software\Microsoft\MediaPlayer\Preferences' 'UsageTracking' 0
# acesso de apps a localizacao (o servico lfsvc ja foi desabilitado acima)
S ('HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location') 'Value' 'Deny' 'String'
S 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
S 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
S 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0
S 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0
L "  aplicado"

# =====================================================================
# 8. ENERGIA
# =====================================================================
L "`n--- Energia ---"
powercfg -setactive SCHEME_MIN 2>&1 | Out-Null          # Alto desempenho
powercfg -h off 2>&1 | Out-Null                          # sem hibernacao/fast startup
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 50  2>&1 | Out-Null
powercfg -setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0 2>&1 | Out-Null
powercfg -setactive SCHEME_CURRENT 2>&1 | Out-Null
L ("  " + (powercfg /getactivescheme))

# =====================================================================
# 9. DEFENDER
# =====================================================================
L "`n--- Defender ---"
if(Get-Command Get-MpComputerStatus -EA SilentlyContinue){
  $tp = (Get-MpComputerStatus).IsTamperProtected
  L "  Tamper Protection: $tp"

  # Exclusoes: funcionam mesmo com Tamper ON. Maior ganho para ferramentas que
  # fazem muito I/O de arquivos pequenos (Claude Code, git, compiladores).
  $exPaths = @(
    "$env:USERPROFILE\.local\bin","$env:USERPROFILE\.claude","$env:USERPROFILE\.cache",
    "$env:USERPROFILE\.config","$env:USERPROFILE\.npm","$env:USERPROFILE\.cargo",
    "$env:LOCALAPPDATA\Temp\claude","$env:LOCALAPPDATA\AnthropicClaude","$env:APPDATA\Claude",
    "$env:USERPROFILE\Documents","$env:USERPROFILE\projects","$env:USERPROFILE\source",
    "$env:USERPROFILE\dev","$env:USERPROFILE\repos",
    'C:\Program Files\Git','C:\Program Files\nodejs',
    'C:\Program Files (x86)\Microsoft Visual Studio','C:\Program Files (x86)\Windows Kits'
  ) | Where-Object { Test-Path $_ }
  $exProc = 'claude.exe','cowork-svc.exe','git.exe','bash.exe','sh.exe','powershell.exe','pwsh.exe',
            'WindowsTerminal.exe','node.exe','npm.exe','python.exe','cl.exe','link.exe','MSBuild.exe','rg.exe','Code.exe'
  foreach($p in $exPaths){ try{ Add-MpPreference -ExclusionPath $p -EA Stop; L "  excl: $p" }catch{} }
  foreach($p in $exProc) { try{ Add-MpPreference -ExclusionProcess $p -EA Stop }catch{} }
  L ("  excl. processos: " + ($exProc -join ', '))

  try{
    Set-MpPreference -ScanAvgCPULoadFactor 5 -DisableCpuThrottleOnIdleScans $true `
      -DisableCatchupFullScan $true -DisableCatchupQuickScan $true `
      -DisableArchiveScanning $true -DisableScanningNetworkFiles $true `
      -DisableRemovableDriveScanning $true -MAPSReporting Disabled `
      -SubmitSamplesConsent NeverSend -EnableNetworkProtection Disabled `
      -PUAProtection Disabled -EA Stop
    L "  motor: CPU 5% | sem archives/rede/removiveis | sem MAPS | sem network protection"
  }catch{ L ("  motor (parcial): " + $_.Exception.Message) }

  if($SemDefender){
    try{
      Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true `
        -DisableIOAVProtection $true -DisableScriptScanning $true -EA Stop
      L "  tempo real: DESLIGADO"
    }catch{
      L ("  tempo real: BLOQUEADO -> " + $_.Exception.Message)
      L "  >> Desligue a Protecao contra Adulteracao e rode de novo com -SemDefender:"
      L "     Seguranca do Windows > Protecao contra virus e ameacas > Gerenciar configuracoes"
    }
    $rt='HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    S $rt 'DisableAntiSpyware' 1
    S "$rt\Real-Time Protection" 'DisableRealtimeMonitoring' 1
    S "$rt\Real-Time Protection" 'DisableBehaviorMonitoring' 1
    S "$rt\Real-Time Protection" 'DisableScanOnRealtimeEnable' 1
    S "$rt\Spynet" 'SpynetReporting' 0
    S "$rt\Spynet" 'SubmitSamplesConsent' 2
  }
  $a = Get-MpComputerStatus
  L "  estado -> RealTime=$($a.RealTimeProtectionEnabled) Tamper=$($a.IsTamperProtected)"
}

# =====================================================================
# 10. APPS UWP
# =====================================================================
if(-not $SemRemoverApps){
  L "`n--- Apps UWP removidos ---"
  # NAO remover: Store, DesktopAppInstaller(winget), Terminal, Notepad, SecHealthUI, Edge,
  # WebViewHost, AccountsControl, ShellExperienceHost, StartMenuExperienceHost, Claude
  $rm = 'Microsoft.BingSearch','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp',
   'Microsoft.Getstarted','Microsoft.WindowsAlarms','Microsoft.WindowsSoundRecorder',
   'Microsoft.WindowsCamera','Microsoft.ZuneMusic','Microsoft.ZuneVideo','Microsoft.YourPhone',
   'Microsoft.Windows.Photos','Microsoft.XboxGameOverlay','Microsoft.XboxGamingOverlay',
   'Microsoft.XboxSpeechToTextOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxGameCallableUI',
   'Microsoft.GamingApp','Microsoft.WidgetsPlatformRuntime','MicrosoftWindows.Client.WebExperience',
   'MicrosoftWindows.CrossDevice','Microsoft.Paint','Microsoft.MSPaint','Microsoft.ScreenSketch',
   'Microsoft.WindowsCalculator','Microsoft.Windows.NarratorQuickStart',
   'Microsoft.Windows.SecureAssessmentBrowser','Microsoft.MicrosoftEdgeDevToolsClient',
   'Microsoft.RawImageExtension','Microsoft.Windows.ParentalControls','Microsoft.WindowsMaps',
   'Microsoft.People','Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection',
   'Microsoft.Todos','Microsoft.OutlookForWindows','Microsoft.Windows.DevHome','Microsoft.Copilot',
   'Microsoft.SkypeApp','Microsoft.MixedReality.Portal','Microsoft.3DBuilder','Microsoft.Print3D',
   'Microsoft.Office.OneNote','Microsoft.WindowsFeedbackHub','Microsoft.549981C3F5F10'
  foreach($a in $rm){
    $pk = Get-AppxPackage -Name $a -AllUsers -EA SilentlyContinue
    if($pk){
      try{ $pk | Remove-AppxPackage -AllUsers -EA Stop; L "  removido: $a" }
      catch{ try{ Get-AppxPackage -Name $a | Remove-AppxPackage -EA Stop; L "  removido(user): $a" }catch{ L "  FALHOU: $a" } }
    }
    $pr = Get-AppxProvisionedPackage -Online -EA SilentlyContinue | Where-Object DisplayName -eq $a
    if($pr){ try{ Remove-AppxProvisionedPackage -Online -PackageName $pr.PackageName -EA Stop | Out-Null }catch{} }
  }
}

# =====================================================================
# 11. RECURSOS OPCIONAIS LEGADOS
# =====================================================================
foreach($f in 'MicrosoftWindowsPowerShellV2Root','SMB1Protocol','WorkFolders-Client',
              'Printing-XPSServices-Features','MediaPlayback'){
  try{ $st = Get-WindowsOptionalFeature -Online -FeatureName $f -EA Stop
       if($st.State -eq 'Enabled'){
         Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -EA Stop | Out-Null
         L "`n  recurso desabilitado: $f" } }catch{}
}

# =====================================================================
# 12. LIMPEZA DE DISCO
#     IMPORTANTE: nunca apagar a pasta deste script.
# =====================================================================
if(-not $SemLimpeza){
  L "`n--- Limpeza ---"
  $antes = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'").FreeSpace
  $dirs = @("$env:SystemRoot\Prefetch","$env:LOCALAPPDATA\CrashDumps",
            "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
            "$env:ProgramData\Microsoft\Windows\WER\ReportArchive")
  if($busy){ L "  [!] instalador ativo: %TEMP% / SoftwareDistribution / DISM preservados" }
  else     { $dirs += "$env:TEMP","$env:SystemRoot\Temp","$env:SystemRoot\SoftwareDistribution\Download" }

  $baseFull = (Resolve-Path $Base).Path.TrimEnd('\')
  # Nunca apagar: a pasta deste script, nem os arquivos de sessao do Claude Code
  # (que ficam em %TEMP%\claude e sao usados enquanto o script roda).
  $manter = @($baseFull, "$env:TEMP\claude", "$env:LOCALAPPDATA\Temp\claude")
  foreach($d in $dirs){
    if(-not (Test-Path $d)){ continue }
    Get-ChildItem $d -Force -EA SilentlyContinue | ForEach-Object {
      $t = $_.FullName.TrimEnd('\')
      $pular = $false
      foreach($k in $manter){
        $k = $k.TrimEnd('\')
        if($t -like "$k*" -or $k -like "$t\*" -or $k -eq $t){ $pular = $true; break }
      }
      if($pular){ return }
      Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue
    }
  }
  Clear-RecycleBin -Force -EA SilentlyContinue
  if(-not $busy){ Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet 2>&1 | Out-Null }
  $depois = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'").FreeSpace
  L ("  liberado: " + [math]::Round(($depois-$antes)/1MB,1) + " MB | livre: " + [math]::Round($depois/1GB,2) + " GB")
}

# =====================================================================
L "`n===== FIM $(Get-Date) ====="
L "Servicos em execucao: $((Get-Service | Where-Object Status -eq Running).Count)"
L "Tarefas desabilitadas: $((Get-ScheduledTask | Where-Object State -eq 'Disabled').Count)"
Write-Host ""
Write-Host "CONCLUIDO. REINICIE o Windows para aplicar tudo." -ForegroundColor Green
Write-Host "Log: $log" -ForegroundColor Gray
Write-Host "Para desfazer: .\Reverter-Windows.ps1" -ForegroundColor Gray
Write-Host ""
Read-Host "Pressione ENTER para fechar"
