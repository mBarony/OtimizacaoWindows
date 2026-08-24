# Proposta de mudanças — OtimizacaoWindows

Comparação de `mBarony/OtimizacaoWindows` contra `AFaustini/OtimizeWindows` e o fork
`mBarony/OtimizeWindows`, com as melhorias que valem ser absorvidas.

Corpus analisado: `Otimizacao11.bat` (691 linhas), `Otimizacao10.bat` (772), `Otimizacao_Insider.bat`
(163), `Edge.bat` (25), contra `Otimizar-Windows.ps1` (624) e `Reverter-Windows.ps1` (183).

**Premissa:** o `OtimizacaoWindows` tem que rodar em qualquer máquina. Nenhuma decisão pode depender
de como está a máquina em que ele foi escrito. Onde este documento cita uma medição, ela serve de
**contraexemplo** — mostra um caso em que o script atual erra —, nunca de critério de inclusão.

---

## Status: aplicado

As seções 3, 4, 5, 6.1 e 9 estão implementadas. O documento fica como registro do raciocínio por
trás de cada escolha — em especial das rejeições da §8, que não deixam rastro no código.

Aplicado, com um extra que apareceu na implementação: `-ManterPrefetch`, escape para quando a
detecção de disco não consegue determinar o tipo (Storage Spaces, RAID, consulta negada).

Deliberadamente **não** aplicado:

- **§7 cosméticos** — são preferência, não desempenho.
- **§6.2 `-SemSmartScreen`** — rebaixa segurança sem ganho mensurável; fica registrado como opção
  caso você mude de ideia.
- **Itens só do Windows 10** da §3.4 (políticas do Edge legado, app Cortana) — o gate `if($win11)`
  existe e protege o 10 do que é exclusivo do 11, mas o caminho inverso não foi preenchido. Se o
  alvo for mesmo "Windows 10/11", falta esse bloco; se for só o 11, o README é que precisa mudar.

---

## 1. Como os três repositórios se relacionam

| Repo | Papel | Estado |
|---|---|---|
| `AFaustini/OtimizeWindows` | upstream, `.bat` | HEAD `a9adca1` "Varios atualizações de privacidade" |
| `mBarony/OtimizeWindows` | fork do acima | 1 commit atrás; único arquivo divergente é `Otimizacao11.bat` |
| `mBarony/OtimizacaoWindows` | reescrita própria em PowerShell | independente, com reversão e log |

A única diferença real entre o fork e o upstream é o commit `a9adca1`, que acrescentou um bloco de
telemetria/privacidade (`PreventDeviceMetadataFromNetwork`, `DisablePushToInstall`,
`DisableSettingSync`, `ConnectedSearchPrivacy`, `LocationSyncEnabled`, `DisableSettingsAgent`).

### 1.1 A contribuição do fork foi perdida num merge

Os commits `e7c12df` / `1fa3395` ("maintain hyper-v") comentavam de propósito:

```bat
REM DISM.exe /Online /norestart /Disable-Feature /featurename:Microsoft-Hyper-V-All /Remove
REM reg add "...\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f
```

O merge de `9c5ec36` ("Add files via upload") sobrescreveu o arquivo inteiro e desfez isso. Hoje
`OtimizeWindows_barony/Otimizacao11.bat:451` volta a desabilitar o HVCI ativamente. No fork, vale
reaplicar os `REM` ou abrir PR no upstream — senão o próximo `pull` apaga a intenção de novo.

Para esta proposta o que importa é a lição de projeto: **desligar Hyper-V ou HVCI quebra máquina que
usa virtualização**. Num script genérico isso não se resolve por opinião, e sim por detecção (§3.4).

---

## 2. O que o PS1 já faz melhor — não regredir

