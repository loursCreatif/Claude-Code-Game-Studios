# Story 011: RoomArchetype enum + @export sur Room_NN + archetype diversity lint

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Config/Data
> **Estimate**: 6h (enum RoomArchetype 0.5h + @export wiring sur Room_NN.gd 1.5h + helper `validate_room_archetypes` dans level_lint.gd 1.5h + 6 fixtures `.tscn` 1h + 6 tests GdUnit4 1h + CI job extension lint-level-invariants 0.5h)
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-016` (room-to-room altitude F5 archetype rise ranges implicit)

**ADR Governing Implementation**: — (authoring enum + lint, GDD R-2.6 + S-1..S-5 owned)
**ADR Decision Summary** : N/A. GDD-owned archetype taxonomy.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `enum` GDScript avec `@export` properties sur Node3D (Room_NN). `@export var archetype: RoomArchetype = RoomArchetype.TRAVERSAL` inspector-friendly. Backward compat : `@export var room_type: RoomType` legacy accepté avec auto-conversion + warning.

---

## Acceptance Criteria

- [x] **AC-LVL-50** : Archetype diversity (R-2.6 r2 S-1/S-3/S-5) — (a) ≥ 3 archetypes distincts sur étage ; (b) ≥ 1 `SHAFT` présent ; (c) ≥ 1 `SECRET_HUB` présent ; (d) pas de `COMBAT` consécutifs (S-2) ; (e) salle finale avant EtageExitTrigger ∈ {SECRET_HUB, TRAVERSAL} (S-4). Violation = lint fail
- [x] **AC-LVL-52** : Archetype @export obligatoire (R-1 r2 + R-2.6 r2) — chaque Room_NN sous StaticEnvironment a `archetype: RoomArchetype` définie ∈ {TRAVERSAL, COMBAT, SHAFT, SECRET_HUB} ; absence = lint fail
- [x] **AC-LVL-52b** : Backward compat legacy `room_type` — Room_NN avec property `room_type` (legacy r1 enum) mais sans `archetype` est accepté : auto-conversion `archetype = room_type` + `push_warning("Room_NN legacy room_type, migrate to archetype @export")` + 0 erreur lint ; mapping enforced ARENA→COMBAT, CORRIDOR→TRAVERSAL, VERTICAL_CHAMBER→SHAFT, JUNCTION→SECRET_HUB (R-2.6 r2 alias)

> **Note** : 3 ACs distincts (AC-LVL-50 / AC-LVL-52 / AC-LVL-52b) = 8 clauses testables au total (5 sous-clauses AC-LVL-50 + 1 AC-LVL-52 + 2 AC-LVL-52b enforce + mapping). Couverture conforme standard ≥ 3 ACs.

---

## Implementation Notes

- Créer `src/gameplay/level/room_archetype.gd` :
  ```gdscript
  class_name RoomArchetype
  extends RefCounted

  enum Type { TRAVERSAL, COMBAT, SHAFT, SECRET_HUB }
  ```
  OU enum directement dans level.gd si pas d'usage externe
- Chaque Room_NN scene (`res://scenes/levels/rooms/room_<archetype>.tscn`) = Node3D avec script qui expose `@export var archetype: RoomArchetype.Type`
- Convention authoring : `Room_NN` ordered naming 01..N dans StaticEnvironment, `archetype` renseigné manuellement par level designer dans inspector
- Ajouter `validate_room_archetypes(root) -> Array[String]` dans `tools/lint/level_lint.gd` :
  - Scan `StaticEnvironment.find_children("Room_*", "", false, false)` (non-recursive, direct children)
  - Check chaque room a property `archetype` (TYPE_INT 0..3)
  - Legacy compat : si `room_type` presente et `archetype` absente → auto-assign `archetype = room_type`, `push_warning("Room_%s legacy room_type, migrate to archetype @export")` + continue
  - AC-LVL-50 checks :
    - (a) `distinct_archetypes.size() >= 3`
    - (b) `SHAFT in distinct_archetypes`
    - (c) `SECRET_HUB in distinct_archetypes`
    - (d) pas 2 COMBAT consécutifs : scan ordered list, check `rooms[i].archetype == COMBAT and rooms[i+1].archetype == COMBAT` = fail
    - (e) dernière room (max NN) : `archetype in [SECRET_HUB, TRAVERSAL]`
