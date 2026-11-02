# Casos de uso e prevenção de regressões do MacSnap

Levantamento de 02/11/2026, baseado no código, nos testes e no [vocabulário do projeto](../../CONTEXT.md). Este catálogo contém **44 casos de uso**. Seu objetivo é orientar a investigação e os testes antes de mudar fluxos de interação. Não representa execução de QA com aplicativos reais, nem comprovação de ausência de defeitos.

## Como usar o catálogo

O ator principal é a **pessoa usando o MacSnap**. O macOS fornece janelas, telas, eventos e autorização de Acessibilidade; Sparkle executa a atualização; o helper executa a desinstalação. Por padrão, os casos de encaixe usam MacSnap ativo, permissão efetiva concedida e uma janela normal redimensionável. Cada linha informa as exceções a essas pré-condições.

- **P0**: impedir perda de funcionalidade básica, alteração involuntária de janelas ou operação destrutiva indevida.
- **P1**: preservar consistência de gesto, geometria e interface nas condições usuais.
- **P2**: conferir configurações e comportamentos secundários.
- **A**: há teste automatizado do módulo ou handler de produção para a parte descrita. Os dados nativos podem ser substituídos por adapters.
- **P**: há cobertura parcial, matemática ou de apresentação; não demonstra o fluxo inteiro.
- **L**: não foi localizado teste específico desse cenário na pesquisa. É uma lacuna, não um defeito confirmado.
- **M**: ainda é necessário executar o caso com os aplicativos, telas e permissões reais relevantes. A presença de **A** não elimina **M**.

Os IDs são estáveis e podem ser usados em relatos de problema, testes e PRs. Ao executar, registrar aplicativo e versão, macOS, monitores, passos e resultado; evitar títulos de documentos e conteúdo pessoal. Para casos destrutivos ou de atualização, usar ambiente descartável ou um teste deliberadamente autorizado, nunca a instalação pessoal como efeito colateral da pesquisa.

## Resposta à pergunta: o Dock durante redimensionamento

Neste pedido, “barra de app” significa o **Dock do macOS**, com os ícones dos aplicativos. Ele é diferente da barra de layouts do MacSnap e da barra de menus do sistema.

**Hoje há consideração indireta da área reservada ao Dock, mas não detecção explícita de “Dock visível agora”.** Os alvos de encaixe e a posição da barra usam `NSScreen.visibleFrame`; os pares guardam uma fotografia dessa área útil e validam se ela ainda corresponde à tela atual. [E], [B], [PAIR]

Segundo a [documentação primária da Apple sobre `visibleFrame`](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe), esse retângulo depende das configurações atuais de UI, exclui a área ocupada por Dock/menu e não deve ser armazenado como valor permanente. Mesmo com Dock auto-oculto, ele pode continuar menor que a tela inteira para preservar a região de rastreamento. Assim, **a diferença entre `frame` e `visibleFrame` não demonstra que o Dock está visível naquele instante**.

Na aplicação do encaixe, [E] consulta novamente a tela conectada e seu `visibleFrame`; uma prévia anterior pode deixar de corresponder à área atual. No ajuste de par, a sessão compara o frame capturado com o frame atual antes de operar. Essas guardas existem, mas não provam que cada aparição do Dock dispara a atualização/limpeza completa da apresentação. `abandonStaleWork` cancela a sessão sem ocultar uma apresentação que poderia pertencer a outra operação; a retirada de overlays numa mudança isolada da área útil precisa de teste integrado. [PAIR], [SESSION]

### Aceitação prioritária para o Dock — variantes de UC-19

Todos os cenários abaixo usam uma janela normal ou um par válido. “Esperado” é o critério a verificar, não uma afirmação de execução bem-sucedida. Não alterar o Dock pessoal nem executar gestos reais como efeito colateral deste levantamento.

| Variante | Configuração e passos executáveis | Resultado esperado / decisão necessária | Evidência atual |
|---|---|---|---|
| **UC-19-A · P1** | Dock fixo embaixo; encaixar nas metades, maximizar e ajustar um par. | Frames aplicados usam a área útil, sem ocupar a região reservada ao Dock. | Uso de `visibleFrame` [E], [PAIR]; falta aceite nativo específico. |
| **UC-19-B · P1** | Repetir A com Dock fixo à esquerda e depois à direita. | A margem reservada acompanha o lado; barra, prévia e divisor ficam utilizáveis. | Mesmas guardas; não presumir simetria comprovada por testes só horizontais. |
| **UC-19-C · P1** | Dock auto-oculto e escondido; encaixar/maximizar, sem aproximar o cursor da borda de revelação. | Usa a área útil reportada pelo macOS. Não interpretar margem de rastreamento como Dock visível nem exigir frame igual à tela inteira. | Sem estado explícito de Dock; sem teste nativo localizado. |
| **UC-19-D · P0** | Durante arraste de janela com prévia, revelar o Dock pela borda e passar sobre seus ícones; soltar fora de alvo válido. | **Critério proposto:** Dock permanece acessível e a interação não gera encaixe involuntário. Definir a política desejada para prévia/controles enquanto o Dock está sobreposto, antes de implementar uma nova detecção. | Overlays de prévia ignoram mouse [OV]; isso não prova sua relação visual com o Dock nem a intenção do gesto. |
| **UC-19-E · P0** | Durante ajuste pelo divisor, revelar o Dock junto à junção; depois soltar e tentar clicar num ícone nessa região. | Nenhum divisor antigo intercepta o clique destinado ao Dock; não há escrita tardia inesperada nem overlay preso. | [DIV] verifica validade e oclusão. A descoberta filtra janelas de camada zero [DISC]; testes de oclusão por janelas normais não demonstram oclusão por elementos do sistema. Não foi medida a camada real do Dock nesta pesquisa. |
| **UC-19-F · P0** | Com barra/prévia ou divisor ativos, alterar lado, tamanho ou auto-ocultação do Dock de forma controlada. | Se a área útil mudar, cancelar coerentemente ou usar a nova geometria; nunca aplicar como atual um alvo antigo sem revalidar. Conferir retirada/reposição de todos os overlays. | Encaixe consulta área atual [E]; par compara área capturada [PAIR]. Reação nativa à alteração e limpeza completa ainda precisam ser observadas. |
| **UC-19-G · P1** | Dois monitores; revelar/mover o Dock para o outro monitor, cruzar a janela ou ajustar um par em cada tela. | A área útil usada corresponde à tela de destino; o Dock de uma tela não desloca indevidamente o par da outra; nenhum controle fica fora de alcance. | Política por tela [S], [PAIR], migração da barra [B]; falta percurso nativo completo. |
| **UC-19-H · P1** | Repetir D–G com barra de menus auto-oculta, escalas diferentes e notebook com notch. | Controles permanecem alcançáveis; diferença de coordenadas e camadas do sistema não produz alvo/clique incorreto. | É uma combinação manual; os testes de matemática de coordenadas não equivalem a esse aceite. |

