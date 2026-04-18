#!/usr/bin/env bash
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Config ───────────────────────────────────────────────────────────────────
MARGEMAI_VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAPERCLIP_DIR="$SCRIPT_DIR/paperclip"
HERMES_DIR="$SCRIPT_DIR/hermes"
INSTALLED_MARKER="$SCRIPT_DIR/.margemai-installed"
SERVER_PORT="3100"
NODE_VERSION="20"
PG_VERSION="15"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log_success() { echo -e "${GREEN}✓  $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠  $1${NC}"; }
log_error()   { echo -e "${RED}✗  $1${NC}"; }
log_info()    { echo -e "${BLUE}→  $1${NC}"; }
log_step()    {
  echo ""
  echo -e "${BOLD}──────────────────────────────────────────────${NC}"
  echo -e "${BOLD}  $1${NC}"
  echo -e "${BOLD}──────────────────────────────────────────────${NC}"
}

die() {
  echo ""
  log_error "ERRO: $1"
  if [ -n "${2:-}" ]; then
    echo -e "  ${YELLOW}Como corrigir: $2${NC}"
  fi
  echo ""
  exit 1
}

confirm() {
  local response
  read -r -p "$(echo -e "${YELLOW}  $1 [s/N]: ${NC}")" response
  [[ "$response" =~ ^[sS]$ ]]
}

prompt_value() {
  local prompt="$1"
  local default="${2:-}"
  local secret="${3:-false}"
  local value
  if [ "$secret" = "true" ]; then
    read -r -s -p "$(echo -e "${BLUE}  $prompt: ${NC}")" value; echo ""
  elif [ -n "$default" ]; then
    read -r -p "$(echo -e "${BLUE}  $prompt [${default}]: ${NC}")" value
    value="${value:-$default}"
  else
    read -r -p "$(echo -e "${BLUE}  $prompt: ${NC}")" value
  fi
  echo "$value"
}

command_exists() { command -v "$1" &>/dev/null; }

generate_secret() {
  openssl rand -hex 32 2>/dev/null \
    || (cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-') \
    || date +%s%N | sha256sum | head -c 64
}

load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
}

# ─── Step 1: OS Check ─────────────────────────────────────────────────────────
check_os() {
  log_step "1/9  Verificando sistema operacional"

  if [ ! -f /etc/os-release ]; then
    log_warn "Não foi possível detectar o sistema operacional."
    confirm "Deseja continuar mesmo assim?" \
      || die "Instalação cancelada pelo usuário."
    return
  fi

  # shellcheck source=/dev/null
  . /etc/os-release
  log_info "Sistema detectado: ${PRETTY_NAME:-desconhecido}"

  if [ "${ID:-}" = "ubuntu" ] && [[ "${VERSION_ID:-}" =~ ^(22\.04|24\.04)$ ]]; then
    log_success "Ubuntu ${VERSION_ID} — suportado oficialmente."
  else
    log_warn "Sistema '${PRETTY_NAME:-}' não é suportado oficialmente (apenas Ubuntu 22.04 e 24.04)."
    confirm "Deseja continuar mesmo assim?" \
      || die "Instalação cancelada." \
             "Use Ubuntu 22.04 ou 24.04 para garantir compatibilidade."
  fi
}

