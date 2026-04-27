# ADR-0006: Combat Tick Model — Scene Tree Ordering, `_prev_position` Ownership, Mock Interfaces, SYNC Exemptions, `_build_capsule_basis()` Helper, Zero-Alloc Exemption

## Status
Accepted 2026-04-23 post-verification Gaps 2/7/8

## Empirical Verification Resolved (2026-04-23)

Trois gaps empiriques Godot 4.6 + Jolt résolus par lead-programmer via runners headless
(`tests/performance/gap2_shapecast_origin_runner.gd`, `gap8_shapecast_margin_runner.gd`) :

- **Gap 2 — Variante A confirmée** : `ShapeCast3D` retourne les overlaps à l'origine
  même avec `target_position = Vector3.ZERO` sous Jolt (`origin_colliding=true`,
  `origin_count=1`). `_tick0_intersect_shape_overlap()` est donc une sécurité redondante
  — peut être retirée au Sprint 1 si AC-CMB-47-Prelim confirme en intégration.
  Ref: `docs/engine-reference/godot/modules/physics.md §ShapeCast3D Overlap at Origin`.

- **Gap 7 — Pattern CapsuleShape3D basis documenté** : convention Godot (grand axe = Y
  local), pattern cross product direct `_build_capsule_basis()` correct, pattern
  `Basis.looking_at * from_euler(PI/2)` incorrect (Y antiparallèle), guards documentés.
  Ref: `docs/engine-reference/godot/modules/physics.md §CapsuleShape3D Basis Orientation`.

- **Gap 8 — Jolt ignore ShapeCast3D.margin** : margin=0.0/0.1/0.2 → tous `colliding=false`
  malgré une géométrie calibrée pour que margin≥0.06 provoque un contact. Jolt ignore
  silencieusement la propriété `margin`. Recommandation : `shape_cast.margin = 0.0`
  explicite dans `CombatSystem._ready()`. Ne pas utiliser `margin` comme levier hitbox.
  Ref: `docs/engine-reference/godot/modules/physics.md §ShapeCast3D.margin`.

Epic `player-combat` débloqué. VC-ZA et VC-DFS restent à résoudre en Sprint 1.

