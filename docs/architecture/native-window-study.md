# MacSnap: estudo de arquitetura nativa e plano de verificação

Base analisada: `314bc1a` (main). Versão preservada: **1.0.7 / build 7**.
Este trabalho implementa os quatro tópicos do relatório anterior. Não inclui tag, atualização de versão, alteração do instalador nem redesign do menu. A publicação da branch e do PR foi autorizada pelo usuário após a preparação do build local; resultados específicos do roteiro manual ainda não foram registrados.

## Resultado do diagnóstico

A linha de base executou **33 testes**, todos aprovados. Esse resultado protege o comportamento já descrito pelos testes, mas não prova a ordem das escritas nativas, identidade das janelas descobertas nem validade do trabalho agendado. Há testes antigos que verificam callbacks atribuídos pelo próprio teste, duplicam regras de exclusão ou aceitam qualquer resultado de uma descoberta real. Eles não substituem os novos testes comportamentais.

O fluxo atual é: evento global → reconhecimento do arraste → escolha de posição → prévia → escrita na janela → registro de pareamento. Outro fluxo é: divisor → proporção da prévia → soltura → escrita ordenada → observação posterior. Estes fluxos devem continuar separados na apresentação, mas cada regra relacionada precisa ter um dono.

## Alternativas comparadas

| Alternativa | Vantagem | Custo ou risco | Decisão |
|---|---|---|---|
| Extrair apenas geometria e helpers puros | Mudança pequena; testes rápidos de matemática | Não alcança recusa de tamanho, identidade, fechamento, ordem ou trabalho atrasado; o chamador continua coordenando tudo | Usar cálculos puros internamente, sem tratar isso como solução completa |
| Modules específicos com adapters nativos e simulados | A interface do comportamento vira a superfície de teste; locality para mudanças; leverage entre produção e testes | Exige definir identidade, falhas e ciclo de vida com cuidado; adapters simulados não provam a resposta do macOS | Escolha recomendada para os quatro tópicos |
| Catálogo global de janelas ou motor genérico de eventos | Flexibilidade para extensões futuras | Cache desatualizado, sincronização de estados, mais configuração e conceitos sem uso demonstrado | Não adotar; complexidade não justificada pelos chamadores atuais |

**Depth** significa esconder decisões úteis na interface, não aumentar o número de linhas. A implementation pode continuar dividida em funções e tipos privados. Uma **seam** só merece existir quando há dois adapters concretamente úteis: operações/observações nativas e comportamento controlado nos testes. Não precisamos de um adapter para multiplicar largura por uma proporção.

## 1. Ciclo de redimensionamento pareado

### Evidência e exemplo

`PairedResizeManager.setupDividerCallbacks` mistura apresentação, aplicação e uma observação agendada que consulta novamente `state.pair`. `PairedSplit` decide ordem e `WindowElement` repete escritas. Se A+B for substituído por C+D antes da observação, a ação antiga não pode atingir o novo par. Em uma tela de 1920 pontos, um alvo de 640 para A pode resultar em 900 por limitação do aplicativo; a segunda janela precisa ser ajustada ao resultado observado, quando isso for possível.

### Mudança e trade-offs

Um module de ciclo de redimensionamento, isolado no main actor, mantém a identidade do par original e o trabalho cancelável. Movimento altera somente prévia; soltura aplica a ordem de redução antes da expansão; ajuste posterior observa e verifica o resultado. Substituir ou limpar o par invalida a operação antiga. Um scheduler controlável evita testes baseados em esperar 60 ms de relógio real.

O ganho é locality para ordem e validade, e leverage para cenários reais de falha. O custo é representar explicitamente cancelamento e falha parcial: duas janelas externas não oferecem uma transação atômica. Se ambas impõem mínimos cuja soma excede a tela, não podemos prometer ausência de sobreposição. Não se deve resolver isso fingindo que a escrita foi aceita.

Na implementação, `PairedResizeSession` é dona de `begin → update → finish → settle`. O `PairedResizeManager` mantém um estado por display e cancela a sessão ao substituir o par. Se um monitor for removido ou sua área útil mudar, esse estado é descartado antes de tentar redescobrir janelas. Uma mudança na altura da tela primária também invalida os estados: a conversão entre AX e Cocoa depende dessa referência mesmo para uma tela secundária que não mudou de tamanho.

## 2. Intenção de encaixe compartilhada

### Evidência e exemplo

A prévia e `SnapEngine` repetem a escolha entre cartão exato e encaixe rente ao vizinho; `registerSnap` redescobre o parceiro sem receber a origem da intenção. Em 1920 pontos, metade direita exata é x=960/largura=960. Com vizinho ocupando 1100, encaixe adaptável é x=1100/largura=820. As respostas diferem porque o pedido difere.

### Mudança e trade-offs