| Área | `.bat` | `Otimizar-Windows.ps1` |
|---|---|---|
| Reversão | não existe | `Reverter-Windows.ps1` + backup `.reg` do autostart |
| Log | `ECHO` na tela | arquivo `otimizacao-AAAAMMDD-HHMMSS.log` |
| Serviço inexistente | `sc config` falha ruidosamente | `if(Get-Service ...)` e fallback via registro |
| Pagefile | `wmic pagefileset delete` (remove) | fixo, dimensionado pela RAM |
| Defender | tudo ou nada, comentado | exclusões + limite de CPU, `-SemDefender` opcional |
| Adaptação | nenhuma | detecta RAM, detecta instalador ativo, preserva `%TEMP%\claude` |

A última linha é a que importa para o resto do documento. O script **já tem** o padrão certo em dois
pontos: `DisablePagingExecutive` só entra se houver 8 GB, e o pagefile é dimensionado pela RAM. Falta
estender esse mesmo padrão ao resto.

---

## 3. Generalidade — o principal trabalho a fazer

Hoje o script carrega decisões que só valem para a máquina em que foi escrito, na forma de **listas
fixas e exceções documentadas em prosa**. O README explica que o Bluetooth é preservado "foi o caso da
máquina de teste, cujo teclado era BLE", e que o `esifsvc` fica porque "em tablets e ultrabooks sem
ventoinha, desabilitar causa superaquecimento". Ambas as regras estão certas — mas estão codificadas
como *ausência* de um item numa lista, o que significa que a máquina que **não** tem teclado
Bluetooth paga o preço da exceção sem precisar.

A mudança estruturante é transformar cada exceção dessas numa condição avaliada em tempo de execução.

### 3.1 Bloco de perfil, no início do script

```powershell
# =====================================================================
# 0. PERFIL DA MAQUINA - tudo abaixo decide por deteccao, nao por lista fixa
# =====================================================================
$os    = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
$win11 = $build -ge 22000

# disco do sistema: SSD ou HDD
$ssd = $true
try{
  $ssd = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -EA Stop |
          Get-Disk | Get-PhysicalDisk).MediaType -ne 'HDD'
}catch{}

# notebook? decide plano de energia e timeouts
$notebook = [bool](Get-CimInstance Win32_Battery -EA SilentlyContinue)

# radio Bluetooth ativo? se houver, a pilha inteira fica de pe
$bluetooth = [bool](Get-PnpDevice -Class Bluetooth -Status OK -EA SilentlyContinue)

# Windows Hello (digital / facial) em uso?
$biometria = [bool](Get-PnpDevice -Class Biometric -Status OK -EA SilentlyContinue)

# BitLocker ligado em algum volume?
$bitlocker = [bool](Get-BitLockerVolume -EA SilentlyContinue | Where-Object ProtectionStatus -eq 'On')

# virtualizacao em uso: Hyper-V, WSL, Docker, WSA
$virtual = [bool](Get-Service vmms,WSLService,LxssManager -EA SilentlyContinue |
                  Where-Object StartType -ne 'Disabled')

# dominio ou MDM: politica externa pode reverter parte destas chaves
$gerenciada = $cs.PartOfDomain -or [bool](
  Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -EA SilentlyContinue |
  Where-Object { (Get-ItemProperty $_.PSPath -EA SilentlyContinue).EnrollmentState -eq 1 })

L "Perfil  : build=$build win11=$win11 ssd=$ssd notebook=$notebook bluetooth=$bluetooth"
L "          biometria=$biometria bitlocker=$bitlocker virtualizacao=$virtual gerenciada=$gerenciada"
if($gerenciada){ L "[!] Maquina gerenciada - politica de dominio/MDM pode reverter parte destas chaves" }
```

### 3.2 SSD × HDD — a suposição mais cara do script atual

`Otimizar-Windows.ps1` desliga Prefetcher e SuperFetch incondicionalmente, e desabilita o serviço
`SysMain`. Isso está certo em SSD e **errado em disco mecânico**: em HDD o SuperFetch é justamente o
que esconde a latência de seek na abertura de programa e no boot. Numa máquina fraca com HDD — que é
exatamente o público do projeto — a otimização deixa o sistema mais lento.