As oito variantes mantêm **UC-19** como um caso principal do catálogo; não são oito novos casos no total de 44.

### Outras fronteiras de gesto encontradas durante o levantamento

Na auditoria inicial, o reconhecimento usava faixa superior e deslocamento, sem distinguir resize de movimento. A correção local de UC-09 reserva uma faixa de quatro pontos na borda para resize e rejeita mudanças de tamanho acima da tolerância durante o gesto ou antes da soltura. A rejeição permanece até soltar. Movimento de posição e pequenas diferenças de arredondamento continuam elegíveis. Isso é uma heurística geométrica testada com adapters, não uma classificação nativa universal por aplicativo. [G], [D], [W]

## Inicialização, autorização e captura

| ID / prioridade | Pré-condição e passos | Resultado esperado e alternativas | Evidência / cobertura |
|---|---|---|---|
| **UC-01 · P0 — Iniciar com autorização válida** | App instalado; acesso efetivo já concedido. Abrir MacSnap e arrastar o cabeçalho de uma janela elegível. | Ícone disponível; captura iniciada; após o limiar, barra/prévia responde. Iniciar o controlador novamente não cria outro ciclo de polling. | Política [APP], [AM]. **A parcial + M**: `repeatedStartCreatesOnlyOnePollingLoop` [TA]; teste do controlador não prova a entrega real do event tap. |
| **UC-02 · P0 — Primeira execução sem autorização** | Sem acesso efetivo. Abrir o app, consultar o status no menu e tentar arrastar. | App informa necessidade de Acessibilidade; não manipula janelas nem cria pares. Verificações de fundo não repetem o pedido a cada ciclo. Recusar/postergar deve manter o menu utilizável. | [AM], [APP], [MENU]. **A parcial + M**: teste de concessão tardia verifica a sequência de consultas [TA]; prompt/Settings precisa de validação nativa. |
| **UC-03 · P0 — Autorizar depois da inicialização** | App aberto sem acesso. Renovar/conceder a autorização pelo fluxo do macOS e voltar a um aplicativo normal. | Monitoramento é tentado novamente sem reinstalar ou reiniciar a versão com recuperação; o próximo gesto novo pode encaixar. A permissão visual antiga não é tratada como acesso efetivo. | **A + M**: `permissionGrantedAfterLaunchStartsCaptureWithoutRestarting` [TA]; implementação [AM]. |
| **UC-04 · P0 — Revogar acesso com gesto ativo** | Arraste ou ajuste de par em andamento. Revogar o acesso; depois concedê-lo novamente e iniciar outro gesto. | Captura, seleção e pares são encerrados quando a perda é detectada; o gesto anterior não produz escrita atrasada. A retomada permite um gesto novo. | [AM], [APP], [G]. **P + M**: `permissionLossStopsCaptureAndRestorationStartsItAgain` [TA] cobre o controlador; a composição com overlays e gesto nativo exige validação. |
| **UC-05 · P0 — Falha transitória de captura ou parada** | Acesso efetivo concedido; criação do event tap falha. Aguardar outra tentativa. Repetir encerrando/reiniciando o ciclo com callback antigo pendente. | Registro é tentado novamente sem repetir prompts; depois de parar, trabalho antigo não reinicia captura nem outro ciclo de polling. | **A + M**: `failedTapCreationIsRetriedEvenWhilePermissionRemainsGranted` e `stoppingRejectsAlreadyQueuedCallbacksIncludingAfterRestart` [TA]. O teste usa monitor programado, não força falha do event tap real. |

## Reconhecimento de intenção e gestos

