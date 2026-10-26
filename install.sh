#!/usr/bin/env bash
set -e

# ==============================================================================
#  __  __            ____                  
# |  \/  | __ _  ___/ ___| _ __   __ _ _ __ 
# | |\/| |/ _` |/ __\___ \| '_ \ / _` | '__|
# | |  | | (_| | (__ ___) | | | | (_| | |   
# |_|  |_|\__,_|\___|____/|_| |_|\__,_|_|   
#
# Instalador automático via linha de comando para macOS
# Repositório: https://github.com/viniciuslidington/MacSnap
# ==============================================================================

REPO="viniciuslidington/MacSnap"
APP_NAME="MacSnap.app"
DEST_DIR="/Applications"
APP_DEST="$DEST_DIR/$APP_NAME"
PLIST_LABEL="com.viniciuslidington.MacSnap"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/$PLIST_LABEL.plist"
RELEASE_URL="https://github.com/$REPO/releases/latest/download/MacSnap.app.zip"

# Cores do terminal
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. Suporte a desinstalação (--uninstall / -u)
if [[ "$1" == "--uninstall" ]] || [[ "$1" == "-u" ]]; then
    echo -e "${YELLOW}🛑 Desinstalando o MacSnap...${NC}"
    pkill -x "MacSnap" 2>/dev/null || true
    if [ -f "$LAUNCH_AGENT_PATH" ]; then
        launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT_PATH"
        echo -e "  ${GREEN}✓${NC} Inicialização automática removida de LaunchAgents"
    fi
    if [ -d "$APP_DEST" ]; then
        rm -rf "$APP_DEST"
        echo -e "  ${GREEN}✓${NC} $APP_DEST removido"
    fi
    echo -e "\n${GREEN}${BOLD}✅ MacSnap desinstalado com sucesso!${NC}\n"
    exit 0
fi

# 2. Verificação de sistema operacional
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${RED}❌ Erro: O MacSnap é exclusivo para macOS.${NC}"
    exit 1
fi

echo -e "${BLUE}${BOLD}"
echo "  __  __            ____                  "
echo " |  \/  | __ _  ___/ ___| _ __   __ _ _ __ "
echo " | |\/| |/ _\` |/ __\___ \| '_ \ / _\` | '__|"
echo " | |  | | (_| | (__ ___) | | | | (_| | |   "
echo " |_|  |_|\__,_|\___|____/|_| |_|\__,_|_|   "
echo -e "${NC}"
echo -e "${BOLD}🪟 Instalando o MacSnap no seu Mac...${NC}"
echo "----------------------------------------------------------"

# Encerra qualquer instância em execução antes da atualização
pkill -x "MacSnap" 2>/dev/null || true

INSTALLED=false

# 3. Se estiver rodando dentro do repositório local clonado, executa o script local
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/Package.swift" ] && [ -f "$SCRIPT_DIR/scripts/install.sh" ]; then
    echo -e "${BLUE}ℹ️  Executando instalador local do projeto...${NC}"
    bash "$SCRIPT_DIR/scripts/install.sh"
    exit 0
fi

# 4. Modo Remoto: tenta baixar o pacote binário pré-compilado do GitHub Releases
echo -e "📥 Baixando versão oficial mais recente..."
TMP_DIR=$(mktemp -d /tmp/macsnap-install-XXXXXX)
ZIP_FILE="$TMP_DIR/MacSnap.app.zip"

if curl -f -L --progress-bar "$RELEASE_URL" -o "$ZIP_FILE" 2>/dev/null; then
    echo -e "📦 Descompactando aplicativo..."
    unzip -q -o "$ZIP_FILE" -d "$TMP_DIR"
    
    if [ -d "$TMP_DIR/$APP_NAME" ]; then
        rm -rf "$APP_DEST"
        cp -R "$TMP_DIR/$APP_NAME" "$APP_DEST"
        INSTALLED=true
        echo -e "  ${GREEN}✓${NC} Aplicativo instalado em $APP_DEST"
    fi
fi

# 5. Fallback: se não houver release disponível ou download falhar, compila via código-fonte
if [ "$INSTALLED" = false ]; then
    echo -e "${YELLOW}⚡ Pacote pré-compilado não encontrado. Compilando do código-fonte...${NC}"
    
    if ! command -v swift >/dev/null 2>&1; then
        echo -e "${RED}❌ Erro: O compilador Swift não foi encontrado no seu sistema.${NC}"
        echo -e "Instale as ferramentas de linha de comando com: ${BOLD}xcode-select --install${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    SRC_DIR="$TMP_DIR/source"
    git clone --depth 1 "https://github.com/$REPO.git" "$SRC_DIR"
    bash "$SRC_DIR/scripts/install.sh"
    rm -rf "$TMP_DIR"
    exit 0
fi

rm -rf "$TMP_DIR"

# 6. Remove quarentena do Gatekeeper e reaplica assinatura segura
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DEST" 2>/dev/null || true

# 7. Configura inicialização automática no login do usuário (LaunchAgent)
echo -e "⚙️  Configurando inicialização automática..."
mkdir -p "$LAUNCH_AGENT_DIR"

cat <<EOF > "$LAUNCH_AGENT_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_DEST/Contents/MacOS/MacSnap</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/MacSnap.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/MacSnap.log</string>
</dict>
</plist>
EOF

launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_PATH" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} LaunchAgent registrado ($LAUNCH_AGENT_PATH)"

# 8. Inicia o aplicativo
open "$APP_DEST" 2>/dev/null || "$APP_DEST/Contents/MacOS/MacSnap" &

echo "----------------------------------------------------------"
echo -e "${GREEN}${BOLD}🎉 MacSnap instalado e iniciado com sucesso!${NC}"
echo "----------------------------------------------------------"
echo -e "\n${BOLD}⚠️  ATENÇÃO (Permissão de Acessibilidade):${NC}"
echo "O MacSnap precisa da permissão de Acessibilidade para gerenciar janelas."
echo -e "Se for a primeira vez instalando, habilite o ${BOLD}MacSnap${NC} em:"
echo -e "   👉 ${BLUE}Ajustes do Sistema > Privacidade e Segurança > Acessibilidade${NC}\n"

# Abre automaticamente o painel de Acessibilidade nos Ajustes para conveniência do usuário
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
