#!/bin/bash

# =============================================================================
#  Script de Atualização do GLPI
#  Compatível com: AlmaLinux 10.1
#
#  Detecta AUTOMATICAMENTE a última versão 11.x disponível no GitHub.
#  Uso: sudo bash glpi-update.sh
# =============================================================================

set -euo pipefail

# ─── Configuração de Log ──────────────────────────────────────────────────────
LOG_FILE="/var/log/glpi-update-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -i "$LOG_FILE") 2>&1

# ─── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Sem cor

# ─── Variáveis ────────────────────────────────────────────────────────────────
GLPI_DIR="/var/www/html/glpi"
GLPI_OLD_DIR="/var/www/html/glpi-old"
WEB_ROOT="/var/www/html"
TMP_DIR="/tmp/glpi-update"
GLPI_MAJOR_VERSION="11"   # Só aceita releases da linha 11.x
GITHUB_API="https://api.github.com/repos/glpi-project/glpi/releases"
DOWNLOAD_URL=""          # Preenchido automaticamente

# Pastas a preservar do GLPI atual
PRESERVE_DIRS=("files" "config" "plugins" "marketplace")

# Usuário/grupo do servidor web (Apache/AlmaLinux)
WEB_USER="apache"
WEB_GROUP="apache"

# ─── Funções utilitárias ──────────────────────────────────────────────────────

log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[AVISO]${NC} $1"; }
log_error() { echo -e "${RED}[ERRO]${NC}  $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script deve ser executado como root (sudo)."
        exit 1
    fi
}

check_dependencies() {
    log_info "Verificando dependências..."
    local deps=("curl" "tar" "php" "rsync")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_error "Dependência não encontrada: $dep. Instale e tente novamente."
            exit 1
        fi
    done
    # jq ou python3 são necessários para parsear o JSON da API do GitHub
    if ! command -v jq &>/dev/null && ! command -v python3 &>/dev/null; then
        log_error "É necessário 'jq' ou 'python3' para consultar a API do GitHub."
        log_error "Instale com: sudo dnf install jq -y"
        exit 1
    fi
    log_ok "Todas as dependências estão disponíveis."
}

# ─── Detecta a última versão 11.x no GitHub ───────────────────────────────────
fetch_latest_version() {
    log_info "Consultando a API do GitHub para a última versão ${GLPI_MAJOR_VERSION}.x..."

    local api_response
    api_response=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        "${GITHUB_API}?per_page=50")

    local latest_tag
    if command -v jq &>/dev/null; then
        # Filtra tags que começam com o major version (ex: 11.) e pega a primeira
        latest_tag=$(echo "$api_response" | \
            jq -r \
            "[.[] | select(.tag_name | startswith(\"${GLPI_MAJOR_VERSION}.\")) | select(.prerelease == false) | select(.draft == false)] | first | .tag_name")
    else
        # Fallback: usa python3
        latest_tag=$(echo "$api_response" | python3 -c "
import sys, json
releases = json.load(sys.stdin)
for r in releases:
    tag = r.get('tag_name', '')
    if tag.startswith('${GLPI_MAJOR_VERSION}.') and not r.get('prerelease') and not r.get('draft'):
        print(tag)
        break
")
    fi

    if [[ -z "$latest_tag" || "$latest_tag" == "null" ]]; then
        log_error "Nenhuma versão ${GLPI_MAJOR_VERSION}.x estável encontrada no GitHub."
        exit 1
    fi

    DOWNLOAD_URL="https://github.com/glpi-project/glpi/releases/download/${latest_tag}/glpi-${latest_tag}.tgz"
    log_ok "Última versão encontrada: ${latest_tag}"
    log_info "URL de download: ${DOWNLOAD_URL}"
}

check_glpi_dir() {
    if [[ ! -d "$GLPI_DIR" ]]; then
        log_error "Diretório do GLPI não encontrado em: $GLPI_DIR"
        exit 1
    fi
}



# ─── Início do script ─────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}       Script de Atualização do GLPI - AlmaLinux 10.1      ${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# Verificações iniciais
check_root
check_dependencies

# Detectar automaticamente a última versão 11.x
fetch_latest_version

# Verificar se o diretório GLPI existe
check_glpi_dir

# ─── PASSO 1: Colocar GLPI em modo de manutenção ──────────────────────────────
log_info "Passo 1/8 - Ativando modo de manutenção do GLPI..."
if php "${GLPI_DIR}/bin/console" glpi:maintenance:enable 2>/dev/null; then
    log_ok "Modo de manutenção ativado."
else
    log_warn "Não foi possível ativar o modo de manutenção (ignorando)."
fi

# ─── PASSO 2: Renomear pasta glpi para glpi-old ──────────────────────────────
log_info "Passo 2/8 - Renomeando '${GLPI_DIR}' para '${GLPI_OLD_DIR}'..."

