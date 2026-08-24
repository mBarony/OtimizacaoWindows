<#
.SYNOPSIS
  Dados compartilhados por Otimizar-Windows.ps1 e Reverter-Windows.ps1.

.DESCRIPTION
  Este arquivo nao executa nada: so declara listas. Ele existe para que as duas
  pontas -- aplicar e reverter -- leiam a MESMA fonte. Enquanto as listas viviam
  duplicadas nos dois scripts, servico desabilitado sem entrada correspondente na
  reversao passava despercebido.

  $SvcPadrao guarda o tipo de inicializacao PADRAO do Windows para cada servico,
  nao o que o otimizador aplica. Otimizar desabilita as chaves; Reverter devolve
  cada uma ao valor daqui. Servico que nao existir na maquina e ignorado nos dois.
#>

# ---------------------------------------------------------------------
# Servicos desabilitados pelo otimizador  ->  tipo de inicializacao padrao
# ---------------------------------------------------------------------
$SvcPadrao = [ordered]@{
  # --- telemetria e diagnostico ---
  'DiagTrack'                                = 'Automatic'
  'diagnosticshub.standardcollector.service' = 'Manual'      # some a partir do 24H2
  'dmwappushservice'                         = 'Manual'
  'DPS'                                      = 'Automatic'
  'WdiServiceHost'                           = 'Manual'
  'WdiSystemHost'                            = 'Manual'
  'WerSvc'                                   = 'Manual'
  'PcaSvc'                                   = 'Automatic'

  # --- cache/pre-carregamento (so desabilitado em SSD; ver Otimizar) ---
  'SysMain'                                  = 'Automatic'

  # --- busca e indexacao ---
  'WSearch'                                  = 'Automatic'

  # --- impressao ---
  'Spooler'                                  = 'Automatic'
  'PrintNotify'                              = 'Manual'

  # --- rede secundaria / descoberta / compartilhamento ---
  'DoSvc'                                    = 'Automatic'
  'DusmSvc'                                  = 'Automatic'
  'SSDPSRV'                                  = 'Manual'
  'upnphost'                                 = 'Manual'
  'lmhosts'                                  = 'Manual'
  'LanmanServer'                             = 'Automatic'
  'RemoteRegistry'                           = 'Disabled'    # ja e o padrao no cliente
  'SharedAccess'                             = 'Manual'
  'AJRouter'                                 = 'Manual'
  'ALG'                                      = 'Manual'
  'TapiSrv'                                  = 'Manual'
  'icssvc'                                   = 'Manual'
  'NcaSvc'                                   = 'Manual'
  'WFDSProviderSvc'                          = 'Manual'
  'SstpSvc'                                  = 'Manual'
  'SmsRouter'                                = 'Manual'

  # --- rastreamento / localizacao / midia ---
  'TrkWks'                                   = 'Automatic'
  'lfsvc'                                    = 'Manual'
  'MapsBroker'                               = 'Automatic'
  'WMPNetworkSvc'                            = 'Manual'
  'MixedRealityOpenXRSvc'                    = 'Manual'
  'SharedRealitySvc'                         = 'Manual'
  'perceptionsimulation'                     = 'Manual'
  'ShellHWDetection'                         = 'Automatic'   # AutoPlay

  # --- Xbox ---
  'XblAuthManager'                           = 'Manual'
  'XblGameSave'                              = 'Manual'
  'XboxGipSvc'                               = 'Manual'
  'XboxNetApiSvc'                            = 'Manual'

  # --- diversos sem uso ---
  'RetailDemo'                               = 'Manual'
  'WaaSMedicSvc'                             = 'Manual'
  'Fax'                                      = 'Manual'
  'PhoneSvc'                                 = 'Manual'
  'WalletService'                            = 'Manual'
  'SEMgrSvc'                                 = 'Manual'
  'seclogon'                                 = 'Manual'
  'SCardSvr'                                 = 'Manual'
  'ScDeviceEnum'                             = 'Manual'
  'SCPolicySvc'                              = 'Manual'
  'SNMPTrap'                                 = 'Manual'
  'StiSvc'                                   = 'Manual'
  'WEPHOSTSVC'                               = 'Manual'
  'wisvc'                                    = 'Manual'
  'workfolderssvc'                           = 'Manual'
  'autotimesvc'                              = 'Manual'
  'CDPSvc'                                   = 'Automatic'
  'WpcMonSvc'                                = 'Manual'

  # --- sensores de brilho adaptativo (SensorService fica, p/ rotacao de tela) ---
  'SensrSvc'                                 = 'Manual'
  'DisplayEnhancementService'                = 'Manual'

  # --- condicionais: so entram se o hardware/uso permitir (ver secao 0 do Otimizar) ---
  'bthserv'                                  = 'Manual'      # so sem radio Bluetooth
  'BTAGService'                              = 'Manual'      # idem
  'BthAvctpSvc'                              = 'Manual'      # idem
  'WbioSrvc'                                 = 'Manual'      # so sem biometria (Windows Hello)
  'BDESVC'                                   = 'Manual'      # so sem BitLocker ativo
  'iphlpsvc'                                 = 'Automatic'   # so sem virtualizacao (WSL usa portproxy)

  # --- bloatware de fabricante ---
  # Servico que nao existir na maquina e ignorado, entao a lista cobre varios
  # fabricantes sem risco para quem tem so um deles. NAO entram aqui, de proposito:
  # gestao termica (esifsvc / DPTF / Dell Power Manager), pilha Bluetooth de driver
  # (RtkBtManServ), armazenamento (RstMwService) e audio de fabricante.
  'igfxCUIService2.0.0.0'                    = 'Automatic'
  'WavesSysSvc'                              = 'Automatic'
  'RtkAudioUniversalService'                 = 'Automatic'
  'RtkAudioService'                          = 'Automatic'
  'NvTelemetryContainer'                     = 'Automatic'
  # Dell
  'DellClientManagementService'              = 'Automatic'
  'SupportAssistAgent'                       = 'Automatic'
  'SupportAssistAppService'                  = 'Automatic'
  'DellDataVault'                            = 'Automatic'
  'DDVDataCollector'                         = 'Automatic'
  'DDVRulesProcessor'                        = 'Automatic'
  'DDVCollectorSvcApi'                       = 'Automatic'
  'DellTechHub'                              = 'Automatic'
  'DellCustomerConnect'                      = 'Automatic'
  # HP
  'HPSupportSolutionsFrameworkService'       = 'Automatic'
  'HPTouchpointAnalyticsService'             = 'Automatic'
  'hpqwmiex'                                 = 'Automatic'
  'HPAppHelperCap'                           = 'Automatic'
  'HPDiagsCap'                               = 'Automatic'
  'HPNetworkCap'                             = 'Automatic'
  'HPSysInfoCap'                             = 'Automatic'
  'HPPrintScanDoctorService'                 = 'Automatic'
  # Lenovo (ImControllerService cuida tambem do Lenovo System Update)
  'LenovoVantageService'                     = 'Automatic'
  'ImControllerService'                      = 'Automatic'
  # Asus
  'ASUSSoftwareManager'                      = 'Automatic'
  'ASUSSystemAnalysis'                       = 'Automatic'
  'ASUSSystemDiagnosis'                      = 'Automatic'
  'ASUSLinkNear'                             = 'Automatic'
  'ASUSLinkRemote'                           = 'Automatic'
  'ASUSSwitch'                               = 'Automatic'

  # --- updaters de terceiros ---
  'edgeupdate'                               = 'Automatic'
  'edgeupdatem'                              = 'Manual'
  'MicrosoftEdgeElevationService'            = 'Manual'
  'gupdate'                                  = 'Automatic'
  'gupdatem'                                 = 'Manual'
  'GoogleChromeElevationService'             = 'Manual'
  'VSInstallerElevationService'              = 'Manual'
  'brave'                                    = 'Automatic'
  'BraveElevationService'                    = 'Manual'
  'AdobeARMservice'                          = 'Automatic'
  'AdobeUpdateService'                       = 'Automatic'
  'MozillaMaintenance'                       = 'Manual'
}

