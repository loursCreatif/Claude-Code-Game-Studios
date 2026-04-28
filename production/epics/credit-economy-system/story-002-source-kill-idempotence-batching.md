# Story 002: Source KILL — handler, idempotence, multi-kill batching

> **Epic**: Credit Economy System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic + Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/credit-economy-system.md`
**Requirement**: R-CRD-3 (sources MVP : KILL exhaustif), R-CRD-5 (connexion event-driven groupe `"enemies"` à `level_active`), R-CRD-6 (idempotence via `_credited_this_run` instance_id), R-CRD-7 (multi-kill batching `BATCH_MULTI_KILL_EMIT = true`), R-CRD-8 (émission SYNC).
*(TR-crd-* IDs non encore présents dans `tr-registry.yaml` — référence directe rules R-CRD-N GDD r3.)*

**ADR Governing Implementation**:
- ADR-0001: Physics Rate 60Hz — émission SYNC depuis `_physics_process` (autorité unique gameplay).
- ADR-0006: Combat Tick Model — `MAX_KILLS_PER_SWING = 3` enforcement upstream Combat ; contrat signal `enemy_killed` propagé via Enemy `die()`.

**ADR Decision Summary**: Le batching multi-kill MVP (`BATCH_MULTI_KILL_EMIT = true`, pillar-driven creative-director r2 B-1) accumule jusqu'à 3 incréments séquentiels dans le même tick `_physics_process` puis émet 1 unique `credits_changed(N+3, +3, KILL)` en fin de chaîne. Le set `_credited_this_run` indexé par `instance_id` filtre les ré-émissions défensivement (Enemy garantit déjà l'idempotence côté `die()`).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `get_tree().get_nodes_in_group("enemies")` standard Godot ; `enemy.get_instance_id()` retourne `int` 64-bit unique. Aucun API post-cutoff. `Dictionary[int, bool]` typage statique Godot 4.6 supporté.

**Control Manifest Rules (Feature layer)**:
- Required: connexion `enemy_killed.connect(_on_enemy_killed)` au handler `_on_level_active()`, indépendamment de `_is_hydrated` (B-7 découplage strict — la connexion s'établit, le guard `_is_hydrated` rejette uniquement les *signaux reçus* avant hydration).
- Forbidden: connexion en `_ready()` (race timing avec Level System) ; émission `credits_changed` depuis le handler `_on_enemy_killed` directement quand `BATCH_MULTI_KILL_EMIT == true` — émettre uniquement après le flush batch en fin de tick.
- Guardrail: zéro alloc heap dans `_on_enemy_killed` hot path (60+ Hz potentiel multi-kill) — réutiliser variables membres pour le batch counter.

---

## Acceptance Criteria

*From GDD §Acceptance Criteria, scoped à cette story (source KILL — handler, idempotence, multi-kill batching, edge cases edge spawn) :*

- [ ] AC-CRD-07 [Logic] — `enemy_killed(enemy, position)` → `total_credits += 1` ET `credits_changed(N+1, +1, KILL)` émis dans le même physics frame.
- [ ] AC-CRD-08 [Logic] (r2 B-1) — 3 `enemy_killed` séquentiels dans le même tick + `BATCH_MULTI_KILL_EMIT == true` → `total_credits += 3`, **exactement 1** `credits_changed(N+3, +3, KILL)` en fin de chaîne.
- [ ] AC-CRD-09 [Logic] — ré-émission `enemy_killed` même `instance_id` → ignoré silencieusement, `total_credits` stable, 0 emit.
- [ ] AC-CRD-11 [Integration] — `MAX_KILLS_PER_SWING == 3` upstream Combat → exactement 3 increments par tick max.
- [ ] AC-CRD-31 [Logic] (r2 B-1) — multi-kill 3 ennemis tick + batching ON → 1 seul payload final `(N+3, +3, KILL)` ; états intermédiaires `N+1`, `N+2` non observables côté listeners.
- [ ] AC-CRD-33 [Integration] — Enemy System réel (ou stub minimal) émet `enemy_killed` ; Credit reçoit, increment, `credits_changed` émis avant fin du même `_physics_process`.
- [ ] AC-CRD-47 [Logic] — `total_credits` valeur très haute (cap théorique 9 999 999) + nouveau gain → pas de crash (Godot int 64-bit, no overflow MVP).
- [ ] AC-CRD-48 [Logic] — 2 ennemis distincts (`instance_id` distincts) même tick → `total_credits += 2` (pas de collision dans le set).
- [ ] AC-CRD-49 [Integration] (r3 NB-CRD-4) — sur premier `level_active` session : (a) `_credited_this_run.size() == 0`, (b) `total_credits` intact, (c) tous nodes groupe `"enemies"` connectés. Sur `level_active` **suivant** (étage 2) : (d) `_credited_this_run` purgé, (e) `total_credits` inchangé.

---

## Implementation Notes

*Derived from ADR-0001 + ADR-0006 Implementation Guidelines + GDD Rules 5/6/7/8 :*

1. **Connexion event-driven** :
   ```gdscript
   func _ready() -> void:
       var level_system := get_node("/root/LevelSystem")
       level_system.level_active.connect(_on_level_active)

   func _on_level_active(_etage_id: int, _player_start: Vector3) -> void:
       # Purge si NOT premier appel session (AC-CRD-49 d/e). Premier appel : set déjà vide.
       _credited_this_run.clear()
       # Connexion indépendante de _is_hydrated (B-7 — voir story 004).
       for enemy in get_tree().get_nodes_in_group("enemies"):
           if not enemy.enemy_killed.is_connected(_on_enemy_killed):
               enemy.enemy_killed.connect(_on_enemy_killed)
   ```
2. **Handler `_on_enemy_killed`** avec batching :
   ```gdscript
   const BATCH_MULTI_KILL_EMIT: bool = true  # MVP r2 B-1
   var _pending_kill_delta: int = 0
   var _has_pending_kill: bool = false

   func _on_enemy_killed(enemy: Node, _position: Vector3) -> void:
       # Guard PAUSED (story 004) + _is_hydrated (story 004) appliqués ici aussi
       # — mais cette story 002 implémente la branche normal-flow PLAYING/hydrated.
       var enemy_id: int = enemy.get_instance_id()
       if _credited_this_run.has(enemy_id):
           return  # idempotence AC-CRD-09 — silent, no log
       _credited_this_run[enemy_id] = true
       _total_credits += 1  # incrément immédiat (cohérence comptable Rule 7)
       if BATCH_MULTI_KILL_EMIT:
           _pending_kill_delta += 1
           _has_pending_kill = true  # flush en fin de _physics_process
       else:
           # Tier 2+ knob : 3 emits séquentiels
           credits_changed.emit(_total_credits, +1, SourceKind.KILL)

   func _physics_process(_delta: float) -> void:
       if _has_pending_kill:
           var delta_to_emit: int = _pending_kill_delta
           _pending_kill_delta = 0
           _has_pending_kill = false
           credits_changed.emit(_total_credits, delta_to_emit, SourceKind.KILL)
   ```
3. **Ordre d'exécution** : signal `enemy_killed` est émis SYNC depuis `Enemy.die()` qui est appelé depuis le `_physics_process` Combat (ADR-0006) ou Enemy. Le handler `_on_enemy_killed` s'exécute donc DANS le tick physics. Le flush batch en fin de `_physics_process` Credit émet `credits_changed` SYNC dans le **même tick** — AC-CRD-07 et AC-CRD-29 satisfaits par construction.
4. **Pourquoi pas un counter local dans `_physics_process`** : le signal `enemy_killed` peut arriver de plusieurs sources Enemy en parallèle pendant le tick ; le handler les agrège dans des variables membres ; le flush final émet 1 seul signal.
5. **`_pending_kill_delta` reset** : OBLIGATOIRE en début de flush — sinon double-comptage frame N+1.
6. **AC-CRD-11 dépendance** : Combat enforcement `MAX_KILLS_PER_SWING = 3` upstream — Credit ne plafonne PAS lui-même. Test de défense : si 4 `enemy_killed` arrivent, le 4ème est filtré seulement si déjà dans `_credited_this_run` (sinon Credit incrémente — c'est un bug Combat, pas Credit).
7. **AC-CRD-49 trigger canonique** : `level_active` est le premier signal Level (Level R-2) — purge `_credited_this_run` à chaque appel. Au premier appel session, set déjà vide → no-op effectif. Au second appel (étage 2) → purge effective.
8. **EC-CRD-15 garde-fou debug** : assertion en debug que tous les nodes `"enemies"` ont leur signal connecté APRÈS `_on_level_active` — `assert(enemy.enemy_killed.get_connections().any(c in c.callable.get_object() == self))` ou équivalent simple.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 001 (skeleton) : enum `SourceKind`, signal `credits_changed`, API `try_spend`.
- Story 003 (Source SECRET) : handler `_on_secret_collected`, formula F-CRD-2.
- Story 004 (Persistence) : guards `_is_hydrated` et `state_changed(PLAYING)` (les ACs 10/36/37/38/51 testent ces guards).
- Story 005 (Run-purge) : handler `_on_request_new_run` (purge via verbe public GSM, distinct du purge `level_active`).
- Story 006 (Performance) : benchmark N=100 multi-kill perf.

---

## QA Test Cases

- **AC-CRD-07** : Given `_total_credits = 5`, mock Enemy, When `enemy.enemy_killed.emit(enemy, Vector3.ZERO)` puis advance 1 tick `_physics_process`, Then `_total_credits == 6`, spy capture 1 appel `(6, +1, KILL)`.
- **AC-CRD-08** : Given 3 mock Enemies (`instance_id` distincts) + `BATCH_MULTI_KILL_EMIT == true`, When 3 emits `enemy_killed` séquentiels même tick puis advance `_physics_process`, Then spy capture **exactement 1** appel `(N+3, +3, KILL)`. Edge : si tick processed 2 fois (advance × 2), 2e tick = 0 emit (pending vide).
- **AC-CRD-09** : Given mock Enemy emits `enemy_killed` 2 fois consécutives (même `instance_id`), When 2 émissions traitées, Then `_total_credits` incrément 1 fois seulement, spy = 1 emit (en fin tick) `(N+1, +1, KILL)`.
- **AC-CRD-11** : Given Combat stub avec garde `MAX_KILLS_PER_SWING = 3`, When 3 emits émis, Then 3 increments. Edge défensif : 4e emit même tick avec `instance_id` distinct → Credit incrémente (Combat est responsable du cap, pas Credit) ; documenté comme bug-Combat-amont si vu en prod.
- **AC-CRD-31** : Given multi-kill 3, When listener spy capture toute la séquence, Then `received_signals.size() == 1` ET `received_signals[0] == (N+3, +3, KILL)`. États intermédiaires `N+1`, `N+2` doivent NE PAS apparaître dans `received_signals`.
- **AC-CRD-33** : Given EnemySystem stub minimal (Node avec signal `enemy_killed`) ajouté au groupe `"enemies"` AVANT `level_active`, When level_active emit puis enemy.die() simulé (emit signal), Then Credit reçoit, increment, `credits_changed` émis avant fin du tick. Mécanisme : test integration avec mock Enemy + spy timing ordered.
- **AC-CRD-47** : Given `_total_credits = 9_999_999`, When 1 `enemy_killed` traité, Then `_total_credits == 10_000_000`, pas de crash. Edge : valeur cap théorique testée ≤ 1B sans assert (Godot int 64-bit).
- **AC-CRD-48** : Given 2 mock Enemies `id_a != id_b`, When 2 emits same tick, Then `_total_credits += 2`, set `_credited_this_run.size() == 2`, spy 1 emit `(N+2, +2, KILL)`.
- **AC-CRD-49** :
  - Premier `level_active` : Given Credit fresh + `_credited_this_run` vide + 3 enemies dans groupe, When `level_active.emit(1, Vector3.ZERO)`, Then `_credited_this_run.size() == 0`, `_total_credits` inchangé (e.g. 0 si pas hydraté), 3 connections établies (assert `enemy.enemy_killed.get_connections().size() >= 1`).
  - Deuxième `level_active` (étage 2) : Given `_credited_this_run` peuplé (e.g. 5 entries), `_total_credits = 12`, When `level_active.emit(2, ...)`, Then `_credited_this_run.size() == 0` (purgé), `_total_credits == 12` (préservé).

---

## Test Evidence

**Story Type**: Logic + Integration
**Required evidence**:
- `tests/unit/credit/credit_economy_kill_source_test.gd` (AC-07, 08, 09, 11, 31, 47, 48) — must exist and pass GUT.
- `tests/integration/credit/credit_economy_kill_integration_test.gd` (AC-33, 49) — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **Story 001** (skeleton — autoload, signal, enum, state vars).
- Unlocks: Story 005 (run-purge a besoin de `_credited_this_run` peuplé pour tester la purge), Story 006 (perf benchmark a besoin du chemin handler complet).
