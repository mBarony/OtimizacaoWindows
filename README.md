# Otimização de Windows para máquinas fracas

Deixa o Windows 10/11 o mais leve possível — pensado para rodar **Claude Code / Claude Desktop**
em hardware limitado (4 GB de RAM, CPU de baixo consumo, SSD pequeno).

O script se adapta ao computador em que roda: nada aqui pressupõe um hardware específico.
Antes de mexer em qualquer coisa ele monta um perfil da máquina e decide a partir dele.

## Como usar em outro computador

1. Copie a pasta inteira `OtimizacaoWindows` para a outra máquina.
2. Clique com o botão direito em **`OTIMIZAR.bat`** → *Executar como administrador*
   (ou clique duas vezes — ele se auto-eleva e pede o UAC).
3. **Reinicie** o Windows ao terminar.

Para desfazer: **`REVERTER.bat`** → reinicie.

Cada execução grava um log `otimizacao-AAAAMMDD-HHMMSS.log` na própria pasta.

### Arquivos

| Arquivo | Papel |
|---|---|
| `Otimizar-Windows.ps1` | perfil da máquina, decisões e aplicação |
| `Reverter-Windows.ps1` | reversão |
| `Listas.ps1` | serviços, tarefas, apps e chaves — lido pelos dois |
| `PROPOSTA.md` | comparação com os `.bat` do AFaustini e o raciocínio por trás de cada escolha |

`Listas.ps1` existe para que aplicar e reverter leiam a **mesma** fonte. Enquanto as listas
viviam duplicadas, serviço desabilitado sem entrada correspondente na reversão passava
despercebido.

## Opções

Pelo PowerShell, se quiser controle fino:

```powershell
.\Otimizar-Windows.ps1                    # padrão
.\Otimizar-Windows.ps1 -SemDefender       # também tenta desligar a proteção em tempo real
.\Otimizar-Windows.ps1 -SemVBS            # desliga VBS/HVCI (ignorado se houver Hyper-V ou WSL)
.\Otimizar-Windows.ps1 -ManterMiniaturas  # preserva as miniaturas do Explorer
.\Otimizar-Windows.ps1 -ManterPrefetch    # preserva Prefetcher/SuperFetch/SysMain mesmo em SSD
.\Otimizar-Windows.ps1 -SemRemoverApps    # não remove nenhum app UWP
.\Otimizar-Windows.ps1 -SemLimpeza        # não faz limpeza de disco
.\Otimizar-Windows.ps1 -TodosUsuarios     # aplica também ao perfil de usuário padrão
```

### Sobre `-SemDefender`

Só funciona se a **Proteção contra Adulteração** estiver desligada. O Windows 11 a mantém
ligada por padrão e ela bloqueia qualquer tentativa de desabilitar o antivírus por script.

Para desligar:
`Segurança do Windows` → `Proteção contra vírus e ameaças` → `Gerenciar configurações` →
**Proteção contra adulteração: Desativado**

Mesmo **sem** essa opção, o script já reduz bastante o peso do Defender: adiciona exclusões
para as pastas do Claude/Git/compiladores, limita a CPU de varredura a 5%, e desliga varredura
de arquivos compactados, de rede e de mídia removível.

### Sobre `-SemVBS`

Desligar a Integridade de Memória é o maior ganho isolado de CPU em carga com muita chamada de
sistema — compilador e `git`, por exemplo. Mas quebra máquina que usa virtualização, então o
script **ignora a opção** se encontrar Hyper-V ou WSL habilitados, e avisa no log. Em máquina de
domínio ou com MDM, a política pode reverter a chave no ciclo seguinte; o script também avisa.

### Sobre `-TodosUsuarios`

Sem essa opção, as preferências de interface e privacidade valem só para o usuário que rodou o
script. Com ela, o mesmo bloco é aplicado ao hive do usuário padrão, de onde perfis novos são
copiados. Use a mesma opção no `Reverter-Windows.ps1` se precisar desfazer.

## Como o script se adapta à máquina

A seção 0 monta o perfil e as seções seguintes consultam esses valores. É o que substitui as
exceções que antes existiam só como comentário.

