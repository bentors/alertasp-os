#!/usr/bin/env bash
# Gera um arquivo em evidencias/ com o estado da VM: rede, DNS, firewall,
# serviços, auditoria e logs. Use após provisionar e após o teste de falha.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
require_root

mkdir -p "$ROOT_DIR/evidencias"
OUT=$ROOT_DIR/evidencias/evidencias-$(date +%F_%H%M%S).txt
sec() { printf '\n########## %s\n$ %s\n' "$1" "$2"; bash -c "$2" 2>&1 || true; }

{
  sec "Sistema"            "hostnamectl; uptime"
  sec "Rede (IP)"          "ip -br addr"
  sec "Rotas"              "ip route"
  sec "DNS"                "resolvectl status | head -20; getent hosts $DOMAIN github.com"
  sec "Firewall"           "ufw status verbose"
  sec "Portas abertas"     "ss -tlnp"
  sec "Servicos"           "systemctl --no-pager status postgresql nginx alertasp-app alertasp-monitor | grep -E '●|Loaded|Active|Main PID'"
  sec "Habilitados no boot" "systemctl is-enabled postgresql nginx alertasp-app alertasp-monitor"
  sec "API via nginx"      "curl -s -o /dev/null -w 'HTTP %{http_code} em %{time_total}s\n' http://127.0.0.1$HEALTH_PATH"
  sec "Recursos"           "free -h; df -h /"
  sec "Monitor (ultimas)"  "tail -20 $LOG_DIR/monitor.log"
  sec "Alertas do monitor" "grep ALERTA $LOG_DIR/monitor.log | tail -20"
  sec "Auditoria scripts"  "tail -40 $AUDIT_LOG"
  sec "Auditoria kernel"   "for k in alertasp_config alertasp_servico alertasp_rede; do ausearch -k \$k -i 2>/dev/null | tail -10; done"
  sec "Reinicios systemd"  "journalctl -u alertasp-app -u alertasp-monitor --no-pager | grep -iE 'killed|restart|Started' | tail -20"
} > "$OUT"

[[ -n ${SUDO_USER:-} ]] && chown "$SUDO_USER:" "$ROOT_DIR/evidencias" "$OUT"
audit OK "evidencias salvas em $OUT"
