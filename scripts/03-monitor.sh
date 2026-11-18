#!/usr/bin/env bash
# 03 - Monitoramento: instala o monitor de CPU/memória/disco como serviço systemd
# tolerante a falhas (Restart=always) e configura rotação dos logs.
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root

audit INFO "===== 03 - Provisionamento do monitoramento ====="

install -m 755 "$ROOT_DIR/scripts/monitor.sh" /usr/local/bin/alertasp-monitor
cat > /etc/alertasp/monitor.env <<EOF
CPU_LIMIT=$CPU_LIMIT
MEM_LIMIT=$MEM_LIMIT
DISK_LIMIT=$DISK_LIMIT
MONITOR_INTERVAL=$MONITOR_INTERVAL
HEALTH_URL=http://127.0.0.1$HEALTH_PATH
APP_SERVICE=alertasp-app
EOF
audit OK "monitor instalado; limites CPU=$CPU_LIMIT% MEM=$MEM_LIMIT% DISCO=$DISK_LIMIT% a cada ${MONITOR_INTERVAL}s"

install -m 644 "$ROOT_DIR/config/alertasp-monitor.service" /etc/systemd/system/alertasp-monitor.service
install -m 644 "$ROOT_DIR/config/logrotate-alertasp" /etc/logrotate.d/alertasp
systemctl daemon-reload
systemctl enable alertasp-monitor
systemctl restart alertasp-monitor
sleep 2
systemctl is-active --quiet alertasp-monitor
audit OK "servico alertasp-monitor ativo (PID $(systemctl show -p MainPID --value alertasp-monitor)); log: $LOG_DIR/monitor.log"

audit OK "===== 03 - Monitoramento concluido ====="