# Servicos que vao para Manual em vez de Disabled: continuam funcionando sob
# demanda, mas param de subir sozinhos. Desabilitar qualquer um destes quebra
# funcao (Windows Update, reparo do Office, instalador MSI, ponto de restauracao).
$SvcSobDemanda = [ordered]@{
  'wuauserv'       = 'Manual'
  'UsoSvc'         = 'Automatic'
  'BITS'           = 'Manual'
  'InstallService' = 'Manual'
  'ClickToRunSvc'  = 'Automatic'   # Microsoft Office Click-to-Run
  'VSS'            = 'Manual'      # usado por instalador MSI e ponto de restauracao
}

# Servicos por-usuario: o nome real tem sufixo aleatorio por sessao, entao a
# desabilitacao e feita pelo template em HKLM. Padrao do Windows: Start = 2.
$SvcPorUsuario = @(
  'OneSyncSvc','PimIndexMaintenanceSvc','UnistoreSvc','UserDataSvc','MessagingService'
  'CDPUserSvc','BcastDVRUserService','CaptureService','DevicesFlowUserSvc','UdkUserSvc'
)

# ---------------------------------------------------------------------
# Tarefas agendadas
# ---------------------------------------------------------------------
# Caminho de tarefa e invariavel (nao e traduzido), entao a lista funciona em
# qualquer idioma. Reverter percorre exatamente esta lista -- nunca "toda tarefa
# desabilitada da maquina", que ligaria tambem as que ja vinham desligadas.
$Tarefas = @(
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
  '\Microsoft\Windows\Customer Experience Improvement Program\Uploader'
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
  '\Microsoft\Windows\Shell\FamilySafetyUpload'
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
  # Office: com o ClickToRunSvc em Manual, isto elimina o updater residente
  '\Microsoft\Office\Office Automatic Updates 2.0'
  '\Microsoft\Office\Office ClickToRun Service Monitor'
  '\Microsoft\Office\Office Feature Updates'
  '\Microsoft\Office\Office Feature Updates Logon'
  # updaters de terceiros
  '\Git for Windows Updater'
  '\GoogleUpdateTaskMachineCore'
  '\GoogleUpdateTaskMachineUA'
  '\MicrosoftEdgeUpdateTaskMachineCore'
  '\MicrosoftEdgeUpdateTaskMachineUA'
)

