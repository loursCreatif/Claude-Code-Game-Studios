# Story 003: Source SECRET — formula tier 1/2/3 + validation

> **Epic**: Credit Economy System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/credit-economy-system.md`
**Requirement**: R-CRD-9 (contrat signal `secret_collected(secret_node: Node, tier: int)` SYNC LOCKED Secret r1), F-CRD-2 (formule `credits = BASE_SECRET_CREDIT × secret.tier`, BASE = 5, tier ∈ {1,2,3}), EC-CRD-9 (tier invalide → ignore + push_warning).
*(TR-crd-* IDs non encore présents dans `tr-registry.yaml` — référence directe rules/formula GDD r3.)*

**ADR Governing Implementation**:
- Aucun ADR direct — le contrat `secret_collected` est GDD-locked (Secret System r1 R-SEC-08, OQ-CRD-1 RESOLVED). Émission SYNC alignée ADR-0001 (autorité physics tick), même pattern que story 002 KILL.

**ADR Decision Summary**: Credit Economy est consumer pur du signal `secret_collected` ; il ne décide ni quand ni comment un secret est collecté — Secret System émet, Credit crédite `BASE_SECRET_CREDIT × tier` et émet `credits_changed(N+credits, +credits, SECRET)` SYNC. Tier ∉ {1,2,3} → comportement défensif silent ignore + push_warning.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: aucun API post-cutoff. Connexion à `SecretSystem` ou groupe `"secrets"` via pattern Godot standard. Pas de batching multi-secret (1 secret = 1 emit, contrairement aux multi-kill — un joueur ne collecte pas physiquement 3 secrets dans le même tick).

**Control Manifest Rules (Feature layer)**:
- Required: validation explicite `tier in [1, 2, 3]` AVANT crédit ; `push_warning` formaté avec `tier` value pour traçabilité.
- Forbidden: utiliser `tier` directement comme multiplier sans validation (allouerait un crédit pour `tier == -1` ou `tier == 99`) ; appeler `try_spend(-credits)` pour "annuler" un crédit secret raté (anti-pattern, EC-CRD-9 demande ignore silencieux).
- Guardrail: pas de batching secret MVP — 1 emit immédiat par signal traité (granularité naturelle, pas de saturation perceptuelle).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria, scoped à cette story (source SECRET — formula F-CRD-2, validation tier, pillar 4 ratio) :*

- [x] AC-CRD-12 [Logic] — secret tier 1 collecté → `delta == +5`, `source == SECRET`, payload `(N+5, +5, SECRET)`.
- [x] AC-CRD-13 [Logic] — secret tier 2 → `delta == +10`, payload `(N+10, +10, SECRET)`.
- [x] AC-CRD-14 [Logic] — secret tier 3 → `delta == +15`, payload `(N+15, +15, SECRET)`.
- [x] AC-CRD-15 [Logic] — tier invalide (`0`, `99`, `-1`) → aucun crédit, `total_credits` stable, `push_warning` loggé, 0 emit.
- [x] AC-CRD-16 [Logic] — Pillar 4 ratio plancher : `BASE_SECRET_CREDIT × 1 >= 5 × kill_credit["grunt"]` (5 ≥ 5 × 1).
- [x] AC-CRD-34 [Integration] — Secret System stub émet `secret_collected(mock_node, tier=2)` → `total_credits += 10`, `credits_changed(N+10, +10, SECRET)` émis.

---

## Implementation Notes

*Derived from GDD F-CRD-2 + Rule 9 + EC-CRD-9 :*

1. **Constante exposée** : `const BASE_SECRET_CREDIT: int = 5` au top du fichier `credit_economy.gd` (Tuning Knob, lu depuis `data/balance/credit_config.tres` Tier 2+ — MVP : constante hardcoded suffisant). Constante doit être accessible pour AC-CRD-16 lint.
2. **Constante kill** : `const KILL_CREDIT_GRUNT: int = 1` (utilisé par story 002 — peut déjà exister, sinon ajouter).
3. **Connexion** : Credit s'abonne au signal Secret System dans `_ready()` :
   ```gdscript
   func _ready() -> void:
       var secret_system := get_node("/root/SecretSystem")  # ou pattern groupe si SecretSystem n'est pas autoload
       secret_system.secret_collected.connect(_on_secret_collected)
       # ... autres connections (story 002 level_active, story 004 state_changed)
   ```
   *(Si SecretSystem n'existe pas encore comme autoload au moment de l'implémentation, utiliser un stub fixture dans le test — la connexion réelle se fera quand Secret epic sera implémenté.)*
4. **Handler `_on_secret_collected`** :
   ```gdscript
   func _on_secret_collected(_secret_node: Node, tier: int) -> void:
       # Guards _is_hydrated + PAUSED appliqués (story 004 implémente le détail).
       # Cette story implémente la branche normale PLAYING/hydrated.
       if tier < 1 or tier > 3:
           push_warning("Credit Economy: invalid secret tier: %d" % tier)
           return  # EC-CRD-9 — ignore silencieusement, no crédit
       var credits: int = BASE_SECRET_CREDIT * tier
       _total_credits += credits
       credits_changed.emit(_total_credits, credits, SourceKind.SECRET)
   ```
5. **Pas de batching secret** : émission immédiate. Justification GDD §Visual Requirements : un secret = 1 pulse HUD plus marqué (Pillar 4 viscéralité) — pas de saturation puisque la collecte de secrets est un événement discret (joueur ne collecte pas 2 secrets dans le même tick 16.6 ms).
6. **Pas d'idempotence guard secret** : Secret System (r1 R-SEC-08) garantit qu'un secret ne peut être collecté qu'une fois — pas besoin de `_collected_secrets` set côté Credit (contrairement à KILL où Enemy peut bug et ré-émettre).
7. **AC-CRD-16 vérification design-time** : assertion runtime `assert(BASE_SECRET_CREDIT >= 5 * KILL_CREDIT_GRUNT)` dans `_ready()` suffit (test will catch if tuning a violé l'invariant Pillar 4 plancher).
8. **Émission SYNC** : `credits_changed.emit()` synchrone. Si `secret_collected` est émis depuis un `Area3D.body_entered` (ou équivalent Secret r1), c'est déjà dans le main thread — pas de cross-thread.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 001 (skeleton).
- Story 002 (Source KILL).
- Story 004 (Persistence) : guards `_is_hydrated`, `state_changed(PAUSED)`.
- Story 007 (Lints/Static) : vérifications statiques de la signature signal.
- HUD pulse différencié SECRET vs KILL — appartient à HUD epic (Pillar 4 viscéralité visuelle) ; Credit ne fait que émettre `source == SECRET`.

---

## QA Test Cases

- **AC-CRD-12** : Given mock SecretNode + spy `credits_changed`, When `secret_collected.emit(mock_node, 1)`, Then `_total_credits == N + 5`, spy 1 appel `(N+5, +5, SECRET)`.
- **AC-CRD-13** : same as 12 mais `tier=2` → `(N+10, +10, SECRET)`.
- **AC-CRD-14** : same mais `tier=3` → `(N+15, +15, SECRET)`.
- **AC-CRD-15** :
  - Given `tier=0`, When emit, Then `_total_credits` stable, spy 0 appel, warning log captured (matcher message regex `invalid secret tier: 0`).
  - Edge cases : `tier=99` (over-bound), `tier=-1` (negative), `tier=4` (just over). Tous → ignore + warn.
- **AC-CRD-16** : assertion runtime testée comme unit test isolated : `assert_int(BASE_SECRET_CREDIT * 1).is_greater_equal(5 * KILL_CREDIT_GRUNT)`. Si tuner abaisse `BASE_SECRET_CREDIT` à `4`, ce test échoue (Pillar 4 plancher cassé).
- **AC-CRD-34** : Given SecretSystem stub minimal (Node avec signal `secret_collected(node, tier)`), When stub émet `(mock_node, 2)`, Then Credit `_total_credits += 10`, spy `credits_changed(N+10, +10, SECRET)`. Mécanisme : test integration avec stub instancié + connexion réelle Credit→stub.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/credit/credit_economy_secret_source_test.gd` (AC-12, 13, 14, 15, 16) — must exist and pass GUT.
- `tests/integration/credit/credit_economy_secret_integration_test.gd` (AC-34) — must exist and pass.

