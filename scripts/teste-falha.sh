#!/usr/bin/env bash
# Teste de falha: derruba os serviços com SIGKILL, força alto consumo de CPU,
# memória e disco e provoca uma falha controlada em script, provando que o
# systemd recupera os processos, que o monitor gera ALERTAS e que erros ficam
# registrados no log de auditoria.
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root

MON_LOG=$LOG_DIR/monitor.log
FILL=/var/tmp/alertasp-teste-disco
trap 'rm -f "$FILL"; pkill -f stress-ng 2>/dev/null || true' EXIT

pid_of() { systemctl show -p MainPID --value "$1"; }

# Mata o processo principal do serviço e espera o systemd subir um novo.
kill_and_recover() {
  local svc=$1 old new t0=$SECONDS
  old=$(pid_of "$svc")
  [[ $old != 0 ]] || { audit ERRO "$svc nao esta rodando; rode o provisionamento antes do teste"; exit 1; }
  audit INFO "TESTE: kill -9 em $svc (PID $old)"
  kill -9 "$old"
  for _ in $(seq 1 60); do
    sleep 1
    new=$(pid_of "$svc")
    systemctl is-active --quiet "$svc" && [[ $new != 0 && $new != "$old" ]] && break
  done
  systemctl is-active --quiet "$svc" || { audit ERRO "$svc NAO voltou"; exit 1; }
  audit OK "TESTE: $svc recuperado pelo systemd em $((SECONDS - t0))s (PID $old -> $new)"
}

# Mostra os alertas gerados pelo monitor desde a linha informada.
show_alerts() {
  local n
  n=$(tail -n +"$(( $1 + 1 ))" "$MON_LOG" | grep -c ALERTA || true)
  audit INFO "TESTE: monitor gerou $n alerta(s):"
  tail -n +"$(( $1 + 1 ))" "$MON_LOG" | grep ALERTA || true
}

audit INFO "===== Teste de falha ====="

# 1) Monitor morto -> systemd reinicia
kill_and_recover alertasp-monitor

# 2) API morta -> systemd reinicia e ela volta a responder
start=$(wc -l < "$MON_LOG")
kill_and_recover alertasp-app
t0=$SECONDS
until [[ $(http_code) == 200 ]]; do
  (( SECONDS - t0 < 180 )) || { audit ERRO "API nao voltou a responder"; exit 1; }
  sleep 2
done
audit OK "TESTE: API respondendo novamente (HTTP 200) $((SECONDS - t0))s apos reinicio"
show_alerts "$start"

# 3) Estresse de CPU e memória -> alertas
command -v stress-ng >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq stress-ng >/dev/null
start=$(wc -l < "$MON_LOG")
audit INFO "TESTE: estressando CPU (todos os nucleos) e memoria por 40s"
stress-ng --cpu 0 --vm 1 --vm-bytes 90% --timeout 40s --quiet
show_alerts "$start"

# 4) Disco cheio -> alerta (arquivo temporário até passar do limite, removido no fim)
read -r used avail < <(df --output=used,avail -B1 / | tail -1)
need=$(( (used + avail) * (DISK_LIMIT + 2) / 100 - used ))
start=$(wc -l < "$MON_LOG")
if (( need > 0 )); then
  audit INFO "TESTE: ocupando $((need / 1024 / 1024)) MB em disco para passar de ${DISK_LIMIT}%"
  fallocate -l "$need" "$FILL"
fi
sleep $(( MONITOR_INTERVAL * 2 + 2 ))
rm -f "$FILL"
audit INFO "TESTE: arquivo de teste removido, disco liberado"
show_alerts "$start"

# 5) Falha controlada em um script -> erro registrado na auditoria
audit INFO "TESTE: executando script com falha proposital (iniciar servico inexistente)"
if bash -c 'set -Eeuo pipefail; source "$1/scripts/lib.sh"; audit INFO "passo que vai falhar"; systemctl start alertasp-inexistente' \
     falha-controlada.sh "$ROOT_DIR"; then
  audit ERRO "TESTE: a falha proposital nao foi detectada"; exit 1
fi
audit OK "TESTE: falha detectada e registrada em $AUDIT_LOG:"
grep 'falha-controlada.sh | falha' "$AUDIT_LOG" | tail -1

audit OK "===== Teste de falha concluido: servicos recuperados e alertas gerados ====="