# ─── Step 2: System Dependencies ──────────────────────────────────────────────
install_system_deps() {
  log_step "2/9  Instalando dependências do sistema"

  # Base tools
  log_info "Atualizando lista de pacotes..."
  sudo apt-get update -qq

  sudo apt-get install -y -qq \
    curl git build-essential ca-certificates gnupg lsb-release openssl \
    2>/dev/null \
    || die "Falha ao instalar ferramentas base" \
           "Verifique sua conexão com a internet e permissões sudo."

  log_success "Ferramentas base instaladas"

  # Node.js via nvm
  load_nvm
  if command_exists node && node --version 2>/dev/null | grep -q "^v${NODE_VERSION}\."; then
    log_success "Node.js $(node --version) já instalado"
  else
    log_info "Instalando Node.js ${NODE_VERSION} via nvm..."
    export NVM_DIR="$HOME/.nvm"
    if [ ! -d "$NVM_DIR" ]; then
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash \
        || die "Falha ao instalar nvm" "Verifique sua conexão com a internet."
    fi
    load_nvm
    nvm install "$NODE_VERSION" \
      || die "Falha ao instalar Node.js ${NODE_VERSION}"
    nvm use "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    log_success "Node.js $(node --version) instalado via nvm"
  fi
  load_nvm

  # pnpm
  if command_exists pnpm && pnpm --version | grep -qE "^[9-9]\.|^1[0-9]\."; then
    log_success "pnpm $(pnpm --version) já instalado"
  else
    log_info "Instalando pnpm..."
    npm install -g pnpm@latest \
      || die "Falha ao instalar pnpm" "Execute: npm install -g pnpm"
    log_success "pnpm $(pnpm --version) instalado"
  fi

  # Python 3.11
  if command_exists python3.11; then
    log_success "Python 3.11 já instalado ($(python3.11 --version))"
  else
    log_info "Instalando Python 3.11..."
    sudo apt-get install -y -qq software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3.11 python3.11-venv python3.11-dev python3-pip \
      || die "Falha ao instalar Python 3.11" \
             "Tente manualmente: sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt-get install python3.11"
    log_success "Python 3.11 instalado"
  fi

  # PostgreSQL 15
  if command_exists psql && psql --version 2>/dev/null | grep -q "PostgreSQL ${PG_VERSION}"; then
    log_success "PostgreSQL ${PG_VERSION} já instalado"
  elif command_exists psql; then
    log_warn "PostgreSQL instalado mas versão diferente: $(psql --version)"
    confirm "Continuar com esta versão?" \
      || die "Instale o PostgreSQL ${PG_VERSION} e tente novamente."
  else
    log_info "Instalando PostgreSQL ${PG_VERSION}..."
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | sudo gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}" \
      || die "Falha ao instalar PostgreSQL" \
             "Consulte: https://www.postgresql.org/download/linux/ubuntu/"
    sudo systemctl enable --now postgresql
    log_success "PostgreSQL ${PG_VERSION} instalado"
  fi

  # PM2
  if command_exists pm2; then
    log_success "PM2 $(pm2 --version 2>/dev/null || echo '?') já instalado"
  else
    log_info "Instalando PM2..."
    npm install -g pm2 \
      || die "Falha ao instalar PM2" "Execute: npm install -g pm2"
    log_success "PM2 instalado"
  fi
}

# ─── Step 3: Submodules ───────────────────────────────────────────────────────
init_submodules() {
  log_step "3/9  Inicializando submodules"
  cd "$SCRIPT_DIR"

  log_info "Executando git submodule update --init --recursive..."
  git submodule update --init --recursive \
    || die "Falha ao inicializar submodules" \
           "Verifique sua conexão com a internet: git submodule status"

  log_success "Submodules prontos"
}

# ─── Step 4: Database ─────────────────────────────────────────────────────────
setup_database() {
  log_step "4/9  Configurando banco de dados"

  local DB_NAME="margemai"
  local DB_USER="margemai"
  local DB_PASS

  # Reuse existing password if .env already exists
  if [ -f "$PAPERCLIP_DIR/.env" ] && grep -q "DATABASE_URL" "$PAPERCLIP_DIR/.env"; then
    DB_PASS=$(grep "^DATABASE_URL=" "$PAPERCLIP_DIR/.env" \
      | sed 's|.*://[^:]*:\([^@]*\)@.*|\1|')
    log_info "Reutilizando senha do banco existente no .env"
  else
    DB_PASS=$(generate_secret | head -c 24)
  fi

  # Ensure PostgreSQL is running
  if ! sudo systemctl is-active --quiet postgresql 2>/dev/null; then
    sudo systemctl start postgresql \
      || die "Não foi possível iniciar o PostgreSQL" \
             "Execute: sudo systemctl start postgresql"
  fi

  # Create user (idempotent)
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" 2>/dev/null \
       | grep -q 1; then
    log_info "Usuário '$DB_USER' já existe — atualizando senha..."
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" &>/dev/null
  else
    log_info "Criando usuário '$DB_USER'..."
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" \
      || die "Falha ao criar usuário no PostgreSQL"
    log_success "Usuário '$DB_USER' criado"
  fi

  # Create database (idempotent)
  if sudo -u postgres psql -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw "$DB_NAME"; then
    log_info "Banco de dados '$DB_NAME' já existe"
  else
    log_info "Criando banco de dados '$DB_NAME'..."
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" \
      || die "Falha ao criar banco de dados"
    log_success "Banco de dados '$DB_NAME' criado"
  fi

  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" &>/dev/null

  # Export for use in later steps
  export MARGEMAI_DB_URL="postgres://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
  export MARGEMAI_DB_PASS="$DB_PASS"

  log_success "Banco de dados configurado: postgres://localhost:5432/$DB_NAME"
}

