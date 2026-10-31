# Teste local da refatoração nativa

A branch prepara a correção de tela cheia na versão **1.0.9 / build 9**; a release pública continua sendo a 1.0.7. Não foi criada tag nem publicada uma nova release. O build de teste fica separado da instalação em `/Applications/MacSnap.app`.

## Abrir e voltar à instalação atual

1. Gere o pacote com `./scripts/build-development-app.sh`. O script roda a suíte de testes e compila Apple Silicon + Intel; não instala nem inicia o programa.
2. Encerre o MacSnap que já está aberto pelo item **Quit** do menu. Não deixe duas instâncias capturando eventos ao mesmo tempo.
3. Abra o caminho impresso pelo script, dentro de `.build/manual-test.XXXXXX/MacSnap.app`. Cada execução gera um diretório novo. O identificador permanece o mesmo do app atual; o framework do atualizador e uma assinatura de desenvolvimento disponível são incluídos. Sem chave pública configurada, as ações de atualização ficam indisponíveis. Em outra máquina sem esse certificado, assinatura ad-hoc pode exigir conceder acessibilidade ao build de teste.
4. Teste os cenários abaixo. O objetivo é conferir comportamento, não somente ausência de mensagens de erro.
5. Para voltar, encerre o build de teste e abra `/Applications/MacSnap.app`. A instalação e a configuração de início automático não são substituídas pelo script.

Para escolher o certificado de assinatura, defina `MACSNAP_SIGNING_IDENTITY` ao executar o script. Use `MACSNAP_SIGNING_IDENTITY=- ./scripts/build-development-app.sh` para solicitar assinatura ad-hoc.

## Roteiro

| Cenário | Verificar |
|---|---|
| Quick Snap: Left, Right, Max, Center | A janela correta ocupa o retângulo escolhido; o menu continua neutro, com cor nos toggles. Reabrir não mantém hover antigo. |
| Tela cheia nativa (botão verde ou Control–Command–F) | Arrastar o cabeçalho até uma borda não abre barra/prévia nem aplica encaixe. Quick Snap também não altera a janela. Ao sair da tela cheia, um novo gesto funciona normalmente. |
| Entrar em tela cheia durante encaixe ou ajuste pelo divisor | O gesto é cancelado; barra, prévia e divisor deixam de interagir. Ações atrasadas não redimensionam a janela nem sua parceira. |
| Janela maximizada e janela sem suporte a redimensionamento | A maximizada continua elegível para encaixe. A janela com tamanho fixo não abre barra/prévia nem é escolhida para um par. |
| Barra de layouts, cartão exato | A prévia e o encaixe respeitam a divisão explícita, mesmo ao lado de janela com tamanho personalizado. |
| Borda com vizinho já posicionado | O alvo se ajusta ao espaço disponível quando há vizinho elegível. Não redimensiona outro aplicativo para fabricar um par. |
| Três colunas | Posicionar esquerda, centro e direita não força duas colunas a ocupar a tela inteira. |
| Divisor em monitor horizontal | Durante movimento, apenas divisor/prévia acompanham. Na soltura, a janela que reduz libera espaço antes da outra ampliar. |
| Divisor em monitor vertical | Repetir com janelas empilhadas; topo/fundo não se invertem. |
| Aplicativo com tamanho mínimo | O divisor acompanha o resultado real após soltar. Se o par for impossível, ele é desfeito; o app não fica repetindo redimensionamentos. |
| Fechar ou mover janela durante interação | O par antigo deixa de ser manipulável; ações atrasadas não alteram um novo par. |
| Duas janelas do mesmo aplicativo | Podem formar um par; são distinguidas individualmente. |
| Terceira janela cobrindo o divisor | O divisor não captura cliques sobre a janela que o cobre, mesmo que ela pertença ao mesmo aplicativo. |
| Janela minimizada ou em outro Space | Não é escolhida como vizinha apenas por conservar um retângulo de acessibilidade. |
| Selecionar texto e arrastar até uma borda | Não inicia encaixe. Soltar e começar outro gesto no cabeçalho permite o encaixe normal. |
| Clique com movimento pequeno no cabeçalho | Não abre encaixe antes do limiar intencional. |
| Pausar e retomar com botão pressionado | O gesto antigo não reaparece. Soltar e começar outro gesto funciona. |
| Alternar telas durante arraste | Barra e alvo seguem a tela atual; o par em outra tela continua independente. |
| Desconectar uma tela antes de soltar ou logo após | Não há encaixe atrasado numa tela removida. Se disponível, repetir após reconectar. |
| Mudar resolução ou tela principal durante ajuste em tela secundária | A operação antiga é cancelada; o divisor é redescoberto com a referência de coordenadas atual. |
| Desligar Top Snap Bar / Edge Snap / Divider | Cada controle afeta seu comportamento; ações pendentes são canceladas quando apropriado. |
| Iniciar, encerrar e abrir novamente | Não aparecem barras ou ações de uma captura anterior. |

## O que os testes automáticos não demonstram

Os testes de lógica usam janelas, observações e tempo controlados. Os testes de integração acionam o mesmo handler MainActor do monitor e os callbacks de apresentação, sem mover as janelas pessoais do usuário. A ordem e entrega real dos callbacks de `CGEventTap`, a resposta de cada aplicativo, VoiceOver e configurações reais de múltiplos monitores dependem deste smoke test.

A detecção consulta `AXFullScreen` em cada validação da janela, além de verificar se `AXSize` aceita escrita. Esse atributo não tem constante pública no SDK e pode não ser exposto por todos os aplicativos ([referência no AXSwift](https://github.com/tmandry/AXSwift/blob/main/Sources/Constants.swift)). Quando indisponível, permanece a verificação de capacidade de redimensionamento. O tamanho da janela não é usado como indicação de tela cheia, para preservar o encaixe de janelas maximizadas.

## Registro do resultado

Registrar quais cenários foram executados, aplicativos/monitores usados e qualquer diferença entre prévia e resultado. Não incluir títulos de documentos ou dados pessoais em logs compartilhados. Cenários sem equipamento disponível devem ser identificados como não testados, sem alegar cobertura completa.

Validação automática de 29/10/2026: 81 testes aprovados e build universal assinado, com versão 1.0.7/build 7. A publicação da branch e do PR foi autorizada; os resultados específicos deste roteiro manual ainda não foram registrados.

Validação automática de 31/10/2026 para tela cheia: inicialmente, 92 testes aprovados em 8 suítes e build universal arm64 + x86_64 assinado e verificado. Após incorporar a `main` atualizada para preparar o PR, 110 testes passaram em 11 suítes, junto dos 20 testes de distribuição de atualizações e dos 4 testes de distribuição do instalador. A falha era a ausência de consulta ao estado de tela cheia e de uso da capacidade de redimensionamento nos fluxos de interação. As regressões cobrem admissão e cancelamento do arraste, encaixe adiado, ajuste e correção de pares e cliques sobre um divisor antigo. Os novos cenários com aplicativos reais ainda não foram executados; a preparação do PR não instala nem inicia um build de teste.
