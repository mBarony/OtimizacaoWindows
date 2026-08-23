# Otimização de Windows para máquinas fracas

Deixa o Windows 10/11 o mais leve possível — pensado para rodar **Claude Code / Claude Desktop**
em hardware limitado (4 GB de RAM, CPU de baixo consumo, SSD pequeno).

Testado em Windows 11 Pro 23H2.

## Como usar em outro computador

1. Copie a pasta inteira `OtimizacaoWindows` para a outra máquina.
2. Clique com o botão direito em **`OTIMIZAR.bat`** → *Executar como administrador*
   (ou clique duas vezes — ele se auto-eleva e pede o UAC).
3. **Reinicie** o Windows ao terminar.

Para desfazer: **`REVERTER.bat`** → reinicie.

Cada execução grava um log `otimizacao-AAAAMMDD-HHMMSS.log` na própria pasta.

## Opções

Pelo PowerShell, se quiser controle fino:

```powershell
.\Otimizar-Windows.ps1                    # padrão: mantém o Defender ligado
.\Otimizar-Windows.ps1 -SemDefender       # também tenta desligar a proteção em tempo real
.\Otimizar-Windows.ps1 -SemRemoverApps    # não remove nenhum app UWP
.\Otimizar-Windows.ps1 -SemLimpeza        # não faz limpeza de disco
```

### Sobre `-SemDefender`

Só funciona se a **Proteção contra Adulteração** estiver desligada. O Windows 11 a mantém
ligada por padrão e ela bloqueia qualquer tentativa de desabilitar o antivírus por script.

Para desligar:
`Segurança do Windows` → `Proteção contra vírus e ameaças` → `Gerenciar configurações` →
**Proteção contra adulteração: Desativado**

Depois rode o script de novo com `-SemDefender`.

Mesmo **sem** essa opção, o script já reduz bastante o peso do Defender: adiciona exclusões
para as pastas do Claude/Git/compiladores, limita a CPU de varredura a 5%, e desliga varredura
de arquivos compactados, de rede e de mídia removível.

## O que o script faz

| Área | Ação |
|---|---|
| **Serviços** | Desabilita ~90: telemetria, SysMain, indexação, spooler, Xbox, UPnP, diagnóstico, bloatware de fabricante (Dell, HP, Lenovo, Asus), updaters de terceiros. Windows Update vai para *Manual* (sob demanda). |
| **Tarefas agendadas** | Desabilita ~70: Compatibility Appraiser, CEIP, Feedback, WER, Flighting, diagnóstico, manutenção, varreduras do Defender. |
| **Autostart** | Remove entradas em HKLM/HKCU por padrão (efeitos de áudio, assistentes e updaters de fabricante, OneDrive, Edge auto-launch, etc). Faz backup `.reg` antes. |
| **Memória** | Prefetch/SuperFetch off, prioridade para o processo em foco, *power throttling* off, pagefile fixo dimensionado pela RAM. |
| **Indexação** | Windows Search desligado, índice apagado, atributo de indexação removido do volume. |
| **Telemetria** | `AllowTelemetry=0`, CEIP/SQM, relatório de erros, linha do tempo, ID de publicidade, personalização de escrita e voz, busca na nuvem/Cortana, sincronização de configurações, WiFi Sense, sessões de rastreamento ETW, telemetria do Edge/Office/Visual Studio/NVIDIA e opt-out de .NET e PowerShell. Sem Copilot, widgets, sugestões nem anúncios. |
| **Interface** | Efeitos visuais em "melhor desempenho", sem transparência, sem animações, menus instantâneos. |
| **Energia** | Plano Alto Desempenho, hibernação/fast startup off. |
| **Apps UWP** | Remove ~40 apps: Xbox, Fotos, Mídia, Mapas, Widgets, Solitaire, Copilot, etc. |
| **Disco** | Limpa temp, prefetch, WER, lixeira e componentes órfãos (DISM). |

## O que NÃO é tocado (de propósito)

- **Bluetooth** — se o teclado ou mouse for Bluetooth, desabilitar deixa a máquina sem input.
  Foi o caso da máquina de teste, cujo teclado era BLE.
- **`esifsvc` / Intel DPTF** — gestão térmica. Em tablets e ultrabooks sem ventoinha,
  desabilitar causa superaquecimento e *throttling* severo.
- **Áudio** — `Audiosrv`, `AudioEndpointBuilder` e o codec do fabricante.
  Só os *efeitos* (Waves/MaxxAudio) são removidos.
- **Rede** — DHCP, DNS, WLAN, firewall, Base Filtering Engine.
- **Base do sistema** — RPC, DCOM, CryptSvc, SamSs, gpsvc, BitLocker, Task Scheduler.
- **Claude** — `CoworkVMService`, e `AppXSvc` / `ClipSVC` / `StateRepository` / `TokenBroker`,
  de que o Claude Desktop depende por ser um app da Store.
- **Microsoft Store e winget** — necessários para atualizar o Claude Desktop.
- **Windows Terminal, Notepad, Git, Visual Studio Build Tools.**

## Efeitos colaterais esperados

- A **busca do Menu Iniciar não encontra arquivos** (só programas). O indexador está desligado.
- **Windows Update não roda sozinho.** Para atualizar: `Configurações` → `Windows Update` →
  *Verificar se há atualizações* (funciona; o serviço está em Manual, não desabilitado).
- **Não dá para imprimir** até reativar o `Spooler`:
  `Set-Service Spooler -StartupType Automatic; Start-Service Spooler`
- **Sem compartilhamento de arquivos** pela rede (`LanmanServer` desabilitado).
- **Sem restauração do sistema** (a tarefa `SR` foi desabilitada).
- Plano Alto Desempenho **consome mais bateria** e esquenta mais.
- **Sem linha do tempo** (histórico de atividades) e **sem área de transferência entre
  dispositivos**. O histórico local do `Win+V` continua funcionando.
- **Configurações não sincronizam** entre máquinas da mesma conta Microsoft.
- **Apps não acessam a localização** e o reconhecimento de voz online fica desligado.
- A busca do Windows **não consulta a web** (sem Bing, sem Cortana).

O arquivo `hosts` **não é alterado** de propósito: bloquear domínios da Microsoft por ali
quebra o Windows Update e a Store, e o bloqueio se perde a cada atualização de recurso.

## Reverter

`REVERTER.bat` restaura serviços, tarefas, políticas, Defender, energia, indexação e interface,
e reimporta os backups `.reg` do autostart.

Os apps UWP removidos **não voltam** automaticamente — reinstale pela Microsoft Store.