## Date
2026-04-23

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Physics / Core / Scene Tree Ordering |
| **Knowledge Risk** | HIGH (Jolt default 4.6 + ShapeCast3D.margin behavior empirically unconfirmed sur cette codebase, cf. Gap 8 + Gap 2) |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` (Godot 4.6 pinned 2026-02-12), `docs/engine-reference/godot/modules/physics.md` (Jolt default 4.6, collision margin "may behave differently", HingeJoint3D.damp caveat non-pertinent ici), `.claude/docs/technical-preferences.md` (Jolt physics engine), `docs/architecture/adr-0001-physics-rate-60hz.md` (physics rate 60Hz + _physics_process authority), `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md` (aim_forward close-form trig), `docs/architecture/adr-0005-movement-signals-architecture.md` (signals D-2, CONNECT_DEFERRED policy D-5, consumer contract D-7, zero-alloc D-9 + amendment r2 SYNC exemption), `design/gdd/player-combat-system.md` r6 APPROVED (Rules 6/7/9/10/13/14/15/17, Invariants D.8, AC-CMB-08/19/37/41/47/49/51/52/audio-01/audio-02). |
| **Post-Cutoff APIs Used** | `Engine.is_in_physics_frame()` (API existait pré-4.3 mais usage assertion Guard = pattern idiomatique Godot 4.6 pour détecter violations ADR-0001). `Time.get_ticks_msec()` wall-clock indépendant de `Engine.time_scale` (comportement stable 4.x, vérifié 4.6). `Performance.get_monitor(Performance.OBJECT_COUNT)` (4.x stable). Jolt Physics par défaut (4.6). |
| **Verification Required** | **(1) Gap 2 AC-CMB-47-Prelim** ✅ RESOLVED 2026-04-23 — Variante A confirmée : `ShapeCast3D` retourne bien les overlaps à l'origine sous Jolt (`origin_colliding=true`). `_tick0_intersect_shape_overlap()` est sécurité redondante. Ref: `docs/engine-reference/godot/modules/physics.md §ShapeCast3D Overlap at Origin`. **(2) Gap 8** ✅ RESOLVED 2026-04-23 — `ShapeCast3D.margin` ignoré par Jolt (margin=0.0/0.1/0.2 → colliding=false). Recommandation: `shape_cast.margin = 0.0` explicite dans CombatSystem._ready(). Ref: `docs/engine-reference/godot/modules/physics.md §ShapeCast3D.margin`. **(3) Gap 7** ✅ RESOLVED 2026-04-23 — Pattern CapsuleShape3D basis documenté (cross product direct correct + Basis.looking_at antiparallèle incorrect + guards). Ref: `docs/engine-reference/godot/modules/physics.md §CapsuleShape3D Basis Orientation`. **(4) VC-ZA** — mesure empirique `Performance.get_monitor(Performance.MEMORY_STATIC)` et `OBJECT_COUNT` delta sur 1000 cycles swing (AC-CMB-37) pour valider exemption zero-alloc ~16 alloc/swing. **(5) VC-DFS** — test fixture minimal qui vérifie ordre DFS `Player._physics_process` → `CombatSystem._physics_process` quand Combat = direct child, et fait échouer le test quand Combat est sibling ou petit-enfant. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Physics Rate 60 Hz + Jolt + _physics_process authority) — fournit l'autorité tick, la règle "pas de mutation d'état gameplay dans `_process`", et le choix Jolt (la cohérence Jolt+ShapeCast3D.margin est gated par Gap 8). ADR-0002 (Camera Scene Tree CameraArm) — fournit `CameraSystem.aim_forward` close-form trig consommé par Rule 6 Combat pour orienter le sweep. ADR-0005 (Movement Signals Architecture) — fournit le contrat des signaux Movement (`attacked`, `died`, `respawned`) consommés par Combat, et D-5 policy CONNECT_DEFERRED/SYNC dont cet ADR étend les exemptions. Les 3 ADRs doivent être `Accepted` avant qu'ADR-0006 puisse l'être. |
| **Enables** | Démarrage Sprint 1 Combat — débloque les stories qui implémentent `CombatSystem`, `MockEnemy`, et les consumers VFX/Audio de `enemy_killed`. Déverrouille l'implémentation des ACs GDD Combat qui référencent explicitement le "Pending ADR Combat Tick Model" : AC-CMB-08 (CONV-1 basis fix via helper `_build_capsule_basis()`), AC-CMB-19 (injection Callable DEC-r5-1), AC-CMB-37 (soak 1000 cycles + exemption zero-alloc rollback), AC-CMB-41 (Rule 17 Hybrid `_death_pending`), AC-CMB-47 (Gap 2 variantes), AC-CMB-49 (invariants structurels physics_process_priority + direct-child), AC-CMB-51 (fade-out swoosh wall-clock injection pattern), AC-CMB-52 (Gap 4 assert `Engine.is_in_physics_frame()`), AC-CMB-audio-01/02 (contrats MockAudioHandler/MockAudioBus). Pose le pattern canonique pour les futurs ADRs Combat-adjacent (Enemy AI, VFX Combat, Audio Combat). |
| **Blocks** | Epic `player-combat` (tout story implémentation Combat est BLOCKED tant qu'ADR-0006 est `Proposed`). Stories dépendantes : `combat/story-001-shapecast-sweep`, `combat/story-002-swing-state-machine`, `combat/story-003-multi-hit-rule9`, `combat/story-004-slow-mo-time-scale`, `combat/story-005-mutual-kill-rule17`, `combat/story-006-respawn-reset`, `combat/story-007-shape-margin-jolt-empirical` (Gap 8), `combat/story-008-zero-alloc-soak` (AC-CMB-37). |
| **Ordering Note** | ADR-0006 dépend de 3 ADRs déjà Accepted (0001, 0002, 0005). Aucun cycle. Peut passer `Proposed → Accepted` via `/architecture-review` fresh session post-rédaction. L'acceptation final attend les Verification Required (1)(2)(3) résolus par lead-programmer pré-Sprint 1 — au MVP, le plan est : rédiger ADR-0006 `Proposed`, résoudre Gaps 2/7/8 empiriquement, annoter résultats dans engine-reference + ADR, `/architecture-review` → `Accepted`. Si Gap 2 Variante B confirmée, l'ADR sera amendé pour déclarer `_tick0_intersect_shape_overlap()` comme "sécurité redondante retirée" au lieu de "mitigation load-bearing". |

## Context

### Problem Statement

La review indépendante `/design-review` du GDD Player Combat System (r1 → r6 `APPROVED`, 2026-04-23) a systematiquement surfacé le même marker : **Pending ADR Combat Tick Model — lead-programmer pré-Sprint 1**. Cette ADR doit figer 7 décisions cross-coupling qui ne peuvent pas vivre dans le GDD Combat seul (elles engagent le scene tree, l'ordre d'exécution, l'architecture de tests, et les exemptions explicites à ADR-0005 D-5 + D-9) :

1. **Ordre d'exécution `_physics_process` Movement vs Combat.** Le mécanisme Rule 17 Hybrid (M1, r2, mutual kill) repose sur le fait que `Player._physics_process` (Movement) s'exécute AVANT `CombatSystem._physics_process` dans le même tick. Ce contrat est garanti par le DFS preorder de Godot UNIQUEMENT si CombatSystem est direct child de Player **et** que `physics_process_priority == 0` (défaut). Un refactor qui rendrait Combat sibling de Player, ou qui changerait `physics_process_priority`, casserait Rule 17 silencieusement. AC-CMB-49 Partie B (r4 B-R3-03) codifie les invariants mais a besoin d'une référence ADR pour être traçable.

2. **Ownership du cache `_prev_position`.** Rule 6 + Formula 2 Combat requièrent un cache de la position Player du tick précédent pour construire le sweep ShapeCast3D inter-tick (anti-tunneling à V=30 m/s). Le GDD r1 BLOCKING #4 a établi que Combat **doit** être propriétaire exclusif de ce cache (pas Movement) car au moment où Combat s'exécute, `player.global_position` reflète déjà tick N (post-`move_and_slide()`). Le cache doit donc être mis à jour **en fin** de `CombatSystem._physics_process`, pas au début. Sans ADR, un implémenteur peut mettre le cache au début (valeur tick N lue → sweep nul) ou céder l'ownership à Movement (coupling amont invalide, viole ADR-0005 D-10 outbound-only).

3. **Interface Mock pour les tests** (`MockMovement`, `MockEnemy`, `MockAudioHandler`, `MockAudioBus`). Plusieurs ACs BLOCKING du GDD Combat sont `[BLOCKED: Gap 1 — MockEnemy non créé]` (AC-CMB-05/06/07/25). AC-CMB-audio-01/02 requièrent `MockAudioHandler` et `MockAudioBus`. AC-CMB-19 (DEC-r5-1) + AC-CMB-51 requièrent un pattern d'injection `_get_time_msec: Callable` substituable. Sans ADR figeant ces contrats, chaque test sera bricolé différemment → cassures de refactor en cascade.

4. **Exemption SYNC pour `enemy_killed` (VFX flash blanc ColorRect) et pour `died` (Combat `_on_player_died` flag `_death_pending`).** ADR-0005 D-5 amendment r2 a déjà documenté ces deux exemptions côté Movement signals, **mais le signal `enemy_killed` est émis par CombatSystem, pas MovementController** (scope note r4 ADR-0005 : "non-normatif au sens ADR-0005, autorité déléguée au Pending ADR Combat Tick Model"). ADR-0006 doit donc récupérer l'autorité canonique sur les connexions aux signaux Combat et re-déclarer les exemptions sous sa propre signature.

5. **Helper `_build_capsule_basis()` — r6 CONV-1 fix.** La r5.2 a convergé (gameplay-programmer + godot-specialist fresh session) sur un bug de construction Basis : `Basis.looking_at(aim_forward, safe_up) * Basis.from_euler(Vector3(PI/2, 0, 0))` produit un axe Y capsule antiparallèle à `aim_forward`, ce qui propage une inversion 180° dans `ShapeCast3D.target_position = basis.inverse() * sweep_delta` → tunneling garanti dès que `aim_forward ≠ Vector3(0, 0, -1)`. r6 a corrigé via construction directe cross product centralisée dans `_build_capsule_basis(forward: Vector3) -> Basis`. 4 call sites dans le GDD (lignes 87, 135, 377, 931). ADR-0006 fige la signature, le contrat mathématique (`(basis * Vector3.UP).angle_to(forward) < 0.001 rad`), la localisation (helper privé de CombatSystem), et les guards (safe_up colinéaire + déterminant quasi-singulier).

6. **Exemption ADR-0005 D-9 (zero-alloc).** DEC-r5-3 a explicité une exemption : `_collect_swing_hits()` + `_tick0_intersect_shape_overlap()` allouent ~16 fois par swing (8 ticks × 2 locaux + 5 allocations au tick 0 : `var seen_ids: Dictionary[int, bool] = {}`, `var merged: Array[Node] = []`, `PhysicsShapeQueryParameters3D.new()`, etc.). ADR-0005 D-9 interdit les allocations dans hot path `_physics_process`. ADR-0006 doit soit déclarer formellement l'exemption avec 4 clauses + clause de rollback conditionnel AC-CMB-37, soit forcer un refactor pool pré-alloué. Le choix DEC-r5-3 : exemption documentée, pas de refactor avant mesure (anti-YAGNI).

7. **Injection `_get_time_msec: Callable` (DEC-r5-1 + REC-03 AC-CMB-51).** AC-CMB-19 (slow-mo timing wall-clock) et AC-CMB-51 (fade-out swoosh wall-clock) requièrent un mock déterministe du wall-clock pour la CI headless. Pattern décidé : `CombatSystem._get_time_msec: Callable = Time.get_ticks_msec` (substituable en test). ADR-0006 fige le pattern pour cohérence cross-consumer et évite qu'un 3e consumer (futur Audio/VFX) invente un autre pattern.

Sans ADR-0006, le Sprint 1 Combat partira avec 7 questions d'architecture non résolues, dont 3 dégradent silencieusement le comportement (DFS order, `_prev_position` lag, Basis inversion) et 4 brisent la testabilité CI (mocks, injection Callable, exemption zero-alloc non tracée, SYNC exemption hors autorité).

### Constraints

- **Engine** : Godot 4.6 + GDScript. Jolt Physics par défaut (collision margin caveat). Scene tree DFS preorder pour `_physics_process`. `physics_process_priority` : int, défaut 0, négatif = exécute avant dans la scope du parent, positif = après.
- **ADR-0001 acquis** : autorité gameplay `_physics_process`. Pas de mutation d'état gameplay dans `_process`. Physics tick 60 Hz. `Engine.is_in_physics_frame()` utilisable pour guard debug.
- **ADR-0002 acquis** : Camera expose `aim_forward: Vector3` close-form trig roll-invariant. Combat consomme via référence scene tree.
- **ADR-0005 acquis** : 8 signals Movement typés, émis depuis `_physics_process` uniquement, D-5 policy CONNECT_DEFERRED/SYNC avec 2 exemptions SYNC documentées (VFX flash blanc sur `enemy_killed` — scope historique; Combat `_on_player_died` sur `died`).
- **ADR-0005 D-9 zero-alloc** : Hot path `_physics_process` interdit Dict literal, push_back Array sans resize, alloc Node/Resource runtime. ADR-0006 doit trancher l'exemption Combat explicitement.
- **ADR-0005 D-10 outbound-only** : MovementController ne référence aucun consumer. Combat = consumer aval de Movement, autorisé à référencer Player (outbound de Movement, inbound de Combat).
- **Pillar 1 — FLOW AVANT TOUT** : latence input→réponse ≤ 1 frame. SYNC exemption pour `enemy_killed`→flash blanc (frame-precise).
- **Pillar 3 — Rétention / Feedback immédiat** : mutual kill preserved (Rule 17 Hybrid, symétrie one-shot).
- **Solo mode** : TD-ADR gate + engine-specialist gate skipped (cohérent avec `production/review-mode.txt` = `solo`). `/architecture-review` fresh session obligatoire avant Accepted.
- **GDD Combat r6 APPROVED** : tous les ACs cités supra sont figés ; ADR-0006 ne modifie pas le GDD mais formalise les contrats qu'il référence.

### Requirements

- **REQ-1** — CombatSystem est un **direct child** du Player node (CharacterBody3D). Le scene tree DOIT être `Player / CombatSystem`, pas `Player / Subsystems / CombatSystem` (petit-enfant = ordre DFS indirect) ni sibling de Player (coupling cross-branch casse l'autorité).
- **REQ-2** — `CombatSystem.physics_process_priority == 0` (défaut Godot). Toute valeur négative ou positive casse l'ordre DFS parent-avant-enfant. Assertion `_ready()` debug build obligatoire.
- **REQ-3** — `_prev_position: Vector3` est **membre privé de CombatSystem**, initialisé à `player.global_position` dans `_ready()`, mis à jour **en fin** de `CombatSystem._physics_process` (après toute logique de sweep du tick courant). Aucun autre système ne lit ou écrit ce cache.
- **REQ-4** — Les tests Combat utilisent un set canonique de mocks : `tests/unit/combat/mock_enemy.gd` (contract `die()` idempotent + `is_dead() -> bool` + `CollisionShape3D` layer=2), `tests/unit/combat/mock_movement.gd` (contract signals `attacked`, `died`, `respawned(pos)` + read-only props `state`, `velocity`, `global_position`), `tests/unit/combat/mock_audio_handler.gd` (contract `_kill_sound_played_this_swing: bool`), `tests/unit/combat/mock_audio_bus.gd` (contract log ducking events timestamped). Leur API est figée par ADR-0006.
- **REQ-5** — CombatSystem expose un point d'injection `_get_time_msec: Callable = Time.get_ticks_msec`. Substituable en test via `combat_system._get_time_msec = func(): return _mocked_ms`. Utilisé par Rule 13 (slow-mo timing) et Audio swoosh fade-out. Tous les consumers wall-clock de Combat passent par ce point unique.
- **REQ-6** — Les connexions aux signaux **Combat** (`swing_started`, `swing_ended`, `enemy_killed`, `multi_kill`) suivent par défaut le pattern ADR-0005 D-5 (CONNECT_DEFERRED pour lourds, SYNC pour light). **Exemption SYNC** autorisée pour **1 cas MVP** : VFX flash blanc ColorRect sur `enemy_killed` (toggle `visible = true` + `Tween.tween_property(alpha)` sur ColorRect pré-existant — pas d'instanciation de Node, pas de stream, pas d'alloc > 256 B, logique trivial). Toute autre exemption SYNC = amendement ADR-0006.
- **REQ-7** — La connexion Combat au signal Movement `died` est en **SYNC** (héritée ADR-0005 D-5 amendment r2, re-déclarée sous l'autorité ADR-0006). Handler `_on_player_died()` : set `_death_pending: bool = true`, retour immédiat, aucune mutation de state Combat ou Movement. Consommation `_death_pending` en **fin** de `CombatSystem._physics_process` (après résolution colliders du tick).
- **REQ-8** — Le helper `_build_capsule_basis(forward: Vector3) -> Basis` est **privé de CombatSystem** (pas exposé comme API publique), avec contrat mathématique : `(_build_capsule_basis(v) * Vector3.UP).angle_to(v) < 0.001 rad` pour tout `v` unit vector non-colinéaire à `safe_up`. Construit par cross product direct (pas `Basis.looking_at * from_euler(+PI/2)`). Guards : fallback `safe_up` si `forward` colinéaire à UP/DOWN (pitch ≥ PITCH_LIMIT), fallback `Basis.IDENTITY` + `push_error` si déterminant quasi-singulier.
- **REQ-9** — L'exemption ADR-0005 D-9 zero-alloc pour Combat est **documentée dans ADR-0006** avec 4 clauses : (1) taille bornée ≤ 3 entrées (MAX_KILLS_PER_SWING), (2) allocation locale scope court avec cleanup GDScript déterministe, (3) AC-CMB-37 soak 1000 cycles valide empiriquement l'absence de fuite (seuils `MEMORY_STATIC` delta ≤ 500 KB + `OBJECT_COUNT` delta ≤ 5), (4) refactor pool anti-YAGNI avant mesure. **Clause de rollback conditionnel** : si AC-CMB-37 échoue, refactor obligatoire vers pool pré-alloué (`_PooledQueryParams`, `_seen_ids`/`_merged` membres privés + `.clear()` en entrée `_collect_swing_hits()`).
- **REQ-10** — CombatSystem **ne référence directement** : aucun VFXManager, AudioManager, HUD, CreditEconomy, class name consumer aval. Les consumers de `enemy_killed` / `multi_kill` / `swing_started` / `swing_ended` se connectent **depuis leur propre `_ready()`** au Player.CombatSystem node. Réplique D-10 ADR-0005 pour Combat.

## Decision

Adopter les décisions D-1..D-8 ci-dessous comme modèle tick canonique du CombatSystem MVP. Elles complètent ADR-0001 (autorité tick), ADR-0002 (aim_forward), ADR-0005 (signals Movement) et forment la base implémentable du GDD Combat r6 APPROVED.

### D-1 — Scene Tree Topology : CombatSystem est direct child de Player

```
Player (CharacterBody3D — MovementController)
 ├─ Camera3D (via CameraArm — ADR-0002)
 ├─ CombatSystem (Node3D — direct child)  ← DFS preorder sibling order n'importe pas, seul "direct child" importe
 └─ (other children — HUD, VFXRoot, etc.)
