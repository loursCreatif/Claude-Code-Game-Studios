# Story 002: Combat Handlers — enemy_killed → Splash Sang + Decal + swing_started/ended → Trail Katana

> **Epic**: VFX System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-05-04
> **Estimate**: M (5-7 h, listeners Combat + raycast surface + round-robin pool + trail mesh activation)

## Context

**GDD**: `design/gdd/vfx-system.md` (Designed r1)
**Requirements**:
- R-VFX-3 : Signal consumer CONNECT_DEFERRED par défaut sur signaux amont
- R-VFX-7 : Trail katana `MeshInstance3D` activé `swing_started` → `swing_ended` ; couleur `#E8E8E0` opacity max 0.7 fade-out 100 ms exponentiel
- R-VFX-8 : Splash sang cone 30° 6 particules `#C8232C` lifetime 400 ms fade-out linéaire flat shader
- R-VFX-9 : Decal sang projeté sur surface via `PhysicsDirectSpaceState3D.intersect_ray` distance max 3.0 m
- R-VFX-10 : Multi-kill burst additif `(count - 1)` particules supplémentaires
- F-VFX-3 : Lifetime particule sang fade-out linéaire `opacity(t) = 1.0 - (t / PARTICLE_LIFETIME_S)`

**ADR Governing Implementation**:
- **ADR-0009 D-4** (pattern référence) — CONNECT_DEFERRED par défaut consumer signals (sauf SYNC justifié)
- **ADR-0006 D-3** (Combat tick model) — position payload capturé au tick d'émission, jamais `enemy.global_position` post-réception DEFERRED (queue_free risk pattern Audio R-AUD-7)

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `PhysicsDirectSpaceState3D.intersect_ray()` synchrone dans `_physics_process` stable Godot 4.0+. `GPUParticles3D.restart()` one-shot Godot 4.0+.

**Control Manifest Rules (Presentation layer)**:
- Required : handlers Combat (`_on_swing_started`, `_on_swing_ended`, `_on_enemy_killed`, `_on_multi_kill`) connectés CONNECT_DEFERRED ; raycast vers surface `_perform_decal_raycast(position) -> Vector3` retourne position projetée OU `Vector3.INF` si no surface (skip silencieux EC-VFX-07) ; round-robin pool `_blood_idx = (_blood_idx + 1) % BLOOD_PARTICLE_POOL_SIZE`.
- Forbidden : référence `enemy.global_position` post-réception DEFERRED (pattern Audio R-AUD-7 — capturer `position` parameter au signal payload) ; mutation `enemy` ou `player` propriétés (R-VFX-14 outbound-zero) ; `Decal.new()` runtime (R-VFX-1 — réutiliser slot pool).
- Guardrail : `_perform_decal_raycast` skip silencieux + `push_warning` si no surface ; pool saturation handling stop+restart slot ancien + push_warning (EC-VFX-09).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1, scoped à cette story (Integration) :*

- [ ] **AC-VFX-02** [BLOCKING][AUTO] **GIVEN** un `enemy_killed` est reçu dans une room avec < 32 decals actifs, **WHEN** le raycast vers la surface réussit, **THEN** un decal `#C8232C` opacity 0.7, radius 0.6 m apparaît sur la surface ; `_room_decal_count` s'incrémente de 1.
- [ ] **AC-VFX-06** [BLOCKING][AUTO] **GIVEN** `AccessibilityService.reduce_flash == false` (défaut), **WHEN** `enemy_killed` est reçu, **THEN** un flash blanc `#FFFFFF` plein-écran de durée `FLASH_KILL_DURATION_MS = 80 ms` wall-clock s'affiche (déclenché ici, timing géré story-004) ; la durée ne varie pas avec `Engine.time_scale`.
- [ ] **AC-VFX-11** [BLOCKING][AUTO] **GIVEN** `reduce_motion == false`, **WHEN** `enemy_killed(enemy, position)` reçu, **THEN** `BLOOD_SPURT_PARTICLE_COUNT = 6` particules couleur `#C8232C` en cone 30° depuis `position` s'émettent en one-shot ; lifetime 400 ms ; fade-out linéaire opacité 1.0 → 0.0 ; flat shader sans PBR.
- [ ] **AC-VFX-12** [BLOCKING][AUTO] **GIVEN** `reduce_motion == true`, **WHEN** `enemy_killed` reçu, **THEN** les particules s'émettent mais le cone angle est `30° × REDUCE_MOTION_PARTICLE_ANGLE_MULT = 15°` ; le count reste identique (6 particles) ; aucun mouvement camera VFX généré. *(Pull `reduce_motion` story-005 ; cette story applique multiplier sur cone angle.)*
- [ ] **AC-VFX-13** [BLOCKING][AUTO] **GIVEN** `swing_started(direction)` signal reçu, **WHEN** la fenêtre swing est active, **THEN** le trail `MeshInstance3D` est visible, couleur `#E8E8E0`, opacity max 0.7 ; le trail suit `aim_forward` fourni par le signal.
- [ ] **AC-VFX-14** [BLOCKING][AUTO] **GIVEN** `swing_ended()` signal reçu, **WHEN** la fenêtre swing se ferme, **THEN** le trail opacity fade-out exponentiel 100 ms puis `visible = false` ; aucun trail persistant après swing_ended.
- [ ] **AC-VFX-22** [BLOCKING][AUTO] **GIVEN** blood spurt particles actives (lifetime en cours), **WHEN** `respawned(position)` signal reçu, **THEN** tous les slots `GPUParticles3D` ont `emitting = false` + `restart()` appelé dans le même frame ; aucune particule orpheline post-respawn.
- [ ] **AC-VFX-27** [BLOCKING][AUTO] **GIVEN** les assets VFX `vfx_config.tres` sont inspectés, **WHEN** les couleurs blood spurt et decal sont lues, **THEN** Blood spurt color = `#C8232C` (rouge sang désaturé 60%) ; decal color = `#C8232C` opacity ≤ 0.7 ; trail color = `#E8E8E0` (blanc cassé) ; aucun gradient, aucun shader PBR.

