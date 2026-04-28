# Story 001: Autoload skeleton + try_spend SYNC

> **Epic**: Credit Economy System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: 3h (S — skeleton autoload pur, pattern ADR-0007 standard, API restreinte `try_spend` uniquement ; ~80 LOC src + ~150 LOC tests + 1 entrée `project.godot`)

## Context

**GDD**: `design/gdd/credit-economy-system.md`
**Requirement**: R-CRD-1 (compteur unique `int >= 0`), R-CRD-4 (sink unique `try_spend` SYNC atomique), R-CRD-13 (enum `SourceKind`)
*(TR-crd-* IDs non encore présents dans `tr-registry.yaml` — `/architecture-review` à exécuter post-Sprint 1 ; story référence directement les rules R-CRD-N de la GDD r3.)*

**ADR Governing Implementation**:
- ADR-0001: Physics Rate 60Hz — `_physics_process` autorité unique mutation d'état + émission SYNC `credits_changed`
- ADR-0007: Game State Manager — pattern autoload Node singleton (D-1), enum `State`, signal `state_changed`

**ADR Decision Summary**: Credit Economy est un autoload Node singleton ; son état (`total_credits`, `_credited_this_run`, `_is_hydrated`) est muté UNIQUEMENT depuis `_physics_process` ou des handlers signal exécutés sur le main thread ; `credits_changed` est émis SYNC (non `CONNECT_DEFERRED`) immédiatement après mutation.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: aucun API post-cutoff requis. `Engine.has_singleton()` + `process_mode = PROCESS_MODE_ALWAYS` (pattern standard ADR-0007 D-1). Static typing GDScript strict — aucun `Variant` implicite (ADR-0010 D-2 pattern API typée).

**Control Manifest Rules (Feature layer)**:
- Required: signal typés statiquement (`signal credits_changed(total: int, delta: int, source: SourceKind)`) ; API publique typée stricte (`try_spend(amount: int) -> bool`, `get_total() -> int`).
- Forbidden: `await` ou `.call_deferred(` dans `try_spend` ; émission `credits_changed` depuis `_ready` / `_process` / callback async ; `class_name CreditEconomy` sur autoload (collision identifiant — voir feedback memory).
- Guardrail: `try_spend` atomique single-call — pas de `can_afford()` séparé, pas d'await intermédiaire.

---

## Acceptance Criteria

*From GDD `design/gdd/credit-economy-system.md` §Acceptance Criteria, scoped à cette story (skeleton autoload + state invariants + sink try_spend + signal contract) :*