# ─── Step 5: Environment Variables ────────────────────────────────────────────
configure_env() {
  log_step "5/9  Configurando variáveis de ambiente"

  echo ""
  echo -e "  ${BOLD}Preencha as informações do seu negócio:${NC}"
  echo ""

  # ANTHROPIC_API_KEY
  local ANTHROPIC_KEY=""
  if [ -f "$PAPERCLIP_DIR/.env" ] && grep -q "^ANTHROPIC_API_KEY=" "$PAPERCLIP_DIR/.env"; then
    ANTHROPIC_KEY=$(grep "^ANTHROPIC_API_KEY=" "$PAPERCLIP_DIR/.env" | cut -d'=' -f2-)
    log_info "ANTHROPIC_API_KEY já configurada — mantendo valor existente."
    echo -e "  ${BLUE}Pressione Enter para manter ou digite nova chave:${NC}"
    local new_key
    read -r -s -p "  ANTHROPIC_API_KEY: " new_key; echo ""
    [ -n "$new_key" ] && ANTHROPIC_KEY="$new_key"
  else
    ANTHROPIC_KEY=$(prompt_value "ANTHROPIC_API_KEY (sk-ant-...)" "" "true")
    [ -z "$ANTHROPIC_KEY" ] \
      && die "ANTHROPIC_API_KEY é obrigatória" \
             "Obtenha em: https://console.anthropic.com/settings/keys"
  fi

  # WhatsApp number
  local WHATSAPP_NUMBER=""
  if [ -f "$HERMES_DIR/.env" ] && grep -q "^WHATSAPP_ALLOWED_USERS=" "$HERMES_DIR/.env"; then
    WHATSAPP_NUMBER=$(grep "^WHATSAPP_ALLOWED_USERS=" "$HERMES_DIR/.env" | cut -d'=' -f2-)
  fi
  WHATSAPP_NUMBER=$(prompt_value "Número WhatsApp do negócio (ex: 5511999998888)" "$WHATSAPP_NUMBER")

  # Business name
  local BUSINESS_NAME=""
  BUSINESS_NAME=$(prompt_value "Nome do negócio" "Meu Negócio")

  # Timezone
  local TIMEZONE="America/Sao_Paulo"
  TIMEZONE=$(prompt_value "Timezone" "$TIMEZONE")

  # Auth secret (generate once, keep if .env exists)
  local AUTH_SECRET
  if [ -f "$PAPERCLIP_DIR/.env" ] && grep -q "^BETTER_AUTH_SECRET=" "$PAPERCLIP_DIR/.env"; then
    AUTH_SECRET=$(grep "^BETTER_AUTH_SECRET=" "$PAPERCLIP_DIR/.env" | cut -d'=' -f2-)
  else
    AUTH_SECRET=$(generate_secret)
  fi

  # Write paperclip/.env
  cat > "$PAPERCLIP_DIR/.env" <<EOF
DATABASE_URL=$MARGEMAI_DB_URL
PORT=$SERVER_PORT
NODE_ENV=production
BETTER_AUTH_SECRET=$AUTH_SECRET
ANTHROPIC_API_KEY=$ANTHROPIC_KEY
TZ=$TIMEZONE
EOF
  log_success "paperclip/.env configurado"

  # Write hermes/.env (only vars needed for MargemAI — user can add more)
  cat > "$HERMES_DIR/.env" <<EOF
ANTHROPIC_API_KEY=$ANTHROPIC_KEY
WHATSAPP_ENABLED=true
WHATSAPP_ALLOWED_USERS=$WHATSAPP_NUMBER
TZ=$TIMEZONE
TERMINAL_TIMEOUT=60
TERMINAL_LIFETIME_SECONDS=300
EOF
  log_success "hermes/.env configurado"

  # Export for start_services
  export MARGEMAI_ANTHROPIC_KEY="$ANTHROPIC_KEY"
  export MARGEMAI_AUTH_SECRET="$AUTH_SECRET"
  export MARGEMAI_WHATSAPP_NUMBER="$WHATSAPP_NUMBER"
  export MARGEMAI_BUSINESS_NAME="$BUSINESS_NAME"
  export MARGEMAI_TIMEZONE="$TIMEZONE"
}