```powershell
if($ssd){
  S "$mm\PrefetchParameters" 'EnablePrefetcher'  0
  S "$mm\PrefetchParameters" 'EnableSuperfetch'  0
}else{
  $off = $off | Where-Object { $_ -ne 'SysMain' }
  L "  HDD detectado: prefetch/superfetch e SysMain MANTIDOS"
}
```

O mesmo raciocínio vale para `fsutil behavior set disablelastaccess 1`: o ganho é maior em HDD e
quase nulo em SSD, mas é inofensivo nos dois — pode ficar incondicional.

### 3.3 Hardware: exceção vira condição

Cada linha abaixo substitui uma exceção que hoje só existe como comentário no README.

```powershell
if(-not $bluetooth){ $off += 'bthserv','BTAGService','BthAvctpSvc','BluetoothUserService' }
if(-not $biometria){ $off += 'WbioSrvc' }
if(-not $bitlocker){ $off += 'BDESVC' }
if(-not $virtual)  { $off += 'iphlpsvc' }   # WSL2 usa portproxy, que depende do IP Helper
```

Gestão térmica (`esifsvc`, DPTF, Dell Power Manager) continua fora da lista sempre — não existe
máquina em que desabilitá-la ajude, então não precisa de condição.

### 3.4 Windows 10 × Windows 11

O upstream mantém `Otimizacao10.bat` e `Otimizacao11.bat` separados por um motivo. O
`OtimizacaoWindows` é um arquivo só e aplica tudo nos dois, o que gera escrita morta numa ponta e
tweak faltando na outra.

```powershell
if($win11){
  S $adv 'ShowCopilotButton' 0
  S $adv 'TaskbarDa' 0          # widgets
  S $adv 'TaskbarMn' 0          # chat/Teams
  S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
  S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
}
if($build -ge 26100){          # Recall so existe a partir do 24H2
  S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
  S 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
}
```

Do lado do Windows 10, o `Otimizacao10.bat` tem itens que o PS1 não cobre e que **não existem** no 11
— políticas do Edge legado (`MicrosoftEdge\Main\AllowPrelaunch`, `TabPreloader`) e o app Cortana.
Escrevê-las no 11 é inofensivo mas morto; a decisão honesta é ou incluí-las sob `if(-not $win11)`,
ou declarar no README que o alvo é Windows 11 e parar de dizer "Windows 10/11".

### 3.5 Energia por tipo de máquina

O plano fixo "Alto desempenho" é a escolha errada num notebook fanless: segura o clock alto até bater
o limite térmico e aí sofre *throttling*. Já num desktop é a escolha certa. E o plano clássico nem
sempre existe — em builds recentes do Windows 11 o `powercfg /list` traz **só o Equilibrado**, porque
"Alto desempenho" virou *overlay*. O `powercfg -setactive SCHEME_MIN` da linha 471 falha em silêncio
nessas máquinas, e o log ainda imprime "Equilibrado" como se tivesse dado certo.

```powershell
$alto = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
if($notebook){
  powercfg -setactive SCHEME_BALANCED 2>&1 | Out-Null
}else{
  if(-not (powercfg /list | Select-String $alto)){ powercfg -duplicatescheme $alto 2>&1 | Out-Null }
  if(powercfg /list | Select-String $alto){ powercfg -setactive $alto 2>&1 | Out-Null }
  else{ powercfg /overlaysetactive ded574b5-45a0-4f42-8737-46345c09c238 2>&1 | Out-Null }
}
powercfg -h off 2>&1 | Out-Null
powercfg -setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0 2>&1 | Out-Null
powercfg -setactive SCHEME_CURRENT 2>&1 | Out-Null
```

Os ajustes finos do `.bat` (`monitor-timeout`, `standby-timeout`, ação da tampa e do botão liga)
valem ser trazidos junto — são independentes de plano e sobrevivem à troca.

### 3.6 Independência de idioma

Num script que roda em qualquer máquina, todo texto de saída de comando é armadilha. Dois pontos:

- **Firewall.** `netsh advfirewall firewall set rule group="Network Discovery"` — usado pelo `.bat` —
  não funciona em Windows em português, porque o nome do grupo é localizado. A forma correta usa o
  identificador indireto, que é invariável.