```

- **DFS preorder garanti** : Godot exécute `_physics_process` en depth-first preorder sur le scene tree. Pour un parent avec N children, l'ordre est : parent → child 0 → child 0 descendants → child 1 → ... Cela garantit que `Player._physics_process()` s'exécute **avant** `CombatSystem._physics_process()` dans le même tick physique.
- **Interdit** : CombatSystem en sibling de Player, ou petit-enfant (`Player / Subsystems / CombatSystem`). Le premier casse l'ordre parent-avant-enfant ; le second décale d'un niveau qui reste correct théoriquement mais devient fragile si `Subsystems` acquiert sa propre logique `_physics_process`.
- **Migration si refactor futur** : un changement de topologie casse Rule 17 Hybrid silencieusement (pas de crash, juste mutual kill semantics invalide). AC-CMB-49 Partie B (d) fait échouer le test si `get_parent() != player_node`.
- **Invariant runtime** : `assert(get_parent() == player_node)` dans `CombatSystem._ready()` debug build.

### D-2 — `physics_process_priority == 0` (default) invariant

- `physics_process_priority: int` (héritage `Node`) contrôle l'ordre d'exécution `_physics_process` des nodes **au sein d'un même parent** (scope fratrie). Valeur par défaut : 0.
- Une valeur négative force le node à s'exécuter **avant** ses siblings (et potentiellement avant son parent selon scope) ; positive, après.
- **Décision** : `CombatSystem.physics_process_priority` DOIT rester 0. Toute valeur différente casse l'ordre DFS parent-avant-enfant garanti par D-1.
- **Invariant runtime** : `assert(physics_process_priority == 0)` dans `CombatSystem._ready()` debug build.
- **AC-CMB-49 Partie B (d)(e)** couvre ce point en test statique + runtime.

### D-3 — `_prev_position: Vector3` Ownership exclusive Combat — update en FIN de `_physics_process`

```gdscript
# CombatSystem (extends Node3D, direct child de Player) :

var _prev_position: Vector3

@onready var _player: CharacterBody3D = get_parent()

func _ready() -> void:
    assert(get_parent() == _player, "Combat must be direct child of Player — D-1")
    assert(physics_process_priority == 0, "Combat priority must stay default 0 — D-2")
    _prev_position = _player.global_position  # init tick 0 — pas de sweep possible au tick 0

func _physics_process(delta: float) -> void:
    # À ce point, player.global_position reflète déjà tick N (Movement _physics_process exécuté avant via DFS D-1).
    # _prev_position contient la position tick N-1 (mise à jour en fin de ce callback au tick précédent).

    if _state == State.SWINGING:
        var sweep_delta: Vector3 = _player.global_position - _prev_position
        # ... configuration ShapeCast3D + force_shapecast_update + _collect_swing_hits ...

    # ... state machine transitions (incluant consume _death_pending en fin — Rule 17) ...

    # UPDATE EN FIN : capture position tick N pour utilisation au tick N+1.
    _prev_position = _player.global_position
```

- **Pourquoi en fin, pas au début** : au début du tick N+1, `player.global_position` reflète déjà tick N+1 (Movement a exécuté son `_physics_process` avant Combat via DFS D-1). Si on capture au début, on capture tick N+1 au lieu de tick N → sweep `delta = position_N+1 - position_N+1 = ZERO`, bug silencieux.
- **Alternative rejetée** : mettre le cache au **début** du tick suivant en utilisant un signal `Movement.physics_stepped_N` — ajoute un signal cross-system pour un problème interne Combat. Plus simple en fin de callback.
- **Initialisation `_ready()`** : `_prev_position = _player.global_position` évite de lire une position non initialisée (Vector3.ZERO) au tick 0. Au tick 0, sweep_delta = ZERO, pas de sweep physique (cohérent avec l'état Idle initial).
- **Write access exclusif Combat** : aucun autre système ne doit lire ou écrire `_prev_position`. Le cache est un détail d'implémentation Combat.

### D-4 — Mock Interface Contract pour les tests Combat

Les mocks canoniques sont placés sous `tests/unit/combat/` et versionnés. Leur API est figée par ADR-0006 ; un changement = amendement.

#### D-4a — `MockEnemy` (contract Enemy System Section F GDD)

```gdscript
# tests/unit/combat/mock_enemy.gd
class_name MockEnemy
extends CharacterBody3D  # layer=2 (Enemy), mask=0 (test seul, pas de physics réelle)

@export var radius: float = 0.35  # contract Enemy hitbox

var _dead: bool = false
var _die_call_count: int = 0

func _ready() -> void:
    collision_layer = 0b00010  # Enemy layer
    collision_mask = 0
    # CollisionShape3D sphère radius=0.35 ajoutée en scene .tscn de test.

func die() -> void:
    # Idempotent — contract AC-CMB-05/06/41 + symétrie one-shot.
    if _dead:
        return
    _dead = true
    _die_call_count += 1

func is_dead() -> bool:
    return _dead

# Helper test uniquement :
func get_die_call_count() -> int:
    return _die_call_count
```

**Contract figé** : `die()` idempotent (early return si `_dead`), `is_dead()` retourne état courant, `_die_call_count` observable pour AC-CMB-05/06 (assert appelé exactement 1 fois). Pas d'IA, pas d'animation, pas de signals — mock pur.

#### D-4b — `MockMovement` (contract Movement signals ADR-0005 D-2 consumed by Combat)

```gdscript
# tests/unit/combat/mock_movement.gd
class_name MockMovement
extends CharacterBody3D

# Signals ADR-0005 D-2 consommés par Combat :
signal attacked()
signal died()
signal respawned(spawn_position: Vector3)
# (Les 5 autres signals Movement non consommés par Combat sont omis — mock minimal.)

# Read-only props consommés par Combat :
enum State { GROUNDED, AIRBORNE, DASHING, WALL_RUNNING, DEAD }
var state: State = State.GROUNDED

# Test helpers pour driver la fixture :
func trigger_attacked() -> void:
    attacked.emit()

func trigger_died() -> void:
    state = State.DEAD
    died.emit()

func trigger_respawned(pos: Vector3) -> void:
    state = State.GROUNDED
    global_position = pos
    respawned.emit(pos)
```

**Contract figé** : 3 signals (attacked, died, respawned) + property `state` read-only enum. Le mock expose explicitement `trigger_*` pour driver depuis le test GUT. Pas de state machine interne, pas de `move_and_slide()` — mock pur.

#### D-4c — `MockAudioHandler` (contract AC-CMB-audio-01 multi-kill)

```gdscript
# tests/unit/combat/mock_audio_handler.gd
class_name MockAudioHandler
extends Node

var _kill_sound_played_this_swing: bool = false
var clac_played_count: int = 0
var blood_played_count: int = 0

func _on_enemy_killed(_enemy: Node, _position: Vector3) -> void:
    if not _kill_sound_played_this_swing:
        _kill_sound_played_this_swing = true
        clac_played_count += 1
    blood_played_count += 1  # blood joue à chaque enemy_killed (AC-CMB-audio-01 (c))

func _on_swing_ended() -> void:
    _kill_sound_played_this_swing = false  # reset pour swing suivant (AC-CMB-audio-01 (d))
```

**Contract figé** : 1 flag `_kill_sound_played_this_swing`, 2 compteurs observables. Coverage AC-CMB-audio-01 (a)(b)(c)(d).

#### D-4d — `MockAudioBus` (contract AC-CMB-audio-02 ducking ordering)

```gdscript
# tests/unit/combat/mock_audio_bus.gd
class_name MockAudioBus
extends Node

# Log de ducking events : timestamp wall-clock (msec), volume_db_delta, bus_name.
var ducking_events: Array[Dictionary] = []

func log_ducking_event(bus_name: String, volume_db_delta: float, timestamp_msec: int) -> void:
    ducking_events.append({
        "bus": bus_name,
        "delta_db": volume_db_delta,
        "t_msec": timestamp_msec,
    })

# Note : ce mock utilise un Dictionary literal — **autorisé exemption test**, pas hot path.
```

**Contract figé** : 1 méthode `log_ducking_event` + log Array observable. Coverage AC-CMB-audio-02.

**Exception zero-alloc** : les mocks sont des fixtures test exécutées hors du hot path `_physics_process` de production. L'alloc Dict literal dans `log_ducking_event` est explicitement autorisée (pas de contradiction avec REQ-9 ou ADR-0005 D-9 — la règle zero-alloc couvre le code `src/`, pas `tests/`).

### D-5 — `_get_time_msec: Callable` Injection Pattern (DEC-r5-1)

```gdscript
# src/gameplay/combat/combat_system.gd :
var _get_time_msec: Callable = Time.get_ticks_msec

# Usage (Rule 13 slow-mo timing, wall-clock):
var now_msec: int = _get_time_msec.call()
if now_msec - _slow_mo_start_msec >= SLOW_MO_DURATION_MS:
    Engine.time_scale = 1.0
    _slow_mo_active = false

# En test :
func test_slow_mo_expires_at_50ms_exact() -> void:
    var combat := preload("res://src/gameplay/combat/combat_system.gd").new()
    var mocked_ms: int = 1000
    combat._get_time_msec = func(): return mocked_ms
    # ... déclencher enemy_killed, mocked_ms = 1050, assert Engine.time_scale == 1.0 ...
