# Epic: Credit Economy System

> **Layer**: Feature
> **GDD**: design/gdd/credit-economy-system.md (APPROVED r3 — 2026-04-28)
> **Architecture Module**: `CreditEconomy` (autoload, Foundation/Persistence-aval)
> **Status**: In Progress (7/8 Complete — story-008 Ready/unblocked, HUD playtest pending)
> **Stories**: 8 stories — 7 Complete + 1 Ready (story-008 visual/feel HUD frame-perfect, unblocked 2026-05-04)
> **Engine Risk**: LOW (architecture.md row 105 — pas d'ADR HIGH-risk gouvernant Credit)

## Overview

Cet epic implémente Credit Economy : l'autoload qui maintient `total_credits`,
unique compteur de monnaie permanente du joueur. Il observe `enemy_killed` (Enemy
System) pour créditer +1 par grunt, observe `secret_collected` (Secret System) pour
créditer +5/+10/+15 selon tier, expose `try_spend(amount: int) -> bool` SYNC atomique
au Shop System, et émet `credits_changed(total, delta, source)` SYNC dans le même
`_physics_process` tick que la source pour que le HUD voie le compteur monter sans
frame delay (Pillar 1 FLOW + Pillar 2 LA PROGRESSION SE VOIT). La persistance est
gérée via Save/Load (boot hydrate sur `state_changed(PLAYING)` first, save sur
`state_changed(MENU)`). Le système est mécaniquement stateless (pas de reset à la
mort, pas de decay, pas de tax) — la seule perte autorisée transite par `try_spend`.
**49 ACs total (48 BLOCKING + 1 ADVISORY)** : 42 Logic/Integration/Perf BLOCKING +
6 Lints/Static BLOCKING + 1 Visual/Feel ADVISORY.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0001: Physics Rate 60Hz | `_physics_process` à 60 Hz fixe = autorité unique pour mutation d'état gameplay et émission SYNC du signal `credits_changed` (Rule 8). | LOW |
| ADR-0006: Combat Tick Model | `MAX_KILLS_PER_SWING = 3` enforcement upstream + contrat `enemy_killed` propagé via Enemy `die()` ; cap utilisé par batching MVP `BATCH_MULTI_KILL_EMIT = true` (Rule 7). | MEDIUM |
| ADR-0007: Game State Manager | Verbe public `request_new_run()` (D-10) + signal `state_changed(new_state)` consommés pour purge `_credited_this_run` (Rule 6/EC-CRD-16), boot hydrate (Rule 11), quit-to-menu save (Rule 12), guard PAUSED (Rule 10). | LOW |
| ADR-0010: Save/Load Serialization Format | API `SaveLoad.load_int(key, default) -> int` + `SaveLoad.save_int(key, value) -> void` à signature exacte attendue par R-CRD-11/R-CRD-12 ; ordre autoload garanti (D-3) ; default sur corrompu couvert par EC-CRD-8 + R-SAV-6/12. **Bloquant Sprint 1 implémentation** (ADR-0010 §Blocks). | MEDIUM |

## GDD Requirements

> ⚠️ **TR registry non rafraîchi pour Credit Economy** — `tr-registry.yaml` ne contient
> aucune entrée `TR-crd-*`. `/architecture-review` n'a pas encore été exécuté pour
> credit-economy-system. Les requirements ci-dessous sont mappés depuis les Detailed
> Rules R-CRD-N de la GDD r3 et leur couverture ADR est inférée par lecture directe
> des ADRs gouvernants. Le registry sera rafraîchi à la prochaine `/architecture-review`
> et les stories pourront référencer les TR-crd-* dès qu'ils existent.

| GDD Rule | Requirement (résumé) | ADR Coverage |
|----------|----------------------|--------------|
| R-CRD-1 | `total_credits : int >= 0` unique compteur, jamais flottant ni segmenté | ADR-0007 (state model) ✅ |
| R-CRD-2 | Irréversibilité à la mort — RESPAWNING n'écrit rien | ADR-0007 D-10 ✅ |
| R-CRD-3 | Sources MVP exhaustives : KILL + SECRET uniquement | ADR-0006 (signal contract) ✅ |
| R-CRD-4 | Sink unique `try_spend(amount: int) -> bool` SYNC atomique ; no-op `try_spend(0)` ; reject `try_spend(<0)` | ADR-0001 (SYNC physics) ✅ |
| R-CRD-5 | Connexion event-driven groupe `"enemies"` à `level_active` (Level R-2), découplé de `_is_hydrated` (B-7) | ADR-0011 (level_active trigger) ✅ |
| R-CRD-6 | Idempotence kill via `Dictionary[int, bool] _credited_this_run` (instance_id) ; purge `request_new_run()` ou `level_active` suivant ; **PAS** purgé checkpoint intra-étage (B-6) | ADR-0007 D-10 (request_new_run) ✅ |
| R-CRD-7 | Multi-kill batching MVP `BATCH_MULTI_KILL_EMIT = true` — 1 emit `(N+3, +3, KILL)` final par tick (B-1, pillar-driven) | ADR-0001 + ADR-0006 ✅ |
| R-CRD-8 | Émission SYNC `credits_changed(total, delta, source)` dans `_physics_process` (non CONNECT_DEFERRED) | ADR-0001 ✅ |
| R-CRD-9 | Contrat Secret `secret_collected(secret_node: Node, tier: int)` SYNC (LOCKED Secret r1) | ❌ pas d'ADR Secret (GDD-locked) |
| R-CRD-10 | Guard PAUSED — ignorer `enemy_killed` hors `State.PLAYING` | ADR-0007 D-10 ✅ |
| R-CRD-11 | Boot hydration `SaveLoad.load_int("total_credits", 0)` à premier `state_changed(PLAYING)`, guard `_is_hydrated`, default 0 si absent/corrompu | ADR-0010 D-2/D-3 + ADR-0007 ✅ |
| R-CRD-12 | Persist quit `SaveLoad.save_int("total_credits", value)` à `state_changed(MENU)` | ADR-0010 D-2 ✅ |
| R-CRD-13 | Enum `SourceKind { KILL=0, SECRET=1, SPEND_SHOP=2, BOOT_HYDRATE=3 }` — réservés Tier 2+ : BOSS_BONUS=4, ROOM_CLEAR_BONUS=5 | ❌ enum interne (pas d'ADR) |

**Couverture ADR estimée** : 11/13 rules ✅ (R-CRD-9 et R-CRD-13 sont des contrats
GDD-locked, non couverts par ADR — R-CRD-9 est verrouillé bidirectionnel via
Secret r1 R-SEC-08, R-CRD-13 est un enum interne consommé par HUD r1).

## Definition of Done

Cet epic est complet quand :

- Toutes les stories sont implémentées, reviewées, et closed via `/story-done`.
- Toutes les **49 acceptance criteria** de `design/gdd/credit-economy-system.md`
  (48 BLOCKING + 1 ADVISORY) sont vérifiées.
- Toutes les stories Logic / Integration / Perf BLOCKING (42) ont des tests GUT
  passants dans `tests/unit/credit/` ou `tests/integration/credit/`.
- Toutes les stories Lints/Static BLOCKING (6) ont leur test statique passant
  dans `tests/static/credit_economy_lint_test.gd`.
- La story Visual/Feel ADVISORY a une evidence + sign-off dans
  `production/qa/evidence/`.
- Les 7 fixes r2 (B-1 batching, B-2 anti-soft-lock, B-3 délégation HUD, B-4 sanity
  Tier 2+, B-5 Lints/Static dédiés, B-6 checkpoint purge, B-7 race boot) et les 4
  reformulations r3 (NB-CRD-2 cross-tuning, NB-CRD-3 délégation HUD, NB-CRD-4
  triggers canoniques, NB-CRD-5 perf gate `< 1 ms médiane N=100`) sont
  implémentés et vérifiés.
- Le RECOMMENDED non-bloquant éditorial r3 (REC-CRD-r3-1 ambiguïté formulation
  invariant runtime balance-check `floor(0.8 × …)` §Tuning Knobs l.392) est traité
  par story Sprint 1 ou amendement GDD ≤ 5 min.
- ADR-0010 **Accepted** ✅ (gate Sprint 1 levé 2026-04-27).

## Dependencies (epic-level — Sprint ordering)

**Hard upstream (DOIT exister avant que stories Sprint 1 entrent en code)** :

- ADR-0010 Accepted ✅ (2026-04-27)
- Game State Manager APPROVED r1 + ADR-0007 ✅
- Enemy System Designed r1 (signal contract `enemy_killed`) ✅
- Secret System Designed r3 (signal contract `secret_collected`) ✅
- Shop System Designed r2.1 (consumer `try_spend`) ✅
- HUD System Designed r1.1 (consumer `credits_changed`) ✅
- **Save/Load System** Not Started ❌ — autoload `SaveLoad` doit être registered
  dans `project.godot` AVANT `CreditEconomy` (ADR-0010 D-3 ordre autoload). Stories
  Sprint 1 R-CRD-11/12 sont **bloquées sur création de l'autoload SaveLoad**.

**Hard downstream consumers** :

- HUD System (presentation Pillar 2 visible)
- Shop System (sink unique)

## Stories

| # | Story | Type | Status | ADR | ACs |
|---|-------|------|--------|-----|-----|
| 001 | Autoload skeleton + try_spend SYNC | Logic | Ready | ADR-0001 + ADR-0007 | 01,02,03,04,05,06,17,18,19,28,29,35 (12) |
| 002 | Source KILL — handler, idempotence, batching | Logic + Integration | Ready | ADR-0001 + ADR-0006 | 07,08,09,11,31,33,47,48,49 (9) |
| 003 | Source SECRET — formula tier 1/2/3 + validation | Logic | Ready | (GDD-locked) | 12,13,14,15,16,34 (6) |
| 004 | Persistence — boot hydrate + quit save | Integration | **Blocked** (SaveLoadSystem autoload) | ADR-0010 + ADR-0007 | 22,23,24,25,26,27,30,36,37,38,51 (11) |
| 005 | Run-purge GSM + checkpoint defensive | Integration | Ready | ADR-0007 | 10,50 (2) |
| 006 | Performance benchmark N=100 | Performance | Ready | ADR-0001 | 39,40 (2) |
| 007 | Lints/Static — credit_economy_lint_test.gd | Logic (Lints) | Ready | ADR-0001 + ADR-0007 | 20,41,42,43,44,45 (6) |
| 008 | Visual/Feel HUD frame-perfect (ADVISORY) | Visual/Feel | Ready | (consumer HUD) | 46 (1) |

**Total** : 49 ACs (48 BLOCKING + 1 ADVISORY) répartis sur 8 stories. Mapping conforme à `design/gdd/credit-economy-system.md` §Acceptance Criteria r3 + Test Coverage Matrix.

**Story 004 BLOCKED** : nécessite l'autoload `SaveLoadSystem` registered dans `project.godot` AVANT `CreditEconomy` (ADR-0010 D-3 ordre #3) avec API publique `load_int(key, default) -> int` + `save_int(key, value) -> void`. Stories 001/002/003/005/006/007 peuvent commencer immédiatement en parallèle.

## Next Step

Run `/story-readiness production/epics/credit-economy-system/story-001-autoload-skeleton-try-spend.md` puis `/dev-story` pour démarrer l'implémentation. Travailler les stories dans l'ordre de dépendance — chaque story `Depends on:` indique ses prérequis.

**Séquencement recommandé Sprint 1** : 001 → (002, 003, 007 parallèle) → (005, 006 séquentiel post-002) → 004 dès que SaveLoadSystem est registered → 008 dès que HUD epic implémenté.
