#!/usr/bin/env bash
# Monitor de infraestrutura AlertaSP: CPU, memória, disco e saúde da API.
# Instalado como /usr/local/bin/alertasp-monitor e executado pelo alertasp-monitor.service.
# Grava uma linha de métricas por ciclo e uma linha ALERTA quando um limite é atingido.
set -uo pipefail

CPU_LIMIT=${CPU_LIMIT:-80}
MEM_LIMIT=${MEM_LIMIT:-85}
DISK_LIMIT=${DISK_LIMIT:-85}
INTERVAL=${MONITOR_INTERVAL:-10}
HEALTH_URL=${HEALTH_URL:-http://127.0.0.1/v3/api-docs}
APP_SERVICE=${APP_SERVICE:-alertasp-app}
LOG=${MONITOR_LOG:-/var/log/alertasp/monitor.log}
mkdir -p "$(dirname "$LOG")"

log()   { echo "$(date '+%F %T') | $*" >> "$LOG"; }
alert() { log "ALERTA  | $*"; logger -t alertasp-monitor -p user.warning "ALERTA: $*" 2>/dev/null; }

# % de CPU ocupada: diferença entre duas leituras de /proc/stat com 1s de intervalo
cpu_usage() {
  local u n s i w q sq st t1 i1 t2 i2
  read -r _ u n s i w q sq st _ < /proc/stat; t1=$((u+n+s+i+w+q+sq+st)); i1=$((i+w))
  sleep 1
  read -r _ u n s i w q sq st _ < /proc/stat; t2=$((u+n+s+i+w+q+sq+st)); i2=$((i+w))
  echo $(( 100 * ((t2-t1) - (i2-i1)) / (t2-t1) ))
}
mem_usage()  { awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{printf "%d", (t-a)*100/t}' /proc/meminfo; }
disk_usage() { df --output=pcent / | tail -1 | tr -dc '0-9'; }

trap 'log "INFO    | monitor parado (pid $$)"; exit 0' TERM INT
log "INFO    | monitor iniciado (pid $$) limites CPU=${CPU_LIMIT}% MEM=${MEM_LIMIT}% DISCO=${DISK_LIMIT}% intervalo=${INTERVAL}s"

while true; do
  cpu=$(cpu_usage); mem=$(mem_usage); disk=$(disk_usage)
  app=$(systemctl is-active "$APP_SERVICE" 2>/dev/null || true)
  http=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$HEALTH_URL" 2>/dev/null || true)

  log "METRICA | CPU=${cpu}% MEM=${mem}% DISCO=${disk}% APP=${app:-desconhecido} HTTP=${http}"
  (( cpu  >= CPU_LIMIT  )) && alert "CPU em ${cpu}% (limite ${CPU_LIMIT}%)"
  (( mem  >= MEM_LIMIT  )) && alert "memoria em ${mem}% (limite ${MEM_LIMIT}%)"
  (( disk >= DISK_LIMIT )) && alert "disco / em ${disk}% (limite ${DISK_LIMIT}%)"
  [[ $app  == active ]] || alert "servico $APP_SERVICE esta '${app:-desconhecido}'"
  [[ $http == 200    ]] || alert "API sem resposta em $HEALTH_URL (HTTP $http)"

  sleep "$INTERVAL" & wait $!
done
