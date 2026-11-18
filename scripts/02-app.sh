#!/usr/bin/env bash
# 02 - Aplicação: dependências (Java 21, Maven, PostgreSQL, nginx), banco, build,
# variáveis de ambiente e orquestração dos serviços via systemd.
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
export DEBIAN_FRONTEND=noninteractive

audit INFO "===== 02 - Provisionamento da aplicacao ====="
[[ -n $APP_REPO ]] || { audit ERRO "APP_REPO vazio em config.env"; exit 1; }

# --- Dependências ---
apt-get install -y -q openjdk-21-jdk-headless maven postgresql nginx
audit OK "dependencias: $(java -version 2>&1 | head -1); $(mvn -B -v | head -1); $(psql --version)"

# --- Banco de dados ---
systemctl enable --now postgresql
ENV_FILE=/etc/alertasp/alertasp.env
if [[ -f $ENV_FILE ]]; then
  DB_PASS=$(sed -n 's/^DB_PASSWORD=//p' "$ENV_FILE")   # reaproveita senha existente
else
  DB_PASS=$(openssl rand -hex 16)
fi
psql_q() { (cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -tAc "$1"); }
[[ $(psql_q "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'") == 1 ]] || psql_q "CREATE ROLE $DB_USER LOGIN"
# senha via stdin para não aparecer na lista de processos (ps)
(cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<< "ALTER ROLE $DB_USER PASSWORD '$DB_PASS'")
[[ $(psql_q "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'") == 1 ]] || psql_q "CREATE DATABASE $DB_NAME OWNER $DB_USER"
audit OK "PostgreSQL: banco '$DB_NAME' e usuario '$DB_USER' prontos (Flyway cria as tabelas no start da API)"

# --- Variáveis de ambiente da aplicação (mesmas do docker-compose da API; segredo fora do repo) ---
cat > "$ENV_FILE" <<EOF
DB_URL=jdbc:postgresql://localhost:5432/$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
SERVER_PORT=8080
JAVA_OPTS=$JAVA_OPTS
EOF
chown root:alertasp "$ENV_FILE"
chmod 640 "$ENV_FILE"
audit OK "variaveis de ambiente em $ENV_FILE (permissao 640, senha nao exibida)"

# --- Código e build (como usuário sem privilégio) ---
SRC=/opt/alertasp/src
as_app() { sudo -u alertasp -H "$@"; }
if [[ -d $SRC/.git ]]; then
  as_app git -C "$SRC" fetch -q origin "$APP_BRANCH"
  as_app git -C "$SRC" reset -q --hard "origin/$APP_BRANCH"
else
  as_app git clone -q -b "$APP_BRANCH" "$APP_REPO" "$SRC"
fi
audit OK "codigo em $SRC (commit $(as_app git -C "$SRC" rev-parse --short HEAD))"

cd "$SRC/$APP_SUBDIR"
if [[ -f mvnw ]]; then MVN=(sh mvnw); else MVN=(mvn); fi
as_app "${MVN[@]}" -B -q -DskipTests package
JAR=$(ls -S target/*.jar | head -1)   # o maior .jar é o executável do Spring Boot
install -o alertasp -g alertasp -m 644 "$JAR" /opt/alertasp/app.jar
audit OK "build Maven concluido: $JAR -> /opt/alertasp/app.jar"

# --- Orquestração: postgresql -> alertasp-app -> nginx ---
install -m 644 "$ROOT_DIR/config/alertasp-app.service" /etc/systemd/system/alertasp-app.service
install -m 644 "$ROOT_DIR/config/nginx-alertasp.conf" /etc/nginx/sites-available/alertasp
ln -sf /etc/nginx/sites-available/alertasp /etc/nginx/sites-enabled/alertasp
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl daemon-reload
systemctl enable alertasp-app nginx
systemctl restart alertasp-app nginx
audit OK "servicos habilitados no boot: postgresql, alertasp-app, nginx"

# --- Validação: API respondendo através do nginx ---
code=000
for _ in $(seq 1 90); do
  code=$(http_code)
  [[ $code == 200 ]] && break
  sleep 2
done
[[ $code == 200 ]] || { audit ERRO "API nao respondeu em $HEALTH_PATH (HTTP $code). Veja: journalctl -u alertasp-app"; exit 1; }
audit OK "API no ar: http://$NET_IP$HEALTH_PATH -> HTTP $code"

audit OK "===== 02 - Aplicacao concluida ====="