| ID / prioridade | Pré-condição e passos | Resultado esperado e alternativas | Evidência / cobertura |
|---|---|---|---|
| **UC-06 · P1 — Mover pelo cabeçalho** | Pressionar o cabeçalho; mover menos de 14 pontos; ultrapassar o limiar; aproximar da borda; soltar. | Antes do limiar não há encaixe. Ao ultrapassá-lo, mantém a janela capturada e permite barra/prévia; soltar aplica somente o alvo válido selecionado. | **A + M**: `acceptsAtExactlyFourteenPointsFromTheOriginalMovement`, `acceptedGestureUsesOneCandidateAndTheSnappingInterfaceForPreviewAndRelease` [TD]; [D], [G]. |
| **UC-07 · P1 — Clique ou tremor pequeno** | Pressionar o cabeçalho, mover pouco e soltar; iniciar outro gesto completo. | O primeiro gesto não encaixa; o segundo começa limpo. Não sobra barra, alvo ou janela capturada. | **A + M**: `subThresholdReleaseCannotCommitAndNextGestureStartsFresh` [TD]; [D]. |
| **UC-08 · P0 — Selecionar conteúdo sem organizar a janela** | Iniciar arraste no conteúdo/texto e atravessar o cabeçalho até uma borda; soltar; depois começar pelo cabeçalho. | O gesto iniciado no conteúdo continua rejeitado até soltar, sem mudar a janela. O gesto seguinte no cabeçalho funciona. | **A + M**: `rejectedContentDoesNotBecomeADragWhenItPassesThroughTheHeader` e `rejectedGestureCannotSnapAndReleaseAdmitsTheNextGesture` [TD]. |
| **UC-09 · P0 — Redimensionar pela borda ou canto nativo** | Janela normal. Arrastar cada uma das quatro bordas e dos quatro cantos, sobretudo os superiores, por mais de 14 pontos; passar perto da pílula e de uma borda da tela; soltar. | **Critério de prevenção proposto:** redimensionamento nativo mantém o controle no aplicativo; não abre barra/prévia de encaixe nem reorganiza a janela ao soltar. Se abrir, registrar ponto inicial, aplicativo e variação do frame para construir regressão. | **A + M**: `auditUC09NativeCornerResizeMustNotOpenSnapBar`, `resizeBorderIsRejectedEvenWithoutSizeChange`, `sizeChangeDuringDragDismissesControlsAndStaysIgnoredUntilRelease` e `sizeChangeImmediatelyBeforeReleaseCannotCommitSnap` [TD] cobrem os caminhos controlados. `translatingWindowAndBoundedRoundingStillAllowSnapping` preserva o caminho positivo. Entrega nativa e restauração automática por aplicativo continuam pendentes. |
| **UC-10 · P0 — Rejeitar janela inelegível** | Repetir o gesto sobre desktop, janela do MacSnap, janela de tamanho fixo e janela em tela cheia nativa. | Não apresenta controles de encaixe nem escreve frames. Tornar a janela elegível no meio do mesmo botão pressionado não deve reativar o gesto rejeitado; soltar permite nova tentativa. | **A + M**: `rejectedDesktopAndOwnWindowsStayIgnoredUntilRelease`, `ineligibleWindowStaysIgnoredUntilRelease` [TD]; `fullScreenWindowRejectsSnappingEvenWhenAXSizeIsSettable`, `nonResizableWindowRejectsBothFrameAPIsAndSnapping` [TS]; [W]. |
| **UC-11 · P0 — Entrar em tela cheia durante o gesto** | Iniciar arraste elegível; entrar em tela cheia antes de outro movimento, imediatamente antes de soltar ou antes do drop agendado. | Cancela interação e escrita atrasada; não deixa controles interativos sobre a tela cheia. Sair desse modo permite um gesto novo. | **A + M**: `enteringFullScreenCancelsCapturedGesture`, `enteringFullScreenImmediatelyBeforeReleaseCancelsDrop` [TD], `enteringFullScreenBeforeDeferredDropPreventsPlacement` [TS]. |
| **UC-12 · P0 — Interromper um gesto** | Selecionar alvo; pausar, parar captura ou simular recuperação de tap; manter botão pressionado, mover e soltar; iniciar novo gesto. | A seleção antiga é limpa e não reaparece enquanto o botão continua pressionado. Eventos de captura anterior não reiniciam a interação encerrada. | **A parcial + M**: `pauseResumeDiscardsTheOldGestureUntilMouseUp`, `tapRecoveryWhileIdleStartsFreshButCancelsAnActiveHeldGesture`, `stoppingAndRestartingHasNoOldCaptureOrRejection` [TD]; geração nativa em [G]. |
| **UC-13 · P1 — Arrastar abas e controles no cabeçalho** | Navegador ou editor com abas. Arrastar uma aba dentro da janela, destacar a aba para outra janela e arrastar um controle do toolbar. | **Critério a validar por aplicativo:** rearranjo de aba/controle não provoca encaixe involuntário; se o aplicativo transforma a ação em movimento de janela, o alvo precisa corresponder à janela realmente movida. | **L + M** para destaque/troca de identidade de aba. O comentário de [G] admite janela/aba, mas [D] retém a candidata sem re-resolver a identidade durante o gesto. Cabeçalhos reais variam entre aplicativos. |

## Barra de layouts, prévia e área útil

| ID / prioridade | Pré-condição e passos | Resultado esperado e alternativas | Evidência / cobertura |
|---|---|---|---|
| **UC-14 · P1 — Exibir pílula e expandir cartões** | Top Snap Bar ligada; iniciar arraste reconhecido; aproximar o cursor da pílula; sair da área expandida. | Pílula aparece no topo da tela atual; hover expande; afastamento recolhe sem perder o controle do gesto. Apenas mover o mouse sem arrastar não inicia esse fluxo. | **A parcial + M**: `testSnapLayoutBarPillAndExpandedStateTransitions` [TG] testa a janela de apresentação; fluxo do handler em [G], apresentação em [B]. |
| **UC-15 · P0 — Prévia corresponder ao encaixe** | Arrastar sobre um slot de cartão e soltar; repetir nos slots com mesma zona mas posições visuais distintas. | Um slot selecionado por vez; alvo do cartão e frame aplicado seguem a mesma intenção, ajustados aos limites mínimos/máximos informados pela janela. Preserva a borda escolhida; limites impossíveis ou inválidos não produzem sombra nem escrita. Sem limites disponíveis, mantém a prévia padrão por decisão do usuário. Não redimensiona vizinha para fabricar par. | **A + M**: `exactAndAdaptiveIntentsUseTheSamePolicyForPreviewAndPlacement`, `constrainedPreviewMatchesPlacementAndStaysInsideScreen`, `partialBoundsAdjustBothPreviewAndPlacement`, `unknownLimitsPreserveDefaultPreviewAndDrop`, `impossibleBoundsSuppressPreviewAndPlacement` [TS]; `testSingleSlotHighlightingInSnapBar`, `testPortraitSlotsIndependentHighlightingForIdenticalZones` [TG]. |
| **UC-16 · P1 — Atravessar o espaço entre cartões** | Selecionar quarto inferior direito, atravessar o intervalo entre cartões e selecionar Maximize; soltar. | O intervalo e uma animação antiga de saída não ocultam a prévia mais recente; drop aplica Maximize. Um descarte atual, ao contrário, precisa ocultar a prévia. | **A + M**: `quarterToMaximizeAcrossLayoutGapKeepsPreviewAndDropInSync` [TD], `dismissingQuarterCannotHideNewerMaximizePreview`, `latestDismissalStillClosesAnInterruptedPreview` [TP]. |
| **UC-17 · P1 — Soltar sem alvo ou cancelar seleção** | Com a barra aberta, sair dos slots e das zonas de borda e soltar; repetir desligando Top Snap Bar durante seleção de cartão. | Não aplica o alvo anterior; barra e prévia desaparecem; ações pendentes são canceladas. Se Edge Snap continuar ligado, sua seleção depende da posição atual. | Política [G]. **P + M**: testes de cancelamento/drop [TD], [TS] exercitam parte do fluxo; não foi localizado teste integrado de todas as combinações dos toggles com hover. |
| **UC-18 · P1 — Cruzar monitores durante arraste** | Dois monitores com tamanhos/orientações e origens diferentes. Iniciar no A, cruzar para B, abrir barra e soltar em B. | Mantém a janela capturada; barra e alvo passam à tela do cursor; drop usa a área útil de B. Pares existentes em outra tela permanecem independentes. | **P + M**: `crossingDisplaysKeepsTheCapturedWindowAndDoesNotReadmit` [TD] cobre reconhecimento; [B] implementa migração. Não demonstra a apresentação completa em dois monitores físicos. |
| **UC-19 · P0/P1 — Respeitar o Dock no uso real** | Executar as variantes UC-19-A a H: Dock fixo, auto-oculto, revelado durante arraste/divisor e mudança de lado/tamanho/monitor; combinar menu auto-oculto. | Área reservada, estado de revelação e captura de cliques são verificações separadas. Revalidar geometria quando necessário; preservar acesso ao Dock e não produzir encaixe involuntário. A política de sobreposição transitória é uma decisão proposta, não comportamento já provado. | **P + M**: [B], [G], [E], [PAIR], [DIV], [OV]. Não foi localizado teste específico do Dock real; `visibleFrame` não detecta sozinho visibilidade instantânea. |
| **UC-20 · P0 — Reconfigurar tela com controles abertos** | Abrir barra/prévia; alterar resolução, rotação ou tela principal, desconectar a tela e repetir em notebook com notch. | **Critério de prevenção:** não aplicar alvo em tela removida; controles não ficam presos, fora da área útil ou sobre região inacessível. Cancelar ou reposicionar deve ser definido e consistente antes de implementar mudanças. | **P + M**: `missingDisplayDuringMovementDiscardsThePreviouslySelectedTarget`, `removedDisplayAtReleaseCannotUseTheRetainedPreviewScreen` [TD]; desconexão de drop em [TS]. [APP] notifica explicitamente o gerenciador de pares, não a barra. Serviço nativo tem fallback à tela principal [S]; fixtures que retornam `nil` não provam esse fallback. |

