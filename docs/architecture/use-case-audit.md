# Auditoria dos 44 casos de uso do MacSnap

Data: 02/11/2026. Base de código: `f4c517262b163178f65074df20980abca7289b14` (`codex/fix-release-api-auth`). Escopo: comparar o [catálogo de 44 casos](../specs/use-cases.md) com os caminhos reais de produção e os testes existentes. O catálogo ainda não está versionado nessa base. Esta auditoria não altera o produto, a instalação, o Dock ou as permissões do macOS.

**Registro histórico:** a matriz abaixo descreve a auditoria da base indicada. As três falhas receberam correções locais posteriormente, descritas em “Acompanhamento das correções”; isso não substitui o aceite nativo pendente.

## Critério de conclusão

- **Atendido na lógica**: o comportamento descrito possui caminho de produção identificado e evidência automatizada relevante. Não significa aceite completo no macOS real, em todos os aplicativos ou combinações de tela.
- **Parcial**: parte do caso é implementada/testada, mas uma alternativa material, integração ou condição de erro não está estabelecida. A linha explica a parte que falta. Ausência isolada de teste não é tratada como defeito comprovado.
- **Falha reproduzida**: um teste ou experimento executado contrariou um resultado esperado específico. Deve registrar comando, observado e limite do experimento. Uma leitura suspeita do código não recebe esse status.
- **Depende de validação nativa**: o critério principal depende de comportamento do macOS/aplicativo real que adapters e testes existentes não demonstram, ou requer uma decisão de UX antes de existir um resultado esperado inequívoco.

Cada caso recebe um status principal, mesmo quando contém partes atendidas. As variantes UC-19-A a H detalham UC-19, sem aumentar o total de 44 casos principais. As contagens não são um percentual de qualidade ou cobertura de código.

**Resultado após revisão e execução:** 27 casos atendidos na lógica, 11 parciais, 3 com falha reproduzida em cenários controlados e 3 dependentes de validação nativa. As três falhas são UC-09, UC-20 e UC-31. As oito variantes do Dock continuam sem aceite nativo; não foram convertidas em falhas do Dock apenas por associação com uma falha de geometria.

## Matriz de auditoria