**Status**: [x] Complete — 10/10 tests PASSED 134 ms (GdUnit4 `--add tests/unit/credit/credit_economy_secret_source_test.gd --add tests/integration/credit/credit_economy_secret_integration_test.gd --ignoreHeadlessMode`, run 2026-04-28). Sync rétroactif (story implémentée durant batch /story-done 002-010, section evidence non synchronisée — corrigée maintenant).

---

## Dependencies

- Depends on: **Story 001** (skeleton — enum `SourceKind`, signal `credits_changed`, state vars).
- Unlocks: aucune autre story Credit (provisoire — quand Secret System epic sera implémenté, refactorer la connexion stub→réelle dans une follow-up story Tier 2).

---

## Completion Notes

**Completed**: 2026-04-28
**Criteria**: 6/6 passing (AC-CRD-12/13/14/15/16/34)
**Verdict**: COMPLETE

**Tests run** : `tests/unit/credit/credit_economy_secret_source_test.gd` (8 tests) + `tests/integration/credit/credit_economy_secret_integration_test.gd` (2 tests) = 10/10 PASSED 161 ms. Suite credit globale **39/39 vert** 427 ms (incluant kill, try_spend, lints).

**Files modified (3)** :
- `src/core/credit_economy.gd` : ajout `BASE_SECRET_CREDIT: int = 5`, `KILL_CREDIT_GRUNT: int = 1` constants ; `_on_secret_collected(node, tier)` handler avec validation tier∈{1,2,3} + EC-CRD-9 ignore silencieux + warn ; `_ready()` assertion AC-CRD-16 plancher Pillar 4. Pas de batching (1 secret = 1 emit immédiat — distinct du multi-kill).
- `tests/unit/credit/credit_economy_secret_source_test.gd` NEW 178 L : 8 tests AC-CRD-12/13/14/15 (4 sous-cas tier invalide : 0, -1, 4, 99) + AC-CRD-16.
- `tests/integration/credit/credit_economy_secret_integration_test.gd` NEW 113 L : 2 tests AC-CRD-34 + edge multi-secret-no-batching via stub `StubSecretSystem extends Node` + signal `secret_collected(node, tier)`.

**Deviations** : aucune. Connexion `get_node("/root/SecretSystem")` reportée — SecretSystem epic pas encore implémenté ; tests connectent directement au handler (pattern conforme story spec point 3).

**Code Review** : Skipped (Solo mode)
**Tech Debt Logged** : 0 items

**Unblocks aval** :
- **credit-economy story-004** Persistence (boot hydrate + state_changed PAUSED guards) — peut désormais ajouter les guards `_is_hydrated` / PAUSED sur `_on_secret_collected` AND `_on_enemy_killed`.
- **Credit Economy epic progress** : 3/8 stories Complete (001 skeleton + 002 KILL + 003 SECRET).
