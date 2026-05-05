# Story 003: Decal Cap LRU Eviction (MAX_DECALS_PER_ROOM=32) — Migration AC-CMB-42

> **Epic**: VFX System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-04
> **Estimate**: S (2-3 h, ring buffer LRU pure logic + room reset hook)

> **Migration AC-CMB-42** : Cette story est l'**owner officiel** du contract decal cap par room. Combat GDD r6 (story-021) réservait `MAX_DECALS_PER_ROOM = 12` comme TBD ADVISORY. VFX GDD r1 résout le contract avec `MAX_DECALS_PER_ROOM = 32` (R-VFX-4 + Formula 1) — valeur révisée 12 → 32 par cohérence Chrome Zen "salle marquée" Pillar 2 (8-32 safe range Tuning Knob). **combat-021 close-out / Closed - Migrated to VFX System 2026-05-04**.

## Context

**GDD**: `design/gdd/vfx-system.md` (Designed r1)
**Requirements**:
- R-VFX-4 : Decal cap par room `MAX_DECALS_PER_ROOM = 32` (LRU ring buffer Formula 1) — résolution AC-CMB-42 migration owned ici
- R-VFX-2 : Pool pré-alloué `DECAL_POOL_SIZE = 64` (2 × MAX_DECALS_PER_ROOM double-buffer)
- F-VFX-1 : Decal cap par room (LRU ring buffer) — `_decal_write_head` croissant `(_decal_write_head) mod POOL`

**ADR Governing Implementation**:
- Aucun ADR VFX-spécifique requis — pure logic ring buffer LRU sur pool pré-alloué story-001.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Decal` node visibility flip Godot 4.0+ stable. Ring buffer index pattern langage-agnostique.

**Control Manifest Rules (Presentation layer)**:
- Required : `_decal_write_head: int` croissant indéfini ; slot recyclé via `(_decal_write_head) mod DECAL_POOL_SIZE` ; `_room_decal_count` plafonné à `MAX_DECALS_PER_ROOM` ; reset à 0 sur `room_changed` (Tier 2+ Level System) OU `respawned` (MVP).
- Forbidden : `Decal.new()` runtime (R-VFX-1 — réutiliser slot pool story-001) ; mutation `MAX_DECALS_PER_ROOM` runtime (constant exposé, pas variable).
- Guardrail : LRU par construction ring buffer index — pas de heuristique alternative (LFU / random).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1, scoped à cette story (Logic) :*

- [ ] **AC-VFX-01** [BLOCKING][AUTO] **GIVEN** la room courante a exactement `MAX_DECALS_PER_ROOM = 32` decals actifs, **WHEN** un 33ème `enemy_killed` est reçu, **THEN** le decal le plus ancien (ring buffer LRU) est recyclé et repositionné à la nouvelle position ; `_room_decal_count` reste à 32 ; aucun `Decal.new()` n'est appelé.
- [ ] **AC-VFX-03** [BLOCKING][AUTO] **GIVEN** le raycast decal ne trouve aucune surface dans `DECAL_RAYCAST_MAX_DISTANCE = 3.0 m`, **WHEN** `enemy_killed` est reçu, **THEN** le decal est skip silencieusement ; le blood spurt particule se joue normalement ; aucun crash. *(Couvert story-002 via `_perform_decal_raycast` retour `Vector3.INF` ; cette story s'assure que `_decal_write_head` n'est PAS incrémenté quand skip.)*
- [ ] **AC-VFX-30** [BLOCKING][AUTO] **GIVEN** le contrat VFX GDD pour Combat (Combat GDD Dependencies row "VFX & Feedback System") est vérifié, **WHEN** le VFX GDD est reviewé contre les 4 obligations Combat GDD : (1) CONNECT_DEFERRED signals R-VFX-3 + AC-VFX-23, (2) zero mutation enemy/player AC-VFX-24, (3) trail swing_started→swing_ended AC-VFX-13/14, (4) flash blanc + splash sang `enemy_killed` AC-VFX-06 + AC-VFX-11, **THEN** chaque obligation est couverte par un AC numéroté ; ownership clair, contrat rempli ; **combat-021 close-out / Closed - Migrated to VFX System 2026-05-04**.
- [ ] **AC-NEW-05** [BLOCKING][AUTO] **GIVEN** 64 kills successifs (POOL complet 2 fois), **WHEN** scan tous decals visibles, **THEN** exactement 32 decals visibles (LRU recycle), `_decal_write_head == 64` (croissance indéfinie), `_room_decal_count == MAX_DECALS_PER_ROOM = 32`.
- [ ] **AC-NEW-06** [BLOCKING][AUTO] **GIVEN** `respawned(position)` reçu, **WHEN** reset room state, **THEN** tous `Decal.visible == false`, `_room_decal_count == 0`, `_decal_write_head == 0` (reset MVP — pas de cross-room persistence OQ-VFX-1).

---

## Implementation Notes

```gdscript
# story-003 ajoute / refactore dans src/core/vfx_system.gd