- **Armazenamento reservado.** Testar a saída de `DISM /Online /Get-ReservedStorageState` com
  `-match 'Enabled'` quebra em pt-BR. O cmdlet retorna enum e não depende de idioma.

```powershell
foreach($g in '@FirewallAPI.dll,-32752',   # Descoberta de Rede
              '@FirewallAPI.dll,-28502',   # Compart. de Arquivos e Impressoras
              '@FirewallAPI.dll,-33002'){  # Assistencia Remota
  Get-NetFirewallRule -Group $g -EA SilentlyContinue | Disable-NetFirewallRule -EA SilentlyContinue
}

if((Get-WindowsReservedStorageState -EA SilentlyContinue).ReservedStorageState -eq 'Enabled'){
  Set-WindowsReservedStorageState -State Disabled -EA SilentlyContinue
  L "  armazenamento reservado desabilitado (~7 GB)"
}
```

Os caminhos de tarefa agendada (`\Microsoft\Windows\...`) são invariáveis, então a lista `$tasks`
já está segura.

### 3.7 Multiusuário

Todo o bloco HKCU (seção 7 do script) aplica-se só ao usuário que rodou. Numa máquina com mais de um
perfil, os demais ficam com widgets, sugestões e telemetria de interface intactos. O caminho barato,
sem duplicar o bloco, é extrair uma função e chamá-la duas vezes — a segunda sobre o hive do usuário
padrão, para que perfis novos já nasçam configurados.

```powershell
function Aplicar-Usuario($raiz){    # $raiz = 'HKCU:' ou 'HKU:\Padrao'
  S "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" 'VisualFXSetting' 2
  # ... o restante da secao 7, trocando HKCU: por $raiz
}
Aplicar-Usuario 'HKCU:'
reg load 'HKU\Padrao' "$env:SystemDrive\Users\Default\NTUSER.DAT" 2>&1 | Out-Null
Aplicar-Usuario 'HKU:\Padrao'
[gc]::Collect(); reg unload 'HKU\Padrao' 2>&1 | Out-Null
```

O `[gc]::Collect()` antes do `unload` não é firula: sem ele o PowerShell segura handles do hive e o
`reg unload` falha.

### 3.8 O log tem que distinguir "não se aplica" de "falhou"

Numa máquina desconhecida, silêncio é ambíguo. Hoje um serviço ausente é pulado sem registro, então
o operador não tem como saber se o item não existia ou se a escrita foi negada. O laço de serviços já
distingue os dois casos internamente — falta só registrar o terceiro:

```powershell
else{ L ("  n/a     $s  (nao existe nesta instalacao)") }
```

E o resumo final ganha uma linha por decisão de perfil, para que o log explique sozinho por que tal
bloco não rodou.

---

## 4. Bugs a corrigir

### B1 — segunda execução destrói o backup do autostart

`Otimizar-Windows.ps1:~248` exporta os `.reg` do `Run` com `/y`, incondicionalmente:

```powershell
reg export "HKLM\SOFTWARE\...\Run" (Join-Path $Base 'backup-Run-HKLM.reg') /y
```

Na segunda execução, a chave já está limpa — o backup passa a ser uma cópia do estado *depois* da
remoção, e as entradas originais se perdem para sempre. O `REVERTER` reimporta um arquivo vazio e não
tem como avisar. É o bug mais grave da lista, porque é silencioso e irreversível.

```powershell
foreach($h in @(@{k='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; f='backup-Run-HKLM.reg'},
                @{k='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; f='backup-Run-HKCU.reg'})){
  $p = Join-Path $Base $h.f
  if(Test-Path $p){ L "  backup preservado (ja existia): $($h.f)" }
  else            { reg export $h.k "$p" /y 2>&1 | Out-Null; L "  backup: $($h.f)" }
}
```

### B2 — o plano de energia nunca é aplicado em build recente

Coberto em §3.5. `powercfg -setactive SCHEME_MIN` com a saída em `Out-Null`: onde o plano clássico
não existe, falha sem deixar rastro.