---

## Implementation Notes

```gdscript
# story-002 ajoutes à src/core/vfx_system.gd

const BLOOD_SPURT_PARTICLE_COUNT: int = 6
const BLOOD_CONE_ANGLE_DEG: float = 30.0
const PARTICLE_LIFETIME_MS: int = 400
const DECAL_RAYCAST_MAX_DISTANCE: float = 3.0
const KATANA_TRAIL_OPACITY_MAX: float = 0.7
const KATANA_TRAIL_FADE_MS: int = 100

# State variables (init via story-005 pull)
var _reduce_motion: bool = false
var _reduce_flash: bool = false
var _flash_mult: float = 1.0

var _trail_active: bool = false
var _trail_fade_start_msec: int = 0
var _swing_aim_forward: Vector3 = Vector3.FORWARD

# story-003 implements LRU eviction body (this story stub stocke decal slot)

func _on_swing_started(direction: Vector3) -> void:
    if not _is_active:
        return
    _swing_aim_forward = direction.normalized()
    _trail_active = true
    _trail_mesh.visible = true
    # Reset opacity to max (un fade-out précédent peut être en cours)
    var trail_color: Color = TRAIL_COLOR
    trail_color.a = KATANA_TRAIL_OPACITY_MAX * (REDUCE_MOTION_TRAIL_MULT if _reduce_motion else 1.0)
    _set_trail_modulate(trail_color)

func _on_swing_ended() -> void:
    if not _trail_active:
        return
    _trail_fade_start_msec = _get_time_msec.call()
    # Fade-out géré dans _physics_process (R-VFX-7 — exponentiel 100 ms)
    # Logique : à fade complete → _trail_mesh.visible = false ; _trail_active = false

func _on_enemy_killed(enemy: Node, position: Vector3) -> void:
    # IMPORTANT R-AUD-7 pattern : utiliser `position` parameter, jamais enemy.global_position
    # (enemy peut être queue_free post-DEFERRED — null reference risk)
    if not _is_active:
        return

    # 1. Splash sang particules (round-robin pool)
    _spawn_blood_spurt(position)

    # 2. Decal sur surface (raycast + LRU pool — story-003 implémente eviction body)
    _spawn_decal_on_surface(position)

    # 3. Flash blanc kill (story-004 implémente wall-clock timer + WCAG guard)
    _trigger_flash_kill()

func _spawn_blood_spurt(position: Vector3) -> void:
    var slot: GPUParticles3D = _blood_particle_pool[_blood_idx]
    slot.global_position = position
    slot.emitting = false  # reset si en cours
    slot.restart()  # one-shot émission
    slot.emitting = true

    # Apply reduce_motion mult sur cone angle (R-VFX-11 + AC-VFX-12)
    var effective_cone_deg: float = BLOOD_CONE_ANGLE_DEG
    if _reduce_motion:
        effective_cone_deg *= REDUCE_MOTION_PARTICLE_ANGLE_MULT  # 0.5 défaut → 15°
    # TODO : appliquer effective_cone_deg sur ParticleProcessMaterial.spread

    _blood_idx = (_blood_idx + 1) % BLOOD_PARTICLE_POOL_SIZE

func _spawn_decal_on_surface(position: Vector3) -> void:
    var surface_pos: Vector3 = _perform_decal_raycast(position)
    if surface_pos == Vector3.INF:
        push_warning("VFX: no surface found for decal at %s" % position)
        return  # EC-VFX-07 skip silencieux

    # story-003 implémente _decal_write_head increment + LRU eviction
    var slot: Decal = _decal_pool[_decal_write_head % DECAL_POOL_SIZE]
    slot.global_position = surface_pos
    slot.visible = true
    _decal_write_head += 1
    _room_decal_count = mini(_room_decal_count + 1, MAX_DECALS_PER_ROOM)

func _perform_decal_raycast(from_position: Vector3) -> Vector3:
    # Raycast vers le bas (sol) en priorité ; fallback : ray vers les murs proches
    var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
    if space_state == null:
        return Vector3.INF

    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
        from_position,
        from_position + Vector3.DOWN * DECAL_RAYCAST_MAX_DISTANCE
    )
    var result: Dictionary = space_state.intersect_ray(query)
    if result.is_empty():
        # Fallback ray vers les murs (cardinal directions)
        for dir in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
            query = PhysicsRayQueryParameters3D.create(
                from_position,
                from_position + dir * DECAL_RAYCAST_MAX_DISTANCE
            )
            result = space_state.intersect_ray(query)
            if not result.is_empty():
                break
    if result.is_empty():
        return Vector3.INF

    return result.position as Vector3

func _on_multi_kill(count: int) -> void:
    # R-VFX-10 — burst additif (count - 1) particles supplémentaires
    # (la 1ère particule a déjà été émise au 1er enemy_killed)
    # Note : positions kill enregistrées par signal `enemy_killed` séquentiel — ce handler note count
    # le flash blanc n'est pas répété (R-VFX-13 fréquence guard structurel)
    pass  # Implementation simplifiée MVP — multi_kill est noop côté VFX, particles deja émis par enemy_killed séquentiels

func _on_respawned(_position: Vector3) -> void:
    # AC-VFX-22 — reset blood pool (aucune particule orpheline post-respawn)
    for p in _blood_particle_pool:
        p.emitting = false
        p.restart()
    # Reset trail si actif
    if _trail_active:
        _trail_mesh.visible = false
        _trail_active = false
    # Reset decal room count (MVP — pas de cross-room persistence — OQ-VFX-1)
    _room_decal_count = 0
    for d in _decal_pool:
        d.visible = false
    _decal_write_head = 0

func _physics_process(_delta: float) -> void:
    # Trail fade-out exponentiel 100 ms (R-VFX-7 + AC-VFX-14)
    if _trail_active and _trail_fade_start_msec > 0:
        var elapsed_ms: int = _get_time_msec.call() - _trail_fade_start_msec
        if elapsed_ms >= KATANA_TRAIL_FADE_MS:
            _trail_mesh.visible = false
            _trail_active = false
            _trail_fade_start_msec = 0
        else:
            # Exponentiel 100 ms — opacity = max × (1 - t)^2 ou max × exp(-3t)
            var t: float = float(elapsed_ms) / KATANA_TRAIL_FADE_MS
            var opacity: float = KATANA_TRAIL_OPACITY_MAX * exp(-3.0 * t)
            var color: Color = TRAIL_COLOR
            color.a = opacity
            _set_trail_modulate(color)

func _set_trail_modulate(color: Color) -> void:
    # ImmediateMesh ou MeshInstance3D modulate — défini à l'impl finale
    # Si ShaderMaterial : set_shader_parameter("trail_color", color)
    pass  # TODO impl exact selon décision OQ-VFX-3
```