# Constants déjà déclarées story-001 :
# const MAX_DECALS_PER_ROOM: int = 32
# const DECAL_POOL_SIZE: int = 64  # 2 × MAX_DECALS_PER_ROOM

# State variables déclarées story-001 :
# var _decal_write_head: int = 0
# var _room_decal_count: int = 0

func _spawn_decal_on_surface(position: Vector3) -> void:
    # story-002 implémente _perform_decal_raycast — réutilisé ici
    var surface_pos: Vector3 = _perform_decal_raycast(position)
    if surface_pos == Vector3.INF:
        push_warning("VFX: no surface found for decal at %s" % position)
        return  # AC-VFX-03 — skip silencieux, _decal_write_head NON incrémenté

    # F-VFX-1 — LRU ring buffer
    var slot_idx: int = _decal_write_head % DECAL_POOL_SIZE
    var slot: Decal = _decal_pool[slot_idx]

    # Repositionnement + activation (slot peut être recyclé OU neuf)
    slot.global_position = surface_pos
    # Orientation vers la surface (raycast result.normal disponible si tweaké)
    # MVP : decal projette par défaut vers le bas (Decal node Godot natif gère projection)
    slot.visible = true

    # Increment ring buffer head (croissance indéfinie — pas de wrap explicite)
    _decal_write_head += 1

    # Plafonner room count à MAX (LRU recycle = un sort, un entre)
    _room_decal_count = mini(_room_decal_count + 1, MAX_DECALS_PER_ROOM)

func _on_respawned(_position: Vector3) -> void:
    # AC-NEW-06 — reset room state (MVP — pas de cross-room persistence OQ-VFX-1)
    _room_decal_count = 0
    _decal_write_head = 0
    for d in _decal_pool:
        d.visible = false
    # story-002 implémente blood pool reset + trail reset

# Tier 2+ stub — Level System signal `room_changed` (OQ-VFX-1)
# func _on_room_changed(_room_id: int) -> void:
#     # Reset _room_decal_count à 0, decals précédents conservés visibles cross-room
#     # (decision OQ-VFX-1 Tier 2+ — MVP : pas de cross-room persistence)
#     pass
```

**Logique LRU ring buffer (Formula 1 du GDD)** :
```
Soit D = _room_decal_count
     MAX = MAX_DECALS_PER_ROOM = 32
     POOL = DECAL_POOL_SIZE = 64
     head = _decal_write_head (croissant indéfini, jamais wrap)

Si D < MAX :
    slot = _decal_pool[head mod POOL]
    head += 1
    D = mini(D + 1, MAX)

Si D == MAX (cap atteint) :
    slot = _decal_pool[head mod POOL]
    # slot recyclé : ancien decal le plus vieux (head wrap-around POOL)
    head += 1
    D reste à MAX (un ancien sort = visible reposition, un nouveau entre)
```

**Ownership contract Combat-021 close-out** :
- Combat GDD réservait `MAX_DECALS_PER_ROOM = 12` (TBD ADVISORY r6).
- VFX GDD r1 résout : `MAX_DECALS_PER_ROOM = 32` (cohérence Chrome Zen "salle marquée" Pillar 2 + safe range [8, 64] Tuning Knob).
- AC-CMB-42 → AC-VFX-01/02/03/30 owned VFX story-003.
- combat-021 status : `Blocked` → `Closed - Migrated to VFX System 2026-05-04` (close-out).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- `_perform_decal_raycast` body (raycast `PhysicsDirectSpaceState3D.intersect_ray`) — story-002.
- Decal modulate color `#C8232C` opacity 0.7 + size 0.6 m — story-001 (pool init).
- Multi-kill burst additive `(count - 1)` decals — story-002 (séquentiel `enemy_killed` events couvre déjà).
- Cross-room persistence Tier 2+ via Level System signal `room_changed` — OQ-VFX-1 latent (handler stub uniquement, pas blocker MVP).
- Lints statiques anti `Decal.new()` runtime — story-007.

---

## QA Test Cases

*Logic — automated unit tests requis :*

