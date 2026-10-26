# MacSnap 🪟⚡

> Gerenciador nativo de janelas para macOS construído em **Swift puro**, trazendo a facilidade e os recursos de **Snap Layouts** e **divisão interativa** do Windows 11 para o ecossistema Mac com a estética visual **Apple Glass UI**.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift&logoColor=white)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%2B%20Intel)-purple)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## ⚡ Instalação Rápida via Linha de Comando

Para instalar o **MacSnap** no seu Mac em segundos, abra o **Terminal** e execute:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/viniciuslidington/MacSnap/main/install.sh)"
```

> **O que o comando faz:**
> 1. Baixa o pacote universal pré-compilado de produção e instala em `/Applications/MacSnap.app`.
> 2. Configura a inicialização automática silenciosa em segundo plano com o macOS via LaunchAgent.
> 3. Inicia o MacSnap e abre o painel de Acessibilidade nos Ajustes do Sistema para habilitar a permissão.

### Desinstalação

Caso queira desinstalar completamente o MacSnap e remover a inicialização automática a qualquer momento:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/viniciuslidington/MacSnap/main/install.sh)" -- --uninstall
```

---

## 🎯 Recursos Principais

### 1. 🪟 Snap Bar no Topo (Windows 11 Style)
- **Pílula Retrátil Apple Glass**: Ao segurar e arrastar uma aba ou janela, surge discretamente no topo da tela ativa uma pílula achatada de vidro translúcido com o ícone vetorial de divisão de tela.
- **Rastreamento Multi-Monitor**: A barra acompanha dinamicamente o monitor onde o cursor do mouse está localizado, migrando fluidamente entre telas horizontais e verticais.
- **Expansão sob Demanda**: Ao aproximar o cursor da pílula, ela se expande fluidamente revelando os templates de layout geométricos sem poluição de texto. Se o cursor se afastar, ela se recolhe de volta para a pílula.
- **Templates para Monitores Horizontais (16:9 / Ultrawide):**
  - **2 Colunas (50/50):** Metade Esquerda e Metade Direita.
  - **3 Colunas (1/3 cada):** Esquerda, Centro e Direita.
  - **Assimétrico (2/3 + 1/3):** Esquerda 2/3 e Direita 1/3.
  - **Assimétrico Inverso (1/3 + 2/3):** Esquerda 1/3 e Direita 2/3.
  - **4 Quadrantes (2x2):** Quatro cantos da tela.
  - **Maximizar:** Preenchimento completo da tela visível.
- **Templates para Monitores Verticais (Portrait):**
  - **Metades Verticais:** Topo (1/2) e Base (1/2).
  - **Terços Verticais:** Topo (1/3), Centro (1/3) e Base (1/3).
  - **Dois Terços:** Topo (2/3) e Base (1/3).
  - **Dois Terços Inverso:** Topo (1/3) e Base (2/3).
  - **Maximizar Vertical:** Tela cheia vertical.

### 2. ⚡ Aero Snap / Ancoragem pelas Bordas da Tela
- **Borda Esquerda / Direita:** Encaixa a janela em metade da tela (50/50).
- **Topo da Tela:** Maximiza a janela respeitando a barra de menus e o Dock.
- **Quatro Cantos:** Divide a tela em quadrantes de 25%.
- **Bordas Laterais em Monitores Verticais:** Divide em terços (1/3) de acordo com a altura em que o mouse atinge a borda.

### 3. 🎨 Design Apple Glass UI & Pré-Visualização Translúcida
- Efeito *frosted glass* translúcido (`NSVisualEffectView` com material popover vibrante) com tom cinza claro, reflexos especulares lapidados e bordas luminosas.
- Alta transparência calibrada para não bloquear a leitura do conteúdo subjacente.
- Nível de exibição de camadas otimizado: o modal de layouts sempre se sobrepõe ao retângulo de prévia, garantindo visibilidade e referência contínuas.

### 4. 🔗 Janelas Emparelhadas & Divisor Interativo Multi-Monitor (Snap Assist)
- **Auto-Reconhecimento de Janelas Existentes**: Detecta automaticamente janelas que já estão posicionadas lado a lado ou empilhadas na mesma tela (mesmo que tenham sido posicionadas manualmente), conectando um divisor de redimensionamento na junção entre elas.
- **Exibição Inteligente sob Demanda (*Hover-Only*)**: O divisor e o controle de ajuste permanecem 100% invisíveis durante o uso normal para não poluir a tela, surgindo com fade-in suave de vidro (*Apple Glass*) apenas quando o cursor se aproxima da borda entre as duas janelas.
- **Suporte Multi-Monitor Persistente**: Cada monitor mantém seu estado de janelas emparelhadas de forma completamente independente. Ajustar janelas em um monitor horizontal não reseta o par do monitor vertical.
- **Atração Magnética Suave:** Ao arrastar o divisor próximo a 50/50, 33/67 ou 67/33, o cursor é puxado suavemente para facilitar o travamento da proporção exata.