# ---------------------------------------------------------------------
# Apps UWP removidos
# ---------------------------------------------------------------------
# NAO remover: Store, DesktopAppInstaller (winget), Terminal, Notepad, SecHealthUI,
# Edge, WebViewHost, AccountsControl, ShellExperienceHost, StartMenuExperienceHost,
# e o proprio Claude.
$AppsUWP = @(
  'Microsoft.BingSearch','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp'
  'Microsoft.Getstarted','Microsoft.WindowsAlarms','Microsoft.WindowsSoundRecorder'
  'Microsoft.WindowsCamera','Microsoft.ZuneMusic','Microsoft.ZuneVideo','Microsoft.YourPhone'
  'Microsoft.Windows.Photos','Microsoft.XboxGameOverlay','Microsoft.XboxGamingOverlay'
  'Microsoft.XboxSpeechToTextOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxGameCallableUI'
  'Microsoft.GamingApp','Microsoft.WidgetsPlatformRuntime','MicrosoftWindows.Client.WebExperience'
  'MicrosoftWindows.CrossDevice','Microsoft.Paint','Microsoft.MSPaint','Microsoft.ScreenSketch'
  'Microsoft.WindowsCalculator','Microsoft.Windows.NarratorQuickStart'
  'Microsoft.Windows.SecureAssessmentBrowser','Microsoft.MicrosoftEdgeDevToolsClient'
  'Microsoft.RawImageExtension','Microsoft.Windows.ParentalControls','Microsoft.WindowsMaps'
  'Microsoft.People','Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection'
  'Microsoft.Todos','Microsoft.OutlookForWindows','Microsoft.Windows.DevHome','Microsoft.Copilot'
  'Microsoft.SkypeApp','Microsoft.MixedReality.Portal','Microsoft.3DBuilder','Microsoft.Print3D'
  'Microsoft.Office.OneNote','Microsoft.WindowsFeedbackHub','Microsoft.549981C3F5F10'
)

# ---------------------------------------------------------------------
# Autostart: padroes de entrada dispensavel em HKLM\...\Run e HKCU\...\Run
# ---------------------------------------------------------------------
$AutostartLixo =
  'RtkNGui|RtI2SBgProc|WavesSvc|RtHDVCpl|Realtek|Nahimic|SecurityHealth|Logi.*Download|LogiLDA|' +
  'EdgeAutoLaunch|OneDrive|Skype|Spotify|Steam|EpicGames|Discord|Adobe|Acrobat|iTunes|' +
  'CCleaner|Dropbox|Teams|GoogleDriveFS|QuickTime|Java|jusched|NvBackend|' +
  'Dell.*Update|SupportAssist|HP.*Update|HPSupport|Lenovo.*Update|Vantage|' +
  'ASUS.*Update|ArmouryCrate|Acer.*Update|MSI.*Update'

