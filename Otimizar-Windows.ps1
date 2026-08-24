<#
.SYNOPSIS
  Otimizacao agressiva de Windows 10/11 para maquinas fracas.
  Alvo: deixar o sistema o mais leve possivel para rodar Claude Code / Claude Desktop.

.DESCRIPTION
  Desabilita servicos, tarefas agendadas, telemetria, indexacao, autostart e apps UWP
  que nao sao necessarios. Ajusta memoria, pagefile, energia e Defender.

  O script se adapta a maquina em que roda. A secao 0 monta um perfil (build do
  Windows, SSD ou HDD, notebook ou desktop, Bluetooth, biometria, BitLocker,
  virtualizacao, dominio/MDM) e as secoes seguintes decidem a partir dele. Nada
  aqui pressupoe o hardware de quem escreveu o script.

  PRESERVA SEMPRE (nao mexe em nenhuma maquina):
    - Gestao termica .. esifsvc / DPTF / Dell Power Manager
    - Audio .......... Audiosrv, AudioEndpointBuilder, codec do fabricante
    - Armazenamento .. RstMwService e demais servicos de driver de disco
    - Rede ........... Dhcp, Dnscache, WlanSvc, nsi, netprofm, Wcmsvc, BFE, firewall
    - Seguranca base . CryptSvc, RpcSs, DcomLaunch, SamSs, gpsvc, Schedule
    - Claude ......... CoworkVMService, AppXSvc, ClipSVC, StateRepository, TokenBroker

  PRESERVA POR DETECCAO (so desabilita quando a maquina nao usa):
    - Bluetooth ...... mantido se houver radio ativo (teclado/mouse BLE)
    - WbioSrvc ....... mantido se houver leitor biometrico (Windows Hello)
    - BDESVC ......... mantido se algum volume estiver com BitLocker ligado
    - iphlpsvc ....... mantido se houver Hyper-V / WSL (portproxy depende dele)
    - SysMain ........ mantido em HDD, onde o SuperFetch ajuda de verdade

.PARAMETER SemDefender
  Tambem tenta desligar a protecao em tempo real do Defender.
  So funciona se a Protecao contra Adulteracao (Tamper Protection) estiver DESLIGADA:
  Seguranca do Windows > Protecao contra virus e ameacas > Gerenciar configuracoes.

.PARAMETER SemVBS
  Desliga VBS e Integridade de Memoria (HVCI). Maior ganho isolado de CPU, mas
  IGNORADO se a maquina usar Hyper-V ou WSL. Em maquina gerenciada, a politica de
  dominio/MDM pode reverter a chave no proximo ciclo.

.PARAMETER SemRemoverApps
  Nao remove nenhum app UWP.

.PARAMETER SemLimpeza
  Pula a limpeza de disco (temp, prefetch, WER, DISM, armazenamento reservado).

.PARAMETER ManterMiniaturas
  Mantem as miniaturas do Explorer. Por padrao elas sao desligadas: e o maior ganho
  de I/O em disco lento, ao custo de icone generico no lugar da previa da imagem.

.PARAMETER ManterPrefetch
  Mantem Prefetcher, SuperFetch e SysMain mesmo em SSD. O script ja preserva os tres
  quando detecta HDD; use esta opcao quando a deteccao nao conseguir determinar o tipo
  de disco (o log avisa) ou quando voce souber que a maquina se beneficia deles.

.PARAMETER TodosUsuarios
  Aplica as preferencias de interface tambem ao hive do usuario padrao, para que
  perfis criados depois ja nascam configurados. Sem isso, so o usuario atual muda.

.EXAMPLE
  .\Otimizar-Windows.ps1
  .\Otimizar-Windows.ps1 -SemDefender -SemVBS
  .\Otimizar-Windows.ps1 -ManterMiniaturas -SemLimpeza

.NOTES
  Reversao: Reverter-Windows.ps1 (mesma pasta).
  Listas de servicos, tarefas e apps: Listas.ps1 (compartilhado com a reversao).
  Reinicie o Windows ao final.