```

- **Portée du pattern** : tous les reads wall-clock internes à CombatSystem passent par `_get_time_msec.call()`. Inclus : Rule 13 slow-mo expiration check (AC-CMB-19), Audio swoosh fade-out interpolation (AC-CMB-51 — à confirmer : ownership Audio-handler ou Combat MVP).
- **Pourquoi Callable et pas un wrapper static de classe** : un Callable est substituable par référence au runtime sans sous-classer CombatSystem ni bricoler un @onready preload. Pattern idiomatique GDScript pour dependency injection test.
- **Coût overhead** : un `Callable.call()` ajoute ~50 ns vs `Time.get_ticks_msec()` direct. Pour 1-5 calls/tick, impact < 0.001 ms/frame. Négligeable.
- **Coverage CI** : AC-CMB-19 (r6 branche C accessibility + teardown `Engine.time_scale = 1.0`), AC-CMB-51 (fade-out swoosh wall-clock sous `time_scale = 0.3`).
- **Teardown obligatoire** : tout test qui mocke `_get_time_msec` DOIT également restaurer `Engine.time_scale = 1.0` en `after_each`, sinon contamination state process-wide (AC-CMB-19 r6).

### D-6 — Combat Signals & Connection Mode Policy

Les 4 signaux publiés par CombatSystem (depuis `_physics_process` uniquement, cohérent ADR-0001) :

```gdscript
# In src/gameplay/combat/combat_system.gd :
signal swing_started(direction: Vector3)
signal swing_ended()
signal enemy_killed(enemy: Node, position: Vector3)
signal multi_kill(count: int)
```

**Table de connexion — exemption SYNC explicite pour 1 cas MVP** :

| Consumer | Signal | Mode | Justification |
|---|---|---|---|
| VFX GPUParticles sang | `enemy_killed` | DEFERRED | instancie GPUParticles3D (critère ADR-0005 D-5 (a)) |
| VFX Decal sang | `enemy_killed` | DEFERRED | instancie Decal (critère (a)) |
| Audio kill impact "clac" | `enemy_killed` | DEFERRED | AudioStreamPlayer3D.play (critère (b)) |
| Audio blood ambiance | `enemy_killed` | DEFERRED | AudioStreamPlayer3D.play (critère (b)) |
| **VFX flash blanc ColorRect** | **`enemy_killed`** | **SYNC (exemption ADR-0006)** | **Toggle `visible = true` + `Tween.tween_property(alpha)` sur ColorRect pré-existant — aucune alloc > 256 B, aucune instanciation Node, logique triviale < 0.1 ms. Pillar 1 frame-precise : flash au tick kill.** |
| VFX trail katana | `swing_started` / `swing_ended` | DEFERRED | instancie GPUParticles3D trail (critère (a)) |
| Audio swoosh | `swing_started` | DEFERRED | AudioStreamPlayer.play (critère (b)) |
| HUD multi-kill counter | `multi_kill` | SYNC | toggle bool + int set (light) |

**Handler Combat SYNC du signal Movement `died`** (hérité ADR-0005 D-5 amendment r2, re-déclaré sous autorité ADR-0006) :

```gdscript
# In combat_system.gd _ready() :
player.died.connect(_on_player_died)  # SYNC (flag CONNECT_0 défaut, pas DEFERRED)

func _on_player_died() -> void:
    # SYNC handler — exemption ADR-0006 D-6 :
    # - Aucune mutation d'état Movement (D-7 ADR-0005 respecté — seul un flag Combat-LOCAL est muté)
    # - Aucune allocation
    # - Retour immédiat (< 0.01 ms)
    # - Pourquoi SYNC : mécanisme Rule 17 Hybrid exige que _death_pending soit set AVANT
    #   que Combat._physics_process démarre. CONNECT_DEFERRED déposerait le set au tick+1,
    #   rompant la séquence "resolve colliders tick N puis transition Dead" (mutual kill cassé).
    _death_pending = true
```

**Toute autre connexion SYNC hors cette table = defect.** Lint grep statique en code review : `grep -nE 'connect\([^,]+\)\s*$' src/gameplay/combat/` doit retourner soit zéro match, soit uniquement les handlers whitelist ci-dessus (vérifié manuellement ou via annotation `# sync-exempt: ADR-0006 D-6`).

**Grep pattern AC-CMB-41 clause (8) r6** (inspection statique pour garantir `died` handler SYNC) :
```
grep -nE 'player\.died\.connect.*CONNECT_DEFERRED' src/gameplay/combat/combat_system.gd
```
DOIT retourner zéro match. Si match, AC-CMB-41 FAIL avec message "player.died connecté en CONNECT_DEFERRED — viole Rule 17 Hybrid + ADR-0006 D-6, mécanisme _death_pending cassé".

### D-7 — Helper `_build_capsule_basis()` : localisation, signature, contrat, guards

```gdscript
# In combat_system.gd (private helper) :

# r6 CONV-1 FIX — construction cross product direct (PAS Basis.looking_at * from_euler(+PI/2) qui
# produisait axe Y capsule antiparallèle à forward, propageait inversion 180° dans
# ShapeCast3D.target_position = basis.inverse() * sweep_delta → tunneling garanti).
# Contract mathématique : (_build_capsule_basis(v) * Vector3.UP).angle_to(v) < 0.001 rad
# pour tout v unit vector non-colinéaire à safe_up.

const PITCH_LIMIT_EPSILON: float = 0.01  # évite colinéaire exact UP/DOWN
const BASIS_DETERMINANT_MIN: float = 0.001  # seuil quasi-singulier

func _build_capsule_basis(forward: Vector3) -> Basis:
    # Normalisation défensive (caller passe aim_forward supposé normalisé, mais belt-and-suspenders).
    var fwd: Vector3 = forward.normalized()

    # safe_up fallback si forward colinéaire UP/DOWN (pitch >= PITCH_LIMIT - epsilon) :
    # Au bord PITCH_LIMIT, aim_forward ≈ Vector3.UP (regard zénith) ou DOWN — cross product dégénère.
    # Le fallback safe_up = Vector3.FORWARD (dans ce cas dégénéré, Y capsule = aim_forward ≈ UP,
    # et on choisit un "avant" arbitraire mais stable).
    var up_ref: Vector3 = Vector3.UP
    if abs(fwd.dot(up_ref)) > 1.0 - PITCH_LIMIT_EPSILON:
        up_ref = Vector3.FORWARD  # fallback safe_up (consistent avec Rule 6 r4 B-R3-01)

    # Cross product direct : axe Y local = forward, axe X local = perpendiculaire à (forward, up_ref).
    var right: Vector3 = up_ref.cross(fwd).normalized()
    var local_z: Vector3 = fwd.cross(right).normalized()
    var basis: Basis = Basis(right, fwd, local_z)

    # Guard determinant quasi-singulier (cas extrêmes float precision) :
    if abs(basis.determinant()) < BASIS_DETERMINANT_MIN:
        push_error("_build_capsule_basis: basis quasi-singulière, fallback IDENTITY — forward=%s" % forward)
        return Basis.IDENTITY

    return basis
```

- **Portée** : helper PRIVÉ de CombatSystem (préfixe `_`). Pas une API publique, pas une classe autonome. Appelé à 4 call sites documentés dans le GDD Combat (lignes ~87, ~135, ~377, ~931) : setup ShapeCast3D swing tick 0, setup ShapeCast3D swing ticks N≥1, setup `PhysicsShapeQueryParameters3D` tick 0 overlap, ShapeCast3D.basis invariant check AC-CMB-08.
- **Contract mathématique** : `(_build_capsule_basis(v) * Vector3.UP).angle_to(v) < 0.001 rad` pour tout `v` unit vector avec `|v.dot(Vector3.UP)| < 1.0 - PITCH_LIMIT_EPSILON`. AC-CMB-08 r6 teste sur 100 échantillons sphère unitaire.
- **Guards** : (1) fallback `safe_up = Vector3.FORWARD` si `forward` colinéaire UP/DOWN, (2) fallback `Basis.IDENTITY` + `push_error` si déterminant quasi-singulier (< 0.001). Le second cas est ultra-rare (float precision edge), le `push_error` signale au dev que quelque chose d'anormal s'est produit.
- **Alternative rejetée (r5.2 CONV-1)** : `Basis.looking_at(target, up) * Basis.from_euler(Vector3(PI/2, 0, 0))` — `Basis.looking_at` oriente -Z local sur target, la rotation +PI/2 X permute Y et Z de telle manière que axe +Y local pointe **antiparallèle** à target. La symétrie CapsuleShape3D masquait l'erreur sur un simple `shape_cast.is_colliding()`, mais `target_position = basis.inverse() * sweep_delta` propageait l'inversion 180° → tunneling garanti dès que `aim_forward ≠ Vector3(0, 0, -1)`.
- **Documentation support** : pattern CapsuleShape3D basis à ajouter par lead-programmer dans `docs/engine-reference/godot/modules/physics.md` section "CapsuleShape3D basis orientation — Godot 4.6 convention" (Gap 7, owner pré-Sprint 1).

### D-8 — Exemption ADR-0005 D-9 Zero-Alloc : 4 clauses + rollback conditionnel

**Déclaration d'exemption** : `CombatSystem._collect_swing_hits()` et `CombatSystem._tick0_intersect_shape_overlap()` sont explicitement EXEMPTÉS de ADR-0005 D-9 (zero-alloc hot path) pour les allocations suivantes :

```gdscript
# In _collect_swing_hits() (exécuté chaque tick actif du swing — 8 ticks/swing) :
var seen_ids: Dictionary[int, bool] = {}  # alloc Dict ; taille ≤ MAX_KILLS_PER_SWING=3
var merged: Array[Node] = []  # alloc Array ; taille ≤ MAX_KILLS_PER_SWING=3

# In _tick0_intersect_shape_overlap() (exécuté UNIQUEMENT tick 0 du swing) :
var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()  # alloc Resource
var hits: Array[Dictionary] = []  # alloc Array de Dict locaux (Godot API retour)
var result: Array[Node] = []  # alloc Array ; taille ≤ count hits
var _tick0_ids: Dictionary[int, Node] = {}  # alloc Dict pour dédup O(1)
```

Total par swing : ~16 allocations max (8 ticks actifs × 2 locaux dans `_collect_swing_hits` + 5 allocations au tick 0 dans `_tick0_intersect_shape_overlap`).

**4 clauses justificatives** :

1. **Taille bornée** : toutes les structures allouées ont une borne supérieure stricte (`MAX_KILLS_PER_SWING = 3`, `hits` borné par nombre de colliders Enemy dans la capsule ≤ quelques unités MVP). Pas de croissance en O(n_ennemis_niveau).
2. **Scope local court** : toutes les variables sont `var` locales à la fonction. GDScript libère déterministiquement à la sortie de fonction (reference counting GC), pas de référence pendante. Pas d'état global growth.
3. **Validation empirique via AC-CMB-37** (soak 1000 cycles) : seuils `Performance.get_monitor(Performance.MEMORY_STATIC)` delta ≤ **500 KB** sur 1000 cycles swing et `OBJECT_COUNT` delta ≤ **5 objets**. Si ces seuils tiennent, l'exemption est validée.
4. **Anti-YAGNI** : un refactor pool pré-alloué (`_PooledQueryParams`, `_seen_ids` / `_merged` membres privés + `.clear()`) ajoute ~50 lignes + maintenance (reset correct des pools entre swings, invariants) pour résoudre un problème non mesuré. Coût-bénéfice négatif avant mesure.