# ---------------------------------------------------------------------
# Sessoes de rastreamento ETW (autologger)
# ---------------------------------------------------------------------
$Autologgers = @(
  'AutoLogger-Diagtrack-Listener','SQMLogger','Diagtrack-Listener','WiFiSession'
  'DiagLog','CloudExperienceHostOobe','Circular Kernel Context Logger'
)

# ---------------------------------------------------------------------
# Recursos opcionais legados
# ---------------------------------------------------------------------
# SMB1, WorkFolders e XPS ficam desligados mesmo na reversao: sao superficie de
# ataque ou peso morto que ninguem sente falta. Os dois de $RecursosRestaurar
# voltam porque software antigo ainda depende deles.
$RecursosDesligar  = @('MicrosoftWindowsPowerShellV2Root','SMB1Protocol','WorkFolders-Client',
                       'Printing-XPSServices-Features','MediaPlayback')
$RecursosRestaurar = @('MicrosoftWindowsPowerShellV2Root','MediaPlayback')

# ---------------------------------------------------------------------
# Permissoes de app (CapabilityAccessManager, HKLM)
# ---------------------------------------------------------------------
# Fora daqui de proposito: broadFileSystemAccess, graphicsCaptureProgrammatic,
# graphicsCaptureWithoutBorder, documentsLibrary e downloadsFolder -- podem afetar
# app empacotado que precise ler disco ou capturar tela. E radios, que tiraria de
# apps o controle do radio Bluetooth.
$Permissoes = @(
  'location','userNotificationListener','userAccountInformation','contacts','email'
  'userDataTasks','chat','appDiagnostics','phoneCallHistory','phoneCall','appointments'
)

# ---------------------------------------------------------------------
# Grupos de regra de firewall
# ---------------------------------------------------------------------
# Identificador indireto, nao o nome exibido: "Network Discovery" e traduzido e
# nao casa em Windows que nao esteja em ingles.
$FirewallGrupos = @(
  '@FirewallAPI.dll,-32752'   # Descoberta de Rede
  '@FirewallAPI.dll,-28502'   # Compartilhamento de Arquivos e Impressoras
  '@FirewallAPI.dll,-33002'   # Assistencia Remota
)

# ---------------------------------------------------------------------
# Defender: exclusoes
# ---------------------------------------------------------------------
# Caminhos inexistentes sao filtrados por quem consome a lista.
$DefenderCaminhos = @(
  "$env:USERPROFILE\.local\bin","$env:USERPROFILE\.claude","$env:USERPROFILE\.cache"
  "$env:USERPROFILE\.config","$env:USERPROFILE\.npm","$env:USERPROFILE\.cargo"
  "$env:LOCALAPPDATA\Temp\claude","$env:LOCALAPPDATA\AnthropicClaude","$env:APPDATA\Claude"
  "$env:USERPROFILE\Documents","$env:USERPROFILE\projects","$env:USERPROFILE\source"
  "$env:USERPROFILE\dev","$env:USERPROFILE\repos"
  'C:\Program Files\Git','C:\Program Files\nodejs'
  'C:\Program Files (x86)\Microsoft Visual Studio','C:\Program Files (x86)\Windows Kits'
)
$DefenderProcessos = @(
  'claude.exe','cowork-svc.exe','git.exe','bash.exe','sh.exe','powershell.exe','pwsh.exe'
  'WindowsTerminal.exe','node.exe','npm.exe','python.exe','cl.exe','link.exe','MSBuild.exe'
  'rg.exe','Code.exe'
)

# ---------------------------------------------------------------------
# Chaves de politica apagadas em bloco pela reversao
# ---------------------------------------------------------------------
$PoliticasApagar = @(
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'
  'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
  'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
  'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
  'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient'
  'HKLM:\SOFTWARE\Policies\Microsoft\MRT'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'
  'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'
  'HKLM:\SOFTWARE\Policies\Microsoft\Speech'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messenger'
  'HKLM:\SOFTWARE\Policies\Microsoft\office'
)
