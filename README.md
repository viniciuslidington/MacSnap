# MacSnap 🪟⚡

Gerenciador nativo de janelas para macOS construído em **Swift puro**, trazendo os recursos de **Snap** e **divisão interativa** do Windows para o Mac.

---

## 🎯 Recursos Implementados

1. **Aero Snap / Edge Snapping**:
   - Arrastar a janela para a borda esquerda/direita: divide a tela em metades (50/50).
   - Arrastar para o topo: maximiza a janela respeitando a barra de menus e o Dock.
   - Arrastar para os quatro cantos: divide a tela em quadrantes (25%).
2. **Apple Glass UI & Preview Translúcido**:
   - Efeito *frosted glass* translúcido (`NSVisualEffectView` com material popover vibrante) com tom cinza claro e bordas especulares lapidadas com brilho interno, inspirado na linguagem visual nativa da Apple (VisionOS e macOS).
3. **Snap Bar Adaptativa no Topo (Windows 11 Style)**:
   - Ao arrastar qualquer janela em direção ao topo da tela, uma barra deslizante em vidro fosco Apple Glass se abre oferecendo templates prontos com destaque em cinza claro translúcido e bordas luminosas:
   - **Telas Horizontais (16:9 / Ultrawide):**
     - **2 Colunas (50/50):** Esquerda e Direita.
     - **3 Colunas (1/3 cada):** Esquerda, Centro e Direita.
     - **Assimétrico (2/3 + 1/3):** Esquerda 2/3 e Direita 1/3.
     - **Assimétrico Inverso (1/3 + 2/3):** Esquerda 1/3 e Direita 2/3.
     - **4 Quadrantes (2x2):** Cantos da tela.
     - **Maximizar:** Tela cheia.
   - **Telas Verticais (Portrait):**
     - **Metades Verticais:** Topo (1/2) e Base (1/2).
     - **Terços Verticais:** Topo (1/3), Centro (1/3) e Base (1/3).
     - **Dois Terços:** Topo (2/3) e Base (1/3).
     - **Dois Terços Inverso:** Topo (1/3) e Base (2/3).
     - **Maximizar:** Tela cheia vertical.
4. **Janelas Emparelhadas & Divisor Interativo Multi-Monitor (Snap Assist)**:
   - **Auto-Reconhecimento de Janelas Existentes**: Detecta automaticamente janelas que já estão posicionadas lado a lado ou empilhadas na mesma tela (mesmo sem ter usado o snap), conectando o divisor de intersecção na inicialização, ao alternar entre aplicativos ou sob demanda.
   - **Exibição Inteligente sob Demanda (*Hover-Only*)**: O divisor e o botão de ajuste permanecem 100% invisíveis durante o uso normal para não poluir a tela, surgindo com fade-in suave de vidro (*Apple Glass*) somente quando o cursor se aproxima da junção entre as janelas.
   - **Suporte Multi-Monitor Persistente**: Cada tela conectada mantém seu par ativo de forma completamente independente. Ajustar janelas em um monitor horizontal não cancela nem "esquece" as janelas emparelhadas no monitor vertical.
   - Cursor adaptativo: `⬌` para horizontal e `⬍` para vertical.
   - **Atração Magnética Suave:** Ao arrastar perto de 50/50, 33/67 ou 67/33, o divisor puxa suavemente para facilitar travar a proporção.
5. **Ícone Vetorizado na Barra de Menus (`NSStatusItem`)**:
   - Ícone exclusivo vetorizado em proporção nativa Retina com estilo visual de janelas emparelhadas e barras de título macOS.
   - Menu dedicado com submenus para layouts horizontais (16:9) e verticais, além de checagem de permissões.
   - Roda como aplicativo de fundo (`LSUIElement` / `.accessory`), sem poluir o Dock.

---

## 🏛 Arquitetura e Estrutura de Código

O projeto foi estruturado seguindo os princípios de **Clean Architecture**, **SOLID** e compatibilidade com **Swift 6 Concurrency**:

```text
Sources/MacSnap/
├── App/
│   ├── main.swift                       # Ponto de entrada (define modo acessório)
│   └── AppDelegate.swift                # Ciclo de vida da aplicação e inicialização dos serviços
│
├── Core/
│   ├── Models/
│   │   ├── SnapZone.swift               # Enums e cálculos geométricos para as zonas de ancoragem
│   │   ├── ScreenGeometry.swift         # Conversão de coordenadas entre Cocoa e Accessibility API
│   │   ├── WindowElement.swift          # Wrapper tipado sobre AXUIElement
│   │   └── PairedSplit.swift            # Modelo matemático de janelas emparelhadas e proporção
│   └── Protocols/
│       └── Protocols.swift              # Contratos e abstrações (para testabilidade)
│
├── Services/
│   ├── Accessibility/
│   │   └── AccessibilityService.swift   # Comunicação com a Accessibility API (HIServices)
│   ├── Screen/
│   │   └── ScreenService.swift          # Cálculo de telas e monitores múltiplos
│   └── EventMonitoring/
│       └── GlobalEventMonitor.swift     # Escuta de eventos globais de mouse via CGEventTap
│
└── Features/
    ├── Snapping/
    │   └── SnapEngine.swift             # Orquestrador de aplicação do Snap
    ├── Pairing/
    │   └── PairedResizeManager.swift    # Gerencia o emparelhamento e divisão sincronizada
    └── UI/
        ├── PreviewOverlayWindow.swift   # Janela translúcida de pré-visualização
        ├── DividerHandleWindow.swift    # Barra divisória arrastável entre janelas
        └── MenuBarController.swift      # Menu da barra superior do sistema
```

---

## 🧪 Testes Unitários

O projeto conta com suíte de testes usando a biblioteca moderna de testes do Swift (`import Testing`):

```bash
swift test
```

Testa:
- Cálculos matemáticos de cada `SnapZone` em telas de diferentes resoluções.
- Conversão bidirecional de coordenadas entre **Cocoa (origem inferior-esquerda)** e **Accessibility API (origem superior-esquerda)**.
- Regras de proporção e limites de trava (*clamping*) de janelas emparelhadas.

---

## 🚀 Como Executar e Instalar

### 1. Instalação e Inicialização Automática (Recomendado)

Disponibilizamos um script que compila a versão otimizada de produção, monta o pacote nativo `MacSnap.app` em `/Applications` e configura a inicialização automática com o macOS:

```bash
./scripts/install.sh
```

Depois de instalado:
- O **MacSnap** iniciará automaticamente todas as vezes que você ligar ou fizer login no Mac.
- Você também pode ativar/desativar a inicialização a qualquer momento clicando no ícone do MacSnap na barra de menus e selecionando **"✓ Iniciar com o Mac"**.
- Para desinstalar e remover do início automático, execute:
  ```bash
  ./scripts/uninstall.sh
  ```

### 2. Compilação Manual via Linha de Comando

```bash
swift build -c release
```

### 3. Abrir no Xcode

Basta abrir o diretório no Xcode:

```bash
open Package.swift
```

### 4. Permissão de Acessibilidade

Para que o macOS permita ao MacSnap redimensionar janelas de outros apps:
1. Ao iniciar pela primeira vez, o sistema exibirá uma solicitação de permissão.
2. Caso não abra automaticamente, vá em:
   **Ajustes do Sistema > Privacidade e Segurança > Acessibilidade**
3. Habilite o aplicativo `MacSnap` (localizado em `/Applications/MacSnap.app`).