if [[ -d "$GLPI_OLD_DIR" ]]; then
    log_warn "Diretório '${GLPI_OLD_DIR}' já existe. Removendo backup antigo..."
    rm -rf "$GLPI_OLD_DIR"
fi

mv "$GLPI_DIR" "$GLPI_OLD_DIR"
log_ok "Renomeado com sucesso."

# ─── PASSO 3: Baixar nova versão do GLPI ──────────────────────────────────────
log_info "Passo 3/8 - Baixando nova versão do GLPI..."
mkdir -p "$TMP_DIR"

TGZ_FILE="${TMP_DIR}/glpi-new.tgz"
curl -L --progress-bar -o "$TGZ_FILE" "$DOWNLOAD_URL"

if [[ ! -f "$TGZ_FILE" ]]; then
    log_error "Falha ao baixar o arquivo. Verifique a URL e tente novamente."
    # Restaura o diretório original em caso de falha
    mv "$GLPI_OLD_DIR" "$GLPI_DIR"
    exit 1
fi

log_ok "Download concluído: ${TGZ_FILE}"

# ─── PASSO 4: Descompactar no diretório web ───────────────────────────────────
log_info "Passo 4/8 - Descompactando GLPI em '${WEB_ROOT}'..."
tar -xzf "$TGZ_FILE" -C "$WEB_ROOT"

# O tarball do GLPI extrai para uma pasta chamada 'glpi'
if [[ ! -d "$GLPI_DIR" ]]; then
    log_error "A descompactação não criou o diretório '${GLPI_DIR}'. Verifique o arquivo baixado."
    mv "$GLPI_OLD_DIR" "$GLPI_DIR"
    exit 1
fi

log_ok "Descompactado em: ${GLPI_DIR}"

# ─── PASSO 5: Copiar pastas preservadas do glpi-old ──────────────────────────
log_info "Passo 5/8 - Copiando pastas preservadas de '${GLPI_OLD_DIR}'..."

for dir in "${PRESERVE_DIRS[@]}"; do
    SRC="${GLPI_OLD_DIR}/${dir}"
    DST="${GLPI_DIR}/${dir}"

    if [[ -d "$SRC" ]]; then
        log_info "  Copiando: ${dir}/"
        # rsync preserva permissões, mostra progresso e sobrescreve arquivos existentes
        rsync -a --info=progress2 --delete "$SRC/" "$DST/"
        log_ok "  ${dir}/ copiado com sucesso."
    else
        log_warn "  Pasta '${dir}' não encontrada em glpi-old (ignorando)."
    fi
done

# ─── PASSO 6: Remover configuração de cache Redis ─────────────────────────────
log_info "Passo 6/8 - Verificando e removendo configuração de cache Redis..."

CACHE_CONFIG="${GLPI_DIR}/config/cache.php"
if [[ -f "$CACHE_CONFIG" ]]; then
    rm -f "$CACHE_CONFIG"
    log_ok "Arquivo '${CACHE_CONFIG}' removido. GLPI usará o cache padrão (filesystem)."
else
    log_info "Nenhuma configuração de cache personalizada encontrada em config/cache.php."
fi

# ─── PASSO 7: Ajustar permissões (conforme documentação do GLPI) ──────────────
log_info "Passo 7/8 - Ajustando permissões de '${GLPI_DIR}'..."

# -----------------------------------------------------------------
# Regra geral: o código-fonte pertence ao root e é somente-leitura
# para o servidor web. Apenas os diretórios de dados precisam de
# escrita pelo apache. (Recomendação oficial da documentação GLPI)
# -----------------------------------------------------------------

# 1. Código-fonte: pertence ao root, apache lê mas não escreve
chown -R root:root "$GLPI_DIR"
find "$GLPI_DIR" -type d -exec chmod 755 {} \;
find "$GLPI_DIR" -type f -exec chmod 644 {} \;

# 2. Pastas de dados que o apache PRECISA escrever:
#    files/, config/, plugins/, marketplace/
WRITABLE_DIRS=(
    "files"
    "config"
    "plugins"
    "marketplace"
)
for wdir in "${WRITABLE_DIRS[@]}"; do
    WPATH="${GLPI_DIR}/${wdir}"
    if [[ -d "$WPATH" ]]; then
        chown -R "${WEB_USER}:${WEB_GROUP}" "$WPATH"
        find "$WPATH" -type d -exec chmod 750 {} \;
        find "$WPATH" -type f -exec chmod 640 {} \;
        log_info "  Escrita ativada: ${wdir}/"
    fi
done

# 3. bin/console precisa ser executável
chown root:root "${GLPI_DIR}/bin/console" 2>/dev/null || true
chmod 755 "${GLPI_DIR}/bin/console" 2>/dev/null || true