**Clause de rollback conditionnel AC-CMB-37** :

Si AC-CMB-37 FAIL au bench empirique (`MEMORY_STATIC` delta > 500 KB OU `OBJECT_COUNT` delta > 5 après 1000 cycles), **refactor obligatoire** vers pool pré-alloué :

```gdscript
# Rollback pattern (activé uniquement si AC-CMB-37 fail) :
var _pooled_query: PhysicsShapeQueryParameters3D
var _seen_ids: Dictionary[int, bool] = {}
var _merged: Array[Node] = []
var _tick0_ids: Dictionary[int, Node] = {}

func _ready() -> void:
    # ... D-1 D-2 asserts ...
    _pooled_query = PhysicsShapeQueryParameters3D.new()

func _collect_swing_hits() -> Array[Node]:
    _seen_ids.clear()  # reset O(n) mais jamais re-alloc
    _merged.clear()
    # ... logique identique, réutilise _seen_ids et _merged ...
    return _merged

func _tick0_intersect_shape_overlap() -> Array[Node]:
    _tick0_ids.clear()
    # ... configure _pooled_query, appelle space_state.intersect_shape ...
```

Le rollback est décrit ici pour que son coût soit documenté à l'avance (ADR-amendment léger : déclarer l'exemption purgée et référencer le commit d'implémentation pool).

**Relation avec forbidden_pattern `alloc_in_hot_path_via_literal_dict_or_pushback`** : cette exemption ADR-0006 D-8 est une **exception documentée** au forbidden_pattern (ADR-0004). L'enregistrement registry documentera l'exemption + son gate de rollback (AC-CMB-37).

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  INPUT LAYER (Foundation — ADR-0004)                              │
│  InputManager.was_pressed_this_tick(&"attack") ─────┐             │
└─────────────────────────────────────────────────────┼─────────────┘
                                                      │
                                                      ▼ (polling _physics_process)
┌──────────────────────────────────────────────────────────────────┐
│  MOVEMENT LAYER (Core — ADR-0005)                                 │
│  Player (CharacterBody3D = MovementController)                    │
│   _physics_process [1st exec via DFS preorder ADR-0006 D-1]       │
│   │                                                               │
│   ├── Signals outbound (ADR-0005 D-2) :                           │
│   │     attacked ───┐                                             │
│   │     died ───────┤────────────────────┐                        │
│   │     respawned ──┘                    │                        │
│   │                                      │                        │
│   └── Children (scene tree) :            │                        │
│       ├─ Camera (ADR-0002)               │                        │
│       └─ CombatSystem (ADR-0006) ◄───────┘                        │
└──────────────────────────────────────────────────────────────────┘
                                            │
                                            │ SYNC handler _on_player_died (D-6 exemption)
                                            │ set _death_pending = true, return
                                            │
                                            ▼
┌──────────────────────────────────────────────────────────────────┐
│  COMBAT LAYER (Core — ADR-0006)                                   │
│  CombatSystem (Node3D = direct child of Player)                   │
│   _physics_process [2nd exec via DFS preorder — D-1 + D-2]        │
│                                                                   │
│   Internal state machine : Idle | Swinging | Dead                 │
│   _prev_position : cached END of _physics_process (D-3)           │
│   _build_capsule_basis(fwd) : helper cross-product (D-7)          │
│   _get_time_msec : Callable = Time.get_ticks_msec (D-5)           │
│   _death_pending : bool (Rule 17 Hybrid — consumed END of tick)   │
│                                                                   │
│   Allocations par swing (D-8 exemption ADR-0005 D-9) :            │
│     _collect_swing_hits() : ~16 alloc / swing (4 clauses)         │
│     AC-CMB-37 soak 1000 cycles gate                               │
│                                                                   │
│   Outbound signals (D-6) :                                        │
│     swing_started(direction)     ─┐                               │
│     swing_ended()                 │                               │
│     enemy_killed(enemy, position) │  emit depuis _physics_process │
│     multi_kill(count)             ┘  (ADR-0001 authority)         │
└───┬──────────┬─────────┬─────────┬──────────┬─────────────────────┘
    │          │         │         │          │
    │ DEFERRED │DEFERRED │DEFERRED │DEFERRED  │ SYNC (exemption D-6)
    ▼          ▼         ▼         ▼          ▼
┌────────┐┌────────┐┌────────┐┌────────┐┌───────────────┐
│VFX     ││VFX     ││Audio   ││Audio   ││VFX ColorRect  │
│GPU     ││Decal   ││clac    ││blood   ││flash blanc    │
│sang    ││sang    ││        ││        ││(SYNC exemption)│
└────────┘└────────┘└────────┘└────────┘└───────────────┘
  instantiate  instantiate  play stream  play stream   toggle visible + Tween
  (critère a)  (critère a)  (critère b)  (critère b)   (trivial, frame-precise)
