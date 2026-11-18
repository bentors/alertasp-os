# AlertaSP — Infraestrutura Linux (Operating Systems)

Global Solution FIAP 2026.2 — CitizenTech.

O **AlertaSP** é uma plataforma de prevenção e monitoramento de alagamentos em São Paulo. Ela combina sensores de nível de água, Machine Learning e câmeras para alertar o cidadão sobre riscos nos seus trajetos ("Minhas Rotas").

Este repositório é a entrega de **Operating Systems**. Ele provisiona automaticamente, via Shell Script, uma VM Linux que hospeda a API AlertaSP (desenvolvida em SOA), com rede, DNS, firewall, banco de dados, proxy reverso, monitoramento, auditoria e teste de falha.

## Integrantes

| Nome | RM |
|---|---|
| Bento Rangel | RM559124 |
| Eric Yuji | RM554869 |
| Higor Batista | RM558907 |
| Kaue Pires | RM554403 |
| Ricardo Di Tilia | RM555155 |

ODS relacionados: **11** (Cidades e comunidades sustentáveis), **13** (Ação contra a mudança do clima) e **9** (Indústria, inovação e infraestrutura).

## Arquitetura

```
 Navegador / App (host Windows)
            │  http://192.168.56.10
            ▼
 ┌───────────────────────── VM Ubuntu Server 24.04 (hostname: alertasp) ─────────────────────────┐
 │  ufw: entrada só 22/tcp e 80/tcp                                                              │
 │                                                                                               │
 │  nginx :80  ──proxy──▶  alertasp-app.service :8080  ──JDBC──▶  postgresql.service :5432       │
 │                         (Java 21, Spring Boot, Flyway)          (banco alertasp)              │
 │                                   ▲                                                           │
 │  alertasp-monitor.service ────────┘ verifica serviço + HTTP; mede CPU, memória e disco        │
 │        └──▶ /var/log/alertasp/monitor.log (METRICA / ALERTA) + journald                       │
 │                                                                                               │
 │  Scripts ──▶ /var/log/alertasp/audit.log       auditd ──▶ alterações em /etc/alertasp etc.    │
 └───────────────────────────────────────────────────────────────────────────────────────────────┘
```

Ordem de inicialização (systemd): `postgresql` → `alertasp-app` (`Requires=postgresql`) → `nginx`. Todos são habilitados no boot e os serviços AlertaSP têm `Restart=always`.

## Estrutura

| Caminho | Função |
|---|---|
| `provision.sh` | Executa tudo em sequência (01 → 02 → 03) e grava o log completo |
| `config.env` | Configuração central: IP, DNS, repositório da API, limites de alerta |
| `scripts/lib.sh` | Funções comuns: log de auditoria e captura de erros (`trap ERR`) |
| `scripts/01-infra.sh` | Hostname, `/etc/hosts`, IP fixo (netplan), DNS (systemd-resolved), fuso, firewall (ufw), usuário de serviço, auditd |
| `scripts/02-app.sh` | Java 21, Maven, PostgreSQL e nginx; cria banco e usuário; gera variáveis de ambiente; clona e compila a API; sobe os serviços |
| `scripts/03-monitor.sh` | Instala o monitor como serviço systemd tolerante a falhas e configura logrotate |
| `scripts/monitor.sh` | Monitor de CPU, memória, disco e saúde da API, com alertas |
| `scripts/teste-falha.sh` | Teste de falha: mata serviços, estressa CPU, memória e disco, e comprova recuperação e alertas |
| `scripts/coletar-evidencias.sh` | Gera um relatório do estado da VM em `evidencias/` |
| `config/` | Units systemd, site do nginx, regras do auditd e logrotate |
| `evidencias/` | Saídas geradas na VM (relatórios e prints) |

## Critérios de avaliação × implementação

| Critério | Pts | Onde |
|---|---|---|
| Provisionamento de infra (redes, DNS, IP) | 2 | `01-infra.sh`: IP fixo `192.168.56.10/24` via netplan, DNS `8.8.8.8 1.1.1.1` via systemd-resolved, hostname e `/etc/hosts`, firewall ufw |
| Provisionamento da aplicação (dependências, configurações, orquestração) | 2 | `02-app.sh`: instalação via apt, banco criado por script, `/etc/alertasp/alertasp.env` (permissão 640), build Maven, units systemd com dependências e nginx como proxy |
| Monitoramento com alertas de CPU, disco e memória | 2 | `monitor.sh`: lê `/proc/stat`, `/proc/meminfo` e `df`; grava `ALERTA` ao passar dos limites do `config.env` |
| Monitoramento como serviço tolerante a falhas | 1 | `alertasp-monitor.service` com `Restart=always` e `StartLimitIntervalSec=0`; comprovado no `teste-falha.sh` |
| Logs de auditoria e execução | 1 | `audit.log` (data, nível, usuário, script e ação de cada passo e de cada erro), `provision-*.log` com a saída completa, e auditd vigiando arquivos de configuração |
| Funcionamento completo | 2 | `provision.sh` termina validando a API pelo nginx (HTTP 200); `teste-falha.sh` e `coletar-evidencias.sh` comprovam o funcionamento |

## Como executar

### 1. Criar a VM (VirtualBox)

- **Sistema:** Ubuntu Server 24.04 LTS. Marque "Install OpenSSH server" na instalação.
- **Recursos:** 2 vCPU, 4 GB de RAM e 25 GB de disco. O build Maven e a JVM precisam dessa memória.
- **Rede:**
  - Adaptador 1: **NAT** (acesso à internet).
  - Adaptador 2: **Host-only** (`VirtualBox Host-Only Ethernet Adapter`, rede `192.168.56.0/24`).
