import Cocoa
import CoreGraphics

/// Monitora eventos globais de cursor do mouse usando `CGEventTap` para detectar
/// quando o usuário arrasta uma janela até as bordas da tela e aciona o Snap.
/// Possui suporte inteligente para monitores verticais com a Snap Bar de layouts.
@MainActor
public final class GlobalEventMonitor: EventMonitoringProtocol {
    public static let shared = GlobalEventMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeZone: SnapZone?
    private var activeScreen: NSScreen?
    private var currentDraggedWindow: WindowElement?

    private let screenService: ScreenServiceProtocol
    private let accessibilityService: AccessibilityServiceProtocol
    private let previewOverlay: PreviewOverlayWindow
    private let snapLayoutBar: SnapLayoutBarWindow
    private let snapEngine: WindowSnappingProtocol

    public init(
        screenService: ScreenServiceProtocol = ScreenService.shared,
        accessibilityService: AccessibilityServiceProtocol = AccessibilityService.shared,
        snapEngine: WindowSnappingProtocol = SnapEngine.shared
    ) {
        self.screenService = screenService
        self.accessibilityService = accessibilityService
        self.snapEngine = snapEngine
        self.previewOverlay = PreviewOverlayWindow()
        self.snapLayoutBar = SnapLayoutBarWindow()
    }