```

## Key Interfaces

| Interface | Owner | Consumers | Pattern | Semantics |
|-----------|-------|-----------|---------|-----------|
| `signal swing_started(direction: Vector3)` | CombatSystem | VFX trail, Audio swoosh, HUD | signal | Émis 1× à la transition Idle → Swinging (début tick 0). `direction` = `aim_forward` au tick 0. |
| `signal swing_ended()` | CombatSystem | VFX stop trail, Audio | signal | Émis 1× à la transition Swinging → Idle (tick ACTIVE_TICKS+1). **Non émis** si transition Swinging → Dead. |
| `signal enemy_killed(enemy: Node, position: Vector3)` | CombatSystem | VFX sang (deferred), Audio clac (deferred), Audio blood (deferred), **VFX flash blanc (SYNC exemption D-6)** | signal | Émis N× par swing (N ≤ MAX_KILLS_PER_SWING=3). `position` = `enemy.global_position` **au tick du kill** (capturé avant freed). |
| `signal multi_kill(count: int)` | CombatSystem | HUD | signal | Émis 1× immédiatement après les N `enemy_killed` du même tick si N ≥ 2. |
| `_on_player_died()` handler | CombatSystem | (connecté au signal `died` de MovementController en SYNC — exemption D-6) | method | Set `_death_pending = true`, return. Ne mute PAS `_state`. Consommé en fin de `CombatSystem._physics_process`. |
| `_build_capsule_basis(forward: Vector3) -> Basis` | CombatSystem (private) | appelé 4× dans `_physics_process` Swinging | method | Construit Basis cross-product avec axe Y = forward. Contract `(result * Vector3.UP).angle_to(forward) < 0.001 rad`. |
| `_get_time_msec: Callable` | CombatSystem | injection test | Callable | Default `Time.get_ticks_msec`. Substituable via `combat_system._get_time_msec = func(): ...` pour mock wall-clock déterministe (AC-CMB-19, AC-CMB-51). |
| `_prev_position: Vector3` | CombatSystem (private) | (aucun — interne) | member | Mis à jour en fin de `_physics_process`. Lu au début du tick suivant pour sweep_delta. |
| MockEnemy contract | `tests/unit/combat/mock_enemy.gd` | AC-CMB-05/06/07/25/41 | test fixture | `die()` idempotent + `is_dead() -> bool` + `CollisionShape3D` layer=2. |
| MockMovement contract | `tests/unit/combat/mock_movement.gd` | tests Combat Integration | test fixture | 3 signals (attacked, died, respawned) + `state` enum read-only + `trigger_*` helpers. |
| MockAudioHandler contract | `tests/unit/combat/mock_audio_handler.gd` | AC-CMB-audio-01 | test fixture | Flag `_kill_sound_played_this_swing` + `clac_played_count` + `blood_played_count`. |
| MockAudioBus contract | `tests/unit/combat/mock_audio_bus.gd` | AC-CMB-audio-02 | test fixture | `log_ducking_event(bus, delta_db, timestamp)` + `ducking_events` array. |

## Alternatives Considered

### Alternative 1 : CombatSystem en sibling de Player au lieu de child direct

- **Description** : `Root / Level / Player` + `Root / Level / CombatSystem` ; CombatSystem référence Player via `@export var player: NodePath` ou `get_node("../Player")`.
- **Pros** : CombatSystem plus "Module" / réutilisable, scene tree plat.
- **Cons** :
  - **Casse DFS preorder garanti** : l'ordre d'exécution `_physics_process` entre siblings dépend de leur ordre dans le parent, ET du fait que Player et CombatSystem sont au **même niveau** — Godot exécute parent → child 0 → child 1 → ..., donc Combat avant Player si Combat est child 0 et Player child 1, ou inverse selon ordre. Le mécanisme Rule 17 Hybrid est fragile à cet ordre : un move de node dans l'éditeur réordonne silencieusement les ticks.
  - **Coupling scene tree** : `get_node("../Player")` brittle à tout déplacement de node.
  - **Reset lifecycle plus compliqué** : respawn Player est géré en place (pas destroyed), mais si un jour Player est recréé, CombatSystem sibling conserve son `_prev_position` stale.
- **Rejection Reason** : DFS parent-avant-enfant est un contrat strict du GDD Combat Rule 17. Sibling le rend dépendant de l'ordre scene .tscn, trop fragile.

### Alternative 2 : `_prev_position` owned by MovementController, published via read-only property

- **Description** : MovementController cache `_prev_position` lui-même en fin de `Player._physics_process`, expose `prev_position: Vector3` read-only. Combat lit `player.prev_position` au début de son `_physics_process`.
- **Pros** : cohérent avec le pattern GDD Movement "Player owns movement state" (ADR-0005 state ownership).
- **Cons** :
  - **Fuite d'implémentation Combat dans Movement** : `_prev_position` est utile à Combat pour anti-tunneling. Movement n'en a aucun usage interne. Exposer une property sur MovementController pour servir un seul consumer aval viole le principe outbound-only minimal (ADR-0005 D-10).
  - **Timing ambigu** : Movement mettrait le cache en fin de `Player._physics_process`, Combat le lit au début de `CombatSystem._physics_process`. La valeur lue est alors la position tick N-1 (correct pour sweep tick N) — MAIS cette dépendance temporelle n'est pas documentée dans ADR-0005 et serait invisible à un dev qui refactore l'ordre. Fragile.
  - **Scaling** : si un jour un 2e consumer (Enemy AI prédictif) a besoin de `player.prev_position`, on garde l'API. Mais `prev_position` est un détail Combat, pas un état Movement partagé. Mauvais design.
- **Rejection Reason** : Combat est le consumer unique, c'est son état interne. Le maintenir dans Combat est plus propre (REQ-3).

### Alternative 3 : Pool pré-alloué dès le MVP (pas d'exemption zero-alloc)

- **Description** : `_pooled_query`, `_seen_ids`, `_merged`, `_tick0_ids` promus membres privés + `.clear()` en entrée `_collect_swing_hits()` / `_tick0_intersect_shape_overlap()`. Aucune exemption ADR-0005 D-9.
- **Pros** :
  - Respecte ADR-0005 D-9 à la lettre. Zero-alloc hot path garanti.
  - Évite le risque AC-CMB-37 FAIL → rollback tardif.
- **Cons** :
  - **Anti-YAGNI** : ~50 lignes de code pool + maintenance invariants (reset correct entre swings, corner cases `_seen_ids` pas clearé → kills du swing précédent ressurgissent) pour résoudre un problème non mesuré.
  - **Surface bug** : pool mal clearé = bug silencieux (kills orphelins comptés double). La version non-pool avec alloc locale est intrinsèquement plus robuste par scope GDScript.
  - **Perf réelle** : les 16 allocs bornées par swing (< 500 KB delta / 1000 cycles selon AC-CMB-37) sont très probablement invisibles dans le profile. Le coût dev + test de la version pool n'est pas justifié sans preuve de besoin.
- **Rejection Reason** : DEC-r5-3 explicite. L'exemption D-8 + rollback conditionnel AC-CMB-37 est le compromis correct pour MVP.

### Alternative 4 : `_get_time_msec` statique helper de classe vs Callable injection

- **Description** : créer une classe helper `class_name Clock extends Object` avec `static func get_ms() -> int: return Time.get_ticks_msec()`. Tests substituent `Clock.get_ms = func(): return _mocked_ms` (pas possible sur static — nécessite injection d'instance).
- **Pros** : namespace clair, utilisable hors Combat (futur Audio, VFX).
- **Cons** :
  - **GDScript static method non-substituable** : on ne peut pas monkey-patch une static method GDScript comme en Python. Il faut soit instancier Clock et faire injection, soit rester Callable.
  - **Callable est idiomatique GDScript 4.x** pour injection test — évite de créer une classe pour un point d'injection mono-usage.
  - **Scope** : Combat MVP n'a qu'un seul callsite wall-clock (Rule 13). AC-CMB-51 Audio est à clarifier ownership (Audio Handler ou Combat). Un Callable local à CombatSystem est suffisant au MVP.
- **Rejection Reason** : Callable par instance est plus simple et idiomatique au MVP. Si un second système nécessite la même injection wall-clock, extraire vers un `Clock` helper à ce moment-là.

### Alternative 5 : Basis helper comme classe autonome `CombatBasisHelper`

- **Description** : extraire `_build_capsule_basis()` dans une classe `class_name CombatBasisHelper extends RefCounted` avec une méthode statique. Utilisé par CombatSystem + potentiellement Enemy AI si un ennemi fait un sweep.
- **Pros** : réutilisable.
- **Cons** :
  - **YAGNI** : un seul consumer au MVP (Combat). L'ennemi ennemi MVP ne sweepe pas — il se tient fixe ou patrouille, sa hitbox sphère est statique.
  - **Lookup overhead** : static method sur RefCounted = lookup de classe par nom. Négligeable mais ajouté sans raison.
  - **Test** : helper statique non-substituable (même problème que Alternative 4). CombatSystem private method testée via AC-CMB-08 qui instantie CombatSystem directement.
- **Rejection Reason** : helper privé de CombatSystem au MVP. Si un 2e sweep user émerge, extraire alors.

## Consequences

### Positive

- **Rule 17 Hybrid mutual kill semantique garantie** : D-1 + D-2 + SYNC `_on_player_died` handler (D-6) + consommation `_death_pending` en fin de tick (D-3) rendent le pattern testable et déterministe. AC-CMB-41 7 assertions + clause (8) grep structural couvrent.
- **Anti-tunneling déterministe** : D-3 (`_prev_position` owned + update en fin) + D-7 (`_build_capsule_basis()` correct) + N_SUBSTEPS=3 constant (GDD Rule 7) = sweep cohérent à V≤30 m/s (seuil théorique V=126 m/s, marge 4×).
- **Testabilité CI complète** : D-4 (4 mocks canoniques) + D-5 (Callable injection) rendent AC-CMB-19 / AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02 déterministes headless, sans dépendre de hardware timing.
- **Pillar 1 FLOW préservé** : exemption SYNC D-6 pour flash blanc (toggle + Tween trivial) + SYNC `died` handler (flag set ≤ 0.01 ms) = zéro latence frame-perceptible sur feedback kill.
- **Zero-alloc discipline maintenue hors exemption** : D-8 documente explicitement 16 alloc/swing avec 4 clauses + AC-37 gate + rollback. Pas de drift silencieux. Registry forbidden_pattern `alloc_in_hot_path_via_literal_dict_or_pushback` reste actif, l'exemption est une exception documentée.
- **CONV-1 basis bug fermé** : D-7 codifie le helper correct + contract mathématique + test AC-CMB-08 100 échantillons sphère unitaire. Régression future détectée en CI.
- **Cohérence cross-ADR** : D-6 étend le pattern ADR-0005 D-5 (direct typed signals, CONNECT_DEFERRED/SYNC policy) pour Combat sans contradiction. Les 2 exemptions SYNC (`died` handler, VFX flash blanc) sont traçables à leur ADR d'origine et ré-déclarées sous l'autorité canonique appropriée.
- **Sprint 1 Combat débloqué** : tous les marqueurs "Pending ADR Combat Tick Model" du GDD r6 APPROVED sont résolus. Les stories Sprint 1 peuvent démarrer dès `/architecture-review` Accepted.

### Negative

- **Couplage scene tree Combat→Player direct child** : contraint la topologie .tscn du Player. Si un refactor futur voulait extraire Combat en module sibling pour raisons de réutilisation (Enemy peut attaquer ?), il faudra amender ADR-0006 et refactor Rule 17 Hybrid. Scope hors MVP.
- **MovementController + CombatSystem sur même physics tick** : D-1 + D-2 garantissent l'ordre mais ils partagent le budget physics 4 ms (ADR-0001). Si Combat + Movement dépassent cumulativement 4 ms, il faudra re-budgéter. Probabilité faible MVP (Movement mesuré théoriquement < 1 ms, Combat swing 8 ticks × ~0.3 ms = 2.4 ms amorti sur 120 ms swing → instantané moyen très faible).
- **16 allocations par swing potentiellement visibles dans profile hardcore** : même avec borne < 500 KB / 1000 cycles, un benchmark très long (100000 cycles = ~2h gameplay) pourrait montrer une croissance. AC-CMB-37 couvre 1000 cycles ; soak test long terme à ajouter en Polish phase.
- **Injection `_get_time_msec` via Callable** : chaque `call()` ajoute ~50 ns vs `Time.get_ticks_msec()` direct. Pour 1-5 calls/tick, impact < 0.001 ms/frame. Négligeable MVP mais mesurable.
- **Documentation overhead** : les 4 mocks sont du code test qui doit être maintenu en sync avec les contrats réels (Enemy System, Movement, Audio, AudioBus). Si un contract change (ex : `enemy_killed` gagne un 3e payload), 2 fichiers mocks à mettre à jour + les ACs dépendants.
- **Deadline Gaps 2/7/8** : l'acceptation finale de l'ADR dépend de 3 tests empiriques lead-programmer pré-Sprint 1. Si un Gap ne peut pas être résolu à temps, ADR reste `Proposed` → Sprint 1 Combat BLOCKED. Risque mitigé par simplicité des tests (scène minimale Godot, ~1h chacun).

### Risks

- **Risk 1 — Refactor scene tree casse D-1/D-2 silencieusement** : un dev déplace CombatSystem dans un wrapper `$Player/Subsystems/CombatSystem` pour "organisation". L'ordre DFS reste parent-avant-enfant mais D-1 n'est pas invalidé, le mécanisme Rule 17 fonctionne encore. CEPENDANT si Subsystems acquiert un `_physics_process` plus tard, l'ordre peut décaler. → **Mitigation** : AC-CMB-49 Partie B (d) `get_parent() == player_node` fail si niveau indirect. Renforcer à `get_parent() == player_node and player_node is CharacterBody3D` pour être strict.
- **Risk 2 — `_prev_position` update en début par erreur** : un dev refactor `_physics_process` et place `_prev_position = _player.global_position` au début (lecture naïve). Bug silencieux : sweep_delta = ZERO → aucun kill. → **Mitigation** : doc comment inline sur le membre `_prev_position` référençant ADR-0006 D-3 avec warning explicite. AC-CMB-47 + AC-CMB-05/06/07 détectent (absence de kill) mais sans pointer la cause.
- **Risk 3 — AC-CMB-37 FAIL → rollback pool tardif** : si le soak détecte fuite après impl MVP, refactor pool = ~50 lignes + re-verif tous les tests Combat (impact ~2 team-days). → **Mitigation** : clause de rollback documentée à l'avance dans D-8. Pattern code déjà rédigé.
- **Risk 4 — Gap 2 / Gap 8 résultat surprise** : test empirique ShapeCast3D overlap origine OU `ShapeCast3D.margin` Jolt comportement inattendu → code Combat à refactor. → **Mitigation** : AC-CMB-47-Prelim (r6 CONV-2) et Gap 8 sont owned lead-programmer pré-Sprint 1 avec deadline stricte. Deux variantes code pattern (A/B) anticipées pour Gap 2. Gap 8 : si margin inconsistant Jolt, fallback `shape_cast.margin = 0.0` explicite.
- **Risk 5 — VFX flash blanc SYNC exemption drift** : un dev tenté de mettre aussi l'Audio clac en SYNC "pour ne pas rater le feedback". Viole D-6. → **Mitigation** : code review strict + annotation `# sync-exempt: ADR-0006 D-6` obligatoire sur toute connexion SYNC. Lint grep annuel sur `src/gameplay/combat/` pour détecter SYNC non whitelistée.
- **Risk 6 — Mocks désynchronisés des contracts réels** : MockEnemy.die() devient idempotent mais le vrai EnemySystem intro plus tard n'est pas idempotent. Tests Combat passent, gameplay casse. → **Mitigation** : quand Enemy System GDD est créé, `/design-review` doit vérifier cohérence `die()` idempotent. Contract tests croisés (`test_mock_enemy_matches_real_enemy_contract.gd`) recommandés post-Enemy GDD.
- **Risk 7 — Injection `_get_time_msec` oubliée en teardown** : test AC-CMB-19 mocke mais n'unset pas `Engine.time_scale = 1.0` en after_each. Test suivant démarre avec slow-mo résiduel → flaky. → **Mitigation** : AC-CMB-19 r6 clause teardown explicite. Helper commun `tests/helpers/combat_time_scale_guard.gd` recommandé pour Sprint 1.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `design/gdd/player-combat-system.md` l. 60 (ownership `_prev_position` Combat) | "Combat est propriétaire exclusif de `_prev_position`, cache en fin de son propre `_physics_process`" | D-3 formalise comme décision architecturale avec code pattern + init `_ready()`. Invariant lifecycle documenté. |
| `design/gdd/player-combat-system.md` Rule 6 l. 63 (sweep setup ShapeCast3D) | Formula 2 `target_position = basis.inverse() * (player.global_position - _prev_position)` | D-7 `_build_capsule_basis()` fournit la `basis` correcte sans inversion 180°. Contract mathématique testable. |
| `design/gdd/player-combat-system.md` Rule 6 r6 CONV-1 FIX (lignes ~87, ~135, ~377, ~931) | Basis via helper centralisé au lieu de `Basis.looking_at * from_euler` | D-7 codifie le helper privé + 4 call sites documentés + AC-CMB-08 test sphère unitaire. |
| `design/gdd/player-combat-system.md` Rule 17 Hybrid (l. 242-253) | Signal `died` connecté SYNC, handler set `_death_pending = true`, consommation fin de tick | D-6 exemption SYNC documentée pour `_on_player_died` + D-3 consommation fin de tick. Re-déclare autorité canonique depuis ADR-0005 amendment r2. |
| `design/gdd/player-combat-system.md` l. 332-334 (invariants structurels scene tree) | "CombatSystem DOIT etre direct child de Player" + "physics_process_priority DOIT rester = 0" | D-1 + D-2 codifient comme décisions canoniques + assert `_ready()` + AC-CMB-49 Partie B. |
| `design/gdd/player-combat-system.md` Addendum r5 l. 158 (exemption ADR-0005 D-9 zero-alloc) | ~16 alloc/swing documentées DEC-r5-3 | D-8 codifie les 4 clauses + clause rollback AC-CMB-37. Cet ADR devient l'autorité sur l'exemption. |
| `design/gdd/player-combat-system.md` AC-CMB-19 DEC-r5-1 (injection Callable wall-clock) | `CombatSystem._get_time_msec: Callable = Time.get_ticks_msec` substituable | D-5 codifie le pattern d'injection + teardown obligatoire + usage cross-consumer. |
| `design/gdd/player-combat-system.md` AC-CMB-51 REC-03 (fade-out swoosh wall-clock injection identique AC-CMB-19) | Pattern identique `_get_time_msec` pour Audio handler | D-5 précise que le pattern couvre tous consumers wall-clock Combat MVP. |
| `design/gdd/player-combat-system.md` AC-CMB-05/06/07 Gap 1 (MockEnemy) | MockEnemy avec `die()` idempotent + `is_dead()` | D-4a fige le contract MockEnemy. |
| `design/gdd/player-combat-system.md` AC-CMB-audio-01 (multi-kill côté Audio, flag `_kill_sound_played_this_swing`) | Contract MockAudioHandler | D-4c fige le contract MockAudioHandler. |
| `design/gdd/player-combat-system.md` AC-CMB-audio-02 (ducking ordering côté Audio) | Contract MockAudioBus log timestamped | D-4d fige le contract MockAudioBus. |
| `design/gdd/player-combat-system.md` AC-CMB-41 clause (8) r6 (grep structural `player.died.connect ... CONNECT_DEFERRED`) | Inspection statique SYNC | D-6 documente le grep pattern comme gate CI. |
| `design/gdd/player-combat-system.md` AC-CMB-52 r6 (assert `Engine.is_in_physics_frame()` dans handler `attacked`) | Garde ADR-0001 violation detection | Cohérent avec D-1/D-2 (`_physics_process` authority) — pattern explicitement autorisé. |
| `docs/architecture/adr-0001-physics-rate-60hz.md` | Autorité gameplay `_physics_process` unique + Jolt | D-1 + D-6 alignés : Combat signals émis depuis `_physics_process` uniquement. Jolt caveat margin noté dans Verification Required (Gap 8). |
| `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md` | `aim_forward` close-form trig roll-invariant | Combat consomme `aim_forward` dans Rule 6 + D-7 `_build_capsule_basis(aim_forward)`. Dépendance unidirectionnelle Camera → Combat respectée. |
| `docs/architecture/adr-0005-movement-signals-architecture.md` D-5 amendment r2 (exemptions SYNC `enemy_killed` flash blanc + `died` Combat handler) | Exemptions non-normatives au sens ADR-0005 (scope note r4) | D-6 récupère l'autorité canonique des exemptions Combat et les re-déclare sous signature ADR-0006. ADR-0005 reste régissant pour signaux Movement uniquement. |
| `docs/architecture/adr-0005-movement-signals-architecture.md` D-7 consumer contract | "Consumer handler ne mute JAMAIS état Movement" | D-6 handler `_on_player_died` mute seulement flag Combat-LOCAL `_death_pending`. ADR-0005 D-7 respecté. |
| `docs/architecture/adr-0005-movement-signals-architecture.md` D-9 zero-alloc | Exemption explicite Combat documentée | D-8 exemption avec 4 clauses + AC-37 gate + rollback conditionnel. |