# ─── Step 6: Install Dependencies ─────────────────────────────────────────────
install_deps() {
  log_step "6/9  Instalando dependências dos projetos"

  # Paperclip
  log_info "Instalando dependências do Paperclip (pnpm install)..."
  cd "$PAPERCLIP_DIR"
  pnpm install --frozen-lockfile \
    || die "Falha ao instalar dependências do Paperclip" \
           "Tente: cd paperclip && pnpm install"
  log_success "Dependências do Paperclip instaladas"

  # Hermes
  log_info "Instalando dependências do Hermes (pip install -e .[all])..."
  cd "$HERMES_DIR"
  python3.11 -m pip install -e ".[all]" --quiet \
    || die "Falha ao instalar dependências do Hermes" \
           "Tente: cd hermes && python3.11 -m pip install -e '.[all]'"
  log_success "Dependências do Hermes instaladas"
}

# ─── Step 7: Build + Migrate ──────────────────────────────────────────────────
build_and_migrate() {
  log_step "7/9  Build e migrations"

  cd "$PAPERCLIP_DIR"

  log_info "Executando pnpm build..."
  pnpm build \
    || die "Falha no build do Paperclip" \
           "Verifique os erros acima. Tente: cd paperclip && pnpm build"
  log_success "Build concluído"

  log_info "Aplicando migrations do banco de dados..."
  DATABASE_URL="$MARGEMAI_DB_URL" pnpm db:migrate \
    || die "Falha nas migrations" \
           "Verifique a conexão com o banco: psql $MARGEMAI_DB_URL"
  log_success "Migrations aplicadas"
}

# ─── Step 8: Start with PM2 ───────────────────────────────────────────────────
start_services() {
  log_step "8/9  Iniciando serviços com PM2"

  # Hermes needs a start wrapper to load its .env
  cat > "$HERMES_DIR/start.sh" <<'HERMESSTART'
#!/usr/bin/env bash
set -a
# shellcheck source=/dev/null
[ -f "$(dirname "$0")/.env" ] && source "$(dirname "$0")/.env"
set +a
exec python3.11 -m gateway.run
HERMESSTART
  chmod +x "$HERMES_DIR/start.sh"

  # Generate PM2 ecosystem config
  # Paperclip server reads .env via NODE_OPTIONS --env-file (Node 20+)
  cat > "$SCRIPT_DIR/pm2.config.js" <<ECOEOF
module.exports = {
  apps: [
    {
      name: 'margemai-server',
      script: 'dist/index.js',
      node_args: '--env-file=${PAPERCLIP_DIR}/.env',
      cwd: '${PAPERCLIP_DIR}/server',
      env: {
        NODE_ENV: 'production',
      },
      restart_delay: 3000,
      max_restarts: 10,
    },
    {
      name: 'margemai-hermes',
      script: '${HERMES_DIR}/start.sh',
      interpreter: 'bash',
      cwd: '${HERMES_DIR}',
      restart_delay: 5000,
      max_restarts: 10,
    },
  ],
};
ECOEOF

  # Stop existing processes (idempotent)
  pm2 delete margemai-server 2>/dev/null || true
  pm2 delete margemai-hermes 2>/dev/null || true

  # Start
  log_info "Iniciando margemai-server..."
  pm2 start "$SCRIPT_DIR/pm2.config.js" --only margemai-server \
    || die "Falha ao iniciar o servidor" \
           "Verifique: pm2 logs margemai-server"
  log_success "margemai-server iniciado"

  log_info "Iniciando margemai-hermes..."
  pm2 start "$SCRIPT_DIR/pm2.config.js" --only margemai-hermes \
    || die "Falha ao iniciar o Hermes gateway" \
           "Verifique: pm2 logs margemai-hermes"
  log_success "margemai-hermes iniciado"

  # Persist and enable on boot
  pm2 save
  pm2 startup 2>/dev/null \
    || log_warn "Configure o startup manualmente: pm2 startup"
}