- Depois de instalar, confira o nome das placas com `ip -br link`. Normalmente são `enp0s3` (NAT) e `enp0s8` (host-only). Se forem diferentes, ajuste `NET_IFACE` no `config.env`.

### 2. Provisionar

```bash
git clone <URL-deste-repositorio> alertasp-infra
cd alertasp-infra
nano config.env            # preencha APP_REPO com a URL da API
sudo ./provision.sh
```

Ao final, a API responde em `http://192.168.56.10/v3/api-docs` e o Swagger em `http://192.168.56.10/swagger-ui.html`, acessíveis pelo navegador do Windows.

> Se o repositório da API for privado, use `APP_REPO=https://<token>@github.com/...`, ou clone a API em `/tmp/alertasp-api` e use esse caminho em `APP_REPO`. O build roda com o usuário `alertasp`, que não lê pastas dentro de `/home`.
>
> O `01-infra.sh` reaplica a rede. Rode o provisionamento pelo console da VM ou por SSH através do IP da placa NAT, não pelo IP que está sendo configurado.

Os scripts são idempotentes: podem ser executados de novo para atualizar a API (eles fazem `git pull`, rebuild e restart).

### 3. Teste de falha e evidências

```bash
sudo ./scripts/teste-falha.sh          # ~2-3 min
sudo ./scripts/coletar-evidencias.sh   # gera evidencias/evidencias-<data>.txt
```

O teste de falha:
1. Mata o monitor com `kill -9`, e o systemd sobe um novo processo (PID muda).
2. Mata a API com `kill -9`, o systemd reinicia, e a API volta a responder HTTP 200. Enquanto ela está fora, o monitor registra ALERTA.
3. Estressa CPU e memória por 40 s (`stress-ng`), e o monitor registra ALERTA de CPU e memória.
4. Ocupa o disco até passar do limite com um arquivo temporário, o monitor registra ALERTA de disco, e o arquivo é removido.
5. Executa um script com falha proposital (iniciar um serviço inexistente), e o erro aparece no `audit.log` com script, linha, comando e código de saída.

### 4. Teste de reinicialização

Os serviços são habilitados no boot, então devem voltar sozinhos depois de reiniciar a máquina:

```bash
sudo reboot
# depois de logar novamente:
systemctl status alertasp-app alertasp-monitor --no-pager
grep 'monitor iniciado' /var/log/alertasp/monitor.log | tail -2   # nova inicialização após o boot
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/v3/api-docs   # 200
```

### 5. Administração do serviço de monitoramento

```bash
sudo systemctl stop alertasp-monitor      # interrompe (registra "monitor parado")
sudo systemctl start alertasp-monitor     # inicia (registra "monitor iniciado")
sudo systemctl restart alertasp-monitor   # reinicia
systemctl is-enabled alertasp-monitor     # enabled = sobe com o sistema
```

## Evidências

As evidências ficam em [`evidencias/`](evidencias/):

- `evidencias-<data>.txt`: relatório gerado por `scripts/coletar-evidencias.sh`.
- Prints numerados na ordem da demonstração:

| Arquivo | O que mostra |
|---|---|
| `01-provision.png` | Fim do `provision.sh` com todos os passos OK |
| `02-rede-dns.png` | `hostnamectl`, `ip -br addr` e `resolvectl status` |
| `03-firewall.png` | `sudo ufw status verbose` |
| `04-servicos.png` | `systemctl status` de postgresql, nginx, alertasp-app e alertasp-monitor |
| `05-swagger.png` | Swagger aberto no navegador do Windows (`http://192.168.56.10/swagger-ui.html`) |
| `06-monitor.png` | `tail -f /var/log/alertasp/monitor.log` com métricas |
| `07-teste-falha.png` | Saída do `teste-falha.sh` com recuperações e alertas |
| `08-auditoria.png` | `audit.log` e `sudo ausearch -k alertasp_config -i` |
| `09-reboot.png` | Serviços ativos após `sudo reboot` |

## Logs

| Arquivo | Conteúdo |
|---|---|
| `/var/log/alertasp/audit.log` | Auditoria de cada passo dos scripts: data, nível, usuário, script e ação |
| `/var/log/alertasp/provision-*.log` | Saída completa de cada execução do provisionamento |
| `/var/log/alertasp/monitor.log` | Métricas a cada 10 s e linhas `ALERTA` |
| `journalctl -u alertasp-app` | Logs da API e reinícios feitos pelo systemd |
| `journalctl -t alertasp-monitor` | Alertas do monitor também no journald |
| `sudo ausearch -k alertasp_config -i` | Auditoria do kernel: quem alterou arquivos de configuração |

Comandos úteis:

```bash
tail -f /var/log/alertasp/monitor.log
grep ALERTA /var/log/alertasp/monitor.log
systemctl status alertasp-app alertasp-monitor
```

## Roteiro do vídeo (até 7 min)

| Tempo | Conteúdo |
|---|---|
| 0:00–0:45 | Problema (alagamentos em SP), solução AlertaSP e papel da infraestrutura |
| 0:45–1:30 | Estrutura do repositório e `config.env` |
| 1:30–3:15 | `sudo ./provision.sh` numa VM limpa (acelere a instalação e o build), destacando rede, DNS, dependências e serviços |
| 3:15–4:00 | Swagger aberto no navegador do Windows, `ip a`, `resolvectl`, `ufw status` e `systemctl status` |
| 4:00–5:45 | `teste-falha.sh` com `tail -f monitor.log` ao lado: serviços voltando, alertas aparecendo e falha controlada no `audit.log` |
| 5:45–6:30 | `systemctl stop/start` do monitor, `sudo reboot` (acelere) e serviços ativos após o boot |
| 6:30–7:00 | `audit.log`, `ausearch`, relatório de evidências e conclusão |