### B3 — a reversão liga tarefas que ela nunca desligou

`Reverter-Windows.ps1:81`:

```powershell
Get-ScheduledTask | Where-Object State -eq 'Disabled' | Enable-ScheduledTask
```

Habilita *toda* tarefa desabilitada da máquina — inclusive as que vêm assim de fábrica e as que o
dono desligou à mão antes de rodar o script. Percorrer a lista `$tasks` resolve, e passa a ser
trivial depois que ela virar arquivo compartilhado (§9).

### B4 — 31 de 117 escritas de registro não têm reversão

Contado descontando as chaves que o `Reverter` apaga em bloco com `Remove-Item -Recurse`. As que
sobram são quase todas HKCU: `HungAppTimeout`, `WaitToKillAppTimeout`, `EnableAeroPeek`,
`BingSearchEnabled`, `CortanaConsent`, `StartupDelayInMSec`, `ShowCopilotButton`,
`GameDVR_FSEBehaviorMode`, `AcceptedPrivacyPolicy`, e 14 valores do `ContentDeliveryManager`.

Nenhuma é grave, mas o README promete que o `REVERTER` "restaura … e a interface". O caminho barato é
exportar o `.reg` das chaves HKCU tocadas antes de mexer, com o mesmo guarda de B1.

### B5 a B8 — assimetrias menores

- **B5** — `gupdate`, `gupdatem`, `brave` e `BraveElevationService` são desabilitados e nunca
  restaurados. Os outros 91 serviços estão cobertos.
- **B6** — `Otimizar` desabilita 5 recursos opcionais, `Reverter` reabilita 2.
- **B7** — `$ws` é declarado duas vezes para a mesma chave (seções 5 e 6), com 4 valores repetidos.
- **B8** — a reversão liga `AutomaticManagedPagefile` mas deixa a instância `Win32_PageFileSetting`
  criada.

---

## 5. Melhorias a absorver

Critério: o laço de serviços já pula em silêncio o que não existe, e o de tarefas também. Então
**incluir um item a mais custa zero** numa máquina onde ele não se aplica — o filtro certo não é
"isso roda?", e sim "isso quebra alguma função?". O que segue passou por esse filtro; o que reprovou
está em §8 com o motivo.

### 5.1 Serviços

```powershell
# no array $off (secao 1) - incondicionais
$off += 'diagnosticshub.standardcollector.service',  # coletor do Diagnostics Hub (Win10)
        'ShellHWDetection',                          # AutoPlay / midia removivel
        'RemoteAccess','NetTcpPortSharing','SstpSvc','SmsRouter',
        'SharedRealitySvc','perceptionsimulation','WpcMonSvc','TabletInputService'

# condicionais, do bloco de perfil (secao 3.3)
if(-not $bluetooth){ $off += 'bthserv','BTAGService','BthAvctpSvc' }
if(-not $biometria){ $off += 'WbioSrvc' }
if(-not $bitlocker){ $off += 'BDESVC' }
if(-not $virtual)  { $off += 'iphlpsvc' }

# junto do bloco "Windows Update -> sob demanda"
foreach($s in 'wuauserv','UsoSvc','BITS','InstallService','ClickToRunSvc','VSS'){ ... }
```

`ClickToRunSvc` e `VSS` vão para **Manual**, não `Disabled`: o Office continua abrindo e o serviço
sobe sob demanda; desabilitado quebra reparo e ativação. O `VSS` é usado por instalador MSI e por
ponto de restauração — Manual é o padrão de fábrica e mantê-lo assim é o que evita surpresa numa
máquina desconhecida.

`TabletInputService` (teclado virtual) entra sem condição porque numa máquina com toque ele volta
sozinho ao ser invocado; se o alvo incluir tablets, prender atrás de `if(-not $toque)`.

Ficam **de fora**: `RstMwService` (Intel Rapid Storage — driver de armazenamento),
`ICEsoundService` e demais serviços de áudio de fabricante, e a gestão térmica.