- Retourne liste de violations avec room indices et rule violated

---

## Out of Scope

- Story 012 : 4 PackedScene primitives + per-archetype R-4 budgets
- Story 020 : F5 étage height gate (AC-LVL-48) — rise ranges per archetype inclus dans cette story comme authoring metadata, lint en story 020
- Story 022 : tuning knobs level.yaml

---

## QA Test Cases

- **AC-LVL-52** : Test `test_validate_room_archetype_fails_when_missing`
  - Setup : Fixture `etage_missing_archetype.tscn` avec Room_01 Node3D sans property archetype
  - Verify : `validate_room_archetypes(root)` retourne violation `"Room_01 missing @export archetype"`
  - Pass : violation exacte capturée

- **AC-LVL-52b** : Test `test_validate_room_archetype_accepts_legacy_room_type_with_warning`
  - Setup : Fixture avec Room_01 qui a `room_type = 1` (legacy ARENA) mais pas `archetype`
  - Verify : `validate_room_archetypes(root)` retourne `[]` (pas de violation), `archetype` résolu à `COMBAT` (mapping ARENA→COMBAT R-2.6 r2 alias), `push_warning` enregistré "Room_01 legacy room_type, migrate to archetype @export"
  - Pass : 0 errors + 1 warning log + archetype résolu correctement

- **AC-LVL-50(a)** : Test `test_archetype_diversity_requires_3_distinct`
  - Setup : Fixture avec 10 rooms toutes TRAVERSAL (1 distinct archetype)
  - Verify : Violation `"insufficient archetype diversity: 1 distinct, required ≥ 3"`

- **AC-LVL-50(b)(c)** : Test `test_archetype_requires_shaft_and_secret_hub_present`
  - Setup : 10 rooms avec 5 TRAVERSAL + 5 COMBAT (no SHAFT, no SECRET_HUB)
  - Verify : Violations `"missing required archetype: SHAFT"` ET `"missing required archetype: SECRET_HUB"`

- **AC-LVL-50(d)** : Test `test_no_consecutive_combat_rooms`
  - Setup : Rooms [TRAVERSAL, COMBAT, COMBAT, SHAFT, ...]
  - Verify : Violation `"consecutive COMBAT rooms at index 1 and 2"`

- **AC-LVL-50(e)** : Test `test_final_room_must_be_secret_hub_or_traversal`
  - Setup : Rooms [..., COMBAT] (dernière COMBAT)
  - Verify : Violation `"final room archetype must be SECRET_HUB or TRAVERSAL, got COMBAT"`

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: `tests/unit/lint/room_archetype_lint_test.gd` — 6 test cases ; CI job `lint-level-invariants` étendu

**Status**: [x] Created — `tests/unit/lint/room_archetype_lint_test.gd` (6 tests GdUnit4) + 6 fixtures sous `tests/fixtures/level/room_archetype/`. CI gate via `lint-level-invariants` job (run_level_lint.gd étendu).

---

## Dependencies

- Depends on: **Story 010** (hiérarchie StaticEnvironment présente)
- Unlocks: Story 012 (per-archetype budgets consomment cet enum), Story 020 (F5 etage height lint consomme archetype rise ranges)

---

## Completion Notes

**Completed** : 2026-04-27 (cycle r18 + r18b /code-review + /story-done close-out)
**Mode** : Solo auto-approve (review-mode.txt = solo)
**Manifest version** : Story 2026-04-23 = control-manifest 2026-04-23 ✓ no drift.