## Intenção de encaixe e identidade da janela

| ID / prioridade | Pré-condição e passos | Resultado esperado e alternativas | Evidência / cobertura |
|---|---|---|---|
| **UC-21 · P1 — Bordas e cantos em monitor horizontal** | Arrastar e soltar em cada borda e canto; repetir com janela já maximizada, mas fora de tela cheia nativa. | Esquerda/direita usam metades; topo usa Maximize quando a barra não está expandida; baixo usa metade inferior; cantos usam quartos. Maximizada continua elegível se redimensionável. | Mapeamento [G]; geometria `testSnapZoneHalfCalculations`, `testSnapZoneCornerCalculations` [TG]. **P + M**: cálculo de zonas não cobre todos os eventos e aplicativos. |
| **UC-22 · P1 — Monitor vertical** | Monitor em retrato; arrastar às bordas laterais em diferentes alturas, ao topo e ao fundo; selecionar slots da barra. | Laterais sugerem terços conforme altura; topo/fundo usam metades correspondentes; cartões respeitam orientação e não trocam destaque entre slots semelhantes. | [G], [B]. **P + M**: `testVerticalMonitorThirdsCalculations`, `testPortraitSlotsIndependentHighlightingForIdenticalZones` [TG]. |
| **UC-23 · P1 — Ajustar ao espaço disponível** | Vizinha já ocupa uma largura/altura personalizada junto à borda; encaixar outra por borda. Repetir com duas vizinhas e alvo central. | Intenção adaptativa usa o espaço elegível observado. Vizinha não sofre escrita; proposta inviável volta à zona padrão. Seleção explícita de cartão continua exata. | **A + M**: `adaptivePlacementFitsLeftTopBottomAndBetweenTwoNeighbors`, `exactAndAdaptiveIntentsUseTheSamePolicyForPreviewAndPlacement`, `constrainedPreviewMatchesPlacementAndStaysInsideScreen`, `partialBoundsAdjustBothPreviewAndPlacement`, `unknownLimitsPreserveDefaultPreviewAndDrop`, `impossibleBoundsSuppressPreviewAndPlacement` [TS]; [R]. |
| **UC-24 · P0 — Mudar condições entre prévia e drop** | Exibir prévia; mover vizinha, rejeitar escrita nativa, desconectar tela ou executar comando explícito antes do drop adiado. | Reavalia observação na aplicação; falha não registra sucesso/par; comando novo substitui drop antigo; tela desconectada impede escrita. Não tratar frame solicitado como resultado real. | **A + M**: `placementRefreshesObservationsAndFailedWritesDoNotRegister`, `disconnectedDisplayCancelsDeferredPlacementAndDiscovery`, `explicitSnapSupersedesADelayedDrop` [TS]; [E]. |
| **UC-25 · P0 — Quick Snap atuar na janela certa** | Focar janela A; abrir o menu e executar Quick Snap; repetir com duas janelas do mesmo app, janela minimizada e observação ambígua. | **Critério de prevenção:** atuar na janela individual pretendida; não escolher janela invisível só por conservar frame AX nem alterar outra janela por adivinhação. | **P + M**: os testes de identidade/visibilidade [TW] cobrem descoberta. Quick Snap usa `AccessibilityService.getFocusedWindow`, com fallbacks próprios de foco/main/windows, não necessariamente o snapshot testado. Falta validar esse caminho completo de foco/menu. [E], [AX], [DISC]. |

## Pares e redimensionamento pelo divisor