### 5. 🍏 Barra de Menus do macOS (`NSStatusItem`)
- Ícone vetorizado nativo Retina no estilo de janelas emparelhadas.
- Menu de contexto com atalhos rápidos para layouts em 1 clique, verificação de status da permissão de Acessibilidade e alternância de inicialização com o Mac.
- Opera como utilitário de fundo leve (`LSUIElement` / `.accessory`), consumindo poucos megabytes de memória RAM e zero impacto de bateria.

---

## 🏛 Arquitetura do Projeto

Construído em conformidade com as diretrizes do **Swift 6 Concurrency**, **Clean Architecture** e **SOLID**:

```text
Sources/MacSnap/
├── App/
│   ├── main.swift                       # Ponto de entrada (define modo acessório)
│   └── AppDelegate.swift                # Ciclo de vida e orquestração dos serviços
│
├── Core/
│   ├── Models/
│   │   ├── SnapZone.swift               # Enums e cálculos geométricos das zonas de encaixe
│   │   ├── ScreenGeometry.swift         # Conversão de coordenadas Cocoa <-> Accessibility API
│   │   ├── WindowElement.swift          # Wrapper tipado sobre AXUIElement com anti-clamp sizing
│   │   └── PairedSplit.swift            # Modelo matemático de janelas emparelhadas e proporção
│   └── Protocols/
│       └── Protocols.swift              # Contratos e abstrações para injeção de dependência
│
├── Services/
│   ├── Accessibility/
│   │   └── AccessibilityService.swift   # Comunicação com Accessibility API (HIServices) com 5 níveis de fallback
│   ├── Screen/
│   │   └── ScreenService.swift          # Descoberta de telas, orientação e coordenadas de monitores
│   └── EventMonitoring/
│       └── GlobalEventMonitor.swift     # Escuta de eventos globais de mouse via CGEventTap
│
└── Features/
    ├── Snapping/
    │   └── SnapEngine.swift             # Mecanismo central de ancoragem e ajuste de janelas
    ├── Pairing/
    │   └── PairedResizeManager.swift    # Gerenciador multi-monitor de janelas emparelhadas e divisores
    └── UI/
        ├── SnapLayoutBarWindow.swift    # Janela flutuante Apple Glass do menu de layouts (Pílula e Expandido)
        ├── PreviewOverlayWindow.swift   # Janela translúcida de pré-visualização de encaixe
        ├── DividerHandleWindow.swift    # Barra divisória interativa entre janelas
        └── MenuBarController.swift      # Controlador do menu superior do sistema
```

---

## 🧪 Testes Unitários

O projeto possui suíte de testes automatizados com o framework moderno de testes do Swift (`import Testing`):

```bash
swift test
```

Cobre:
- Cálculos geométricos de todas as `SnapZone` para resoluções horizontais, verticais e ultrawide.
- Conversão bidirecional de coordenadas entre **Cocoa** (origem no canto inferior-esquerdo) e **Accessibility API** (origem no canto superior-esquerdo).
- Transições de estado entre modo pílula, expansão por hover e recolhimento no menu de layouts.
- Independência de destaque visual de slots para cartões com zonas compartilhadas.
- Algoritmo de auto-detecção de janelas vizinhas e persistência de pares em múltiplos monitores simultâneos.

---

## 🛠 Compilação a Partir do Código-Fonte

Caso queira clonar e compilar o projeto localmente:

### Requisitos:
- macOS 13.0 (Ventura) ou superior
- Xcode 15+ ou Command Line Tools com suporte a Swift 6

```bash
# 1. Clone o repositório
git clone https://github.com/viniciuslidington/MacSnap.git
cd MacSnap

# 2. Compile e instale localmente
./scripts/install.sh
```

---

## 🔒 Permissões de Acessibilidade

O macOS exige permissão de **Acessibilidade** para que qualquer software possa ler dimensões e mover janelas de outros aplicativos:

1. Ao abrir o MacSnap pela primeira vez, uma caixa de diálogo do sistema solicitará acesso.
2. Você também pode habilitar a qualquer momento acessando:
   **Ajustes do Sistema > Privacidade e Segurança > Acessibilidade**
3. Ative a chave ao lado de **MacSnap**.

---

## 📄 Licença

Distribuído sob a licença MIT. Veja `LICENSE` para mais informações.
