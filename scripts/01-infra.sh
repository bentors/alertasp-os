#!/usr/bin/env bash
# 01 - Infraestrutura: hostname, IP fixo, DNS, fuso, pacotes base, firewall e auditoria.
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
export DEBIAN_FRONTEND=noninteractive

audit INFO "===== 01 - Provisionamento de infraestrutura ====="

# --- Hostname ---
hostnamectl set-hostname "$VM_HOSTNAME"
sed -i '/# alertasp$/d;/^127\.0\.1\.1[[:space:]]/d' /etc/hosts
printf '127.0.1.1 %s # alertasp\n%s %s %s # alertasp\n' \
  "$VM_HOSTNAME" "$NET_IP" "$DOMAIN" "$VM_HOSTNAME" >> /etc/hosts
audit OK "hostname=$VM_HOSTNAME; /etc/hosts: $NET_IP -> $DOMAIN"

timedatectl set-timezone "$TIMEZONE"
audit OK "fuso horario: $TIMEZONE"

# --- Rede: IP fixo na placa host-only (a placa NAT segue em DHCP para internet) ---
ip link show "$NET_IFACE" >/dev/null 2>&1 || {
  audit ERRO "interface $NET_IFACE nao existe. Disponiveis: $(ls /sys/class/net | tr '\n' ' ')"
  exit 1
}
cat > /etc/netplan/60-alertasp.yaml <<EOF
network:
  version: 2
  ethernets:
    $NET_IFACE:
      dhcp4: false
      addresses: [$NET_IP/$NET_PREFIX]
EOF
chmod 600 /etc/netplan/60-alertasp.yaml
netplan apply
sleep 2
ip -4 addr show "$NET_IFACE" | grep -q "$NET_IP/" || { audit ERRO "IP $NET_IP nao aplicado em $NET_IFACE"; exit 1; }
audit OK "IP fixo $NET_IP/$NET_PREFIX em $NET_IFACE"

# --- DNS (systemd-resolved) ---
mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNS=%s\nFallbackDNS=9.9.9.9\nDomains=~.\n' "$DNS_SERVERS" \
  > /etc/systemd/resolved.conf.d/alertasp.conf
systemctl restart systemd-resolved
sleep 1
getent hosts github.com >/dev/null || { audit ERRO "DNS nao esta resolvendo nomes"; exit 1; }
audit OK "DNS configurado ($DNS_SERVERS) e resolvendo"

# --- Pacotes base ---
apt-get update -q
apt-get install -y -q curl git ufw auditd openssl ca-certificates
audit OK "pacotes base instalados"

# --- Firewall: só SSH e HTTP entram ---
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw --force enable
audit OK "firewall ativo: entrada liberada apenas 22/tcp e 80/tcp"

# --- Usuário de serviço e diretórios ---
id -u alertasp >/dev/null 2>&1 || useradd --system --home-dir /opt/alertasp --shell /usr/sbin/nologin alertasp
install -d -o alertasp -g alertasp /opt/alertasp
install -d -m 750 -o root -g alertasp /etc/alertasp
audit OK "usuario de servico 'alertasp' e diretorios /opt/alertasp, /etc/alertasp"

# --- Auditoria do kernel (auditd): vigia alterações de configuração ---
systemctl enable --now auditd
install -m 640 "$ROOT_DIR/config/audit-alertasp.rules" /etc/audit/rules.d/alertasp.rules
augenrules --load
audit OK "auditd ativo com regras AlertaSP (consulta: ausearch -k alertasp_config)"

audit OK "===== 01 - Infraestrutura concluida ====="