| ID / prioridade | Pré-condição e passos | Resultado esperado e alternativas | Evidência / cobertura |
|---|---|---|---|
| **UC-26 · P1 — Descobrir duas janelas adjacentes** | Posicionar duas janelas elegíveis lado a lado ou empilhadas, incluindo duas do mesmo aplicativo; ativar o app ou encaixar uma delas. | Forma par entre duas identidades distintas; orientação e proporção correspondem à geometria observada. Não admite uma janela como as duas integrantes. | **A + M**: `managerDetectsExactSameAppPairOcclusionAndObservationAvailability` [TW], `pairAdmissionRejectsPartialRowsAndThreeColumnsButAcceptsBothAxes` [TS]; [PAIR]. |
| **UC-27 · P1 — Ajustar a divisão** | Par válido. Arrastar divisor, observar as duas prévias e soltar; repetir nos dois eixos e nos extremos permitidos. | Durante o movimento altera razão e apresentação; na soltura escreve os frames na ordem de redução antes de expansão. Confere o resultado real e estabiliza a divisão. | **A + M**: `draggingChangesOnlyPreviewThenReleaseCommitsAndSettles`, `releaseShrinksBeforeExpandingInBothOrientations` [TR]; [SESSION]. |
| **UC-28 · P0 — Não competir com o divisor** | Par válido e Top Snap Bar ligada. Arrastar o divisor pelo topo, por slots e pelas bordas da tela; soltar. | Ajusta apenas o par; barra de layouts e encaixe individual não iniciam outro gesto. Não mantém uma seleção antiga depois da supressão. | **A parcial + M**: `dividerSuppressionAndStopDiscardTheCapturedWindow` [TD]; a guarda explícita é `isDraggingDivider` em [G]. A fixture não substitui o percurso real do cursor sobre todos os painéis. |
| **UC-29 · P0 — Janela sobre o divisor** | Cobrir a junção com terceira janela, inclusive do mesmo app; mover o mouse e clicar na região coberta. | Divisor não captura clique nem exibe cursor de ajuste sobre janela não integrante. Se identidade/observação estiver indisponível, a oclusão é tratada conservadoramente. | **A + M**: `thirdWindowOfSameApplicationOccludesTheDivider`, `ambiguousOrUnavailableWindowIdentityDoesNotPermitDividerInteraction` [TW]; [DIV], [DISC]. |
| **UC-30 · P0 — Tamanho mínimo e recusa de resize** | Par com aplicativo que impõe tamanho mínimo; ajustar além dele; repetir recusa de uma escrita e limite no eixo perpendicular. | Reconcilia com o frame observado por correção limitada; se a divisão não puder existir, desfaz o par. Não repete redimensionamento indefinidamente nem expande sobre espaço não liberado. | **A + M**: `minimumSizeReadbackRealignsPartnerToTheObservedFirstWindow`, `impossibleMinimumSizesInvalidateWithoutAnUnboundedRetry`, `unsupportedCrossAxisMinimumCannotClaimAFullDisplaySplit`, `failedShrinkingWriteDoesNotExpandTheOtherWindow` [TR]. |
| **UC-31 · P0 — Invalidar integrante do par** | Com divisor visível ou em ajuste, fechar, mover para longe ou colocar uma integrante em tela cheia; repetir antes da correção adiada. | Remove controle inválido; não escreve na outra janela para completar uma operação impossível. Divisor antigo não intercepta cliques. | **A + M**: `auditUC31MovedMemberMustNotBeOverwrittenOnRelease` e `externallyChangedMemberInvalidatesDuringPreview` [TR] cobrem movimento externo; os testes existentes preservam fechamento e fullscreen. O ambiente real continua pendente. |
| **UC-32 · P0 — Substituir/cancelar par durante trabalho pendente** | Iniciar ajuste e soltura; limpar ou substituir o par antes do callback de estabilização. Entregar inclusive callback cancelado no teste. | Sessão antiga não escreve, não modifica o par novo e não oculta apresentação de outra operação. | **A + M**: `aStaleReadbackCannotWriteOrDismissAnotherPair`, `replacingOrClearingScreenPairStateCancelsItsPendingLifetime` [TR]; [SESSION]. |
| **UC-33 · P0 — Pares independentes e reconfiguração de telas** | Formar par em cada tela; ajustar uma; desconectar/reconfigurar a outra, mudar altura da tela principal e depois reencontrar as janelas. | Operações por tela permanecem independentes; referência de coordenadas antiga é invalidada; callback atrasado não usa tela removida ou geometria antiga. | **A parcial + M**: `removedDisplayPurgesPairAndCancelsDeferredWrites`, `screenGeometryMismatchCancelsSettlementBeforeRediscovery`, `primaryReferenceHeightChangeCancelsEvenWhenDisplayGeometryIsUnchanged` [TR]; [PAIR]. |
| **UC-34 · P1 — Não fabricar par de layout incompatível** | Criar três colunas, apenas dois quartos superiores ou janelas com frames sem divisão binária válida; solicitar encaixe/descoberta. | Não estica janelas vizinhas para ocupar a tela inteira nem anuncia divisor de par incompatível. Slots individuais continuam funcionando. | **A + M**: `threeColumnsAreNotConvertedToABinaryPair`, `pairAdmissionRejectsPartialRowsAndThreeColumnsButAcceptsBothAxes` [TS]; [PAIR]. |

## Controles e menu