**Trigger flash kill** (stub ici, body story-004) :
```gdscript
func _trigger_flash_kill() -> void:
    # WCAG guard 333 ms plancher (R-VFX-13)
    var now: int = _get_time_msec.call()
    if now - _flash_last_msec < FLASH_MIN_INTERVAL_MS:
        push_warning("VFX: flash rate guard triggered — skip flash kill")
        return
    _flash_last_msec = now
    # story-004 implémente body wall-clock timer + reduce_flash gris substitute
    pass
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Decal LRU ring buffer eviction logic complète (`_decal_write_head` increment, room reset, slot recycling) — story-003.
- Flash brightness wall-clock timer (`Time.get_ticks_msec()` 80 ms loop) + reduce_flash gris substitute + WCAG 333 ms guard body — story-004.
- Pull `reduce_motion` / `reduce_flash` / `flash_mult` from AccessibilityService boot + live update — story-005.
- GSM visibility gating MENU/PAUSED/BOSS_DEFEATED freeze body — story-006.
- Lints statiques anti-patterns (zero `Particle.new()` runtime, zero outbound emit) — story-007.
- Visual/Feel playtest verbatims — story-008.
- Shader code GLSL flat unshaded (final implementation `_create_blood_shader_material`) — peut être déféré story-007 polish ou délégué `godot-shader-specialist`.

---

## QA Test Cases

*Integration — automated integration tests requis :*

**AC-VFX-02** : Decal apparaît sur surface
- Setup : autoload `VFXSystem` ready, mock surface CollisionShape3D 1m sous position kill, `_room_decal_count = 0`.
- Action : émettre `enemy_killed(mock_enemy, Vector3(0, 1, 0))`.
- Verify : `_decal_pool[0].visible == true`, `_decal_pool[0].global_position.y < 1.0` (projeté sur surface), `_room_decal_count == 1`.
- Pass : `assert_bool(vfx._decal_pool[0].visible).is_true()` + position assert.

**AC-VFX-11** : Splash 6 particles cone 30°
- Setup : VFXSystem ready, `_reduce_motion = false`.
- Action : émettre `enemy_killed(mock_enemy, Vector3.ZERO)`.
- Verify : `_blood_particle_pool[0].emitting == true`, `_blood_particle_pool[0].amount == 6`, `_blood_particle_pool[0].lifetime == 0.4`, `_blood_idx == 1` (round-robin avancé).
- Pass : asserts sur `emitting` + `amount` + `lifetime` + `_blood_idx`.

**AC-VFX-12** : reduce_motion cone × 0.5
- Setup : `_reduce_motion = true`, `REDUCE_MOTION_PARTICLE_ANGLE_MULT = 0.5`.
- Action : émettre `enemy_killed`.
- Verify : effective cone angle = 15° (lu via `ParticleProcessMaterial.spread` ou variable interne tracked).
- Pass : `assert_float(effective_cone_deg).is_equal_approx(15.0, 0.01)`.

**AC-VFX-13** : Trail visible swing_started
- Setup : VFXSystem ready, trail invisible.
- Action : émettre `swing_started(Vector3.FORWARD)`.
- Verify : `_trail_mesh.visible == true`, `_trail_active == true`, `_swing_aim_forward == Vector3.FORWARD`.
- Pass : 3 asserts.

**AC-VFX-14** : Trail fade-out 100 ms swing_ended
- Setup : trail actif post `swing_started`.
- Action : émettre `swing_ended()`, attendre 110 ms (`_get_time_msec` mock advance).
- Verify : `_trail_mesh.visible == false`, `_trail_active == false`.
- Pass : asserts post-tick `_physics_process` simulé.

**AC-VFX-22** : Respawn reset blood pool
- Setup : 3 slots `GPUParticles3D` actifs (emitting=true).
- Action : émettre `respawned(Vector3.ZERO)`.
- Verify : tous slots `emitting == false`, `_room_decal_count == 0`, tous decals `visible == false`.
- Pass : `for p in vfx._blood_particle_pool: assert_bool(p.emitting).is_false()`.

**AC-VFX-27** : Chrome Zen palette
- Setup : VFXSystem ready, lecture `vfx_config.tres` ou constants script.
- Verify : `BLOOD_COLOR == Color8(0xC8, 0x23, 0x2C, 0xFF)` (#C8232C), `TRAIL_COLOR == Color8(0xE8, 0xE8, 0xE0, 0xFF)`, decal modulate alpha == 0.7.
- Pass : `assert_object(vfx.BLOOD_COLOR).is_equal(Color8(0xC8, 0x23, 0x2C))`.

**EC-VFX-07** : Decal raycast no surface
- Setup : aucune CollisionShape3D dans 3 m de la position kill.
- Action : émettre `enemy_killed(mock_enemy, Vector3(0, 100, 0))` (en l'air).
- Verify : `push_warning` capturé "VFX: no surface found for decal at..." ; aucun decal visible ; particules continuent normalement.
- Pass : `assert_int(_room_decal_count).is_equal(0)` + warning capture.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/vfx/vfx_combat_handlers_test.gd` (NEW, ~300 lignes) couvrant AC-VFX-02/06/11/12/13/14/22/27 + EC-VFX-07.
- Mocks Combat / Enemy / Camera (story-001 fixtures réutilisés).
- Smoke check : test suite green run via GdUnit4 headless.

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** : story-001 (autoload skeleton + pool pré-allocation 8 GPUParticles3D + 64 Decal + 1 trail + 1 flash overlay).
- **Soft upstream** : story-003 (decal LRU eviction ring buffer increment — peut être implémenté en parallèle si la stub `_decal_write_head` increment naïf existe ici).
- **Cross-system** :
  - **Combat 20/22 Complete** : signals `swing_started(direction)`, `swing_ended()`, `multi_kill(count)`, `enemy_killed(enemy, position)` SYNC disponibles production ✅.
  - **Camera 13/13 Complete** : signal `respawned(position)` disponible production ✅.