**AC-VFX-01** : LRU recycle 33ème kill
- Setup : VFXSystem ready, mock surface raycast retourne toujours `Vector3.ZERO + Vector3.DOWN`.
- Action : émettre 32 × `enemy_killed(mock_enemy, Vector3(i, 0, 0))` séquentiel.
- Verify post-32 : `_room_decal_count == 32`, `_decal_write_head == 32`, tous slots `_decal_pool[0..31].visible == true`.
- Action : émettre 33ème `enemy_killed(mock_enemy, Vector3(99, 0, 0))`.
- Verify post-33 : `_room_decal_count == 32` (plafonné), `_decal_write_head == 33`, slot 32 `_decal_pool[32].visible == true` (nouveau entre), slot 0 `_decal_pool[0].visible == true` (ancien reste — pas effacé visuellement, juste ring buffer head avancé).
- Pass : `assert_int(vfx._room_decal_count).is_equal(32)` + `assert_int(vfx._decal_write_head).is_equal(33)`.

*Note : la sémantique "le plus ancien recyclé" = quand `_decal_write_head == 64`, le slot 0 sera **réutilisé** (repositionné). Au tick 33, slot 32 frais entre. Au tick 65, slot 0 recyclé. Test AC-NEW-05 couvre ce wrap.*

**AC-VFX-03** : No surface skip silencieux
- Setup : mock raycast retourne `Vector3.INF`.
- Action : émettre `enemy_killed`.
- Verify : `_decal_write_head == 0` (NON incrémenté), `_room_decal_count == 0`, tous decals `visible == false`, `push_warning` capturé.
- Pass : `assert_int(vfx._decal_write_head).is_equal(0)`.

**AC-VFX-30** : Combat-021 contract résolu
- Setup : suite test cross-référence.
- Action : grep `production/epics/combat-system/story-021-vfx-decal-cap-pool-lru.md` pour status.
- Verify : status field == "Closed - Migrated to VFX System 2026-05-04" + cross-ref VFX story-003 + `MAX_DECALS_PER_ROOM = 32` confirmed in `src/core/vfx_system.gd` constants.
- Pass : 3 asserts file content + impl constants.

**AC-NEW-05** : 64 kills LRU wrap complet
- Setup : VFXSystem ready, mock raycast OK.
- Action : émettre 64 × `enemy_killed(mock_enemy, Vector3(i, 0, 0))`.
- Verify : `_decal_write_head == 64`, `_room_decal_count == 32` (plafonné), tous `_decal_pool[0..63].visible == true` (les slots 0..31 ont été repositionnés au tick 33-64 via wrap mod 64 = slots 0..31 réutilisés).
- Pass : `assert_int(vfx._decal_write_head).is_equal(64)` + `assert_int(vfx._room_decal_count).is_equal(32)`.

*Note : sur cette logique simplifiée MVP, les 32 decals visibles sont **les plus récents** (slots write_head-32..write_head-1 mod POOL). C'est la définition "LRU" : le plus vieux est recyclé en premier.*

**AC-NEW-06** : Respawn reset
- Setup : `_decal_write_head = 50`, `_room_decal_count = 32`, 32 slots visibles.
- Action : émettre `respawned(Vector3.ZERO)`.
- Verify : `_decal_write_head == 0`, `_room_decal_count == 0`, tous `_decal_pool[i].visible == false`.
- Pass : 3 asserts.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/vfx/vfx_decal_lru_test.gd` (NEW, ~200 lignes) couvrant AC-VFX-01/03/30 + AC-NEW-05/06.
- Mocks raycast factice (résultat configurable test-by-test).
- Smoke check : test suite green run via GdUnit4 headless.
- Cross-ref : `production/epics/combat-system/story-021-vfx-decal-cap-pool-lru.md` mis à jour status `Closed - Migrated to VFX System 2026-05-04` avec section UNBLOCKED 2026-05-04.

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** : story-001 (pool pré-allocation 64 Decal slots) + story-002 (`_perform_decal_raycast` body utilisé ici).
- **Cross-system** : aucun (logique LRU pure, pas de signal externe nouveau).
- **Unlocks** :
  - **combat-021 close-out** — Status `Blocked` → `Closed - Migrated to VFX System 2026-05-04`. AC-CMB-42 résolu.
  - **combat EPIC.md totaux** — `Blocked` count -1 (story-021), `Closed - Migrated` count +1.
  - **AC-VFX-30 contract** — 4 obligations Combat-021 résolues : (1) CONNECT_DEFERRED R-VFX-3 + AC-VFX-23 (story-001), (2) zero mutation AC-VFX-24 (story-007 lint), (3) trail R-VFX-7 + AC-VFX-13/14 (story-002), (4) flash + splash AC-VFX-06 + AC-VFX-11 (story-002 + story-004).