| ID / prioridade | Pré-condição e passos | Resultado esperado e alternativas | Evidência / cobertura |
|---|---|---|---|
| **UC-35 · P0 — Pausar e retomar** | Abrir menu; pausar; tentar Quick Snap e arraste; retomar ainda com o botão pressionado e depois iniciar outro gesto. | Pausa impede organização e limpa interação/pares; atualização continua acessível. Retomada não ressuscita o gesto antigo. Preferência não é reescrita por uma atualização. | **A parcial + M**: `pauseResumeDiscardsTheOldGestureUntilMouseUp` [TD], `accessibilityPressClearsHoverAndPausedMenuRejectsActions` [TM], `menuChecksForUpdatesEvenWhenSnappingIsPaused` [TU]; [G], [MENU]. |
| **UC-36 · P1 — Alternar cada recurso isoladamente** | Desligar Top Snap Bar, Edge Snap e Divider separadamente; repetir com alvo de cartão, alvo de borda e ajuste de par ativos. | Cada toggle desativa seu recurso, limpa a apresentação/trabalho correspondente e preserva os outros recursos habilitados. Sem barra, bordas ainda podem funcionar; sem bordas, cartões ainda podem funcionar. | Política [G], [PAIR]. **P + M**: `testMenuBarControllerAndFeatureToggles` [TG] não prova todos os percursos de gesto. Falta matriz integrada das combinações e do instante da alteração. |
| **UC-37 · P2 — Reabrir menu e usar ações acessíveis** | Passar o mouse por ações, clicar/fechar menu, reabrir e acionar via acessibilidade; alternar início no login e reabrir o app. | Sem hover antigo; controles refletem estado atual, versão e permissão efetiva; ações acessíveis seguem a mesma política de pausa. Início no login requer conferir comportamento real do sistema. | **A parcial + M**: `quickSnapClickDoesNotKeepHoverWhenMenuReopens`, `dismissingMenuClearsHoverForQuickSnapAndActionButtons`, `accessibilityPressClearsHoverAndPausedMenuRejectsActions` [TM]; login não está demonstrado por esses testes. |

## Atualização e continuidade de uso

| ID / prioridade | Pré-condição e passos | Resultado esperado e alternativas | Evidência / cobertura |
|---|---|---|---|
| **UC-38 · P1 — Consultar atualização pelo menu** | Build configurado; pausar snapping; escolher Check for Updates. Repetir com sessão já indisponível ou build sem chave/feed válido. | Consulta manual funciona quando permitida, inclusive pausado; ação fica indisponível quando não pode consultar. Build não configurado não inicia atualização/rede. | **A parcial + M**: `menuChecksForUpdatesEvenWhenSnappingIsPaused`, `unconfiguredBuildDoesNotEnableUpdates` [TU]; [UP]. A consulta real ao servidor é do SDK. |
| **UC-39 · P1 — Lembretes e preferências de atualização** | Alternar consulta periódica e download/instalação automática separadamente; receber oferta em segundo plano; abrir menu; cancelar/dispensar a sessão. | Preferências continuam separadas; oferta aparece no menu sem interromper o trabalho; consulta explícita usa UI de Sparkle. Encerrar/abortar limpa a versão pendente. | **A parcial + M**: `pendingUpdateAndPreferencesArePresentedThroughTheMenu` [TU] usa updater controlado; delegação e callbacks em [UP]. Fluxo completo de consentimento/skip/defer e persistência nativa precisa ser exercitado. |
| **UC-40 · P0 — Atualizar sem interromper interação** | Com atualização disponível, iniciar arraste de janela ou divisor e solicitar instalação/encerramento; manter botão pressionado e depois soltar. | Encerramento espera a operação terminar; resposta antiga não encerra uma solicitação nova; ao terminar, captura e overlays são limpos. Não interpretar teste do booleano `busy` como prova de todas as interações nativas. | **A parcial + M**: `terminationWaitsUntilTheWindowInteractionHasFinished`, `cancelledTerminationWorkCannotReplyToAnEarlierRequest` [TU]; composição `installationIsBusy` em [APP], espera [UP]. |
| **UC-41 · P0 — Falha de rede, assinatura ou oferta inválida** | Usar ambiente controlado para interromper download, fornecer arquivo alterado/assinatura inválida, build antigo/retirado ou metadados incompatíveis. | Não substituir instalação válida por arquivo não autenticado/incompatível; não reintroduzir oferta retirada nem regredir o feed; falha deve permitir recuperação segura. | **A parcial + M**: testes reais de assinatura, retirada e promoção em [TUP]. Eles exercitam ferramentas de distribuição; não demonstram todas as falhas de rede/instalação na UI de Sparkle. Arquivos/condições do SDK exigem teste próprio. |
| **UC-42 · P0 — Renovar Acessibilidade após atualização real** | Atualizar entre dois builds ad hoc pelo canal aprovado; manter a instalação normal; tentar encaixar antes/depois de renovar a entrada de Acessibilidade quando necessário. | Integridade do download e continuidade de autorização são verificadas separadamente. Se macOS conservar entrada antiga sem conceder acesso efetivo, instruções indicam remover/reinserir o app atual, sem reinstalar. A partir de 1.0.10, a captura retoma após a renovação detectada. | **P + M obrigatório**: controlador [AM]/[TA] cobre transições programadas; o ciclo de substituição de binário + TCC real não é comprovado por esses testes. Política gratuita e incidente conhecido estão em [UPDATE-DOC]. |

## Desinstalação

| ID / prioridade | Pré-condição e passos | Resultado esperado e alternativas | Evidência / cobertura |
|---|---|---|---|
| **UC-43 · P0 — Cancelar ou impedir desinstalação concorrente** | Solicitar desinstalação, cancelar; repetir durante atualização ou iniciando atualização enquanto a confirmação está aberta. | Cancelar não inicia remoção. Operação de atualização impede desinstalação; verifica disponibilidade de novo após a confirmação. Erros mantêm o app utilizável quando possível e apresentam a falha. | **A + M**: `cancelConfirmationAndUpdateInProgressNeverStartRemoval`, `menuRoutesUninstallOnlyWhenTheActionIsAvailable` [TX]; [UN]. Não executar sobre instalação pessoal como simples smoke test. |
| **UC-44 · P0 — Remover somente o que pertence ao app** | Ambiente descartável autorizado; visualizar plano; confirmar remoção. Repetir identidade trocada, symlink malicioso e falha ao mover app para lixeira. | Prévia não altera nada. Confirmação só remove app/dados enumerados; não alcança documentos, projetos ou chaves. Falha ao remover o app não apaga suas configurações. Limpeza de login/permissões precisa corresponder ao plano e à resposta real do macOS. | **A + M**: `previewDoesNotChangeTheApplicationOrItsSettings`, `cleanRemovalPreservesProjectsKeysAndOtherApplications`, `changedIdentityAfterPreviewCannotBeRemoved`, `symbolicLinkCannotRedirectCacheRemovalIntoDocuments`, `failedTrashOperationKeepsSettingsAndApplication` [TX]; [PLAN]. |

