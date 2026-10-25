# MacSnap 🪟⚡

Gerenciador nativo de janelas para macOS construído em **Swift puro**, trazendo os recursos de **Snap** e **divisão interativa** do Windows para o Mac.

---

## 🎯 Recursos Implementados

1. **Aero Snap / Edge Snapping**:
   - Arrastar a janela para a borda esquerda/direita: divide a tela em metades (50/50).
   - Arrastar para o topo: maximiza a janela respeitando a barra de menus e o Dock.
   - Arrastar para os quatro cantos: divide a tela em quadrantes (25%).
2. **Preview Overlay Translúcido**:
   - Sombra estilizada em efeito *frosted glass* (`NSVisualEffectView`) que mostra a área antes de você soltar a janela.
3. **Janelas Emparelhadas & Divisor Central (Windows Snap Assist)**:
   - Quando duas janelas são posicionadas lado a lado, uma **barra divisória flutuante interativa** (`DividerHandleWindow`) surge na junção.
   - Ao arrastar esse divisor central com o cursor `⬌`, **ambas as janelas são redimensionadas simultaneamente**, mantendo a tela preenchida de forma proporcional.
4. **Ícone na Barra de Menus (`NSStatusItem`)**:
   - Permite verificar permissões de acessibilidade em tempo real e acionar snaps manuais.
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

## 🚀 Como Executar

### 1. Compilação via Linha de Comando

```bash
swift build
```

Para executar o binário diretamente:

```bash
.build/debug/MacSnap
```

### 2. Abrir no Xcode

Basta abrir o diretório no Xcode:

```bash
open Package.swift
```

### 3. Permissão de Acessibilidade

Para que o macOS permita ao MacSnap redimensionar janelas de outros apps:
1. Ao iniciar, o sistema exibirá uma solicitação de permissão.
2. Caso não abra automaticamente, vá em:
   **Ajustes do Sistema > Privacidade e Segurança > Acessibilidade**
3. Habilite o terminal ou o aplicativo `MacSnap`.
