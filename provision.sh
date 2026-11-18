#!/usr/bin/env bash
# Provisiona a VM AlertaSP do zero: infraestrutura -> aplicação -> monitoramento.
# Uso: sudo ./provision.sh      (log completo em /var/log/alertasp/provision-*.log)
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || exec sudo bash "$(readlink -f "$0")" "$@"
cd "$(dirname "$(readlink -f "$0")")"

mkdir -p /var/log/alertasp
exec > >(tee -a "/var/log/alertasp/provision-$(date +%F_%H%M%S).log") 2>&1

t0=$SECONDS
bash scripts/01-infra.sh
bash scripts/02-app.sh
bash scripts/03-monitor.sh

source scripts/lib.sh
audit OK "PROVISIONAMENTO CONCLUIDO em $((SECONDS - t0))s"
audit OK "API: http://$NET_IP$HEALTH_PATH | Swagger: http://$NET_IP/swagger-ui.html"