### 5.2 Tarefas agendadas

```powershell
'\Microsoft\Office\Office Automatic Updates 2.0'
'\Microsoft\Office\Office ClickToRun Service Monitor'
'\Microsoft\Office\Office Feature Updates'
'\Microsoft\Office\Office Feature Updates Logon'
'\Microsoft\Windows\Customer Experience Improvement Program\Uploader'
'\Microsoft\Windows\Shell\FamilySafetyUpload'
```

As quatro do Office, junto com `ClickToRunSvc` em Manual, eliminam o updater residente na máquina que
tiver Office — e não fazem nada na que não tiver.

### 5.3 Armazenamento reservado

Maior ganho de disco da proposta: libera tipicamente **7 GB**. Código locale-safe em §3.6. Falha se
houver atualização pendente, daí manter o guarda `$busy` que o script já tem.
Reversão: `Set-WindowsReservedStorageState -State Enabled`.

### 5.4 Apps UWP em segundo plano

```powershell
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
```

O valor `2` é "forçar negação" para tarefas em segundo plano UWP e não deveria afetar app
*desktop bridge* em execução. Como o projeto declara o Claude Desktop como dependência, vale um teste
depois de aplicar; se as notificações pararem, libera-se só ele via
`LetAppsRunInBackground_ForceAllowTheseApps`.

### 5.5 Explorer: menos I/O

```powershell
$pe='HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
S $pe 'DisableThumbnails' 1      # nao gera nem grava thumbcache
S $pe 'NoResolveSearch'   1      # atalho quebrado nao varre o disco
S $pe 'NoResolveTrack'    1      # nem consulta a rede
S $adv 'ShowPreviewHandlers' 0   # painel nao carrega DLL por tipo de arquivo
S $adv 'ShowInfoTip' 0
S $adv 'FolderContentsInfoTip' 0
S 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'EnableFirstLogonAnimation' 0
```

Efeito colateral honesto: **sem miniaturas de imagem e vídeo no Explorer**. É o item com maior ganho
de I/O e o mais visível no uso diário — candidato natural a ficar atrás de `-SemMiniaturas` se você
preferir não impor a quem instalar o script.

### 5.6 Telemetria, drivers e permissões

```powershell
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 1     # sem MSRT mensal
S 'HKLM:\SOFTWARE\Policies\Microsoft' 'DisablePushToInstall' 1
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableCdp' 0
S 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput' 'AllowLinguisticDataCollection' 0
S 'HKLM:\SOFTWARE\Microsoft\MdmCommon\SettingValues' 'LocationSyncEnabled' 0
S 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsSyncWithDevices' 2
S 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\features' 'WiFiSenseCredShared' 0
S 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\features' 'WiFiSenseOpen' 0
S $ws 'ConnectedSearchPrivacy' 3
S $ws 'EnableDynamicContentInWSB' 0                                    # destaques de pesquisa
S 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDeviceSearchHistoryEnabled' 0

$cs2='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
foreach($c in 'location','userNotificationListener','userAccountInformation','contacts','email',
              'userDataTasks','chat','appDiagnostics','phoneCallHistory','phoneCall',
              'appointments'){ S "$cs2\$c" 'Value' 'Deny' 'String' }
```

Do `ConsentStore` ficam de fora, de propósito, `broadFileSystemAccess`,
`graphicsCaptureProgrammatic`, `graphicsCaptureWithoutBorder`, `documentsLibrary`,
`downloadsFolder` e `radios` — os primeiros podem afetar app empacotado que precise ler disco ou
capturar tela, e `radios` tira de apps o controle do rádio Bluetooth.

### 5.7 Edge

```powershell
$ed='HKLM:\SOFTWARE\Policies\Microsoft\Edge'
S $ed 'HubsSidebarEnabled' 0
S $ed 'ShowRecommendationsEnabled' 0
S $ed 'DefaultGeolocationSetting' 2
S $ed 'DefaultNotificationsSetting' 2
S $ed 'DefaultSensorsSetting' 2
S 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'RemoveDesktopShortcutDefault' 1
S 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0
```

