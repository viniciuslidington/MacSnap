#!/bin/bash
set -e

# ==============================================================================
# MacSnap - Script de Instalação e Inicialização Automática com o macOS
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacSnap.app"
DEST_DIR="/Applications"
APP_DEST="$DEST_DIR/$APP_NAME"
PLIST_LABEL="com.viniciuslidington.MacSnap"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/$PLIST_LABEL.plist"

echo "=========================================================="
echo "🚀 Instalando o MacSnap no macOS"
echo "=========================================================="

# 1. Compila a versão Release otimizada
echo "📦 Compilando binário de produção (Release)..."
cd "$PROJECT_DIR"
swift build -c release

RELEASE_BIN="$PROJECT_DIR/.build/out/Products/Release/MacSnap"
if [ ! -f "$RELEASE_BIN" ]; then
    # Fallback para o caminho padrão do Swift PM se diferente
    RELEASE_BIN=$(find "$PROJECT_DIR/.build" -type f -name "MacSnap" -perm +111 | grep -i "release" | head -n 1)
fi

if [ ! -f "$RELEASE_BIN" ]; then
    echo "❌ Erro: Binário compilado não foi encontrado."
    exit 1
fi

# 2. Cria a estrutura do pacote .app
echo "📁 Montando o pacote $APP_NAME..."
TMP_APP="/tmp/$APP_NAME"
rm -rf "$TMP_APP"
mkdir -p "$TMP_APP/Contents/MacOS"
mkdir -p "$TMP_APP/Contents/Resources"

# Copia o binário
cp "$RELEASE_BIN" "$TMP_APP/Contents/MacOS/MacSnap"
chmod +x "$TMP_APP/Contents/MacOS/MacSnap"

# Copia o Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$TMP_APP/Contents/Info.plist"

# Copia o ícone se existir
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$TMP_APP/Contents/Resources/AppIcon.icns"
fi

# 3. Assinatura Ad-hoc para execução segura no macOS
echo "🔏 Aplicando assinatura ad-hoc (codesign)..."
codesign --force --deep --sign - "$TMP_APP"

# 4. Instala em /Applications
echo "📂 Copiando para $DEST_DIR..."
# Se já estiver rodando, encerra a versão anterior
pkill -x "MacSnap" || true
rm -rf "$APP_DEST"
cp -R "$TMP_APP" "$APP_DEST"
rm -rf "$TMP_APP"

# 5. Configura o LaunchAgent para Iniciar com o Mac
echo "⚙️ Configurando inicialização automática no login do usuário..."
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
</dict>
</plist>
EOF

# Registra e ativa o LaunchAgent (que já inicia o app automaticamente)
launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_PATH"

echo "=========================================================="
echo "✅ MacSnap instalado com sucesso em: $APP_DEST"
echo "✅ Inicialização automática configurada em: $LAUNCH_AGENT_PATH"
echo "=========================================================="
echo ""
echo "💡 Dica: O MacSnap opera na barra de menus superior."
echo "Se for a primeira execução, certifique-se de conceder a permissão em:"
echo "   👉 Ajustes do Sistema > Privacidade e Segurança > Acessibilidade"
echo ""