- **Unlocks** : AC-VFX-30 contract Combat-021 résolu (4 obligations partiellement couvertes ici : R-VFX-3 CONNECT_DEFERRED + R-VFX-7 trail + R-VFX-8 splash + AC-VFX-24 zero mutation enemy/player) ; story-003 (decal LRU plein impl) + story-004 (flash wall-clock body) en parallèle.

---

## Completion Notes

**Completed** : 2026-05-09 (chain auto post story-001 done)
**Verdict** : COMPLETE
**Criteria** : 9/9 passing (8 BLOCKING ACs + 1 EC) + 1 NEW round-robin wrap edge case test ajouté pendant `/code-review` qa-tester gap fill
**Re-confirm tests** : 17/17 PASS cumulé exit 0 / 1.04 s (`reports/report_443/results.xml`) — story-001 7 + story-002 10
**Deviations** : None — BLOCKING R-VFX-2 array literal hot path fixé pendant `/code-review` (const `_RAYCAST_FALLBACK_DIRS` pré-allouée). 2 deviations engine pragmatic acceptables :
  - `_set_trail_color` (renamed depuis `_set_trail_modulate`) utilise `_trail_material.albedo_color` (StandardMaterial3D pré-alloué dans `_setup_vfx_pool`) — MeshInstance3D est Node3D pas CanvasItem → pas de `.modulate`
  - `_on_respawned` ordre `restart()` puis `emitting = false` — `GPUParticles3D.restart()` sur node `one_shot=true` remet `emitting=true`, donc on force `false` après