## Performance Implications

- **CPU** :
  - DFS ordering D-1/D-2 : aucun coût additionnel (comportement par défaut Godot). Les asserts `_ready()` sont exécutés 1× au boot.
  - `_prev_position` update en fin de `_physics_process` (D-3) : 1 assignement Vector3 (value type, 3 floats) = ~50 ns. Négligeable.
  - `_build_capsule_basis()` (D-7) : 2 cross products + 2 normalizations + 1 check determinant = ~500 ns amorti. Appelé 4× par tick Swinging, soit ~2 µs/tick. Sur 8 ticks actifs : ~16 µs par swing. Négligeable.
  - `_get_time_msec.call()` (D-5) : ~50 ns overhead vs direct. 1-5 calls/tick → < 0.001 ms/frame. Négligeable.
  - `_on_player_died` SYNC handler (D-6) : 1 bool assignment = ~10 ns. Négligeable.
  - Signal dispatch Combat (D-6) : 1 emit + N callbacks. Pour peak gameplay (1 swing/0.5s × ~2 `enemy_killed`/swing × 4 consumers moyens) = ~16 dispatches/s × 5 µs = 80 µs/s = 0.0013 ms/frame. Négligeable.
- **Memory** :
  - D-8 exemption documentée : ~16 alloc/swing × ≤ quelques KB chacune = ~5 KB/swing allocation locale. Libéré par GC GDScript à sortie fonction. AC-CMB-37 gate `MEMORY_STATIC` delta ≤ 500 KB / 1000 cycles + `OBJECT_COUNT` delta ≤ 5.
  - MockEnemy / MockMovement / MockAudioHandler / MockAudioBus : fixtures test, pas en production.
  - `_prev_position`, `_get_time_msec`, `_death_pending`, `_state`, `_active_tick`, `_cooldown_timer`, `_hit_this_swing` (borné ≤ 3), `_slow_mo_*` : overhead CombatSystem < 200 bytes.
  - Overhead signal Combat : 4 signals × ~80 bytes (Godot Callable array) = 320 bytes. Fixed boot cost.
- **Load Time** : `_ready()` CombatSystem = 4 asserts + 1 init `_prev_position` + 2 connections signals Player (attacked, died, respawned) = ~100 µs. Négligeable.
- **Network** : non applicable (MVP single-player).
- **Budget registry** : pas de nouvelle entrée dédiée. Combat s'inscrit dans le budget `physics` 4.0 ms (ADR-0001 stub). Affiner post-impl Sprint 1 avec profiler.

## Migration Plan

- **Code** : aucun code Combat n'existe encore dans `src/gameplay/combat/`. Pas de migration. L'implémentation v1 du Sprint 1 Combat sera construite directement selon ADR-0006.
- **Prototype `prototypes/movement-katana/`** : le prototype n'implémente pas Rule 17 Hybrid ni le cache `_prev_position` correct. Non affecté — remplacé par l'implémentation MVP propre au Sprint 1.
- **GDD `player-combat-system.md`** : aucune modification requise. Le GDD r6 APPROVED référence déjà "Pending ADR Combat Tick Model" en multiple endroits — ces références deviennent rétroactivement résolues par ADR-0006 Accepted. Annotation facultative post-Accepted : remplacer dans le GDD `Pending ADR` par `ADR-0006 — adr-0006-combat-tick-model.md` pour traçabilité directe (effort ~10 min).
- **Registry `docs/registry/architecture.yaml`** : nouvelles entrées (détail Step 6 du skill) :
  - 1 `state_ownership` : `_prev_position` → combat-system.
  - 4 `interfaces` : `combat_signals` (swing_started, swing_ended, enemy_killed, multi_kill avec modes connexion), `combat_death_handler_sync` (Combat consumer `died`), `combat_test_mocks` (les 4 mocks canoniques), `combat_time_injection` (`_get_time_msec` Callable).
  - 3 `api_decisions` : `combat_scene_tree_direct_child_of_player`, `combat_physics_process_priority_default_zero`, `combat_time_msec_callable_injection`.
  - 3 `forbidden_patterns` : `combat_system_as_sibling_or_grandchild_of_player`, `combat_physics_process_priority_nonzero`, `combat_prev_position_update_at_start_of_physics_process`.
  - 1 `performance_budgets` (optionnel) : `combat` budget_ms (stub ≤ 1.0 ms à raffiner post-Sprint 1).
  - 1 exemption documentée du forbidden_pattern existant `alloc_in_hot_path_via_literal_dict_or_pushback` → référence ADR-0006 D-8 + gate AC-CMB-37.
- **Tests** : créer les 4 mocks `tests/unit/combat/mock_enemy.gd`, `mock_movement.gd`, `mock_audio_handler.gd`, `mock_audio_bus.gd` selon contracts D-4. Créer `tests/helpers/combat_time_scale_guard.gd` pour teardown `Engine.time_scale = 1.0` commun.
- **Engine reference** : ajouter 2 sections dans `docs/engine-reference/godot/modules/physics.md` (owner lead-programmer, pré-Sprint 1) :
  1. "CapsuleShape3D basis orientation — Godot 4.6 convention" (Gap 7 résolution, support pour D-7).
  2. "ShapeCast3D overlap at origin — Godot 4.6 + Jolt empirical test" (Gap 2 résolution, résultat AC-CMB-47-Prelim).
  3. "ShapeCast3D.margin — Jolt vs GodotPhysics3D comportement" (Gap 8 résolution, support pour choix `margin` par défaut).