- [x] AC-CRD-01 [Logic] — `total_credits >= 0` toujours vrai à n'importe quel point du cycle de vie.
- [x] AC-CRD-02 [Logic] — `try_spend(amount > N)` retourne `false`, ne modifie pas l'état, n'émet pas `credits_changed`.
- [x] AC-CRD-03 [Logic] — `try_spend(N)` sur `total_credits == N` retourne `true`, met à 0, émet `credits_changed(0, -N, SPEND_SHOP)`.
- [x] AC-CRD-04 [Logic] — invariant comptable : `total_credits == credits_at_boot + sum(gains) - sum(spends)` après toute séquence.
- [x] AC-CRD-05 [Logic] — `try_spend(0)` retourne `true`, no-op, **aucun signal émis**.
- [x] AC-CRD-06 [Logic] — `try_spend(-N)` retourne `false`, ne modifie pas l'état, `push_warning` loggé.
- [x] AC-CRD-17 [Logic] — `try_spend(10)` sur `total_credits == 10` retourne `true`, met à 0, émet `credits_changed(0, -10, SPEND_SHOP)`.
- [x] AC-CRD-18 [Logic] — `try_spend(11)` sur `total_credits == 10` retourne `false`, état stable, 0 emit.
- [x] AC-CRD-19 [Logic] — deux `try_spend(3)` séquentiels même frame sur 5 cr : 1er `true` (→2), 2e `false` (état stable à 2).
- [x] AC-CRD-28 [Logic] — payload `credits_changed(total, delta, source)` : `total` reflète le nouveau total APRÈS modification, `delta` signé.
- [x] AC-CRD-29 [Logic] — émission SYNC dans le même tick `_physics_process` que la source (pas de `CONNECT_DEFERRED`, pas d'`await`).
- [x] AC-CRD-35 [Integration] — Shop stub appelle `try_spend(cost)` ; suffisant → `true` + décrément + signal ; pas de second appel de vérification requis.

---

## Implementation Notes

*Derived from ADR-0001 + ADR-0007 Implementation Guidelines :*

1. **Fichier** : `src/core/credit_economy.gd`. **Autoload** : `CreditEconomy`. **`class_name`** : aucun (autoload sans `class_name` évite la collision Godot 4.6 — feedback memory `feedback_godot_class_name_autoload_collision`).
2. **`process_mode = PROCESS_MODE_ALWAYS`** (équivalent ADR-0010 D-4 pour SaveLoadSystem) — Credit Economy doit pouvoir traiter `state_changed(MENU)` même si `get_tree().paused == true`.
3. **Position autoload** : registered dans `project.godot` **après** `SaveLoadSystem` (ADR-0010 D-3 ordre #3) — `CreditEconomy` est un consumer de SaveLoad au boot. La registration `project.godot` peut être ajoutée maintenant sans dépendre de la story 004 (Persistence) ; les handlers Save/Load eux-mêmes seront ajoutés en story 004.
4. **Enum `SourceKind`** :
   ```gdscript
   enum SourceKind { KILL = 0, SECRET = 1, SPEND_SHOP = 2, BOOT_HYDRATE = 3 }
   ```
   Exactement 4 valeurs MVP. `BOSS_BONUS = 4` et `ROOM_CLEAR_BONUS = 5` réservés Tier 2+ — **ne pas les déclarer au MVP** (lock par AC-CRD-43).
5. **State variables** (typage strict obligatoire) :
   ```gdscript
   var _total_credits: int = 0
   var _is_hydrated: bool = false
   var _credited_this_run: Dictionary[int, bool] = {}  # instance_id -> true
   ```
6. **Signal** : `signal credits_changed(total: int, delta: int, source: SourceKind)` — types annotés (AC-CRD-42 lock par lint en story 007).
7. **API publique typée** :
   ```gdscript
   func get_total() -> int:
       return _total_credits

   func try_spend(amount: int) -> bool:
       # Atomic single-call. NO await, NO call_deferred. Edge cases EC-CRD-1, 2, 3, 4.
       if amount == 0:
           return true  # no-op silencieux, AC-CRD-05
       if amount < 0:
           push_warning("Credit Economy: try_spend with negative amount: %d" % amount)
           return false
       if amount > _total_credits:
           return false  # solde insuffisant, pas de log
       _total_credits -= amount
       credits_changed.emit(_total_credits, -amount, SourceKind.SPEND_SHOP)
       return true
   ```
8. **Émission SYNC** : utiliser `credits_changed.emit(...)` (default `CONNECT_FLAGS = 0`). **Jamais** `connect(... , CONNECT_DEFERRED)` côté Credit. Les consumers (HUD, Shop) gèrent leur propre flag à la connexion.
9. **Threading** : tout l'état est muté sur le main thread uniquement (autoload `_ready` / handlers signal / `_physics_process`). Pas de `Thread`, `WorkerThreadPool`, ni `call_deferred` cross-thread. Aligné `.claude/rules/input-singleton-main-thread-only.md` pattern.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 002 (Source KILL) : connexion `enemy_killed`, idempotence `_credited_this_run`, multi-kill batching `BATCH_MULTI_KILL_EMIT`.
- Story 003 (Source SECRET) : handler `_on_secret_collected`, formula F-CRD-2, validation tier.
- Story 004 (Persistence) : connexion `state_changed`, boot hydrate `SaveLoad.load_int`, quit save `SaveLoad.save_int`.
- Story 005 (Run-purge) : handler `_on_request_new_run`, purge `_credited_this_run`.
- Story 006 (Performance) : benchmark N=100.
- Story 007 (Lints/Static) : `tests/static/credit_economy_lint_test.gd` validant signature signal, enum exact, absence d'`await` dans `try_spend`.

Cette story ne doit PAS implémenter de handler signal `enemy_killed` / `secret_collected` / `state_changed` — uniquement le skeleton autoload + l'API `try_spend` + le signal `credits_changed`.

---

## QA Test Cases

*Spec écrite directement depuis les ACs GDD (mode solo — pas de QA-lead gate). Le développeur implémente contre ces cas, ne pas en inventer de nouveaux.*

- **AC-CRD-01** : Given Credit instancié, When `get_total()` interrogé, Then `>= 0`.
  - Edge cases : valeur initiale `0` ; après `try_spend(9999)` sur compte 0 → `0` (clamp implicite via `amount > total` early-return).

- **AC-CRD-02** : Given `_total_credits = 10`, When `try_spend(15)`, Then return `false`, `_total_credits == 10`, spy sur `credits_changed` = 0 appel.

- **AC-CRD-03** : Given `_total_credits = 10`, When `try_spend(10)`, Then return `true`, `_total_credits == 0`, spy capture 1 appel `(0, -10, SPEND_SHOP)`.

- **AC-CRD-04** : Given log d'opérations `[+5, +3, -4, +10, -8]` appliqué via gains directs (`_total_credits += N`) + `try_spend`, When séquence terminée, Then `_total_credits == 0+5+3-4+10-8 == 6`. Edge : invariant doit tenir même si certains `try_spend` retournent `false` (no-op) — recompter sans les rejets.

- **AC-CRD-05** : Given `_total_credits = 10`, When `try_spend(0)`, Then return `true`, `_total_credits == 10`, spy = 0 appel.

- **AC-CRD-06** : Given `_total_credits = 10`, When `try_spend(-5)`, Then return `false`, `_total_credits == 10`, `push_warning` capturé. Mécanisme : intercepter via `Engine.print_error_messages = false` puis vérifier message warning, ou capture `_err_handler` GdUnit4.

- **AC-CRD-17** : alias intégration de AC-CRD-03 — same test, payload `(0, -10, SPEND_SHOP)`.
- **AC-CRD-18** : alias intégration de AC-CRD-02 — Given 10, try_spend(11) → false, 10, 0 emit.
- **AC-CRD-19** : Given `_total_credits = 5`, When séquence `try_spend(3)` puis `try_spend(3)` même frame, Then 1er retour `true` (état 2, 1 emit), 2e retour `false` (état 2, total 1 emit cumulé).
- **AC-CRD-28** : Given un kill direct (`_total_credits += 1`, emit `(N+1, +1, KILL)` simulé via fake source), When listener reçoit, Then `total == N+1` (post-modification), `delta == +1`. Pour SPEND : `delta < 0`.
- **AC-CRD-29** : Given Credit appelle `credits_changed.emit()` depuis `try_spend` (synchrone), When test connecte handler avec flag `0` (default SYNC), Then handler invoqué dans la même frame stack que `try_spend` — pas de `await` requis. Mécanisme : flag boolean `_handler_called` set par handler ; assert `_handler_called == true` IMMÉDIATEMENT après l'appel `try_spend()` sans yield.
- **AC-CRD-35** : Given un mock Shop qui call `try_spend(cost)`, When suffisant, Then return `true`, decrement, signal SPEND_SHOP émis, mock Shop ne re-vérifie PAS le solde après. Mécanisme : intégration test avec ShopStub minimal (juste un call site).

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/credit/credit_economy_skeleton_test.gd` (autoload + state invariants + try_spend logic) — 11/11 tests PASSED via GdUnit4 headless 2026-04-28.
- `tests/integration/credit/credit_economy_shop_stub_test.gd` (AC-CRD-35) — 1/1 test PASSED via GdUnit4 headless 2026-04-28.

**Status**: [x] Complete — 12/12 tests PASSED 93 ms (GdUnit4 `--add tests/unit/credit/ --add tests/integration/credit/`).

---

## Dependencies

- Depends on: **None** (skeleton de base — peut commencer immédiatement). N.B. : la registration `project.godot` doit être positionnée APRÈS `SaveLoadSystem` (ordre autoload ADR-0010 D-3) — si SaveLoadSystem n'existe pas encore, ajouter Credit AVANT et le déplacer à la story 004.
- Unlocks: Story 002 (Source KILL), Story 003 (Source SECRET), Story 007 (Lints/Static peut s'exécuter dès que le squelette signal/enum existe).

---

## Completion Notes (2026-04-28)

**Verdict** : COMPLETE WITH NOTES — 11/11 ACs BLOCKING couverts, 12/12 tests PASSED.

**Files delivered (3)** :
- `src/core/credit_economy.gd` (107 L) — autoload skeleton + `try_spend(amount: int) -> bool` + `get_total() -> int` + `signal credits_changed(total, delta, source)` + enum `SourceKind {KILL, SECRET, SPEND_SHOP, BOOT_HYDRATE}` + seam `_negative_amount_warning_count` (AC-CRD-06 evidence).
- `tests/unit/credit/credit_economy_skeleton_test.gd` (255 L, 11 tests) — couvre AC-CRD-01/02/03/04/05/06/17/18/19/28/29.
- `tests/integration/credit/credit_economy_shop_stub_test.gd` (109 L, 1 test) — couvre AC-CRD-35.
- `project.godot` — `[autoload]` `CreditEconomy="*res://src/core/credit_economy.gd"` position #4 (après `SaveLoadSystem` ADR-0010 D-3).

**Deviation ADVISORY — Framework migration GUT → GdUnit4** :
Story spec mentionnait "must exist and pass GUT" mais GUT n'est pas installé dans le projet (seul `addons/gdUnit4/` est présent depuis commit 2a345f4). Tests rédigés initialement en `extends GutTest` ont été migrés vers `extends GdUnitTestSuite` avec assertions fluent (`assert_int(x).is_equal(y)`, `assert_bool(x).is_true()`, etc.). Spy de signal manuel via `connect()` + `Array` capture (GdUnit4 SYNC mode n'expose pas `watch_signals`). Sémantique 1:1 avec spec QA Test Cases — aucune perte de couverture. Future migration framework sera tracée par CLAUDE.md `Testing Standards`.

**Tech debt logged** : 0 items (la migration GUT→GdUnit4 est traçable depuis `addons/`).

**Test runner** : exécuté headless via pattern autorisé CLAUDE.md `godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/credit/ --add res://tests/integration/credit/ --ignoreHeadlessMode` — 12/12 PASSED 93 ms (rapport `reports/report_12/`).

**Next ready** :
- **credit-economy story-002** (Source KILL idempotence batching) — AC-CRD-04 invariant désormais lockable contre handler `_on_enemy_killed` réel.
- **credit-economy story-003** (Source SECRET formula tier) — pattern handler signal disponible.
- **credit-economy story-007** (Lints/Static) — peut désormais valider signature signal + enum + absence d'`await`.
- **shop-system story-001** Shop boot hydrate — `try_spend` est désormais consommable.