#>
[CmdletBinding()]
param(
  [switch]$SemDefender,
  [switch]$SemVBS,
  [switch]$SemRemoverApps,
  [switch]$SemLimpeza,
  [switch]$ManterMiniaturas,
  [switch]$ManterPrefetch,
  [switch]$TodosUsuarios
)

# ---------------------------------------------------------------------
# Auto-elevacao
# ---------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  Write-Host "Elevando privilegios..." -ForegroundColor Yellow
  $argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
  foreach($p in $PSBoundParameters.Keys){ if($PSBoundParameters[$p] -is [switch] -and $PSBoundParameters[$p]){ $argv += "-$p" } }
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
# Exporta uma chave so na primeira execucao. Sem esse guarda, rodar o script duas
# vezes gravaria por cima do backup uma copia do estado JA otimizado, e a reversao
# passaria a restaurar nada -- em silencio, e sem volta.
function Backup-Chave($chave,$arquivo){
  $p = Join-Path $Base $arquivo
  if(Test-Path $p){ L "  backup preservado (ja existia): $arquivo"; return }
  reg export "$chave" "$p" /y 2>&1 | Out-Null
  if(Test-Path $p){ L "  backup: $arquivo" }else{ L "  backup FALHOU: $arquivo" }
}

$listas = Join-Path $Base 'Listas.ps1'
if(-not (Test-Path $listas)){ Write-Host "Listas.ps1 nao encontrado em $Base" -ForegroundColor Red; Read-Host "ENTER"; return }
. $listas

# =====================================================================
# 0. PERFIL DA MAQUINA
#    Tudo abaixo decide por deteccao, nunca por lista fixa de hardware.
# =====================================================================
$cs    = Get-CimInstance Win32_ComputerSystem
$os    = Get-CimInstance Win32_OperatingSystem
$ramGB = [math]::Round($cs.TotalPhysicalMemory/1GB,2)
$build = [int]$os.BuildNumber
$win11 = $build -ge 22000

# Disco do sistema. Em HDD o SuperFetch e o Prefetcher escondem a latencia de seek:
# desligar deixa boot e abertura de programa MAIS lentos, nao mais rapidos.
# Um volume pode mapear para mais de um disco fisico (Storage Spaces, RAID): basta
# um HDD no conjunto para o comportamento ser de HDD.
$ssd = $null
foreach($tentativa in @(
  { @(Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -EA Stop | Get-Disk | Get-PhysicalDisk).MediaType },
  { @(Get-PhysicalDisk -EA Stop).MediaType })){
  if($null -ne $ssd){ break }
  try{
    $mt = @(& $tentativa) | Where-Object { $_ }
    if($mt.Count){ $ssd = -not ($mt -contains 'HDD') }
  }catch{}
}
$ssdIncerto = $null -eq $ssd
if($ssdIncerto){ $ssd = $true }   # alvo do projeto e SSD; a incerteza vai para o log
$prefetchOff = $ssd -and -not $ManterPrefetch

$notebook  = [bool](Get-CimInstance Win32_Battery -EA SilentlyContinue)
$bluetooth = [bool](Get-PnpDevice -Class Bluetooth -Status OK -EA SilentlyContinue)
$biometria = [bool](Get-PnpDevice -Class Biometric -Status OK -EA SilentlyContinue)
$bitlocker = [bool](Get-BitLockerVolume -EA SilentlyContinue | Where-Object ProtectionStatus -eq 'On')
$virtual   = [bool](Get-Service vmms,WSLService,LxssManager,vmcompute -EA SilentlyContinue |
                    Where-Object StartType -ne 'Disabled')
$gerenciada = $cs.PartOfDomain -or [bool](
  Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -EA SilentlyContinue |
  Where-Object { (Get-ItemProperty $_.PSPath -EA SilentlyContinue).EnrollmentState -eq 1 })