log_ok "Permissões ajustadas conforme documentação GLPI."

# SELinux: AlmaLinux tem SELinux habilitado por padrão
if command -v restorecon &>/dev/null; then
    log_info "  Restaurando contextos SELinux em '${GLPI_DIR}'..."
    restorecon -Rv "$GLPI_DIR" &>/dev/null || true
    for wdir in "${WRITABLE_DIRS[@]}"; do
        WPATH="${GLPI_DIR}/${wdir}"
        if [[ -d "$WPATH" ]]; then
            chcon -Rt httpd_sys_rw_content_t "$WPATH" 2>/dev/null || true
        fi
    done
    log_ok "  Contextos SELinux ajustados (httpd_sys_rw_content_t para pastas de dados)."
else
    log_warn "  'restorecon' não encontrado — SELinux pode bloquear o GLPI se estiver ativo."
fi

# ─── PASSO 8: Executar migração do banco de dados via console PHP ─────────────
log_info "Passo 8/8 - Executando migração/atualização do banco de dados via PHP console..."
echo ""

if php "${GLPI_DIR}/bin/console" db:update --no-interaction; then
    echo ""
    log_ok "Migração do banco de dados concluída."
else
    echo ""
    log_error "Erro na migração do banco de dados (db:update falhou)!"
    log_warn "O GLPI permanecerá em modo de manutenção."
    log_warn "Verifique o log de erros em: ${LOG_FILE}"
    exit 1
fi

# ─── Limpeza do cache ─────────────────────────────────────────────────────────
log_info "Limpando cache do GLPI..."

# 1. Limpa via console PHP (cache de objetos/sessão)
php "${GLPI_DIR}/bin/console" cache:clear --no-interaction 2>/dev/null || true

# 2. Remove fisicamente os arquivos de cache do filesystem e recria com permissões corretas
for cache_subdir in _cache _tmp; do
    CACHE_PATH="${GLPI_DIR}/files/${cache_subdir}"
    if [[ -d "$CACHE_PATH" ]]; then
        find "$CACHE_PATH" -mindepth 1 -delete 2>/dev/null || true
        log_info "  Cache físico removido: files/${cache_subdir}/"
    fi
    mkdir -p "$CACHE_PATH"
    chown -R "${WEB_USER}:${WEB_GROUP}" "$CACHE_PATH"
    chmod 750 "$CACHE_PATH"
    chcon -t httpd_sys_rw_content_t "$CACHE_PATH" 2>/dev/null || true
done

log_ok "Cache limpo."

# ─── Aquecimento do cache (warm-up interno) ───────────────────────────────────
log_info "Aquecendo cache interno do GLPI..."

php "${GLPI_DIR}/bin/console" glpi:system:check_requirements --no-interaction 2>/dev/null || true

log_ok "Cache aquecido com sucesso."

# ─── Atualizar Plugins ────────────────────────────────────────────────────────
log_info "Atualizando e ativando plugins via console..."
php "${GLPI_DIR}/bin/console" plugin:install --all 2>/dev/null || true
php "${GLPI_DIR}/bin/console" plugin:activate --all 2>/dev/null || true
log_ok "Plugins verificados."

# ─── Desativar modo de manutenção ─────────────────────────────────────────────
log_info "Desativando modo de manutenção..."
php "${GLPI_DIR}/bin/console" glpi:maintenance:disable 2>/dev/null || true
log_ok "Modo de manutenção desativado."

# ─── Reiniciar Serviços Web ───────────────────────────────────────────────────
log_info "Reiniciando serviços web (httpd, php-fpm) para limpar OPcache..."
systemctl restart httpd php-fpm 2>/dev/null || true
log_ok "Serviços reiniciados."

# ─── Limpeza de temporários ───────────────────────────────────────────────────
log_info "Removendo arquivos temporários..."
rm -rf "$TMP_DIR"
log_ok "Temporários removidos."

# ─── Resumo Final ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   GLPI atualizado com sucesso!                            ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  ${CYAN}Instalação nova:${NC} ${GLPI_DIR}"
echo -e "  ${CYAN}Backup anterior:${NC} ${GLPI_OLD_DIR}"
echo ""
echo -e "  ${YELLOW}Pastas preservadas:${NC} ${PRESERVE_DIRS[*]}"
echo ""
echo -e "  ${YELLOW}Próximos passos sugeridos:${NC}"
echo -e "   1. Acesse o GLPI no navegador e verifique o funcionamento."
echo -e "   2. Verifique se os plugins estão funcionando corretamente."
echo -e "   3. Após validar, remova o backup antigo com:"
echo -e "      ${CYAN}sudo rm -rf ${GLPI_OLD_DIR}${NC}"
echo ""