    public func startMonitoring() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo = userInfo else {
                return Unmanaged.passRetained(event)
            }
            let monitor = Unmanaged<GlobalEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in
                monitor.handleEvent(type: type, event: event)
            }
            return Unmanaged.passRetained(event)
        }

        let observer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: observer
        )

        guard let tap = eventTap else {
            print("[GlobalEventMonitor] Aviso: Não foi possível criar o CGEventTap. Verifique permissões de Acessibilidade.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[GlobalEventMonitor] Monitoramento de arraste ativado.")
    }

    public func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let mouseLocation = NSEvent.mouseLocation

        switch type {
        case .leftMouseDragged:
            handleDrag(at: mouseLocation)
        case .leftMouseUp:
            handleRelease()
        default:
            break
        }
    }

    private func handleDrag(at point: CGPoint) {
        guard let screen = screenService.screenContaining(point: point) else { return }

        // Captura a janela que está sendo arrastada no início do movimento antes que o foco mude
        if currentDraggedWindow == nil {
            currentDraggedWindow = accessibilityService.getFocusedWindow()
        }

        let visibleFrame = screen.visibleFrame
        let edgeThreshold: CGFloat = 20.0
        let cornerThreshold: CGFloat = 80.0
        let isPortrait = screen.isPortrait

        let isLeft = point.x <= visibleFrame.minX + edgeThreshold
        let isRight = point.x >= visibleFrame.maxX - edgeThreshold
        let isTop = point.y >= visibleFrame.maxY - edgeThreshold
        let isBottom = point.y <= visibleFrame.minY + edgeThreshold

        let isNearTop = point.y >= visibleFrame.maxY - cornerThreshold
        let isNearBottom = point.y <= visibleFrame.minY + cornerThreshold

        var detectedZone: SnapZone?

        // 1. MONITOR VERTICAL: Tratamento especial com 50/50 no topo/base e 1/3 nas laterais
        if isPortrait {
            let topZoneThreshold: CGFloat = 160.0
            let isInsideBar = snapLayoutBar.frame.insetBy(dx: -20, dy: -20).contains(point)
            let isApproachingTop = (point.y >= visibleFrame.maxY - topZoneThreshold) || isInsideBar

            if isApproachingTop {
                // Abre a barra flutuante com layouts otimizados para monitores verticais
                snapLayoutBar.present(on: screen)

                // Verifica se o usuário está pairando sobre um dos cards da barra
                if let hoveredBarZone = snapLayoutBar.checkHover(at: point) {
                    detectedZone = hoveredBarZone
                } else if isTop {
                    // Regra: Vértices superiores e borda superior padronizados em 50/50 (Metade Superior)
                    detectedZone = .topHalf
                }
            } else {
                snapLayoutBar.dismiss()
            }

            // Ações nas outras bordas do monitor vertical
            if detectedZone == nil {
                if isBottom {
                    // Regra: Vértices inferiores e borda inferior padronizados em 50/50 (Metade Inferior)
                    detectedZone = .bottomHalf
                } else if isLeft || isRight {
                    // Regra: Bordas laterais sugerem a divisão em 1/3 de acordo com a altura do cursor
                    let relativeY = point.y - visibleFrame.minY
                    let thirdHeight = visibleFrame.height / 3.0

                    if relativeY >= (thirdHeight * 2.0) {
                        detectedZone = .topThird
                    } else if relativeY >= thirdHeight {
                        detectedZone = .middleThird
                    } else {
                        detectedZone = .bottomThird
                    }
                }
            }
        } else {
            // 2. MONITOR HORIZONTAL (16:9 / Ultrawide)
            let topZoneThreshold: CGFloat = 160.0
            let isInsideBar = snapLayoutBar.frame.insetBy(dx: -20, dy: -20).contains(point)
            let isApproachingTop = (point.y >= visibleFrame.maxY - topZoneThreshold) || isInsideBar

            if isApproachingTop {
                // Abre a barra flutuante com layouts adaptados para telas horizontais (50/50, 3 colunas, 2/3, 1/3, quadrantes, maximizar)
                snapLayoutBar.present(on: screen)

                // Verifica se o usuário está pairando sobre um dos cards da barra
                if let hoveredBarZone = snapLayoutBar.checkHover(at: point) {
                    detectedZone = hoveredBarZone
                } else if isTop {
                    detectedZone = .maximize
                }
            } else {
                snapLayoutBar.dismiss()
            }

            if detectedZone == nil {
                // Detecção de cantos (quadrantes)
                if isLeft && isNearTop {
                    detectedZone = .topLeftQuarter
                } else if isRight && isNearTop {
                    detectedZone = .topRightQuarter
                } else if isLeft && isNearBottom {
                    detectedZone = .bottomLeftQuarter
                } else if isRight && isNearBottom {
                    detectedZone = .bottomRightQuarter
                // Metades e maximização
                } else if isTop {
                    detectedZone = .maximize
                } else if isLeft {
                    detectedZone = .leftHalf
                } else if isRight {
                    detectedZone = .rightHalf
                } else if isBottom {
                    detectedZone = .bottomHalf
                }
            }
        }

        if let zone = detectedZone {
            self.activeZone = zone
            self.activeScreen = screen

            // Preview dinâmico inteligente: se houver parceiro (como Xcode), a caixa azul
            // para exatamente na borda dele, evitando a sobreposição visual feia na tela
            let targetRect: CGRect
            if let flush = PairedResizeManager.shared.calculateFlushTargetRect(for: zone, screen: screen, windowToExclude: currentDraggedWindow) {
                targetRect = flush.targetRect
            } else {
                targetRect = zone.targetRect(for: visibleFrame)
            }

            self.previewOverlay.present(at: targetRect, animated: true)
        } else {
            if self.activeZone != nil {
                self.activeZone = nil
                self.activeScreen = nil
                self.previewOverlay.dismiss()
            }
        }
    }

    private func handleRelease() {
        self.previewOverlay.dismiss()
        self.snapLayoutBar.dismiss()

        if let zone = self.activeZone {
            let windowToSnap = self.currentDraggedWindow ?? self.accessibilityService.getFocusedWindow()
            if let window = windowToSnap {
                if let screen = self.activeScreen ?? self.screenService.screenContaining(point: NSEvent.mouseLocation) {
                    self.snapEngine.snapWindow(window, to: zone, on: screen)
                } else {
                    self.snapEngine.snapFocusedWindow(to: zone)
                }
            } else {
                self.snapEngine.snapFocusedWindow(to: zone)
            }
        }

        self.activeZone = nil
        self.activeScreen = nil
        self.currentDraggedWindow = nil
    }
}