| Caso | Status principal | Caminho de produção verificado | Evidência de teste existente e limite |
|---|---|---|---|
| **UC-01 — Iniciar autorizado** | Atendido na lógica | [APP] cria menu e controlador; [AM] consulta confiança e inicia captura; [G] apresenta controles após admissão. | `repeatedStartCreatesOnlyOnePollingLoop` [TA] e `acceptedGestureUsesOneCandidateAndTheSnappingInterfaceForPreviewAndRelease` [TD]. Não executam todo o lançamento com event tap real. |
| **UC-02 — Iniciar sem autorização** | Parcial | [AM] evita `startMonitoring` quando confiança efetiva é falsa; [APP] limpa pares; [MENU] informa o estado consultado. | `permissionGrantedAfterLaunchStartsCaptureWithoutRestarting` [TA] verifica que captura não começa negada e não há prompt de fundo repetido. Prompt inicial, alerta de Settings e comportamento de todos os comandos sem acesso não têm aceite nativo aqui. |
| **UC-03 — Conceder depois de abrir** | Atendido na lógica | [AM] reconsulta na ativação e no ciclo agendado; tenta iniciar quando acesso retorna; não exige reiniciar o controlador. | `permissionGrantedAfterLaunchStartsCaptureWithoutRestarting` [TA]. A atualização de confiança pela implementação real de TCC precisa ser observada no dispositivo. |
| **UC-04 — Revogar durante gesto** | Parcial | Transição negada chama `stopMonitoring` [AM]; o monitor limpa gesto, barra e ações [G]; callback de [APP] limpa pares. A detecção é periódica/por ativação, não instantânea. | `permissionLossStopsCaptureAndRestorationStartsItAgain` [TA] verifica transições do controlador. Não cobre integralmente revogação real durante drop/settlement ou todos os overlays; sem falha nativa reproduzida. |
| **UC-05 — Registro falha/parada** | Atendido na lógica | [AM] repete início mesmo sem alteração da confiança e invalida callbacks antigos por geração; `startMonitoring` é idempotente se já houver tap [G]. | `failedTapCreationIsRetriedEvenWhilePermissionRemainsGranted`, `stoppingRejectsAlreadyQueuedCallbacksIncludingAfterRestart` [TA]. Monitor programado simula falha; não força a API real a falhar. |
| **UC-06 — Mover pelo cabeçalho** | Atendido na lógica | [D] admite faixa de cabeçalho, retém candidata e só passa a arrastar após 14 pontos; [G] usa a janela capturada até a soltura. | `acceptsAtExactlyFourteenPointsFromTheOriginalMovement`, `acceptedGestureUsesOneCandidateAndTheSnappingInterfaceForPreviewAndRelease` [TD]. Interpretação do cabeçalho por aplicativo permanece uma hipótese geométrica. |
| **UC-07 — Movimento pequeno** | Atendido na lógica | [D] distingue candidata de arraste aceito e limpa no release. [G] só entrega drop quando `wasDragging`. | `subThresholdReleaseCannotCommitAndNextGestureStartsFresh` [TD]. Não é teste de mouse físico. |
| **UC-08 — Selecionar conteúdo** | Atendido na lógica | Rejeição do início fica latched até soltar [D]; passar mais tarde pelo cabeçalho não readmite o mesmo gesto. | `rejectedContentDoesNotBecomeADragWhenItPassesThroughTheHeader`, `rejectedGestureCannotSnapAndReleaseAdmitsTheNextGesture` [TD]. Conteúdo customizado dentro da faixa superior pertence ao caso UC-13. |
| **UC-09 — Resize nativo por borda/canto** | Falha reproduzida | A admissão usa faixa superior e deslocamento [D], [W]; [G] não compara a variação do tamanho da janela para distinguir resize de movimento. | Probe `auditUC09NativeCornerResizeMustNotOpenSnapBar` em [PROBE]: após aumentar largura/altura e deslocar o cursor como no canto superior direito, o handler apresenta `.pill` e encaminha um drop de janela (zona nula). Contraria a rejeição prevista no catálogo. O frame AX é simulado; a frequência e entrega desse padrão em aplicativos reais ainda não foram medidas. |
| **UC-10 — Janela inelegível** | Atendido na lógica | [G], [W] rejeitam fullscreen/tamanho fixo; [D] rejeita desktop/janela própria e mantém rejeição até release. Escritas também revalidam elegibilidade [E]. | `ineligibleWindowStaysIgnoredUntilRelease`, `rejectedDesktopAndOwnWindowsStayIgnoredUntilRelease` [TD]; `fullScreenWindowRejectsSnappingEvenWhenAXSizeIsSettable`, `nonResizableWindowRejectsBothFrameAPIsAndSnapping` [TS]. Falta de atributo AX por app permanece dependência nativa. |
| **UC-11 — Fullscreen no meio** | Atendido na lógica | [G] revalida durante movimento e release; [E] revalida drop agendado; [W] impede escrita inelegível. | `enteringFullScreenCancelsCapturedGesture`, `enteringFullScreenImmediatelyBeforeReleaseCancelsDrop` [TD]; `enteringFullScreenBeforeDeferredDropPreventsPlacement` [TS]. Mudança de estado é programada no adapter. |
| **UC-12 — Interromper gesto** | Atendido na lógica | [G] limpa seleção e suprime o gesto mantido ao pausar/tap recovery; geração de captura barra eventos de registro anterior. [D] limpa capture/rejeição no release. | `pauseResumeDiscardsTheOldGestureUntilMouseUp`, `tapRecoveryWhileIdleStartsFreshButCancelsAnActiveHeldGesture`, `stoppingAndRestartingHasNoOldCaptureOrRejection` [TD]. Eventos nativos perdidos/atrasados ainda exigem teste real. |
| **UC-13 — Abas e controles** | Depende de validação nativa | [D] retém candidata resolvida no começo. [G] não tem política por tipo de aba/controle nem troca de identidade após destacar uma aba. | Não foi localizado teste de destaque de aba ou toolbar customizado. Precisa definir o que conta como movimento intencional da janela e verificar navegadores/editores concretos. A lacuna não demonstra uma falha específica. |
| **UC-14 — Pílula e expansão** | Atendido na lógica | [G] só apresenta durante arraste reconhecido com recurso ligado; [B] controla `hidden/pill/expanded`, hover e recolhimento. | `testSnapLayoutBarPillAndExpandedStateTransitions` [TG] exercita apresentação; handler de gesto em [TD]. Não prova legibilidade, camadas e animação em toda tela física. |
| **UC-15 — Prévia e slot exato** | Atendido na lógica | [G] marca intenção de cartão; [E], [R] compartilham a política exata/adaptativa; escrita bem-sucedida precede registro do par. | `exactAndAdaptiveIntentsUseTheSamePolicyForPreviewAndPlacement` [TS], `testSingleSlotHighlightingInSnapBar`, `testPortraitSlotsIndependentHighlightingForIdenticalZones` [TG]. Mudanças externas de geometria entre preview/drop são UC-24. |
| **UC-16 — Intervalo entre cartões** | Atendido na lógica | A apresentação da prévia não permite que animação antiga de saída oculte a nova seleção; handler mantém intenção exata do slot atual. | `quarterToMaximizeAcrossLayoutGapKeepsPreviewAndDropInSync` [TD], `dismissingQuarterCannotHideNewerMaximizePreview`, `latestDismissalStillClosesAnInterruptedPreview` [TP]. São testes do caminho real com eventos/frames controlados e animações aguardadas. |
| **UC-17 — Soltar sem alvo/toggle** | Parcial | [G] limpa seleção sem zona, oculta barra no release e cancela operações ao desligar Top Snap Bar; Edge Snap pode continuar. | Há testes de cancelamento e release [TD], [TS], mas não uma matriz integrada de troca de toggles em cada estado de hover. Composições específicas precisam de probe; não assumir sucesso de todas por ler setters. |
| **UC-18 — Cruzar monitores** | Parcial | [G], [B] migram barra conforme a tela do cursor; [D] preserva janela capturada. [S] seleciona tela ou usa fallback principal. | `crossingDisplaysKeepsTheCapturedWindowAndDoesNotReadmit` [TD] cobre o reconhecedor. Não valida toda apresentação/drop com duas telas físicas, escala e origens distintas. |
| **UC-19 — Dock real** | Depende de validação nativa | [B], [E], [PAIR] usam área útil. Não há estado explícito de Dock revelado. [DIV] usa validade/oclusão de descoberta que filtra camada zero [DISC]. | Não foi localizado teste do Dock real, incluindo clique em ícones perto do divisor. Ver oito variantes abaixo. Esse status não significa que um Dock fixo já esteja quebrado. |
| **UC-20 — Reconfigurar tela** | Falha reproduzida | O callback real do gerenciador detecta geometria desatualizada e chama `abandonStaleWork` [SESSION], mas esse caminho não encerra a apresentação ainda pertencente à própria sessão. | Probe `auditUC20GeometryMismatchMustDismissOwnResizeOverlay` em [PROBE]: após mudar a referência de altura primária no adapter e entregar movimento ao divisor, a sessão fica `.cancelled`, não escreve frames, mas seu overlay continua em apresentação/visível. O probe verifica o intervalo antes de uma notificação separada purgar o estado; não modifica Dock ou tela físicos. As outras alternativas de UC-20 continuam parciais. |
| **UC-21 — Bordas horizontais** | Atendido na lógica | O mapeamento esquerda/direita/topo/fundo/cantos está explícito em [G]; [E] usa área útil atual; maximização comum não é igual a fullscreen [W]. | `testSnapZoneHalfCalculations`, `testSnapZoneCornerCalculations` [TG], testes de gesto [TD]. A matriz inteira de bordas não foi rodada fisicamente nesta auditoria. |
| **UC-22 — Monitor vertical** | Atendido na lógica | [G] tem ramificação de retrato com terços pelas laterais e metades topo/fundo; [B] oferece cartões da orientação atual. | `testVerticalMonitorThirdsCalculations`, `testPortraitSlotsIndependentHighlightingForIdenticalZones` [TG]. A evidência de testes é principalmente geometria/apresentação, não todos os trajetos de mouse no monitor vertical. |
| **UC-23 — Espaço disponível** | Atendido na lógica | [R] observa vizinhos, calcula alvo adaptativo e recusa proposta inválida; [E] não escreve vizinhas para fabricar par. Slot explícito usa intenção exata. | `adaptivePlacementFitsLeftTopBottomAndBetweenTwoNeighbors`, `exactAndAdaptiveIntentsUseTheSamePolicyForPreviewAndPlacement` [TS] verificam alvos e ausência de escritas nas vizinhas. |
| **UC-24 — Mudança antes do drop** | Atendido na lógica | [E] recalcula a partir de observações/tela conectada na execução, rejeita escrita falha e cancela jobs substituídos. Não promete igualdade com prévia obsoleta se o mundo mudou. | `placementRefreshesObservationsAndFailedWritesDoNotRegister`, `disconnectedDisplayCancelsDeferredPlacementAndDiscovery`, `explicitSnapSupersedesADelayedDrop` [TS]. Adapters controlam mudanças entre observação e aplicação. |
| **UC-25 — Quick Snap na janela correta** | Parcial | [E] chama `AccessibilityService.getFocusedWindow`; [AX] usa AX focused/main/windows[0], último app e fallbacks WindowServer/cursor. Essa rota é distinta de `NativeWindowDiscovery`. | Testes de identidade/visibilidade de [TW] não provam os fallbacks de foco [AX]. Os testes de menu usam engine controlada. Falta teste específico de foco/menu com duas janelas do mesmo app, minimização e fallback ambíguo. |
| **UC-26 — Descobrir par** | Atendido na lógica | [PAIR] exige janelas distintas e geometria binária representável; [DISC] reconcilia identidade individual de janela. | `managerDetectsExactSameAppPairOcclusionAndObservationAvailability` [TW], `pairAdmissionRejectsPartialRowsAndThreeColumnsButAcceptsBothAxes` [TS]. Descoberta usa observações programadas. |
| **UC-27 — Ajustar divisão** | Atendido na lógica | [SESSION] altera apenas razão/apresentação no movimento; `PairedSplit.applyCurrentSplit` [SPLIT] reduz antes de expandir; settlement usa readback limitado. | `draggingChangesOnlyPreviewThenReleaseCommitsAndSettles`, `releaseShrinksBeforeExpandingInBothOrientations` [TR]. Resposta de terceiros às escritas permanece validação nativa. |
| **UC-28 — Não competir com divisor** | Atendido na lógica | [G] testa `isDraggingDivider` antes de admitir/soltar encaixe individual e suprime interação até release. | `dividerSuppressionAndStopDiscardTheCapturedWindow` [TD]. O callback de divisor e o handler são reais, mas o percurso completo sobre Dock e cartões é nativo; Dock pertence a UC-19. |
| **UC-29 — Oclusão por terceira janela** | Atendido na lógica | [DIV] valida par e consulta oclusão; [DISC] protege contra identidade desconhecida e distingue janelas do mesmo processo. | `thirdWindowOfSameApplicationOccludesTheDivider`, `ambiguousOrUnavailableWindowIdentityDoesNotPermitDividerInteraction` [TW]. O escopo é janela observada normal; não ampliar a conclusão a Dock/menu/notch. |
| **UC-30 — Mínimos e recusa** | Atendido na lógica | [SPLIT] usa ordem de escrita anticoli­são e aborta falha; [SESSION] lê resultado, faz correção limitada e invalida divisão irrepresentável. | `minimumSizeReadbackRealignsPartnerToTheObservedFirstWindow`, `impossibleMinimumSizesInvalidateWithoutAnUnboundedRetry`, `unsupportedCrossAxisMinimumCannotClaimAFullDisplaySplit`, `failedShrinkingWriteDoesNotExpandTheOtherWindow` [TR]. |
| **UC-31 — Fechar/mover/fullscreen no par** | Falha reproduzida | `finish` aceita frames acessíveis/redimensionáveis [SESSION] sem validar que uma integrante permaneceu na posição do par antes de aplicar novamente a divisão. | Probe `auditUC31MovedMemberMustNotBeOverwrittenOnRelease` em [PROBE], pelos callbacks reais do gerenciador: mover a primeira janela para fora do par durante o ajuste e soltar produz duas novas escritas e retorna a janela ao layout; a sessão entra em `.settling`, em vez de invalidar. Frames são programados; fechamento/fullscreen continuam cobertos pelos testes existentes. |
| **UC-32 — Sessão antiga versus par novo** | Atendido na lógica | [PAIR] associa sessão a identidade de par; [SESSION] cancela trabalho antigo sem ocultar apresentação possivelmente pertencente a outra operação. | `aStaleReadbackCannotWriteOrDismissAnotherPair`, `replacingOrClearingScreenPairStateCancelsItsPendingLifetime` [TR]. A escolha de não ocultar é correta para substituição; mudança isolada de geometria é outra composição, UC-20/19-F. |
| **UC-33 — Pares por tela/reconfiguração** | Atendido na lógica | [PAIR] mantém estado por display ID e retira estados com tela ausente, área útil ou referência primária alterada; sessões têm predicado `isCurrent`. | `removedDisplayPurgesPairAndCancelsDeferredWrites`, `screenGeometryMismatchCancelsSettlementBeforeRediscovery`, `primaryReferenceHeightChangeCancelsEvenWhenDisplayGeometryIsUnchanged` [TR]. Testes usam configurações programadas, não monitores físicos. |
| **UC-34 — Recusar par incompatível** | Atendido na lógica | [PAIR] usa `PairGeometry` para impedir identidade duplicada, fileiras parciais e combinação sem divisão binária válida. [E] mantém encaixe individual. | `threeColumnsAreNotConvertedToABinaryPair`, `pairAdmissionRejectsPartialRowsAndThreeColumnsButAcceptsBothAxes` [TS]. Há verificação de ausência de escrita nas vizinhas. |
| **UC-35 — Pausar/retomar** | Atendido na lógica | Setters em [G] persistem master, limpam gesto/pares e não readmitem botão já pressionado; [MENU] desabilita ações; updater não depende do master. | `pauseResumeDiscardsTheOldGestureUntilMouseUp` [TD], `accessibilityPressClearsHoverAndPausedMenuRejectsActions` [TM], `menuChecksForUpdatesEvenWhenSnappingIsPaused` [TU]. Persistência pós-instalação real é tratada separadamente em UC-42. |
| **UC-36 — Toggles isolados** | Parcial | [G] limpa seleção/barra conforme origem e cancela ações; [PAIR] limpa pares ao desligar divisor. Há interação entre o toggle do divisor, `isDraggingDivider` e gesto de mouse ainda mantido que os testes atuais não demonstram. | `testMenuBarControllerAndFeatureToggles` [TG] verifica partes dos controles; faltam todas as sequências cartão/borda/divisor × momento da alteração. Atualizar se probe mostrar falha. |
| **UC-37 — Menu/acessibilidade/login** | Parcial | [MENU] limpa hover, consulta estado atual e expõe ações; login usa `SMAppService`, dependendo do sistema. | Testes de hover/press/pausa [TM] são relevantes; início no login, reabertura do processo e estado de Settings não são demonstrados por eles. |
| **UC-38 — Check for Updates** | Parcial | [UP] só inicia SDK em app configurado e só consulta quando permitido; [MENU] deixa consulta acessível com snapping pausado. | `menuChecksForUpdatesEvenWhenSnappingIsPaused`, `unconfiguredBuildDoesNotEnableUpdates` [TU]. O primeiro usa updater controlado; rede e UI real pertencem ao SDK e não foram executadas aqui. |
| **UC-39 — Lembretes/preferências** | Parcial | [UP] mantém preferências separadas e publica versão pendente pelos callbacks; oferece lembrete no menu sem forçar UI de fundo. | `pendingUpdateAndPreferencesArePresentedThroughTheMenu` [TU] usa updater controlado. Consentimento/skip/defer, erro do SDK e persistência após substituição ainda não têm aceite nativo nesta auditoria. |
| **UC-40 — Instalação espera interação** | Parcial | [APP] combina gesto, resize/settlement e botão físico; [UP] posterga término e invalida resposta antiga. | `terminationWaitsUntilTheWindowInteractionHasFinished`, `cancelledTerminationWorkCannotReplyToAnEarlierRequest` [TU] testam espera com booleano programado. A composição física arraste/divisor/atualização não foi demonstrada nessa execução. |
| **UC-41 — Rede/assinatura/oferta inválida** | Parcial | [DIST] valida metadados/assinatura, monotonicidade e retirada; Sparkle recebe verificação de download/instalação. | [TUP] inclui CryptoKit real com arquivo adulterado e políticas de feed. Não exercita toda instalação interrompida, offline/retomada e UI de erro de Sparkle. |
| **UC-42 — Atualizar e renovar TCC real** | Depende de validação nativa | [AM] consulta confiança efetiva e retoma após concessão; [MENU] orienta renovação; distribuição permanece ad hoc por escolha explícita. Não existe promessa de preservar o grant automaticamente. | [TA] cobre transições programadas. A continuidade de TCC e a renovação após substituição do binário exigem ciclo real de atualização/Settings; não foi realizado como parte desta auditoria. |
| **UC-43 — Cancelar/desinstalação concorrente** | Atendido na lógica | [UN] verifica disponibilidade antes e depois da confirmação; cancelar não chama remoção; bloqueia concorrência com atualização. | `cancelConfirmationAndUpdateInProgressNeverStartRemoval`, `menuRoutesUninstallOnlyWhenTheActionIsAvailable` [TX]. Confirmação/helper são injetados nos testes, sem remover a instalação pessoal. |
| **UC-44 — Limitar remoção e preservar dados** | Atendido na lógica | [PLAN] limita caminhos/identidade e rejeita symlinks; [UN] e helper removem somente plano validado. Falha de lixeira não prossegue como sucesso. | `previewDoesNotChangeTheApplicationOrItsSettings`, `cleanRemovalPreservesProjectsKeysAndOtherApplications`, `changedIdentityAfterPreviewCannotBeRemoved`, `symbolicLinkCannotRedirectCacheRemovalIntoDocuments`, `failedTrashOperationKeepsSettingsAndApplication` [TX] usam filesystem temporário. Login/TCC reais exigem aceite descartável. |