## Lacunas e prioridades antes de escolher novos fixes

| Ordem | Evidência encontrada | Próximo teste ou decisão | Limite da conclusão |
|---|---|---|---|
| 1 | **UC-19:** considera área útil, mas não há estado explícito de Dock revelado. Previews ignoram mouse; divisor consulta oclusão baseada em observação de janelas normais. [E], [OV], [DIV], [DISC] | Executar primeiro Dock auto-oculto revelado durante arraste/divisor e clique em ícone perto da junção. Definir o que deve acontecer com a prévia nessa sobreposição transitória. | Ausência de cobertura nativa do Dock não demonstra falha de clique/resize. `visibleFrame` não prova visibilidade instantânea. |
| 2 | **UC-19/20:** barra usa `visibleFrame` ao apresentar/expandir/migrar; par compara a área atual com a capturada. [B], [PAIR] | Testar mudança de lado/tamanho/monitor do Dock, menu auto-oculto, rotação, notch e área útil pequena. Conferir que cancelamento geométrico também retira/recoloca os controles apropriados. | Há guardas de geometria. Sua composição com todos os eventos nativos e limpeza de overlays ainda não foi executada. |
| 3 | **UC-09:** a correção local acrescenta proteção da borda e revalidação do tamanho, com regressão permanente e controles positivos de movimento. [D], [G], [TD] | Validar bordas/cantos em Finder, navegador e editor, incluindo janela no tamanho mínimo, restauração de janela maximizada e abas. | Testes controlados passaram; compatibilidade de gestos e entrega de eventos reais continua pendente. |
| 4 | **UC-42:** assinatura ad hoc não estabelece identidade estável entre builds; recuperação automática depende de autorização efetiva renovada. [UPDATE-DOC], [AM] | Registrar um ciclo real de atualização, renovação e primeiro arraste; conferir menu e captura. Manter explícita a escolha de distribuição gratuita. | Testes do controlador e assinatura do ZIP não demonstram preservação de TCC. |
| 5 | **UC-13/25:** candidata de arraste é retida durante o gesto; descoberta evita ambiguidades, mas abas podem criar outra janela nativa. [D], [DISC] | Exercitar destaque de abas e toolbars customizados; definir a janela cujo movimento deve constituir intenção de encaixe. | Compatibilidade por aplicativo está pendente, sem defeito confirmado. |
| 6 | **UC-20/36/40:** seleção nativa de tela tem fallback para a principal [S], enquanto fixtures podem retornar `nil`; toggles e busy/encerramento têm testes parciais. [TD], [TU] | Exercitar o adapter de tela/fallback e a matriz cartão/borda/divisor × toggle/pausa/atualização. | Diferença entre produção e fixture e composições não exercitadas; não são reproduções de falha. |

Priorizar cenários P0 que alteram uma janela sem intenção, tornam o app inoperante após atualização ou podem remover dados. Só converter uma lacuna em bug depois de estabelecer passos e um sinal de falha reproduzível. Não há proposta de implementação nem autorização de publicação neste catálogo.

## Conjunto mínimo de aceitação para uma mudança de interação

Selecionar os IDs afetados pela mudança e executar os caminhos positivo e negativo juntos: mover pelo cabeçalho **e** redimensionar pelas bordas; janela normal **e** tela cheia; barra **e** divisor; uma tela **e** troca/perda de tela; acesso concedido **e** revogado. Conferir prévia, resultado real e ausência de escrita quando rejeitado/cancelado. Para uma alteração apenas de documentação, não exigir uma reinstalação nem um novo build pessoal.

Para cada execução, registrar `ID`, configuração, aplicativo, passos, esperado, observado, evidência e resultado (`passou`, `falhou` ou `não executado`). Manter o [roteiro manual existente](../architecture/manual-test.md) como complemento. A mera existência de um teste, inclusive teste de hierarquia visual ou cálculo geométrico, não deve ser registrada como aceite nativo.

## Fontes primárias e referências de testes

As referências abaixo são da revisão local pesquisada. Links de linha ajudam a localizar o comportamento; nomes de testes no catálogo identificam o cenário mesmo quando as linhas mudarem. Nenhuma suíte foi executada para produzir este levantamento.