L "===== OTIMIZACAO WINDOWS - $(Get-Date) ====="
L "Maquina : $($cs.Manufacturer) $($cs.Model)"
L "SO      : $($os.Caption) build $build"
L "RAM     : $ramGB GB"
L "Perfil  : win11=$win11 ssd=$ssd notebook=$notebook bluetooth=$bluetooth biometria=$biometria"
L "          bitlocker=$bitlocker virtualizacao=$virtual gerenciada=$gerenciada"
L "Opcoes  : SemDefender=$SemDefender SemVBS=$SemVBS SemRemoverApps=$SemRemoverApps"
L "          SemLimpeza=$SemLimpeza ManterMiniaturas=$ManterMiniaturas ManterPrefetch=$ManterPrefetch"
L "          TodosUsuarios=$TodosUsuarios"
if($gerenciada){ L "[!] Maquina gerenciada - politica de dominio/MDM pode reverter parte destas chaves" }
if($ssdIncerto){ L "[!] Tipo de disco indeterminado - assumindo SSD. Se for HDD, rode com -ManterPrefetch" }

# Instalador pesado em andamento? Nao mexer em %TEMP% nem no DISM.
$busy = [bool](Get-Process -Name 'vs_BuildTools','vs_setup_bootstrapper','setup','winsdksetup','msiexec','TiWorker','TrustedInstaller' -EA SilentlyContinue)
if($busy){ L "[!] Instalador/servicing ATIVO - %TEMP%, SoftwareDistribution e DISM serao preservados" }

# =====================================================================
# 1. SERVICOS
# =====================================================================
# Servico so entra na lista se a condicao do perfil permitir. Cada linha aqui
# substitui uma excecao que antes so existia como comentario no README.
$condicao = @{
  'bthserv'     = -not $bluetooth
  'BTAGService' = -not $bluetooth
  'BthAvctpSvc' = -not $bluetooth
  'WbioSrvc'    = -not $biometria
  'BDESVC'      = -not $bitlocker
  'iphlpsvc'    = -not $virtual
  'SysMain'     = $prefetchOff
}
$off = @($SvcPadrao.Keys | Where-Object { -not $condicao.ContainsKey($_) -or $condicao[$_] })
if($busy){ $off = $off | Where-Object { $_ -ne 'VSInstallerElevationService' } }

foreach($k in $condicao.Keys | Sort-Object){
  if(-not $condicao[$k]){ L "  preservado por deteccao: $k" }
}