## Dock — oito variantes de UC-19

Nenhuma variante abaixo foi validada manipulando o Dock real. A área útil reportada por `visibleFrame` não é um sensor de visibilidade instantânea do Dock; pode haver margem de rastreamento mesmo com auto-ocultação. O [catálogo](../specs/use-cases.md#resposta-à-pergunta-o-dock-durante-redimensionamento) contém a referência primária da Apple e os passos completos.

| Variante | Status | O que o código já faz | O que falta demonstrar |
|---|---|---|---|
| **UC-19-A — Dock fixo embaixo** | Depende de validação nativa | [E], [PAIR] posicionam usando área útil; [B] ancora controles nela. | Confirmar a reserva real e acessibilidade dos controles ao maximizar/ajustar par com Dock nesse lado. |
| **UC-19-B — Dock fixo nas laterais** | Depende de validação nativa | Usa origem/largura da área útil, não apenas altura. | Mesma confirmação à esquerda/direita com aplicativo real; cálculos não provam simetria da UI nativa. |
| **UC-19-C — Dock auto-oculto escondido** | Depende de validação nativa | Usa `visibleFrame` reportado; não há detector de Dock revelado. | Confirmar geometria sem confundir margem de rastreamento com Dock visível. Não exigir automaticamente frame igual à tela inteira. |
| **UC-19-D — Revelar Dock durante arraste** | Depende de validação nativa | Overlays de prévia ignoram mouse [OV]; gesto continua sob política de bordas [G]. | Definir a UX da sobreposição transitória e verificar que não produz encaixe involuntário nem impede acesso ao Dock. |
| **UC-19-E — Revelar Dock junto ao divisor** | Depende de validação nativa | [DIV] valida par e oclusão; [DISC] observa janelas normais de camada zero; previews não capturam mouse [OV]. | Verificar clique/cursor nativo sobre ícones do Dock. Os testes de terceira janela normal não estabelecem a camada/oclusão do Dock. |
| **UC-19-F — Dock muda lado/tamanho no meio** | Depende de validação nativa | [E] relê área útil ao colocar janela; [PAIR] compara área capturada; [SESSION] evita escrita quando sessão deixa de ser atual. | Confirmar notificação nativa e limpeza dos overlays, especialmente quando apenas geometria muda. A guarda de escrita não equivale a retirada garantida da apresentação. |
| **UC-19-G — Dock muda monitor** | Depende de validação nativa | [S], [B], [PAIR] têm seleção/migração/estado por tela. | Confirmar áreas úteis reais por monitor e independência dos pares enquanto o Dock se desloca. |
| **UC-19-H — Combinação menu/notch/escala** | Depende de validação nativa | [G], [B], [E] usam coordenadas e área útil; não há tratamento específico de notch ou estado instantâneo dos elementos do sistema. | Executar combinações físicas e confirmar alcançabilidade, camadas, clique e alvo correto. |

## Pontos que não podem ser inferidos de testes verdes

1. Cobertura de região de cabeçalho não demonstra distinção entre mover e redimensionar. A mesma faixa inclui cantos/borda superior dentro da tolerância [W].
2. Um teste de screen service que retorna `nil` não demonstra o comportamento do adapter nativo [S], que faz fallback para a tela principal quando o ponto não pertence a nenhuma tela.
3. Oclusão por janela normal observada não demonstra oclusão por Dock/menu; [DISC] filtra registros por camada zero, enquanto a camada do Dock real não foi medida aqui.
4. Cancelar uma sessão de resize não prova ocultação de todos os overlays. O caminho `abandonStaleWork` [SESSION] preserva apresentação deliberadamente para proteger outra operação; sem operação substituta, a limpeza precisa ser estabelecida pela composição com [PAIR].
5. Os fallbacks de foco de [AX] não herdam as garantias de identidade/visibilidade dos testes de `NativeWindowDiscovery` [TW].
6. Integridade de arquivo/assinatura e recuperação de autorização de TCC são provas diferentes. Uma atualização autenticada não demonstra que a autorização anterior corresponde ao binário novo.

## Experimentos e evidência de execução

As verificações abaixo foram executadas em 02/11/2026 sobre a base indicada. Não houve instalação, abertura de outro MacSnap, alteração de permissões ou mudança nas configurações do Dock. Os testes AppKit criam seus próprios painéis; janelas de aplicativos pessoais não são movidas.

| Comando | Resultado | Alcance |
|---|---|---|
| `swift test` | 115 testes em 12 suítes aprovados. | Suíte regular existente; não contém os três novos critérios que falharam. |
| `python3 scripts/test-update-distribution.py` | 22 testes aprovados. | Políticas de publicação, assinatura, feed e autenticação de metadados. |
| `python3 scripts/test-dmg-distribution.py` | 4 testes aprovados. | Políticas de distribuição do instalador. |
| `python3 scripts/check-site.py` | Aprovado nos dois idiomas. | Estrutura, assets, links, tradução e metadados do site. |
| `node --test scripts/test-site-motion.cjs` | 12 testes aprovados. | Ciclo das demonstrações do site; não é cobertura do aplicativo nativo. |
| `python3 scripts/audit-use-cases.py` | 3 testes de aceitação reprovados: UC-09, UC-20 e UC-31; saída 1. | Novas provas dos handlers/callbacks de produção com frames e geometria programados. Não demonstram o Dock real ou o event tap físico. |

Na execução original, o reprodutor adicionava temporariamente três cenários e restaurava as fixtures em `finally`. Os logs anteriores e hashes de restauração permanecem em `.build/use-case-audit/probes.log` e `summary.json`, ignorados pelo Git. A suíte regular foi executada novamente após a restauração e passou.

As três provas agora são testes de regressão permanentes. O [runner atual](../../scripts/audit-use-cases.py) apenas executa `swift test --filter auditUC`; ele não injeta, reescreve nem restaura arquivos. Seus novos resultados ficam em `.build/use-case-audit/regressions.log` e `regressions-summary.json`. Saída 0 indica aprovação dos três critérios; saída diferente de zero deve ser investigada.

## Acompanhamento das correções — 02/11/2026

Branch local: `codex/fix-window-interaction-regressions`. Não foi feita instalação ou publicação destas correções.

| Caso | Mudança | Validação |
|---|---|---|
| UC-31 | A sessão captura os frames iniciais e verifica se ambas as janelas permanecem neles antes de atualizar a prévia ou gravar a divisão. Alterações externas acima da tolerância de quatro pontos invalidam a operação sem puxar a janela de volta. A reconciliação de tamanho mínimo após o commit continua separada. | Regressão pelo callback real do gerenciador; mudança de cada integrante durante prévia; tolerância de arredondamento; testes existentes de tamanho mínimo e ordem de escrita. |
| UC-20 | Validade geométrica e propriedade da apresentação são verificações separadas. Se a geometria expira mas a sessão ainda possui sua apresentação, ela a encerra e limpa o estado; não interfere na operação que a substituiu. | Regressão com par inicialmente válido, alteração da referência primária e novo movimento antes da notificação de limpeza; controle de substituição de par e callbacks antigos. As demais alternativas de reconfiguração continuam pendentes. |
| UC-09 | A borda de quatro pontos é reservada ao resize; alterações de tamanho acima da tolerância rejeitam o gesto durante movimento ou release, sem reativá-lo antes de soltar. Deslocamento de origem não é confundido com resize. | Canto superior simulado; bordas/cantos com frame limitado por tamanho mínimo; alteração após admissão e antes da soltura; arraste normal com arredondamento. |

**Resultado local:** 125 testes em 12 suítes aprovados e build de produção concluído. As três regressões originais estão incluídas na suíte. O fluxo do Dock real, alterações automáticas de tamanho ao retirar uma janela de seu layout nativo e diferenças entre cabeçalhos de aplicativos ainda exigem validação nativa; os testes não demonstram um detector universal de resize ou visibilidade do Dock.

## Ordem recomendada de correção

1. **UC-31:** impedir que uma operação antiga sobrescreva a posição de uma janela que saiu do par. Manter os testes de tamanho mínimo e de redução antes de expansão, para não confundir limitação de tamanho com abandono do par.
2. **UC-09:** distinguir resize nativo de movimento, preservando o caminho positivo de arraste do cabeçalho e investigando abas destacadas separadamente.
3. **UC-20:** retirar a apresentação da própria operação quando sua geometria expira, preservando a proteção que impede uma sessão antiga de ocultar a apresentação de uma sessão nova.
4. **UC-19:** realizar as oito variantes nativas do Dock e decidir a política de sobreposição/drop antes de introduzir um detector específico.

A ordem acima registra a recomendação da auditoria original. As três correções locais estão detalhadas no acompanhamento; não foram publicadas.

## Fontes primárias

Os nomes de teste são citados para preservar rastreabilidade quando linhas mudarem. As âncoras abaixo correspondem aos arquivos da base pesquisada. Testes temporários da investigação não são usados como se já fossem regressões permanentes.

[APP]: ../../Sources/MacSnap/App/AppDelegate.swift#L18
[AM]: ../../Sources/MacSnap/Services/EventMonitoring/AccessibilityMonitoringController.swift#L28
[G]: ../../Sources/MacSnap/Services/EventMonitoring/GlobalEventMonitor.swift#L142
[D]: ../../Sources/MacSnap/Services/EventMonitoring/DragRecognition.swift#L47
[W]: ../../Sources/MacSnap/Core/Models/WindowElement.swift#L116
[B]: ../../Sources/MacSnap/Features/UI/SnapLayoutBarWindow.swift#L39
[S]: ../../Sources/MacSnap/Services/Screen/ScreenService.swift#L23
[E]: ../../Sources/MacSnap/Features/Snapping/SnapEngine.swift#L30
[R]: ../../Sources/MacSnap/Features/Snapping/SnapTargetResolver.swift#L11
[PAIR]: ../../Sources/MacSnap/Features/Pairing/PairedResizeManager.swift#L100
[SESSION]: ../../Sources/MacSnap/Features/Pairing/PairedResizeSession.swift#L43
[SPLIT]: ../../Sources/MacSnap/Core/Models/PairedSplit.swift#L131
[DIV]: ../../Sources/MacSnap/Features/UI/DividerHandleWindow.swift#L132
[DISC]: ../../Sources/MacSnap/Services/Accessibility/WindowDiscovery.swift#L14
[AX]: ../../Sources/MacSnap/Services/Accessibility/AccessibilityService.swift#L52
[OV]: ../../Sources/MacSnap/Features/UI/PreviewOverlayWindow.swift#L25
[MENU]: ../../Sources/MacSnap/Features/UI/MenuBarController.swift#L232
[UP]: ../../Sources/MacSnap/Services/Updating/SparkleAppUpdater.swift#L19
[UN]: ../../Sources/MacSnap/Services/Uninstallation/AppUninstaller.swift#L33
[PLAN]: ../../Sources/MacSnapUninstallation/UninstallPlan.swift#L12
[DIST]: ../../scripts/update-distribution.py#L60
[TA]: ../../Tests/MacSnapTests/AccessibilityMonitoringControllerTests.swift#L8
[TD]: ../../Tests/MacSnapTests/DragRecognitionTests.swift#L12
[TG]: ../../Tests/MacSnapTests/MacSnapTests.swift#L9
[TS]: ../../Tests/MacSnapTests/SnapEngineTests.swift#L10
[TR]: ../../Tests/MacSnapTests/PairedResizeSessionTests.swift#L8
[TW]: ../../Tests/MacSnapTests/WindowDiscoveryTests.swift#L9
[TM]: ../../Tests/MacSnapTests/MenuBarControllerTests.swift#L12
[TU]: ../../Tests/MacSnapTests/AppUpdatingTests.swift#L8
[TP]: ../../Tests/MacSnapTests/SnapPreviewTransitionTests.swift#L8
[TX]: ../../Tests/MacSnapTests/UninstallationTests.swift#L15
[TUP]: ../../scripts/test-update-distribution.py#L29

[PROBE]: ../../scripts/audit-use-cases.py


### Seguimento: limites de tamanho na sombra (UC-15)

A prévia e a aplicação agora compartilham ajuste aos limites de tamanho reportados por AX, com alinhamento à borda/centro e recusa de limites inválidos ou impossíveis na área útil. A consulta é somente leitura. Quando os limites não estão disponíveis, preserva-se a prévia padrão, conforme escolha do usuário; isso permanece uma estimativa nesses aplicativos. Limites incompletos ajustam apenas os eixos/bounds conhecidos. Proporções e incrementos não informados continuam fora da previsão.

Novos testes cobrem mínimo/máximo fixos em seis zonas, igualdade entre sombra e encaixe, limites parciais, ausência de limites, inconsistência e mínimo maior que a tela. O teste do monitor verifica que uma prévia indisponível encerra a sombra anterior e preserva a seleção do drop. Não houve instalação de build ou manipulação de janelas de outros aplicativos.
