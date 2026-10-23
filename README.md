# TRT-Tracker

App para iPhone que acompanha protocolos de TRT e outras medicações: protocolos, compostos, vials,
agenda de aplicações, registro do que foi aplicado, projeção de duração dos vials, lembretes locais
e perfis de liberação dos ésteres.

Sem login e 100% offline: todos os dados ficam no aparelho (SwiftData), não há servidor, analytics
nem SDKs de terceiros.

> **Aviso.** O TRT-Tracker é uma ferramenta de registro e lembrete. As doses são informadas pelo
> usuário e o app não sugere nem ajusta doses. Os gráficos de liberação são estimativas teóricas
> e normalizadas, e não substituem orientação médica nem exames laboratoriais.

## Requisitos

| | |
|---|---|
| Aparelho | iPhone com iOS 17 ou superior (sem layout para iPad) |
| Desenvolvimento | Xcode 16 ou superior (o projeto usa grupos sincronizados com pastas) |
| Linguagem | Swift 5, SwiftUI, SwiftData, Swift Charts, UserNotifications |
| Dependências externas | nenhuma |

## Como rodar

1. Abra `TRTTracker.xcodeproj` no Xcode. O pacote local `TRTCore` é resolvido automaticamente e
   aparece em **Package Dependencies**.
2. **Simulador:** escolha um iPhone como destino e rode (⌘R). Se não houver simulador instalado,
   baixe o runtime do iOS em **Xcode ▸ Settings ▸ Components**.
3. **iPhone:** em **TRTTracker ▸ Signing & Capabilities**, escolha seu **Team** (um Apple ID
   gratuito serve) e, se preciso, troque o **Bundle Identifier** (`com.trttracker.TRTTracker`).
   No aparelho, ative **Ajustes ▸ Privacidade e Segurança ▸ Modo de Desenvolvedor**.

Se o Xcode reclamar do pacote (`Missing package product 'TRTCore'`), use
**File ▸ Packages ▸ Reset Package Caches**. Não abra `Packages/TRTCore/Package.swift` em outra
janela enquanto o app estiver aberto.

## Testes

Toda a lógica de cálculo fica no pacote `TRTCore` e é testada no macOS, sem simulador:

```bash
swift test --package-path Packages/TRTCore
```

Se o terminal estiver apontando para as Command Line Tools em vez do Xcode, prefixe com
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` ou rode
`sudo xcode-select -s /Applications/Xcode.app`.

Os testes cobrem:

- os exemplos da especificação (vial que "dura até qui, 10 dez" e "2 vials · 24 aplicações · sobra 8,0 ml");
- agenda (todos os dias, dia sim/dia não com recontagem, 2x e 3x por semana), situação do protocolo
  e das aplicações, volumes, divisão de dose entre vials, projeções e vials a comprar;
- leitura, validação e filtro do catálogo de compostos;
- os 7 invariantes analíticos do modelo de cinética (meia-vida, t_90, normalização, t_max,
  AUC independente de k_a, limite flip-flop e monotonicidade), métricas, Monte Carlo e CSV.

### Integração contínua

`.github/workflows/ci.yml` roda em todo push para `main`, em pull requests e manualmente:

| Job | O que faz |
|---|---|
| Testes do TRTCore | `swift test` no macOS |
| Build do app | `xcodebuild build` para o simulador do iOS, sem assinatura |

## Estrutura

```
TRTTracker.xcodeproj        projeto e scheme compartilhado
Config/Info.plist           chaves que o Xcode não gera (tarefa em segundo plano, tela de abertura)
TRTTracker/
  App/                      entrada, delegate de notificações, estado global, abas
  Model/                    SwiftData (SchemaV1, SchemaV2 + migração) e regras derivadas
  Services/                 persistência, registro de doses, vials, compostos, notificações, bloqueio
  Features/                 telas: Hoje, Protocolos, Compostos, Vials, Histórico, Calendário,
                            Níveis (cinética), Ajustes, Onboarding
  UI/                       tema, componentes e gráficos
  Resources/                Asset Catalog (tokens de cor), String Catalog, Privacy Manifest
Packages/TRTCore/           lógica pura, sem UI e sem I/O de app
  Sources/TRTCore/
    Resources/compound-catalog.json   catálogo de compostos