- [G]: [GlobalEventMonitor: admissão, exclusão do divisor, apresentação e limpeza](../../Sources/MacSnap/Services/EventMonitoring/GlobalEventMonitor.swift#L142).
- [D]: [DragRecognition: estados, limiar e região de admissão](../../Sources/MacSnap/Services/EventMonitoring/DragRecognition.swift#L47).
- [W]: [WindowElement: elegibilidade e região do cabeçalho](../../Sources/MacSnap/Core/Models/WindowElement.swift#L116).
- [B]: [SnapLayoutBarWindow: estados e frames da barra](../../Sources/MacSnap/Features/UI/SnapLayoutBarWindow.swift#L39).
- [S]: [ScreenService: seleção/fallback de tela](../../Sources/MacSnap/Services/Screen/ScreenService.swift#L23).
- [E]: [SnapEngine: prévia, escrita, drop e cancelamento](../../Sources/MacSnap/Features/Snapping/SnapEngine.swift#L30).
- [R]: [SnapTargetResolver: intenção exata/adaptativa](../../Sources/MacSnap/Features/Snapping/SnapTargetResolver.swift#L11).
- [PAIR]: [PairedResizeManager: sessões, descoberta e validação de pares](../../Sources/MacSnap/Features/Pairing/PairedResizeManager.swift#L100).
- [SESSION]: [PairedResizeSession: begin, update, finish, cancel e readback](../../Sources/MacSnap/Features/Pairing/PairedResizeSession.swift#L41).
- [DIV]: [DividerHandleWindow: validação, hit testing e interação](../../Sources/MacSnap/Features/UI/DividerHandleWindow.swift#L132).
- [OV]: [PreviewOverlayWindow: overlay ignora mouse](../../Sources/MacSnap/Features/UI/PreviewOverlayWindow.swift#L25) e [PairedResizeOverlayWindow](../../Sources/MacSnap/Features/UI/PairedResizeOverlayWindow.swift#L25).
- [DISC]: [WindowDiscovery: observações, identidade e oclusão](../../Sources/MacSnap/Services/Accessibility/WindowDiscovery.swift#L14).
- [AX]: [AccessibilityService: obtenção de foco e seus fallbacks](../../Sources/MacSnap/Services/Accessibility/AccessibilityService.swift#L57).
- [AM]: [AccessibilityMonitoringController: reconciliação de confiança efetiva](../../Sources/MacSnap/Services/EventMonitoring/AccessibilityMonitoringController.swift#L28).
- [APP]: [AppDelegate: integração, encerramento e mudanças de tela](../../Sources/MacSnap/App/AppDelegate.swift#L18).
- [MENU]: [MenuBarController: estado atual do menu e orientação de Acessibilidade](../../Sources/MacSnap/Features/UI/MenuBarController.swift#L232).
- [UP]: [SparkleAppUpdater: configuração, preferências, callbacks e encerramento](../../Sources/MacSnap/Services/Updating/SparkleAppUpdater.swift#L19).
- [UN]: [AppUninstaller: confirmação e concorrência com atualização](../../Sources/MacSnap/Services/Uninstallation/AppUninstaller.swift#L33).
- [PLAN]: [UninstallPlan: identidade, caminhos limitados e validação](../../Sources/MacSnapUninstallation/UninstallPlan.swift#L12).
- [UPDATE-DOC]: [Distribuição gratuita e recuperação após atualização](../automatic-updates.md#recovering-window-management-after-an-update).
- [TA]: [AccessibilityMonitoringControllerTests](../../Tests/MacSnapTests/AccessibilityMonitoringControllerTests.swift#L8).
- [TD]: [DragRecognitionTests e GlobalEventMonitorIntegrationTests](../../Tests/MacSnapTests/DragRecognitionTests.swift#L12).
- [TG]: [MacSnapTests: geometria, apresentação e integração parcial](../../Tests/MacSnapTests/MacSnapTests.swift#L9).
- [TS]: [SnapEngineTests](../../Tests/MacSnapTests/SnapEngineTests.swift#L10).
- [TR]: [PairedResizeSessionTests](../../Tests/MacSnapTests/PairedResizeSessionTests.swift#L8).
- [TW]: [WindowDiscoveryTests](../../Tests/MacSnapTests/WindowDiscoveryTests.swift#L9).
- [TM]: [MenuBarControllerTests](../../Tests/MacSnapTests/MenuBarControllerTests.swift#L12).
- [TU]: [AppUpdatingTests](../../Tests/MacSnapTests/AppUpdatingTests.swift#L8).
- [TP]: [SnapPreviewTransitionTests](../../Tests/MacSnapTests/SnapPreviewTransitionTests.swift#L8).
- [TX]: [UninstallationTests](../../Tests/MacSnapTests/UninstallationTests.swift#L15).
- [TUP]: [Testes das políticas de atualização, assinaturas e publicação](../../scripts/test-update-distribution.py#L29) e [políticas do instalador](../../scripts/test-dmg-distribution.py#L27).

[G]: ../../Sources/MacSnap/Services/EventMonitoring/GlobalEventMonitor.swift#L142
[D]: ../../Sources/MacSnap/Services/EventMonitoring/DragRecognition.swift#L47
[W]: ../../Sources/MacSnap/Core/Models/WindowElement.swift#L116
[B]: ../../Sources/MacSnap/Features/UI/SnapLayoutBarWindow.swift#L39
[S]: ../../Sources/MacSnap/Services/Screen/ScreenService.swift#L23
[E]: ../../Sources/MacSnap/Features/Snapping/SnapEngine.swift#L30
[R]: ../../Sources/MacSnap/Features/Snapping/SnapTargetResolver.swift#L11
[PAIR]: ../../Sources/MacSnap/Features/Pairing/PairedResizeManager.swift#L100
[SESSION]: ../../Sources/MacSnap/Features/Pairing/PairedResizeSession.swift#L41
[DIV]: ../../Sources/MacSnap/Features/UI/DividerHandleWindow.swift#L132
[OV]: ../../Sources/MacSnap/Features/UI/PreviewOverlayWindow.swift#L25
[DISC]: ../../Sources/MacSnap/Services/Accessibility/WindowDiscovery.swift#L14
[AX]: ../../Sources/MacSnap/Services/Accessibility/AccessibilityService.swift#L57
[AM]: ../../Sources/MacSnap/Services/EventMonitoring/AccessibilityMonitoringController.swift#L28
[APP]: ../../Sources/MacSnap/App/AppDelegate.swift#L18
[MENU]: ../../Sources/MacSnap/Features/UI/MenuBarController.swift#L232
[UP]: ../../Sources/MacSnap/Services/Updating/SparkleAppUpdater.swift#L19
[UN]: ../../Sources/MacSnap/Services/Uninstallation/AppUninstaller.swift#L33
[PLAN]: ../../Sources/MacSnapUninstallation/UninstallPlan.swift#L12
[UPDATE-DOC]: ../automatic-updates.md#recovering-window-management-after-an-update
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


### Limites da previsão de tamanho (UC-15)

O adaptador consulta os atributos opcionais `AXMinSize`/`AXMinimumSize` e `AXMaxSize`/`AXMaximumSize`, quando o aplicativo os expõe como `CGSize`. Não há inferência de tamanho ilimitado a partir de `AXSize` gravável. A leitura não redimensiona a janela para descobrir restrições.

O mesmo cálculo limita a prévia e o encaixe, mantendo borda ou centro e a área útil da tela. Limites são relidos ao soltar. A decisão de produto é manter a sombra padrão quando faltarem limites; nesse caso a sombra continua sendo uma estimativa. Limites de proporção, incrementos discretos e restrições dinâmicas não expostas pelo aplicativo também podem alterar o resultado nativo. Os testes usam adaptadores controlados: a exposição desses atributos pelo Settings e outros aplicativos reais ainda precisa ser validada.

Referência de implementação independente para os atributos mínimos: [Rectangle — AccessibilityElement.minimumSize](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift). Os nomes opcionais não constituem garantia de suporte por todos os aplicativos.