- **Control Manifest** (`docs/architecture/control-manifest.md`) : ajouter section Combat Layer :
  - REQUIRED : CombatSystem = direct child Player ; `physics_process_priority == 0` ; `_prev_position` update en FIN de `_physics_process` ; `_build_capsule_basis()` pour tout sweep capsule ; `_get_time_msec` Callable pour wall-clock ; 4 mocks canoniques pour tests.
  - FORBIDDEN : CombatSystem sibling ou grandchild de Player ; `physics_process_priority` non-zero ; `_prev_position` update en début de `_physics_process` ; `Basis.looking_at * from_euler` pour capsule sweep basis ; connect autre que SYNC whitelistée D-6 pour Combat signals ; `_collect_swing_hits` sans clause exemption référençant ADR-0006 D-8.
  - GUARDRAIL : AC-CMB-37 soak 1000 cycles est gate zero-alloc exemption ; grep static AC-CMB-41 clause (8) + AC-CMB-49 Partie B ; teardown `Engine.time_scale = 1.0` obligatoire post-test slow-mo.
- **TR Registry** (`docs/architecture/tr-registry.yaml`) : append entries `TR-cmb-001` à `TR-cmb-N` pour les requirements Combat qui réfèrent ADR-0006 (à produire par `/architecture-review` Phase 8, pas Step 6 de cet ADR).
- **Session state** : marquer `[x]` sur ADR-0006 Proposed ; déclarer next task = "Résoudre Gaps 2/7/8 empiriquement → `/architecture-review` fresh session → ADR-0006 Accepted".

## Validation Criteria

- **VC-DFS (Scene tree DFS parent-before-child — D-1 + D-2)** : `tests/integration/combat/test_scene_tree_dfs_order.gd` — GIVEN scène fixture Player + CombatSystem child + MockEnemy, each logging un timestamp dans `_physics_process` via `Time.get_ticks_usec()`. WHEN 10 physics ticks exécutés. THEN pour chaque tick, `player_timestamp < combat_timestamp` avec delta > 0 µs. ALSO : test fail si fixture replace CombatSystem par sibling (inversion d'ordre ou non-monotone détectée).
- **VC-CHILD (direct-child invariant runtime)** : `tests/unit/combat/test_structural_invariants.gd` — GIVEN CombatSystem instancié comme child de CharacterBody3D. WHEN `_ready()` exécuté. THEN `get_parent() == player` assertion PASSE. AUTRE fixture CombatSystem comme child d'un Node wrapper → `_ready()` assertion FAIL en debug build (`assert` push_error).
- **VC-PRIORITY (physics_process_priority == 0 invariant)** : même fichier test, WHEN `combat.physics_process_priority = -1` avant `_ready()`. THEN `_ready()` assertion FAIL.
- **VC-PREV-POS (update en fin de `_physics_process` — D-3)** : `tests/integration/combat/test_prev_position_end_of_tick.gd` — GIVEN MockMovement Player + CombatSystem child. WHEN Player bouge de `(0,0,0)` à `(1,0,0)` au tick N, Combat exécute son `_physics_process` au tick N. THEN au DÉBUT du tick N+1, `combat._prev_position == Vector3(1,0,0)` (position tick N), pas `Vector3(0,0,0)` (position tick N-1 qui aurait été stale update au début) ni `Vector3(2,0,0)` (position tick N+1 qui aurait été update au début). Vérifie le timing d'update.
- **VC-BASIS (helper `_build_capsule_basis()` contract — D-7)** : couvert par AC-CMB-08 r6 (100 échantillons sphère unitaire, `(basis * Vector3.UP).angle_to(aim) < 0.001 rad`).
- **VC-SYNC-DIED (Combat SYNC handler `died` — D-6)** : `tests/integration/combat/test_death_handler_sync.gd` — GIVEN MockMovement + CombatSystem. WHEN `mock_movement.trigger_died()` émis. THEN immédiatement (avant retour de `trigger_died()`), `combat._death_pending == true`, `combat._state == Swinging` (pas encore transitionné). AUTRE test : grep statique `grep -nE 'player\.died\.connect.*CONNECT_DEFERRED' src/gameplay/combat/combat_system.gd` retourne 0 match. Couvre AC-CMB-41 clause (8).
- **VC-SYNC-FLASH (VFX flash blanc SYNC exemption — D-6)** : `tests/integration/combat/test_vfx_flash_sync.gd` — GIVEN MockVFXFlash (ColorRect wrapper) connecté à `enemy_killed` en SYNC. WHEN MockEnemy tué par sweep tick N. THEN au tick N (avant retour de `CombatSystem._physics_process`), `MockVFXFlash.visible == true`. AUTRE test fixture MockVFXFlashBloated (instancie GPUParticles3D dans handler) connecté SYNC → assertion debug build fail (code review catch + lint grep).
- **VC-ZA (Zero-alloc exemption soak — D-8)** : couvert par AC-CMB-37 (1000 cycles, seuils 500 KB MEMORY_STATIC + 5 OBJECT_COUNT).
- **VC-INJECT (`_get_time_msec` Callable injection — D-5)** : couvert par AC-CMB-19 (slow-mo expiration wall-clock mocké) et AC-CMB-51 (swoosh fade-out wall-clock mocké).
- **VC-MOCK-ENEMY** : `tests/unit/combat/test_mock_enemy_contract.gd` — GIVEN MockEnemy instancié. WHEN `die()` appelé 2×. THEN `_die_call_count == 1`, `is_dead() == true`. Vérifie idempotence.
- **VC-MOCK-MOVEMENT** : `tests/unit/combat/test_mock_movement_contract.gd` — GIVEN MockMovement + test harness connectant `attacked`, `died`, `respawned`. WHEN `trigger_attacked()` / `trigger_died()` / `trigger_respawned(pos)`. THEN signals reçus dans l'ordre avec payload correct. `state` lecture retourne enum correct.
- **VC-MOCK-AUDIO-HANDLER** : couvert par AC-CMB-audio-01 (multi-kill flag `_kill_sound_played_this_swing`).
- **VC-MOCK-AUDIO-BUS** : couvert par AC-CMB-audio-02 (log ducking events timestamped).
- **VC-GAP2 (AC-CMB-47-Prelim)** : test empirique owner lead-programmer pré-Sprint 1, résultat consigné dans engine-reference. Détermine Variante A vs B pour AC-CMB-47.
- **VC-GAP7 (pattern CapsuleShape3D basis documenté)** : lead-programmer append section dans `docs/engine-reference/godot/modules/physics.md`. Vérifié par grep "CapsuleShape3D basis orientation — Godot 4.6 convention" retourne 1 match.
- **VC-GAP8 (ShapeCast3D.margin Jolt)** : test empirique owner lead-programmer pré-Sprint 1, résultat consigné dans engine-reference.

Si VC-DFS échoue → re-parenter CombatSystem comme direct child strict. Si VC-CHILD échoue → fix scene .tscn (template Player prefab).
Si VC-PREV-POS échoue → grep `_prev_position =` dans combat_system.gd, vérifier ordre dans `_physics_process` (doit être dernière ligne).
Si VC-BASIS (AC-CMB-08) échoue → vérifier que `_build_capsule_basis` utilise bien cross product direct, pas `Basis.looking_at * from_euler`.
Si VC-ZA (AC-CMB-37) échoue → activer rollback pool pré-alloué selon D-8 clause de rollback conditionnel.
Si VC-SYNC-* échoue → vérifier patterns de connexion + grep lint.

## Related Decisions

- **ADR-0001 (Physics Rate 60 Hz + Jolt)** — Amont direct. D-1 + D-6 appliquent l'autorité `_physics_process`. Jolt caveat margin résolu via Gap 8 verification.
- **ADR-0002 (Camera Scene Tree CameraArm)** — Amont. Combat consomme `aim_forward` close-form trig dans Rule 6 + D-7. Dépendance unidirectionnelle Camera → Combat confirmée.
- **ADR-0005 (Movement Signals Architecture)** — Amont direct. D-6 étend policy D-5 pour Combat signals ; re-déclare les 2 exemptions SYNC sous autorité ADR-0006. D-8 exempts explicitement de D-9 avec clauses + rollback. D-7 respecté (handler `_on_player_died` mute uniquement flag Combat-LOCAL).
- **ADR-0004 (Input API & Focus Handling)** — Indirect. `InputManager.was_pressed_this_tick(&"attack")` consommé par Movement, forwardé via signal `attacked` (ADR-0005 D-2), lu par Combat dans `_on_player_attacked` handler (assert `Engine.is_in_physics_frame()` AC-CMB-52).
- **Futur ADR Enemy AI** — Consumer potentiel du Mock canonique étendu. Contract `MockEnemy` posé ici sera étendu (ajout AI behavior) ou classe concrète héritera.
- **Futur ADR VFX Combat** — Consumer de `enemy_killed`. Devra documenter les 4 consumers DEFERRED + 1 SYNC exemption (ColorRect flash blanc) en référençant ADR-0006 D-6.
- **Futur ADR Audio Combat** — Consumer de tous signals Combat. Devra documenter `CONNECT_DEFERRED` pour clac + blood ambiance (D-5 critère (b) ADR-0005). Ownership `_get_time_msec` pour fade-out swoosh à clarifier (Combat vs Audio Handler).
- **Futur `.claude/rules/combat-scene-tree-direct-child.md`** — lint qui enforce D-1 (grep scene .tscn root nodes).
- **Futur `.claude/rules/combat-prev-position-end-of-tick.md`** — lint qui enforce D-3 (vérifie ordre assignment dans `_physics_process`).
- **Futur `.claude/rules/combat-sync-exemption-whitelist.md`** — lint qui enforce D-6 (whitelist SYNC connections).

---

*Auteur : Architecture Decision skill, 2026-04-23 (lead-programmer), solo mode (TD-ADR gate + engine-specialist gate skipped).*
*Source directe : GDD `design/gdd/player-combat-system.md` r6 APPROVED 2026-04-23, marqueur "Pending ADR Combat Tick Model" (ligne 8), DEC-r5-1 (injection Callable), DEC-r5-3 (exemption zero-alloc ~16 alloc/swing), r5.2 CONV-1 (helper `_build_capsule_basis()`), invariants structurels l. 332-334 (AC-CMB-49 Partie B).*
*Gaps owned pré-Sprint 1 : Gap 1 MockEnemy (résolu par D-4a), Gap 2 ShapeCast3D overlap origine (VC-GAP2 + AC-CMB-47-Prelim), Gap 7 CapsuleShape3D basis pattern (VC-GAP7), Gap 8 ShapeCast3D.margin Jolt (VC-GAP8).*
*Validation indépendante requise : `/architecture-review` fresh session avant transition Proposed → Accepted.*