L "`n--- Servicos desabilitados ---"
$okS=0; $naS=0
foreach($s in $off){
  if(-not (Get-Service -Name $s -EA SilentlyContinue)){ $naS++; continue }
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
L "  total: $okS desabilitados | $naS nao existem nesta instalacao"

L "`n--- Servicos sob demanda (Manual) ---"
foreach($s in $SvcSobDemanda.Keys){
  if(-not (Get-Service -Name $s -EA SilentlyContinue)){ L "  n/a     $s"; continue }
  try{ Set-Service $s -StartupType Manual -EA Stop; L "  OK      $s" }catch{ L "  FALHOU  $s" }
}

# Servicos por-usuario tem sufixo aleatorio: desabilitar pelo template em HKLM
L "`n--- Servicos por-usuario (template HKLM) ---"
foreach($t in $SvcPorUsuario){
  $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$t"
  if(Test-Path $k){ S $k 'Start' 4; L "  OK      $t" }
}

# =====================================================================
# 2. TAREFAS AGENDADAS
# =====================================================================
L "`n--- Tarefas agendadas ---"
$okT=0
foreach($t in $Tarefas){
  $p = Split-Path $t -Parent; if($p -notmatch '\\$'){ $p += '\' }
  try{ Disable-ScheduledTask -TaskPath $p -TaskName (Split-Path $t -Leaf) -EA Stop | Out-Null; $okT++ }catch{}
}
L "  desabilitadas: $okT de $($Tarefas.Count) (as demais nao existem nesta instalacao)"

# =====================================================================
# 3. AUTOSTART
# =====================================================================
L "`n--- Autostart ---"
$runHKLM = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$runHKCU = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
Backup-Chave 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'backup-Run-HKLM.reg'
Backup-Chave 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'backup-Run-HKCU.reg'

foreach($k in $runHKLM,$runHKCU){
  if(Test-Path $k){
    (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
      if($_.Name -match $AutostartLixo -or $_.Value -match $AutostartLixo){
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
if($prefetchOff){
  S "$mm\PrefetchParameters" 'EnablePrefetcher' 0
  S "$mm\PrefetchParameters" 'EnableSuperfetch' 0
  L "  prefetch/superfetch OFF (SSD)"
}else{
  L ("  prefetch/superfetch e SysMain MANTIDOS (" + $(if($ManterPrefetch){'-ManterPrefetch'}else{'HDD detectado'}) + ")")
}
S 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 26
S 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000' 'String'
S 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
L "  prioridade p/ foreground | power throttling OFF"

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
# 6. TELEMETRIA / NUVEM / POLITICAS (HKLM)
# =====================================================================
L "`n--- Telemetria e politicas (HKLM) ---"
$dc='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
S $dc 'AllowTelemetry' 0; S $dc 'DoNotShowFeedbackNotifications' 1
S $dc 'AllowDeviceNameInTelemetry' 0; S $dc 'LimitDiagnosticLogCollection' 1
S $dc 'LimitDumpCollection' 1; S $dc 'DisableOneSettingsDownloads' 1
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
$ac='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
S $ac 'AITEnable' 0; S $ac 'DisableInventory' 1; S $ac 'DisableUAR' 1; S $ac 'DisablePCA' 1
$cc='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
S $cc 'DisableWindowsConsumerFeatures' 1; S $cc 'DisableSoftLanding' 1
S $cc 'DisableCloudOptimizedContent' 1; S $cc 'DisableConsumerAccountStateContent' 1
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
S 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
S 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
S 'HKLM:\SOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 1        # sem MSRT mensal pelo WU
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput' 'AllowLinguisticDataCollection' 0
S 'HKLM:\SOFTWARE\Microsoft\MdmCommon\SettingValues' 'LocationSyncEnabled' 0

# --- Copilot / Recall: dependem da versao do Windows ---
if($win11){
  S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
}
if($build -ge 26100){    # Recall so existe a partir do 24H2
  S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
  S 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
  S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableSettingsAgent' 1
  L "  Recall e agente de configuracoes desligados (build >= 26100)"
}

# --- apps em segundo plano ---
$ap='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
S $ap 'LetAppsRunInBackground' 2      # 2 = forcar negacao
S $ap 'LetAppsSyncWithDevices' 2
S 'HKLM:\SOFTWARE\Policies\Microsoft' 'DisablePushToInstall' 1

# --- CEIP / SQM ---
S 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messenger\Client' 'CEIP' 2
S 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable' 0

# --- relatorio de erros (WER) ---
$wer='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
S $wer 'Disabled' 1; S $wer 'DontSendAdditionalData' 1; S $wer 'AutoApproveOSDumps' 0
S $wer 'LoggingDisabled' 1

# --- linha do tempo / historico de atividades / experiencias compartilhadas ---
$sys='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
S $sys 'EnableActivityFeed' 0; S $sys 'PublishUserActivities' 0; S $sys 'UploadUserActivities' 0
S $sys 'EnableCdp' 0
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
S $ws 'AllowIndexingEncryptedStoresOrItems' 0
S $ws 'ConnectedSearchPrivacy' 3
S $ws 'EnableDynamicContentInWSB' 0                                      # destaques de pesquisa

# --- sincronizacao de configuracoes e WiFi Sense ---
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSync' 2
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSyncUserOverride' 1
S 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' 'Value' 0
S 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'Value' 0
S 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\features' 'WiFiSenseCredShared' 0
S 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\features' 'WiFiSenseOpen' 0

# --- Edge ---
$ed='HKLM:\SOFTWARE\Policies\Microsoft\Edge'
S $ed 'MetricsReportingEnabled' 0; S $ed 'SendSiteInfoToImproveServices' 0
S $ed 'PersonalizationReportingEnabled' 0; S $ed 'UserFeedbackAllowed' 0
S $ed 'DiagnosticData' 0; S $ed 'SpotlightExperiencesAndRecommendationsEnabled' 0
S $ed 'StartupBoostEnabled' 0; S $ed 'BackgroundModeEnabled' 0
S $ed 'HubsSidebarEnabled' 0; S $ed 'ShowRecommendationsEnabled' 0
S $ed 'DefaultGeolocationSetting' 2; S $ed 'DefaultNotificationsSetting' 2
S $ed 'DefaultSensorsSetting' 2
S 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'RemoveDesktopShortcutDefault' 1
S 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0

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

# --- permissoes de app para a maquina inteira (nao so o usuario atual) ---
$csm='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
foreach($c in $Permissoes){ S "$csm\$c" 'Value' 'Deny' 'String' }
L "  aplicado ($($Permissoes.Count) permissoes de app negadas em HKLM)"

# --- sessoes de rastreamento ETW (autologger) ---
# Nao mexemos no arquivo hosts: bloquear dominios da Microsoft por ali quebra
# Windows Update e Store, e volta a valer a cada atualizacao de recurso.
L "`n--- Sessoes de rastreamento ETW ---"
$okE=0
foreach($al in $Autologgers){
  $k = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$al"
  if(Test-Path $k){ S $k 'Start' 0; S $k 'Enabled' 0; $okE++; L "  OK      $al" }
}
L "  total: $okE"

# --- VBS / Integridade de Memoria ---
if($SemVBS){
  L "`n--- VBS / HVCI ---"
  if($virtual){
    L "  -SemVBS IGNORADO: Hyper-V/WSL em uso nesta maquina"
  }else{
    if($gerenciada){ L "  [!] maquina gerenciada: a politica pode reverter esta chave" }
    S 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
    S 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
    L "  VBS/HVCI desligados (efetivo apos reiniciar)"
  }
}

# =====================================================================
# 7. PREFERENCIAS DO USUARIO
#    A mesma funcao serve para o usuario atual e para o hive do usuario padrao,
#    de onde perfis novos sao copiados.
# =====================================================================
function Aplicar-Usuario($raiz){
  $adv = "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
  $cdm = "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
  $pex = "$raiz\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
  $bsc = "$raiz\Software\Microsoft\Windows\CurrentVersion\Search"

  S "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" 'VisualFXSetting' 2
  S "$raiz\Control Panel\Desktop\WindowMetrics" 'MinAnimate' '0' 'String'
  S "$raiz\Control Panel\Desktop" 'MenuShowDelay' '0' 'String'
  S "$raiz\Control Panel\Desktop" 'DragFullWindows' '0' 'String'
  S "$raiz\Control Panel\Desktop" 'AutoEndTasks' '1' 'String'
  S "$raiz\Control Panel\Desktop" 'HungAppTimeout' '2000' 'String'
  S "$raiz\Control Panel\Desktop" 'WaitToKillAppTimeout' '2000' 'String'
  try{
    if(-not(Test-Path "$raiz\Control Panel\Desktop")){ New-Item "$raiz\Control Panel\Desktop" -Force | Out-Null }
    New-ItemProperty "$raiz\Control Panel\Desktop" -Name 'UserPreferencesMask' `
      -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -PropertyType Binary -Force | Out-Null
  }catch{}
  S "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'EnableTransparency' 0
  S "$raiz\SOFTWARE\Microsoft\Windows\DWM" 'EnableAeroPeek' 0
  S "$raiz\SOFTWARE\Microsoft\Windows\DWM" 'AlwaysHibernateThumbnails' 0

  foreach($n in 'TaskbarAnimations','ListviewAlphaSelect','ListviewShadow','ShowTaskViewButton',
                'Start_TrackDocs','Start_TrackProgs','ShowSyncProviderNotifications',
                'ShowInfoTip','FolderContentsInfoTip','ShowPreviewHandlers'){ S $adv $n 0 }
  S $adv 'IconsOnly' 1
  # Widgets, chat e Copilot na barra: so existem no Windows 11
  if($win11){
    foreach($n in 'TaskbarDa','TaskbarMn','ShowCopilotButton','Start_IrisRecommendations',
                  'Start_AccountNotifications'){ S $adv $n 0 }
  }

  # I/O do Explorer: miniatura e o item mais visivel, entao tem escape proprio
  S $pex 'NoResolveSearch' 1
  S $pex 'NoResolveTrack' 1
  S $pex 'LinkResolveIgnoreLinkInfo' 1
  if(-not $ManterMiniaturas){ S $pex 'DisableThumbnails' 1 }

  S $bsc 'SearchboxTaskbarMode' 0
  S $bsc 'BingSearchEnabled' 0
  S $bsc 'CortanaConsent' 0
  S $bsc 'BackgroundAppGlobalToggle' 0
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\SearchSettings" 'IsDeviceSearchHistoryEnabled' 0
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" 'GlobalUserDisabled' 1
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" 'StartupDelayInMSec' 0

  foreach($n in 'ContentDeliveryAllowed','FeatureManagementEnabled','OemPreInstalledAppsEnabled',
   'PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled',
   'SubscribedContentEnabled','SubscribedContent-310093Enabled','SubscribedContent-338388Enabled',
   'SubscribedContent-338389Enabled','SubscribedContent-338393Enabled','SubscribedContent-353694Enabled',
   'SubscribedContent-353696Enabled','SubscribedContent-338387Enabled','SubscribedContent-88000326Enabled',
   'SystemPaneSuggestionsEnabled','RotatingLockScreenEnabled','RotatingLockScreenOverlayEnabled'){ S $cdm $n 0 }
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" 'ScoobeSystemSettingEnabled' 0

  S "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" 'Enabled' 0
  S "$raiz\Software\Microsoft\Siuf\Rules" 'NumberOfSIUFInPeriod' 0
  S "$raiz\Software\Microsoft\Siuf\Rules" 'PeriodInNanoSeconds' 0
  S "$raiz\Software\Microsoft\InputPersonalization" 'RestrictImplicitTextCollection' 1
  S "$raiz\Software\Microsoft\InputPersonalization" 'RestrictImplicitInkCollection' 1
  S "$raiz\Software\Microsoft\InputPersonalization\TrainedDataStore" 'HarvestContacts' 0
  S "$raiz\Software\Microsoft\Personalization\Settings" 'AcceptedPrivacyPolicy' 0
  S "$raiz\Software\Policies\Microsoft\Windows\EdgeUI" 'DisableMFUTracking' 1
  # "experiencias personalizadas com dados de diagnostico"
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\Privacy" 'TailoredExperiencesWithDiagnosticDataEnabled' 0
  S "$raiz\Software\Policies\Microsoft\Windows\CloudContent" 'DisableTailoredExperiencesWithDiagnosticData' 1
  # reconhecimento de voz online
  S "$raiz\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" 'HasAccepted' 0
  S "$raiz\Software\Microsoft\MediaPlayer\Preferences" 'UsageTracking' 0
  # acesso de apps a localizacao (o servico lfsvc ja foi desabilitado acima)
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" 'Value' 'Deny' 'String'
  S "$raiz\System\GameConfigStore" 'GameDVR_Enabled' 0
  S "$raiz\System\GameConfigStore" 'GameDVR_FSEBehaviorMode' 2
  S "$raiz\Software\Microsoft\GameBar" 'AutoGameModeEnabled' 0
  S "$raiz\Software\Microsoft\GameBar" 'ShowStartupPanel' 0
}

L "`n--- Interface e privacidade do usuario ---"
foreach($p in @(@{k='HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; f='backup-Explorer-Advanced.reg'},
                @{k='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; f='backup-ContentDelivery.reg'},
                @{k='HKCU\Control Panel\Desktop'; f='backup-ControlPanel-Desktop.reg'},
                @{k='HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; f='backup-Search.reg'})){
  Backup-Chave $p.k $p.f
}
Aplicar-Usuario 'HKCU:'
L "  aplicado ao usuario atual"

if($TodosUsuarios){
  $ntuser = "$env:SystemDrive\Users\Default\NTUSER.DAT"
  if(Test-Path $ntuser){
    if(-not (Get-PSDrive -Name HKU -EA SilentlyContinue)){
      New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -Scope Script | Out-Null
    }
    reg load 'HKU\PadraoOtim' "$ntuser" 2>&1 | Out-Null
    if(Test-Path 'HKU:\PadraoOtim'){
      Aplicar-Usuario 'HKU:\PadraoOtim'
      # sem o Collect o PowerShell segura handles do hive e o unload falha
      [gc]::Collect(); [gc]::WaitForPendingFinalizers()
      reg unload 'HKU\PadraoOtim' 2>&1 | Out-Null
      L "  aplicado ao hive do usuario padrao (perfis novos ja nascem configurados)"
    }else{ L "  hive do usuario padrao: nao foi possivel carregar" }
  }
}

# =====================================================================
# 8. ENERGIA
# =====================================================================
L "`n--- Energia ---"
# "Alto desempenho" e a escolha certa em desktop e a errada em notebook fanless,
# que segura o clock alto ate bater o limite termico e ai sofre throttling.
# E em build recente do Windows 11 o plano classico nem existe: virou overlay.
$alto = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
if($notebook){
  powercfg -setactive SCHEME_BALANCED 2>&1 | Out-Null
  L "  notebook: plano Equilibrado (evita throttling termico)"
}else{
  if(-not (powercfg /list | Select-String $alto)){ powercfg -duplicatescheme $alto 2>&1 | Out-Null }
  if(powercfg /list | Select-String $alto){
    powercfg -setactive $alto 2>&1 | Out-Null
    L "  desktop: plano Alto desempenho"
  }else{
    powercfg /overlaysetactive ded574b5-45a0-4f42-8737-46345c09c238 2>&1 | Out-Null
    L "  desktop: overlay Melhor desempenho (plano classico indisponivel)"
  }
}
powercfg -h off 2>&1 | Out-Null                          # sem hibernacao/fast startup
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 50  2>&1 | Out-Null
powercfg -setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0 2>&1 | Out-Null
powercfg -setdcvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0 2>&1 | Out-Null
powercfg -change -hibernate-timeout-ac 0 2>&1 | Out-Null
powercfg -change -hibernate-timeout-dc 0 2>&1 | Out-Null
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
  foreach($p in ($DefenderCaminhos | Where-Object { Test-Path $_ })){
    try{ Add-MpPreference -ExclusionPath $p -EA Stop; L "  excl: $p" }catch{}
  }
  foreach($p in $DefenderProcessos){ try{ Add-MpPreference -ExclusionProcess $p -EA Stop }catch{} }
  L ("  excl. processos: " + ($DefenderProcessos -join ', '))

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
  foreach($a in $AppsUWP){
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
# 11. RECURSOS OPCIONAIS LEGADOS E FIREWALL
# =====================================================================
foreach($f in $RecursosDesligar){
  try{ $st = Get-WindowsOptionalFeature -Online -FeatureName $f -EA Stop
       if($st.State -eq 'Enabled'){
         Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -EA Stop | Out-Null
         L "`n  recurso desabilitado: $f" } }catch{}
}

# Descoberta de rede e compartilhamento: complementa o LanmanServer desabilitado.
# Pelo identificador do grupo, nao pelo nome exibido -- que e traduzido.
L "`n--- Firewall ---"
foreach($g in $FirewallGrupos){
  $r = Get-NetFirewallRule -Group $g -EA SilentlyContinue
  if($r){ $r | Disable-NetFirewallRule -EA SilentlyContinue; L "  desabilitado: $g ($($r.Count) regras)" }
  else  { L "  n/a     $g" }
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

  # Armazenamento reservado: libera tipicamente ~7 GB. O cmdlet devolve enum, ao
  # contrario da saida de texto do DISM, que muda de idioma.
  if(-not $busy -and (Get-Command Get-WindowsReservedStorageState -EA SilentlyContinue)){
    try{
      if((Get-WindowsReservedStorageState).ReservedStorageState -eq 'Enabled'){
        Set-WindowsReservedStorageState -State Disabled -EA Stop
        L "  armazenamento reservado desabilitado (~7 GB, efetivo apos reiniciar)"
      }
    }catch{ L "  armazenamento reservado: nao aplicado (atualizacao pendente?)" }
  }

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