```

## Arquitetura

- **Dados locais (SwiftData).** Volumes são inteiros em microlitros, massas em microgramas e
  concentrações em µg/ml, para evitar erro de ponto flutuante. O nível de um vial é derivado
  (volume no cadastro − aplicações ± ajustes), então editar ou excluir um registro recalcula tudo.
- **Aplicações previstas não são gravadas:** são derivadas da agenda. Só registros, pulos e
  ajustes são persistidos.
- **Migração versionada.** `SchemaV1` está congelado; `SchemaV2` é o atual, com migração leve
  em `TRTMigrationPlan`. Mudanças de modelo entram como uma nova versão e um novo estágio.
- **Proteção de dados** "até a primeira autenticação", para permitir reagendar lembretes em segundo plano.
- **Lembretes** em janela móvel de até 60 notificações (o iOS aceita 64 pendentes), reagendados ao
  abrir o app, ao voltar ao primeiro plano, após qualquer alteração e em `BGAppRefreshTask`.
  Horário local do aparelho, inclusive após troca de fuso.
- **Interface** só no tema escuro, com cores como tokens no Asset Catalog, textos em pt-BR no String
  Catalog, suporte a Dynamic Type, VoiceOver e "Reduzir movimento".

## Catálogo de compostos

`Packages/TRTCore/Sources/TRTCore/Resources/compound-catalog.json` (chaves em pt-BR) alimenta o
cadastro de compostos. Cada variante tem `ester`, `via`, `forma`/`veiculo`, `meiaVidaHoras`,
`doseAtivaPercentual` e, quando conhecida, `origemMeiaVida` (`medido` ou `extrapolado`).

Ao carregar, variantes com meia-vida ≤ 0, `doseAtivaPercentual` fora de (0, 100] ou duplicadas
são descartadas; divergência entre `meiaVidaDias × 24` e `meiaVidaHoras` gera só aviso.
Compostos fora da lista podem ser cadastrados como "Outro", sem perfil de liberação.

## Modelo de cinética

Implementa a spec de liberação de ésteres em veículo oleoso (`ReleaseKinetics`,
`ReleaseMetrics`, `RegimenProfile` no `TRTCore`):

- só ésteres **intramusculares** (orais e suspensões aquosas ficam fora);
- a meia-vida tabelada é tratada como de **absorção** (flip-flop): `k_a = ln 2 / t½`;
- saída primária: liberação cumulativa `F_lib(t) = 1 − e^(−k_a·t)`;
- saída secundária: Bateman normalizada (`C / C_max`), com `k_e` varrido em t½ de 1; 4,3; 12 e 24 h
  e exibido como faixa;
- métricas: t_90, t_99, C_max relativo ao propionato de testosterona, t_max (sempre com o `k_e`
  assumido) e a incerteza do C_max absoluto por Monte Carlo (10⁴ amostras);
- nenhuma concentração absoluta: V_d e F se cancelam na normalização.

No app: **Ajustes ▸ Cinética dos ésteres** (liberação, t_90, sensibilidade, métricas e exportação
de `metricas.csv`, `fig_liberacao` e `fig_sensibilidade` em PNG/PDF) e o **perfil normalizado**
do protocolo, que soma as doses da agenda em múltiplos do pico de uma dose.

## Pendências e decisões em aberto

- **P2 fora do app:** duplicar protocolo, exportar/importar backup, rodízio de local de aplicação,
  margem de perda.
- **Divergências da especificação original**, a pedido: exclusão de vial com aplicações
  (com "Arquivar" como primeira opção) e os gráficos de cinética (antes fora do MVP).
- **Durateston:** `meiaVidaHoras` é 360, mas a `observacao` diz que o valor corresponde ao
  componente propionato (19,2 h). Confirmar qual está certo.
- **Monte Carlo:** com t½ ×/÷2 para valores extrapolados, a razão P95/P5 do C_max fica perto de
  7×. A spec não fixa essa largura (`UncertaintyParameters`).
- **Decisões assumidas da especificação:** concentração em mg/ml, dose em mg, agenda opcional
  por composto, 7 dias até "Não registrada", vários protocolos ativos, iOS 17 e só iPhone.
