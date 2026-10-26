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

        // 1. MONITOR VERTICAL: Tratamento especial no topo
        if isPortrait {
            let topZoneThreshold: CGFloat = 130.0
            let isApproachingTop = point.y >= visibleFrame.maxY - topZoneThreshold

            if isApproachingTop {
                // Abre a barra flutuante com layouts otimizados para monitores verticais
                snapLayoutBar.present(on: screen)

                // Verifica se o usuário está pairando sobre um dos cards da barra
                if let hoveredBarZone = snapLayoutBar.checkHover(at: point) {
                    detectedZone = hoveredBarZone
                } else if isTop {
                    // Se encostou na borda superior fora dos botões:
                    // Esquerda do topo = Metade Superior, Direita do topo = 2/3 Superior
                    if point.x < visibleFrame.midX {
                        detectedZone = .topHalf
                    } else {
                        detectedZone = .topTwoThirds
                    }
                }
            } else {
                snapLayoutBar.dismiss()
            }

            // Ações laterais em monitor vertical
            if detectedZone == nil {
                if isLeft {
                    detectedZone = isNearTop ? .topHalf : (isNearBottom ? .bottomHalf : .leftHalf)
                } else if isRight {
                    detectedZone = isNearTop ? .topTwoThirds : (isNearBottom ? .bottomThird : .rightHalf)
                } else if isBottom {
                    detectedZone = .bottomHalf
                }
            }
        } else {
            // 2. MONITOR HORIZONTAL (Padrão)
            snapLayoutBar.dismiss()

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

        if let zone = detectedZone {
            self.activeZone = zone
            self.activeScreen = screen
            let targetRect = zone.targetRect(for: visibleFrame)
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
            self.snapEngine.snapFocusedWindow(to: zone)
            self.activeZone = nil
            self.activeScreen = nil
        }
    }
}