# ─── Step 9: Verify ───────────────────────────────────────────────────────────
verify_installation() {
  log_step "9/9  Verificação final"

  # Wait for server
  log_info "Aguardando o servidor iniciar (até 30s)..."
  local ok=false
  local i
  for i in $(seq 1 15); do
    if curl -sf "http://localhost:${SERVER_PORT}/health" &>/dev/null \
        || curl -sf "http://localhost:${SERVER_PORT}" &>/dev/null; then
      ok=true
      break
    fi
    sleep 2
  done

  if $ok; then
    log_success "Servidor respondendo em http://localhost:${SERVER_PORT}"
  else
    log_warn "Servidor ainda não respondeu — pode levar mais alguns segundos."
    log_info "Verifique com: pm2 logs margemai-server"
  fi

  # Hermes status
  if pm2 jlist 2>/dev/null | python3.11 -c \
       "import sys,json; apps=json.load(sys.stdin); \
        print(next((a['pm2_env']['status'] for a in apps if a['name']=='margemai-hermes'),'?'))" \
       2>/dev/null | grep -q "^online$"; then
    log_success "Hermes gateway está online"
  else
    log_warn "Hermes gateway não está online ainda."
    log_info "Verifique com: pm2 logs margemai-hermes"
  fi

  echo ""
  pm2 list
  echo ""

  # Write installed marker
  cat > "$INSTALLED_MARKER" <<EOF
version=$MARGEMAI_VERSION
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "unknown")
paperclip_dir=$PAPERCLIP_DIR
hermes_dir=$HERMES_DIR
server_port=$SERVER_PORT
EOF
  log_success "Arquivo .margemai-installed criado"
}

# ─── Final Banner ─────────────────────────────────────────────────────────────
print_success_banner() {
  local whatsapp="${MARGEMAI_WHATSAPP_NUMBER:-não configurado}"

  echo ""
  echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║         MargemAI instalado!           ║${NC}"
  echo -e "${GREEN}║                                       ║${NC}"
  echo -e "${GREEN}║   Dashboard:                          ║${NC}"
  printf "${GREEN}║   http://localhost:%-19s║${NC}\n" "${SERVER_PORT}              "
  echo -e "${GREEN}║                                       ║${NC}"
  echo -e "${GREEN}║   CMV Dashboard:                      ║${NC}"
  printf "${GREEN}║   http://localhost:%-19s║${NC}\n" "${SERVER_PORT}/cmv          "
  echo -e "${GREEN}║                                       ║${NC}"
  echo -e "${GREEN}║   WhatsApp conectado em:              ║${NC}"
  printf "${GREEN}║   %-36s║${NC}\n" "$whatsapp"
  echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  Gerenciar processos: ${BOLD}pm2 list${NC}"
  echo -e "  Logs do servidor:   ${BOLD}pm2 logs margemai-server${NC}"
  echo -e "  Logs do Hermes:     ${BOLD}pm2 logs margemai-hermes${NC}"
  echo -e "  Reiniciar tudo:     ${BOLD}pm2 restart all${NC}"
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BOLD}  MargemAI — Instalador v${MARGEMAI_VERSION}${NC}"
  echo -e "  Assistente autônomo de CMV para pequenos negócios"
  echo ""

  check_os
  install_system_deps
  init_submodules
  setup_database
  configure_env
  install_deps
  build_and_migrate
  start_services
  verify_installation
  print_success_banner
}

main "$@"
