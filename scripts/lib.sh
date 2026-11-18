# shellcheck shell=bash
# Funções comuns: carrega config.env, registra log de auditoria e captura erros.
# Uso: source "$(dirname "$0")/lib.sh"

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config.env
source "$ROOT_DIR/config.env"

LOG_DIR=/var/log/alertasp
AUDIT_LOG=$LOG_DIR/audit.log

# audit NIVEL mensagem -> "data | NIVEL | user=quem | script | mensagem"
audit() {
  local level=$1; shift
  mkdir -p "$LOG_DIR"
  printf '%s | %-5s | user=%s | %s | %s\n' \
    "$(date '+%F %T')" "$level" "${SUDO_USER:-$(id -un)}" "$(basename "$0")" "$*" \
    | tee -a "$AUDIT_LOG"
}

# Código HTTP da API através do nginx (000 se não respondeu)
http_code() {
  curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1$HEALTH_PATH" || true
}

require_root() {
  [[ $EUID -eq 0 ]] || { echo "Execute como root: sudo $0" >&2; exit 1; }
}

# Qualquer comando que falhar fica registrado na auditoria antes do script parar.
trap 'audit ERRO "falha na linha $LINENO: $BASH_COMMAND (exit $?)"' ERR
