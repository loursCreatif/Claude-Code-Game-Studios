# Story 001: Autoload Skeleton + Pool Pré-Allocation Zero-Alloc

> **Epic**: VFX System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-04
> **Estimate**: M (4-6 h, autoload skeleton + pool pré-allocation 74 nodes + project.godot registration + scene tree minimal + stub handlers)

## Context

**GDD**: `design/gdd/vfx-system.md` (Designed r1)
**Requirements** (R-VFX stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-VFX-1 : Autoload pool exclusive — `GPUParticles3D.new()` / `Decal.new()` / `MeshInstance3D.new()` interdits hors `src/core/vfx_system.gd`
- R-VFX-2 : Pool pré-alloué au boot — `BLOOD_PARTICLE_POOL_SIZE = 8` + `DECAL_POOL_SIZE = 64` + 1 trail mesh + 1 flash overlay CanvasLayer
- R-VFX-16 : Draw calls VFX < 50 par frame ; un seul `ShaderMaterial` partagé pour particules sang
*(TR-vfx-* IDs non encore présents dans `tr-registry.yaml` — référence directe R-VFX/AC-VFX GDD r1.)*

**ADR Governing Implementation**:
- **ADR-0009 D-2** (pattern référence) — pool exclusive : seul `src/core/vfx_system.gd` instancie nodes VFX runtime ; consumers passent par API publique (`play_kill_at`, `start_katana_trail`, etc.)
- **ADR-0001** (60 Hz physics) — pool boot one-shot dans `_ready()` avant 1ère frame physics ; aucune alloc dans `_physics_process` / `_process`

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: APIs `GPUParticles3D` + `Decal` + `MeshInstance3D` + `ColorRect` + `CanvasLayer` + `Node` stables Godot 4.0+. Aucun breaking change 4.4-4.6 attendu.

**Control Manifest Rules (Presentation layer)**:
- Required : autoload registered AVANT 1ère scene Game ; pool 74 nodes pré-alloués + ajoutés scene tree au `_ready()` (8 GPUParticles3D + 64 Decal + 1 MeshInstance3D trail + 1 CanvasLayer flash overlay) ; un seul `ShaderMaterial` partagé pour particules sang (R-VFX-16) ; assert ordre autoload defensive (`assert(GameStateManager != null and is_instance_valid(AccessibilityService) or true)` — guard EC-VFX-08).
- Forbidden : appel `get_node("/root/CombatSystem")` ou tout consumer downstream (R-VFX-14 outbound-zero terminal) ; `GPUParticles3D.new()` / `Decal.new()` / `MeshInstance3D.new()` dans `_physics_process` / handlers signal (R-VFX-2 zero-alloc hot path) ; `emit_signal` / `.emit(` dans `vfx_system.gd` (R-VFX-14).
- Guardrail : pas de hot path runtime dans cette story — autoload skeleton boot one-shot uniquement (alloc tolérée `_ready()` exception unique).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1, scoped à cette story (Logic) :*

- [ ] **AC-VFX-04** [BLOCKING][AUTO] **GIVEN** un profile mémoire GdUnit4 headless est exécuté sur 60 secondes de gameplay simulé avec 30 kills, **WHEN** le système VFX est actif, **THEN** `MEMORY_STATIC` delta sur 60 s < 16 KB (pas de `Decal.new()`, `GPUParticles3D.new()`, `MeshInstance3D.new()` dans les hot paths post-boot). *(Mesure portée story-001 : pool pré-alloué dans `_ready()`. Validation runtime déférée story-007 lint static + story-002+ stress test.)*
- [ ] **AC-VFX-05** [BLOCKING][AUTO] **GIVEN** le code VFX est scanné par le lint statique CI, **WHEN** `grep -rE "GPUParticles3D\.new\(\)|Decal\.new\(\)|MeshInstance3D\.new\(\)" src/ | grep -v src/core/vfx_system.gd`, **THEN** zéro match (aucune instanciation VFX hors `vfx_system.gd`). *(Lint final story-007 ; cette story s'assure que `vfx_system.gd` est l'**unique** site d'instanciation.)*
- [ ] **AC-NEW-01** [BLOCKING][AUTO] **GIVEN** `VFXSystem._ready()` s'exécute, **THEN** scene tree contient :
  - 1 × `CanvasLayer` "VFXFlashOverlay" enfant direct VFXSystem
  - 1 × `ColorRect` plein-écran enfant CanvasLayer (`mouse_filter = MOUSE_FILTER_IGNORE`)
  - 1 × `Node3D` "VFXPool3D" parent des 8 `GPUParticles3D` + 64 `Decal` + 1 `MeshInstance3D` trail
  - assert exact `_blood_particle_pool.size() == 8`, `_decal_pool.size() == 64`, `_trail_mesh != null`, `_flash_overlay_rect != null`
- [ ] **AC-NEW-02** [BLOCKING][AUTO] **GIVEN** pool pré-alloué, **WHEN** `_ready()` complet, **THEN** tous les `GPUParticles3D` ont `emitting = false`, `one_shot = true`, et tous les `Decal` ont `visible = false` ; trail `MeshInstance3D.visible = false` ; flash overlay `ColorRect.visible = false`.
- [ ] **AC-NEW-03** [BLOCKING][AUTO] **GIVEN** `BLOOD_PARTICLE_POOL_SIZE = 8`, **WHEN** scan tous les `GPUParticles3D.process_material`, **THEN** **un seul** `ShaderMaterial` instance partagée (pas 8 distincts) — vérifié via `_blood_particle_pool[0].process_material == _blood_particle_pool[7].process_material` (R-VFX-16 budget draw calls).
- [ ] **AC-NEW-04** [BLOCKING][AUTO] **GIVEN** VFXSystem instancié, **WHEN** `_ready()` s'exécute, **THEN** VFXSystem connecté aux signaux `Combat.swing_started/swing_ended/multi_kill` + `Enemy.enemy_killed` + `Camera.died/respawned` + `GameStateManager.state_changed` + `AccessibilityService.settings_changed` (vérifiable via `Signal.get_connections()`), avant tout tick `_physics_process`. *(Stubs handlers no-op ici ; bodies story-002..006.)*

---

## Implementation Notes

1. **Fichier `src/core/vfx_system.gd`** (autoload skeleton ~180 lignes) :
   ```gdscript
   class_name VFXSystemScript
   extends Node

   const BLOOD_PARTICLE_POOL_SIZE: int = 8
   const DECAL_POOL_SIZE: int = 64  # 2 × MAX_DECALS_PER_ROOM (story-003)
   const MAX_DECALS_PER_ROOM: int = 32  # F-VFX-1 LRU ring buffer
   const FLASH_KILL_DURATION_MS: int = 80
   const FLASH_RESPAWN_DURATION_MS: int = 50
   const FLASH_MIN_INTERVAL_MS: int = 333  # WCAG 2.3.1 3 Hz plancher
   const FLASH_OVERLAY_LAYER: int = 60  # < 80 Pause Menu (R-MNU-14) < 100 GSM fade

   const BLOOD_COLOR: Color = Color(0xC8, 0x23, 0x2C, 0xFF) / 255.0  # #C8232C
   const TRAIL_COLOR: Color = Color(0xE8, 0xE8, 0xE0, 0xFF) / 255.0  # #E8E8E0

   var _blood_particle_pool: Array[GPUParticles3D] = []
   var _decal_pool: Array[Decal] = []
   var _trail_mesh: MeshInstance3D
   var _flash_overlay_rect: ColorRect
   var _vfx_pool_3d: Node3D  # parent 3D nodes pour scene tree organization

   var _blood_idx: int = 0  # round-robin pool
   var _decal_write_head: int = 0  # ring buffer LRU (story-003)
   var _room_decal_count: int = 0
   var _is_active: bool = true  # GSM gating story-006

   # Wall-clock injection (pattern Audio R-AUD-4 / Combat ADR-0006 D-4)
   var _get_time_msec: Callable = Time.get_ticks_msec

   var _flash_last_msec: int = 0  # WCAG guard R-VFX-13

   func _ready() -> void:
       # Guard EC-VFX-08 — AccessibilityService non initialisé tolérance
       assert(GameStateManager != null, "VFX: GSM autoload missing — check project.godot order")

       # Pool 3D parent organization
       _vfx_pool_3d = Node3D.new()
       _vfx_pool_3d.name = "VFXPool3D"
       add_child(_vfx_pool_3d)

       # Blood particle pool (R-VFX-2/8/16 — un seul ShaderMaterial partagé)
       var blood_material: ShaderMaterial = _create_blood_shader_material()
       for i in range(BLOOD_PARTICLE_POOL_SIZE):
           var p: GPUParticles3D = GPUParticles3D.new()
           p.name = "BloodParticle_%d" % i
           p.emitting = false
           p.one_shot = true
           p.amount = 6  # BLOOD_SPURT_PARTICLE_COUNT
           p.lifetime = 0.4  # PARTICLE_LIFETIME_MS = 400
           p.process_material = blood_material  # SHARED instance
           _vfx_pool_3d.add_child(p)
           _blood_particle_pool.append(p)

       # Decal pool (R-VFX-2/9 — story-003 LRU ring buffer)
       for i in range(DECAL_POOL_SIZE):
           var d: Decal = Decal.new()
           d.name = "Decal_%d" % i
           d.visible = false
           d.modulate = BLOOD_COLOR
           d.modulate.a = 0.7
           d.size = Vector3(0.6, 0.3, 0.6)  # DECAL_SIZE = 0.6 m radius
           _vfx_pool_3d.add_child(d)
           _decal_pool.append(d)

       # Trail katana mesh (R-VFX-7 — MeshInstance3D pas GPUParticles3D budget draw calls)
       _trail_mesh = MeshInstance3D.new()
       _trail_mesh.name = "KatanaTrailMesh"
       _trail_mesh.visible = false
       # ImmediateMesh ou Trail3D (OQ-VFX-3) — décision lead-programmer Sprint 1
       _trail_mesh.mesh = ImmediateMesh.new()
       _vfx_pool_3d.add_child(_trail_mesh)

       # Flash overlay CanvasLayer (R-VFX-5/15 — 2D plein-écran)
       var flash_canvas: CanvasLayer = CanvasLayer.new()
       flash_canvas.name = "VFXFlashOverlay"
       flash_canvas.layer = FLASH_OVERLAY_LAYER
       add_child(flash_canvas)

       _flash_overlay_rect = ColorRect.new()
       _flash_overlay_rect.name = "FlashOverlayRect"
       _flash_overlay_rect.set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_FULL_RECT)
       _flash_overlay_rect.color = Color(1.0, 1.0, 1.0, 0.0)  # blanc transparent au boot
       _flash_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
       _flash_overlay_rect.visible = false
       flash_canvas.add_child(_flash_overlay_rect)

       # Connect upstream signals — stubs handlers (bodies story-002..006)
       # Note : connections SYNC vs CONNECT_DEFERRED selon R-VFX-3 + OQ-VFX-4 playtest
       # MVP : tous CONNECT_DEFERRED par défaut sauf flash kill SYNC à valider playtest
       _connect_upstream_signals()

       print("[VFXSystem] boot — pool=%d/%d trail=%d flash_layer=%d" % [
           _blood_particle_pool.size(), _decal_pool.size(),
           1 if _trail_mesh != null else 0, FLASH_OVERLAY_LAYER
       ])

   func _connect_upstream_signals() -> void:
       # Combat (story-002 implements bodies)
       if Engine.has_singleton("CombatSystem") or get_node_or_null("/root/CombatSystem"):
           var combat: Node = get_node("/root/CombatSystem")
           combat.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
           combat.swing_ended.connect(_on_swing_ended, CONNECT_DEFERRED)
           combat.multi_kill.connect(_on_multi_kill, CONNECT_DEFERRED)

       # Enemy (story-002)
       if get_node_or_null("/root/EnemySystem"):
           var enemy: Node = get_node("/root/EnemySystem")
           enemy.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)
           # Note : flash kill SYNC TBD playtest OQ-VFX-4 — MVP DEFERRED safe

       # Camera (story-002 + story-004)
       if get_node_or_null("/root/CameraSystem"):
           var camera: Node = get_node("/root/CameraSystem")
           camera.died.connect(_on_died, CONNECT_DEFERRED)
           camera.respawned.connect(_on_respawned, CONNECT_DEFERRED)

       # GSM (story-006)
       if GameStateManager != null:
           GameStateManager.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)

       # Accessibility (story-005)
       if is_instance_valid(AccessibilityService):
           AccessibilityService.settings_changed.connect(_on_accessibility_settings_changed, CONNECT_DEFERRED)

   func _create_blood_shader_material() -> ShaderMaterial:
       # Flat unshaded shader — zéro PBR (R-VFX-8 + Chrome Zen palette)
       var mat: ShaderMaterial = ShaderMaterial.new()
       # TODO story-002 : shader code flat color BLOOD_COLOR + opacity fade-out linéaire F-VFX-3
       return mat

   # Stubs — bodies dans stories 002-006
   func _on_swing_started(_direction: Vector3) -> void: pass
   func _on_swing_ended() -> void: pass
   func _on_multi_kill(_count: int) -> void: pass
   func _on_enemy_killed(_enemy: Node, _position: Vector3) -> void: pass
   func _on_died() -> void: pass
   func _on_respawned(_position: Vector3) -> void: pass
   func _on_state_changed(_new_state: int) -> void: pass
   func _on_accessibility_settings_changed() -> void: pass
   ```

2. **`project.godot` registration** : ajouter `VFXSystem="*res://src/core/vfx_system.gd"` dans `[autoload]` APRÈS `InputManager`, `GameStateManager`, `CreditEconomy`, `HUDSystem`, `AudioSystem` (Presentation layer terminal — position `>= 6`).

3. **Scene tree garanti** post-`_ready()` :
   ```
   VFXSystem (autoload, Node)
   ├── VFXPool3D (Node3D)
   │   ├── BloodParticle_0..7 (GPUParticles3D × 8, emitting=false, shared ShaderMaterial)
   │   ├── Decal_0..63 (Decal × 64, visible=false, modulate #C8232C alpha=0.7)
   │   └── KatanaTrailMesh (MeshInstance3D, visible=false, ImmediateMesh)
   └── VFXFlashOverlay (CanvasLayer, layer=60)
       └── FlashOverlayRect (ColorRect, PRESET_FULL_RECT, alpha=0, visible=false)
   ```

4. **Test fixture** : autoload mocks `MockGSM` + `MockCombat` + `MockEnemy` + `MockCamera` + `MockAccessibility` dans `tests/unit/vfx/` exposant `state_changed` / `swing_started` / `enemy_killed` / `died` / `respawned` / `settings_changed` signals. Pattern Combat MockAudioHandler référence canonique (171 lignes).

5. **Verbose log** : `print("[VFXSystem] boot — pool=8/64 trail=1 flash_layer=60")` au `_ready()` (debug-only, supprimable post-validation Sprint).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Listener `_on_enemy_killed` body (splash + decal raycast + flash kill) — story-002.
- Listener `_on_swing_started` / `_on_swing_ended` body (trail activation) — story-002.
- Decal LRU ring buffer eviction logic (`_decal_write_head` increment, room reset) — story-003.
- Flash brightness wall-clock timer + reduce_flash gris substitute + WCAG 333 ms guard — story-004.
- Listener `_on_accessibility_settings_changed` body (pull `reduce_flash` / `flash_mult` / `reduce_motion`) — story-005.
- Listener `_on_state_changed` body (visibility gating MENU/PAUSED/BOSS_DEFEATED) — story-006.
- Lints statiques anti-patterns + outbound-only enforce + Tween-on-volatile guard — story-007.
- Visual/Feel playtest verbatims — story-008.
- Shader code flat unshaded blood color + opacity fade-out linéaire F-VFX-3 — déféré story-002 (impl complet quand handler kill body écrit).

---

## QA Test Cases

*Logic — automated unit tests requis :*

**AC-VFX-04** : Zero-alloc post-boot
- Setup : autoload `VFXSystem` instancié, baseline `Performance.MEMORY_STATIC` capturé après `_ready()`.
- Action : 60 ticks idle (ou 1000 frames `_physics_process` simulés sans signal entrant).
- Verify : `Performance.MEMORY_STATIC` delta < 16 KB.
- Pass : `assert_int(after - before).is_less(16_384)`.

**AC-VFX-05** : Lint static anti `*.new()` hors vfx_system.gd
- Setup : suite `tests/static/vfx_anti_patterns_lint_test.gd` (story-007 plein impl).
- Action : grep recursive sur `src/`.
- Verify : zéro match `GPUParticles3D.new()` / `Decal.new()` / `MeshInstance3D.new()` hors `src/core/vfx_system.gd`.
- Pass : `assert_array(matches).is_empty()`.

**AC-NEW-01** : Pool pré-alloué exact size
- Setup : autoload `VFXSystem` instancié.
- Action : `_ready()` complet (await idle frame).
- Verify : `vfx._blood_particle_pool.size() == 8` ET `vfx._decal_pool.size() == 64` ET `vfx._trail_mesh != null` ET `vfx._flash_overlay_rect != null`.
- Pass : `assert_int(vfx._blood_particle_pool.size()).is_equal(8)` + 3 autres asserts.

**AC-NEW-02** : Pool nodes invisibles au boot
- Setup : `_ready()` terminé.
- Verify : tous `GPUParticles3D.emitting == false` ; tous `Decal.visible == false` ; `_trail_mesh.visible == false` ; `_flash_overlay_rect.visible == false`.
- Pass : `for p in vfx._blood_particle_pool: assert_bool(p.emitting).is_false()`.

**AC-NEW-03** : ShaderMaterial partagé
- Setup : `_ready()` terminé.
- Verify : `vfx._blood_particle_pool[0].process_material != null` ET `vfx._blood_particle_pool[0].process_material == vfx._blood_particle_pool[7].process_material` (référence identique, pas instances distinctes).
- Pass : `assert_object(vfx._blood_particle_pool[0].process_material).is_same(vfx._blood_particle_pool[7].process_material)`.

**AC-NEW-04** : Connexions upstream signals
- Setup : autoload mocks Combat/Enemy/Camera/GSM/AccessibilityService.
- Action : `_ready()` complet.
- Verify : `MockCombat.swing_started.get_connections().size() == 1` (CONNECT_DEFERRED flag set) + 7 autres signals connectés.
- Pass : asserts sur `get_connections()` array + flag check `connection.flags & CONNECT_DEFERRED != 0`.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/vfx/vfx_system_boot_test.gd` (NEW, ~180 lignes) couvrant AC-VFX-04/05 + AC-NEW-01/02/03/04.
- Mocks `tests/unit/vfx/mock_combat.gd` + `mock_enemy.gd` + `mock_camera.gd` + `mock_gsm.gd` + `mock_accessibility.gd` (référence pattern Combat MockAudioHandler 171 lignes).
- Smoke check : test suite green run via GdUnit4 headless (`godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/unit/vfx/vfx_system_boot_test.gd --ignoreHeadlessMode`).

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** :
  - **Combat / Enemy / Camera autoloads Ready** : Combat 20/22 Complete + Enemy 6/6 Complete + Camera 13/13 Complete ✅. Signals `swing_started/swing_ended/multi_kill/enemy_killed/died/respawned` disponibles production.
  - **AccessibilityService autoload Ready** : ADR-0015 Accepted 2026-05-02 + accessibility-system epic 1/1 Complete ✅. APIs `reduce_flash` / `flash_mult` / `reduce_motion` + signal `settings_changed` disponibles production.
  - **GameStateManager autoload Not Started** : ADR-0007 Accepted, GSM GDD APPROVED r1, mais GSM autoload `src/core/game_state_manager.gd` n'est **pas encore implémenté**. **Mitigation Sprint VFX** : utiliser mocks `MockGSM` test fixture pattern. Production VFX attend GSM autoload boot Sprint A multi-epic.
- **Soft upstream** : Audio System 12/12 Complete (pattern référence pool exclusive + wall-clock fades + CONNECT_DEFERRED — VFX **réutilise architecturalement** le même idiome).
- **Unlocks** : story-002 (Combat handlers body) + story-003 (decal LRU eviction logic) + story-004 (flash events wall-clock) + story-005 (accessibility pull) + story-006 (GSM visibility) + story-007 (lints CI activated post-impl).