| Detecção | Consequência |
|---|---|
| **SSD ou HDD** | Em HDD, Prefetcher, SuperFetch e `SysMain` são **mantidos** — desligá-los deixa boot e abertura de programa mais lentos em disco mecânico. Basta um HDD no conjunto (Storage Spaces, RAID) para valer a regra do HDD. Se o tipo não puder ser determinado, o log avisa e assume SSD; nesse caso use `-ManterPrefetch`. |
| **Notebook ou desktop** | Notebook recebe plano Equilibrado, porque "Alto desempenho" em máquina sem ventoinha só antecipa o *throttling* térmico. Desktop recebe Alto desempenho — e, se o plano clássico não existir mais na build, o *overlay* equivalente. |
| **Rádio Bluetooth ativo** | Se houver, a pilha Bluetooth inteira é preservada (teclado ou mouse BLE deixaria a máquina sem entrada). Se não houver, `bthserv`, `BTAGService` e `BthAvctpSvc` saem. |
| **Leitor biométrico** | `WbioSrvc` só é desabilitado onde não há Windows Hello. |
| **BitLocker ativo** | `BDESVC` só é desabilitado se nenhum volume estiver criptografado. |
| **Hyper-V / WSL** | `iphlpsvc` é preservado (o `portproxy` do WSL2 depende dele), e `-SemVBS` é ignorado. |
| **Build do Windows** | Copilot só no 11 (≥ 22000); Recall e agente de configurações só no 24H2+ (≥ 26100). |
| **Domínio ou MDM** | Aviso no log de que parte das chaves pode ser revertida por política externa. |
| **RAM** | `DisablePagingExecutive` só com 8 GB ou mais; pagefile fixo dimensionado pela RAM. |
| **Instalador em execução** | `%TEMP%`, `SoftwareDistribution` e o DISM são preservados. |

Todo texto de saída de comando é evitado: as regras de firewall são identificadas pelo grupo
(`@FirewallAPI.dll,-32752`), não pelo nome exibido, e o armazenamento reservado é consultado pelo
cmdlet tipado. Assim o script funciona em Windows de qualquer idioma.

## O que o script faz

| Área | Ação |
|---|---|
| **Serviços** | Desabilita ~108: telemetria, SysMain, indexação, spooler, Xbox, UPnP, diagnóstico, bloatware de fabricante (Dell, HP, Lenovo, Asus), updaters de terceiros. `wuauserv`, `UsoSvc`, `BITS`, `InstallService`, `ClickToRunSvc` (Office) e `VSS` vão para *Manual* — continuam funcionando sob demanda. |
| **Tarefas agendadas** | Desabilita ~79: Compatibility Appraiser, CEIP, Feedback, WER, Flighting, diagnóstico, manutenção, varreduras do Defender e os quatro updaters do Office. |
| **Autostart** | Remove entradas em HKLM/HKCU (efeitos de áudio, assistentes e updaters de fabricante, OneDrive, Edge auto-launch). Faz backup `.reg` antes — e **não sobrescreve** um backup existente. |
| **Memória** | Prefetch/SuperFetch off em SSD, prioridade para o processo em foco, *power throttling* off, pagefile fixo dimensionado pela RAM. |
| **Indexação** | Windows Search desligado, índice apagado, atributo de indexação removido do volume. |
| **Telemetria** | `AllowTelemetry=0`, CEIP/SQM, relatório de erros, linha do tempo, ID de publicidade, personalização de escrita e voz, busca na nuvem/Cortana, sincronização, WiFi Sense, sessões ETW, metadados de dispositivo, MSRT mensal, telemetria do Edge/Office/Visual Studio/NVIDIA e opt-out de .NET e PowerShell. Sem Copilot, Recall, widgets, sugestões nem anúncios. |
| **Permissões** | Nega em HKLM o acesso de apps a localização, contatos, e-mail, chamadas, notificações e diagnóstico — para a máquina toda, não só o usuário atual. |
| **Apps em segundo plano** | `LetAppsRunInBackground=2` e os equivalentes em HKCU: nenhum app UWP roda sozinho. |
| **Interface** | Efeitos visuais em "melhor desempenho", sem transparência, sem animações, menus instantâneos, sem miniaturas nem painel de visualização no Explorer. |
| **Energia** | Plano conforme o tipo de máquina, hibernação/fast startup off, disco nunca desliga. |
| **Rede** | Descoberta de rede, compartilhamento de arquivos e assistência remota desligados no firewall. |
| **Apps UWP** | Remove ~45 apps: Xbox, Fotos, Mídia, Mapas, Widgets, Solitaire, Copilot, etc. |
| **Disco** | Limpa temp, prefetch, WER, lixeira, componentes órfãos (DISM) e desliga o armazenamento reservado (~7 GB). |