Concentrar a resolução em um module de encaixe que atende prévia e aplicação. Reavaliar observações na aplicação é necessário: o vizinho pode ter fechado. Consistência de regra não exige congelar uma observação antiga. O registro usa a geometria observada e não redimensiona vizinhos apenas para fabricar um par binário; uma coluna central continua não sendo metade de um par que ocupa a tela inteira.

O ganho é locality da política e leverage entre barra, borda e menu. O custo é tornar explícita a precedência: preservar o cartão exato pode ser incompatível com evitar sobreposição se o vizinho não mudar. A refatoração preserva a prioridade de tamanho exato para o cartão; não inventa uma nova regra de mover a outra janela.

`SnapTargetResolver` concentra essa escolha; `SnapEngine` usa a mesma política na prévia e na aplicação. O motor também é dono do trabalho atrasado após uma soltura. Por exemplo, se uma soltura agendar Left e o usuário acionar Right antes da execução, Right cancela Left. Um identificador da operação impede que um callback antigo volte a agir mesmo se for entregue após o cancelamento.

## 3. Descoberta e operações de janela

### Evidência e exemplo

O pareamento enumera diretamente WindowServer e acessibilidade apesar da dependência já injetada. Identidade aparece como elemento AX, PID, número de janela e proximidade de retângulos. PID identifica o aplicativo, não cada janela: A e B podem compartilhar PID, e uma terceira C pode cobrir o divisor.

### Mudança e trade-offs

Concentrar leitura nativa e reconciliação num module de descoberta. Uma observação registra geometria e ordem; o chamador não precisa interpretar dicionários nativos. Preservar a representação AX existente evita troca desnecessária de todo o modelo. Um adapter de operações permite programar falha, tamanho mínimo e desaparecimento sem operar janelas reais.

A seam ganha depth ao esconder a tradução entre representações. O custo é que AX e WindowServer não oferecem uma fotografia atômica conjunta: associações ambíguas devem ser recusadas em vez de adivinhar identidade. Não acrescentar cache global. Evitar chamadas privadas do sistema para obter números de janela.

## 4. Reconhecimento de gesto

### Evidência e exemplo

`GlobalEventMonitor` mantém reconhecimento e seleção juntos, com limpezas diferentes ao parar, soltar ou suprimir pelo divisor. Pausar esconde a apresentação mas não encerra explicitamente o reconhecimento. Um gesto iniciado no conteúdo precisa continuar rejeitado ao passar pelo cabeçalho; a soltura permite nova tentativa.

### Mudança e trade-offs

Um module em memória passa a manter candidata, rejeição persistente e arraste aceito. A resolução nativa é feita de forma preguiçosa na admissão, e não repetida a cada movimento. O monitor mantém apenas apresentação e seleção da posição. Encerrar, pausar e suprimir invalidam a tentativa em andamento.

Preservamos o início observado no primeiro evento de arraste. Passar a capturar mouseDown mudaria a heurística de produto e exigiria outra validação; não é necessário para obter locality e testes de sequência nesta mudança. O custo é evitar estado duplicado entre o reconhecedor e o monitor. O monitor agora captura o ponto do evento antes do salto ao main actor; eventos de um registro encerrado são recusados por geração. Perda de tela cancela a tentativa e impede uma aplicação atrasada em um display removido.

## Boas práticas de Swift e AppKit