`ShowAcrobatSubscriptionButton` e `EfficiencyMode` do `Edge.bat` ficam de fora: o segundo não é nome
de política válido — a real é `EfficiencyModeEnabled`, e o `.bat` grava `0`, que *desliga* o modo de
eficiência, o contrário do que o comentário promete.

---

## 6. Só atrás de flag

### 6.1 `-SemVBS` — desligar VBS e Integridade de Memória

Maior ganho de CPU isolado da lista: o HVCI cobra caro em carga com muita chamada de sistema, que é o
perfil de compilador e `git`. Mas quebra máquina que usa virtualização, e em máquina gerenciada a
chave volta no próximo ciclo de política — deixando o log mentindo.

```powershell
if($SemVBS){
  if($virtual){
    L "  -SemVBS IGNORADO: Hyper-V/WSL em uso nesta maquina"
  }else{
    if($gerenciada){ L "  [!] maquina gerenciada: a politica pode reverter esta chave" }
    S 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
    S 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
    L "  VBS/HVCI desligados (efetivo apos reiniciar)"
  }
}
```

A detecção é o que torna isso seguro de embarcar num script genérico — sem ela, seria uma escolha
apostando na máquina de quem escreveu.

### 6.2 `-SemSmartScreen`

Rebaixa segurança sem ganho de desempenho perceptível. Se entrar, pela mesma porta do
`-SemDefender`, nunca por padrão.

### 6.3 `-SemMiniaturas`

Ver §5.5 — se `DisableThumbnails` for considerado intrusivo demais para o padrão.

---

## 7. Cosméticos — adotar só se quiser

Nenhum muda desempenho de forma mensurável.

| Tweak | Origem |
|---|---|
| `Max Cached Icons = 4096` | `Otimizacao11.bat:298` |
| `PrintScreenKeyForSnippingEnabled = 1` | `Otimizacao11.bat:147` |
| `LaunchTo = 1` (Explorer abre em "Este Computador") | `Otimizacao11.bat:156` |
| `Hidden = 1` / `ShowSuperHidden = 1` | `Otimizacao11.bat:255` |
| `TaskbarEndTask = 1` | `Otimizacao11.bat:517` |
| `DisableMFUTracking = 1` | `Otimizacao11.bat:397` |
| `Start_AccountNotifications = 0`, `ScoobeSystemSettingEnabled = 0` | `Otimizacao11.bat:523`, `536` |
| `ColorPrevalence = 0` | `Otimizacao11.bat:180` |
| `EnableBalloonTips = 0` | `Otimizacao10.bat:387` |
| Flags de StickyKeys / ToggleKeys / FilterKeys | `Otimizacao11.bat:271` |

---

## 8. O que **não** copiar