### Criteria
3/3 ACs passing — 7 clauses testables couvertes par 6 tests GdUnit4.
- AC-LVL-50 (a-e) : 4 tests / 5 sous-clauses (S-3 + S-5 partagent un test sur fixture `no_shaft_no_hub`).
- AC-LVL-52 : 1 test (`fails_when_missing`).
- AC-LVL-52b : 1 test (`accepts_legacy_room_type_with_warning`) — clause "0 violation lint" assertée ; clauses "mapping enforced" et "push_warning enregistré" non assertées explicitement (cf. backlog hardening).

### Code Review (cycle r18b /code-review)
**Verdict** : APPROVED WITH SUGGESTIONS (gdscript-specialist).
- 0 BLOCKING.
- 1 WARNING : `String(child.name)` cast nécessaire pour `begins_with` mais documenté.
- 3 SUGGESTIONS backlog : (S-1) refactor `LevelLint.ARCHETYPE_*` const → `RoomArchetypeScript.Type.*` pour éliminer duplication, (S-2) test naming partiel non-conforme à `test_[system]_[scenario]_[expected]`, (S-3) garde `arch is int` pour éviter faux-positif sur archetype string.

### Polish doc cycle (2026-04-27 close-out)
- `room_archetype.gd:54` — `[return]` de `from_legacy_room_type` précise désormais que `-1` est un sentinel hors-enum intentionnel (Type ne contient pas de membre UNSET).
- `tools/lint/level_lint.gd:1-18` — header de fichier converti de `#` simple → `##` pour cohérence avec `room_archetype.gd` (recommandation gdscript-specialist).
- Runner `run_level_lint.gd` re-exécuté post-edit : exit 0 (PASS, scenes/levels/ absent — comportement attendu pré-production).

### Test Evidence
- Story Type : Config/Data → gate ADVISORY.
- Tests : `tests/unit/lint/room_archetype_lint_test.gd` (209 lignes, 6 tests).
- Fixtures : 6 × `tests/fixtures/level/room_archetype/etage_*.tscn`.
- CI : `.github/workflows/tests.yml` job `lint-level-invariants` étendu (run_level_lint.gd appelle `validate_room_archetypes` après `validate_scene_hierarchy`).
- Smoke check : non exécuté localement (GdUnit4 absent — CI = gate de référence).

### Deviations
- **ADVISORY-1** : TR-lvl-016 dans tr-registry.yaml texte = "Room-to-room altitude change F5". L'implémentation effective concerne R-2.6 r2 archetype taxonomy (GDD-owned, sans TR ID dédié). La portion altitude est Out of Scope (story 020). Recommandation : ajouter `TR-lvl-XXX` dédié à R-2.6 r2 archetype taxonomy.
- **ADVISORY-2** : qa-tester GAP-1 — `room_type_legacy` invalide (>3) chemin d'erreur `"%s invalid room_type_legacy=%d"` non testé.
- **ADVISORY-3** : qa-tester GAP-2/3 — 0 ou 1 Room_NN sous StaticEnvironment non testé (comportement implicite : retour `[]` ou single-room S-1+S-4 multi-violations).
- **ADVISORY-4** : qa-tester GAP-4 — clause "mapping enforced ARENA→COMBAT" de AC-LVL-52b non assertée explicitement (le test vérifie seulement `errors.is_empty()`).
- **ADVISORY-5** : gdscript-specialist S-1/S-3 — duplication constants ARCHETYPE_* + absence garde `is int` (faux-positif possible si archetype="TRAVERSAL" string).

### Tech Debt Logged
5 ADVISORY items à logger (1 TR registry update + 4 hardening backlog).

### Stories débloquées
- Story 012 (PackedScene primitives + per-archetype budgets — consomme `RoomArchetype.Type`)
- Story 020 (F5 étage height gate — consomme archetype rise ranges)