- Estado mutável de interação deve ter isolamento explícito. `@unchecked Sendable` desliga uma verificação; não produz segurança. Pares mutáveis não devem declarar esse contrato sem necessidade. [Sendable, Swift](https://docs.swift.org/latest/documentation/swift/sendable/).
- O main actor serializa alterações de UI, mas não garante que um objeto continue sendo o mesmo quando uma ação agendada roda mais tarde. Identidade e cancelamento continuam necessários. [Concurrency, Swift](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html).
- Escritas AX têm resultados de erro distintos; tamanho solicitado não equivale a tamanho observado. Validar valores recebidos antes de convertê-los e não tratar qualquer erro como sucesso. [AXError, Apple](https://developer.apple.com/documentation/applicationservices/axerror/cannotcomplete).
- Copiar dados de evento antes de agendar trabalho; não transportar referências de evento emprestadas sem cuidar da vida útil. Rever a propriedade do evento retornado pelo callback. [CGEventTapCallBack, Apple](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback).
- Observadores devem ter um dono e remoção explícita no término. Usar o notificationCenter do workspace para eventos de ativação. [NSWorkspace, Apple](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification).
- Evitar singleton consultado por dentro de uma dependência já injetada: isso impede que um teste controle a operação inteira.

### Compatibilidade dos argumentos padrão com Swift 6.1

O primeiro CI no Xcode 16.4 falhou antes dos testes: o compilador Swift 6.1.2 encerrava durante a geração dos inicializadores estáticos de `PairedResizeManager` e `SnapEngine`. Um exemplo mínimo reproduziu a combinação de argumentos padrão isolados no MainActor, um `nil` intermediário e outro argumento padrão. A falha corresponde ao [problema corrigido no compilador Swift](https://github.com/swiftlang/swift/pull/81370).

A correção mantém o `init` no MainActor e resolve ali o scheduler e a closure de estado quando esses argumentos são omitidos. Por exemplo, `scheduler: nil` vira `MainActorScheduler.shared` dentro do inicializador; um scheduler fornecido pelo teste continua sendo usado. Isso evita duplicar todos os argumentos nas propriedades `shared` e protege também outros chamadores do inicializador padrão. O custo é aceitar `nil` como escolha explícita da dependência padrão nesses dois parâmetros; o comportamento padrão continua o mesmo.

O projeto completo passou os mesmos **81 testes** com o toolchain oficial Swift.org 6.1.2 e SDK 15.4, usando um diretório de build separado. Esse toolchain reproduz a família da falha, mas seu identificador difere do compilador Apple incluído no Xcode 16.4; o CI continua sendo a verificação dessa combinação exata.

## Verificação e limites

1. Rodar a linha de base antes das mudanças; rodar testes focados de cada module e a suíte integrada após a integração.
2. Verificar ordem de escritas, ausência de escritas durante movimento, falha parcial, mínimo de tamanho, cancelamento, troca de par e isolamento de telas.
3. Verificar a mesma intenção na prévia e aplicação, observação atualizada, rejeição de auto-pareamento e três colunas.
4. Verificar mesma aplicação com janelas distintas, janela sobre o divisor, ausência e associação ambígua.
5. Verificar gestos rejeitados, limiar de 14 pontos, soltura/reinício, parada, pausa e supressão pelo divisor.
6. Construir release universal e confirmar versão/plist/assinatura preservados. Não modificar `Resources/Info.plist`, fallback da versão, CHANGELOG ou workflows de publicação.
7. Preparar um `.app` separado e um roteiro de teste manual. Simulação não substitui o teste com aplicativos reais, monitores e permissões da máquina do usuário.
8. O roteiro manual foi preparado antes da publicação. A autorização posterior para subir a branch e abrir PR não é tratada como prova de que cada cenário manual foi executado. Testes verdes não significam ausência de todo defeito possível; cada conclusão deve identificar seu alcance.

### Resultado automático desta implementação

Em 29/10/2026, `./scripts/build-development-app.sh` concluiu **81 testes em 8 suítes**, sem falhas, e gerou um executável universal **arm64 + x86_64**. `codesign --verify --strict --deep` aprovou o pacote de teste; os dois slices mantêm o mínimo de macOS 13.0. O SDK local emitiu um aviso de depreciação de x86_64, sem impedir a geração das duas arquiteturas.

O plist do build é idêntico ao de origem: **1.0.7 / build 7**. A comparação com os hashes anteriores confirmou que a geração do build separado não alterou o executável nem o plist instalados em `/Applications/MacSnap.app`. O build separado fica em `.build/manual-test/MacSnap.app`. Os testes de menu ainda emitem um aviso de layout do AppKit já observado na linha de base; a suíte conclui sem falhas.

## Revisões e regressões encontradas na integração

As revisões cruzadas dos subagentes verificaram a ligação entre o adapter nativo, o module de descoberta, a intenção de encaixe, o reconhecedor e o ciclo pareado. Foram acrescentadas regressões para: restrição de tamanho no eixo perpendicular; arredondamento de uma divisão de 15% numa tela de largura ímpar; janela AX que não está visível; observação indisponível versus cena vazia; perda de monitor antes e depois da soltura; lógica de recuperação do monitor em repouso; e comando explícito que substitui um drop agendado. A revisão final também isolou a configuração persistida das fixtures e acrescentou verificação direta dos alvos adaptativos esquerdo, superior, inferior e central.

Seis testes antigos que apenas copiavam regras, invocavam callbacks atribuídos pelo próprio teste, aceitavam nil ou contagens tautológicas foram substituídos por testes dos módulos e fluxos reais. Os testes de geometria úteis e as garantias anteriores continuam cobertos. As falhas de fixture/macro encontradas na integração foram corrigidas sem enfraquecer as verificações de comportamento.

A fronteira automática/manual continua explícita: os testes de shell acionam o mesmo handler de eventos com dados controlados; não alegam reproduzir todas as decisões do WindowServer ou a entrega real de CGEventTap.

## Estado da execução

- [x] Linha de base: 33 testes aprovados.
- [x] Comparar alternativas e registrar trade-offs com fontes primárias.
- [x] Integrar os quatro módulos e seus adapters.
- [x] Executar e revisar testes comportamentais: 81 testes aprovados; build universal validado.
- [x] Preparar build local assinado e roteiro manual, com versão inalterada.
- [x] Receber autorização do usuário para publicar a branch e abrir PR para main.
- [ ] Registrar os resultados específicos do teste manual; não presumir cobertura nativa completa.