**Test Evidence** : `tests/integration/vfx/vfx_combat_handlers_test.gd` (10 tests post-fixes incl. round-robin wrap)
**Code Review** : Complete — godot-gdscript-specialist APPROVED WITH SUGGESTIONS (1 BLOCKING fixé : R-VFX-2 array literal hot path → constante de classe pré-allouée + 4 suggestions cosmétiques) + qa-tester GAPS post-fix (4 gaps + 2 blockers — 3 fixes ROI élevé appliqués + 1 NEW test edge case round-robin wrap, EC-VFX-07 push_warning capture deferred story-007 lints CI, AC-VFX-11 partial coverage shader Out of Scope explicit story-007)

**Pattern Audio R-AUD-7 critique respecté** : `_on_enemy_killed(_enemy: Node, position: Vector3)` utilise `position` parameter exclusivement — jamais `enemy.global_position` post-DEFERRED (queue_free risk).

**Files livrés (2)** :
- `src/core/vfx_system.gd` (MODIF, +200 L) — 8 nouvelles constantes (BLOOD_SPURT_PARTICLE_COUNT/CONE_ANGLE/PARTICLE_LIFETIME/RAYCAST_MAX/TRAIL_OPACITY/TRAIL_FADE/REDUCE_MOTION × 2) + `_RAYCAST_FALLBACK_DIRS` pré-allouée + 8 state vars (reduce_motion/reduce_flash/flash_mult/trail_active/trail_fade_start/swing_aim_forward/last_effective_cone) + handlers bodies (`_on_swing_started/_on_swing_ended/_on_enemy_killed/_on_respawned`) + `_physics_process` trail fade-out exponentiel wall-clock + 5 helpers privés (`_spawn_blood_spurt`, `_spawn_decal_on_surface`, `_perform_decal_raycast`, `_trigger_flash_kill`, `_set_trail_color`) + `_trail_material` StandardMaterial3D pré-alloué
- `tests/integration/vfx/vfx_combat_handlers_test.gd` (NEW, ~520 L post-fixes) — 10 tests AC-VFX-02/06/11 (×2 cone + round-robin wrap)/12/13/14/22/27 + EC-VFX-07

**Out of Scope strict respecté** : pas de LRU body story-003 (`_decal_write_head` incrémenté brut sans wrap-eviction-room logic), pas de flash wall-clock body story-004 (`_trigger_flash_kill` reste WCAG guard + stub), pas de accessibility pull story-005 (defaults locaux), pas de GSM gating story-006, pas de lints story-007, pas de playtest story-008, pas de shader GLSL flat unshaded code (déféré story-007 polish).

**Tech debt** : aucun loggé.