| Item | Onde | Problema |
|---|---|---|
| `EnableTransparency /d 1` sob "Desabilitar Transparencias" | `Otimizacao11.bat:193` | grava `1`, que **liga** a transparência. O PS1 grava `0`, correto |
| `PowerThrottlingOff` em `...Session Manager\Power\...` | `Otimizacao11.bat:349` | caminho errado; o correto é `...Control\Power\PowerThrottling`, que é o que o PS1 usa |
| `WaitToKillServiceTimeout` sob `PrefetchParameters` | `Otimizacao10.bat:202` | chave errada, e escreve direto em `ControlSet001/002` |
| `EnableAutoTray` em `...CurrentVersion\Explore` | `Otimizacao10.bat:205` | erro de digitação: falta o `r` de `Explorer` |
| `sc config MapsBroke` | `Otimizacao_Insider.bat:74` | erro de digitação de `MapsBroker` |
| `wmic pagefileset ... delete` | `Otimizacao10.bat:195` | remove o pagefile. Em máquina de 4 GB é receita de OOM |
| `sc config BTAGService/BthAvctpSvc disabled` incondicional | `Otimizacao11.bat:76,81` | mata o Bluetooth em máquina que depende dele para teclado/mouse. Só sob detecção (§3.3) |
| `TouchGate = 0` | `Otimizacao10.bat:406` | desabilita a tela sensível ao toque |
| `SEE_MASK_NOZONECHECKS`, `SaveZoneInformation = 1` | `Otimizacao10.bat:296,300` | desliga o *Mark of the Web*: executável baixado roda sem aviso |
| `VerifiedAndReputablePolicyState = 0` (Smart App Control) | `Otimizacao11.bat:449` | **irreversível**: o SAC só volta reinstalando o Windows |
| MVPS HOSTS | `Otimizacao10.bat:504` | mexe no `hosts` — o README já explica por que não |
| `NetFx3`, `LegacyComponents`, `DirectPlay` via DISM | `Otimizacao11.bat:130-135` | *adiciona* peso; é o inverso do objetivo |
| `IsContinuousInnovationOptedIn = 1` | `Otimizacao11.bat:511` | pede atualizações **antes**, contra o `wuauserv` em Manual |
| `HideFileExt = 1` | `Otimizacao11.bat:520` | esconde extensão; contradiz o próprio `Otimizacao10.bat`, que mostra |
| `netsh advfirewall ... group="Network Discovery"` | `Otimizacao11.bat:464` | nome de grupo localizado; não funciona fora do inglês (§3.6) |
| `icacls ... /deny` nos caches de navegador | `Otimizacao11.bat:356-391` | quebra Chrome/Edge/Firefox de formas difíceis de diagnosticar |
| `winget install` de jogos, emuladores, navegadores | `Otimizacao11.bat:580+` | fora do escopo: o projeto otimiza, não provisiona |
| Caminhos com `D:\Programas\...` | `Otimizacao11.bat:383-389` | endereço da máquina do autor dentro do script — exatamente o que evitar |

---

## 9. Estrutura

Com o bloco de perfil e as condicionais, o `Otimizar-Windows.ps1` passa de 624 para ~720 linhas. A
maior parte continua sendo **dado**, não lógica — `$off`, `$tasks` e `$rm` sozinhos são ~180 linhas.

```
OtimizacaoWindows/
  Otimizar-Windows.ps1     # perfil + orquestracao + logica
  Reverter-Windows.ps1     # reversao
  Listas.ps1               # $off, $tasks, $rm, $lixo, $exPaths, $exProc
```

O ganho não é contagem de linhas: hoje as listas de serviços e de tarefas estão **duplicadas** entre
os dois scripts, e o bug B5 existe exatamente por isso. Fonte única elimina a classe do problema, e
B3 passa a ser corrigível reusando `$tasks`.

Não vale dividir mais — separar "telemetria" de "interface" criaria arquivos que sempre mudam juntos.

---

## 10. Ordem sugerida

1. **B1 primeiro** — o backup do autostart destruído na segunda execução é silencioso e irreversível.
2. **§3.1 bloco de perfil** — é a fundação de quase tudo que vem depois.
3. **§3.2 SSD × HDD** — a suposição que hoje pode deixar uma máquina mais lenta em vez de mais rápida.
4. **§3.3 e §3.4** — hardware e Windows 10 × 11 por detecção.
5. **B2, B3, B5** — energia, reversão de tarefas, 4 serviços sem restauração.
6. **`Listas.ps1`** — desduplica e destrava B3/B5 de vez.
7. **§5.3 armazenamento reservado** — maior ganho isolado (~7 GB), reversível num comando.
8. **§5.1, §5.2, §5.4** — serviços, tarefas do Office, apps em segundo plano.
9. **§5.6, §5.7 e §3.6** — telemetria, permissões, Edge, firewall locale-safe.
10. **§5.5 Explorer** — por último, por ser o mais visível.
11. **§3.7 multiusuário** e **§3.8 log** — quando o script for usado fora da sua máquina.
12. **README** — trocar as exceções em prosa ("foi o caso da máquina de teste") pela regra de detecção
    correspondente, e acrescentar aos efeitos colaterais: sem miniaturas no Explorer, apps UWP sem
    segundo plano, Office sem atualização automática, armazenamento reservado desligado.