## O que NÃO é tocado, em nenhuma máquina

- **Gestão térmica** — `esifsvc` / Intel DPTF / Dell Power Manager. Em tablets e ultrabooks sem
  ventoinha, desabilitar causa superaquecimento e *throttling* severo.
- **Áudio** — `Audiosrv`, `AudioEndpointBuilder` e o codec do fabricante.
  Só os *efeitos* (Waves/MaxxAudio) são removidos.
- **Armazenamento** — `RstMwService` e demais serviços de driver de disco.
- **Rede** — DHCP, DNS, WLAN, firewall, Base Filtering Engine.
- **Base do sistema** — RPC, DCOM, CryptSvc, SamSs, gpsvc, Task Scheduler.
- **Claude** — `CoworkVMService`, e `AppXSvc` / `ClipSVC` / `StateRepository` / `TokenBroker`,
  de que o Claude Desktop depende por ser um app da Store.
- **Microsoft Store e winget** — necessários para atualizar o Claude Desktop.
- **Windows Terminal, Notepad, Git, Visual Studio Build Tools.**

O arquivo `hosts` **não é alterado** de propósito: bloquear domínios da Microsoft por ali
quebra o Windows Update e a Store, e o bloqueio se perde a cada atualização de recurso.

## Efeitos colaterais esperados

- A **busca do Menu Iniciar não encontra arquivos** (só programas). O indexador está desligado.
- **Sem miniaturas de imagem e vídeo no Explorer** — ícone genérico por tipo. É o maior ganho de
  I/O em disco lento; use `-ManterMiniaturas` se preferir.
- **Nenhum app da Store roda em segundo plano.** Se as notificações do Claude Desktop pararem,
  libere só ele em `LetAppsRunInBackground_ForceAllowTheseApps`.
- **Office não se atualiza sozinho** (`ClickToRunSvc` em Manual e as quatro tarefas desabilitadas).
  Para atualizar: `Arquivo` → `Conta` → *Opções de Atualização* → *Atualizar Agora*.
- **Windows Update não roda sozinho.** Para atualizar: `Configurações` → `Windows Update` →
  *Verificar se há atualizações* (funciona; o serviço está em Manual, não desabilitado).
- **Não dá para imprimir** até reativar o `Spooler`:
  `Set-Service Spooler -StartupType Automatic; Start-Service Spooler`
- **Sem compartilhamento de arquivos** pela rede e **sem descoberta de rede** no firewall.
- **Sem restauração do sistema** (a tarefa `SR` foi desabilitada).
- **Armazenamento reservado desligado** — libera ~7 GB, mas atualizações de recurso podem exigir
  espaço livre manual.
- **Sem linha do tempo** e **sem área de transferência entre dispositivos**. O histórico local do
  `Win+V` continua funcionando.
- **Configurações não sincronizam** entre máquinas da mesma conta Microsoft.
- **Apps não acessam localização, contatos, e-mail nem notificações**, e o reconhecimento de voz
  online fica desligado.
- A busca do Windows **não consulta a web** (sem Bing, sem Cortana).
- **AutoPlay desligado** (`ShellHWDetection`) — pendrive não abre janela sozinho.

## Reverter

`REVERTER.bat` restaura serviços, tarefas, políticas, Defender, energia, indexação, firewall e a
interface, e reimporta os backups `.reg`.

A reversão tem duas etapas, nesta ordem: primeiro devolve ao padrão ou apaga cada valor que o
otimizador escreveu; depois reimporta os backups. Assim, valor que já existia volta ao original,
e valor que o otimizador criou do nada some.

Duas coisas **não** voltam, de propósito:

- Os **apps UWP removidos** — reinstale pela Microsoft Store.
- **SMB1, WorkFolders e XPS**, que são superfície de ataque ou peso morto.
