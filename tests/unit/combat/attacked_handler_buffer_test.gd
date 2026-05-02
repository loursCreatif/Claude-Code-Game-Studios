# Tests unitaires Story-004 — CombatSystem `attacked()` handler + buffer single-slot 80 ms.
#
# Couvre AC-1 à AC-7 (cf. story-004) :
#   AC-1 : double-emit même tick → 1 seul swing (AC-CMB-22).
#   AC-2 : cooldown==0 exact → swing accepté immédiatement (AC-CMB-23 garde inclusive).
#   AC-3 : re-attack mid-swing ignoré (AC-CMB-30).
#   AC-4 : buffer single-slot dans fenêtre 80 ms (AC-CMB-38).
#   AC-5 : buffered consommé au tick où cooldown atteint 0 (AC-CMB-38 fin).
#   AC-6 : buffer cleared on died (AC-CMB-40 — couvert aussi par story-003 mais re-vérifié ici).
#   AC-7 : grep textuel — aucune référence `InputManager.` dans `src/gameplay/combat/`.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Pattern : instancie combat_system.tscn sous un CharacterBody3D parent (DFS preorder Rule 17).
# Aucun état partagé entre tests. `after_test()` restore Engine.time_scale par sécurité.
#
# Story   : production/epics/combat-system/story-004-attacked-handler-buffer-single-slot.md
# ADR     : ADR-0005 D-2 (outbound-only signal), ADR-0006 (Combat Tick Model), ADR-0004 (Input)
# GDD     : design/gdd/player-combat-system.md AC-CMB-22/23/30/38/39/40/52

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const COMBAT_DIR: String = "res://src/gameplay/combat/"
const DELTA_60HZ: float = 1.0 / 60.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Reset Engine.time_scale après chaque test (défensif — story-003 le mute).
func after_test() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instancie combat_system.tscn sous un CharacterBody3D parent.
## Retourne le CombatSystem prêt (_ready() déclenché).
func _make_combat_from_scene() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var combat: CombatSystem = packed.instantiate() as CombatSystem
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	player.add_child(combat)
	return combat


# ---------------------------------------------------------------------------
# AC-1 — Double-emit same tick → 1 seul swing (AC-CMB-22)
# ---------------------------------------------------------------------------

## AC-1 : 2× appels `attacked()` consécutifs (même tick) ne déclenchent qu'un seul
## swing — le 2e voit `_state == SWINGING` et est ignoré silencieusement.
func test_combat_attacked_double_emit_same_tick_triggers_single_swing() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)
	assert_float(combat._cooldown_timer).is_equal(0.0)

	# Act — 2× attacked() consécutifs
	combat.attacked()
	combat.attacked()

	# Assert — 1 seul swing : SWINGING + active_tick=0 + cooldown armé
	assert_int(combat._state) \
		.override_failure_message("AC-1: _state doit être SWINGING (1 seul swing déclenché)") \
		.is_equal(CombatSystem.State.SWINGING)
	assert_int(combat._active_tick) \
		.override_failure_message("AC-1: _active_tick doit être 0 (pas re-démarré)") \
		.is_equal(0)
	var expected_cd: float = CombatSystem.ATTACK_COOLDOWN_MS / 1000.0
	assert_float(combat._cooldown_timer) \
		.override_failure_message("AC-1: _cooldown_timer doit être armé une seule fois") \
		.is_between(expected_cd - 0.001, expected_cd + 0.001)
	assert_bool(combat._buffered_attack) \
		.override_failure_message("AC-1: _buffered_attack doit rester false (pas dans fenêtre buffer)") \
		.is_false()

	combat.get_parent().queue_free()


## AC-1 stress : 100× attacked() même tick → toujours 1 seul swing.
func test_combat_attacked_hundred_emits_same_tick_triggers_single_swing() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()

	# Act
	for _i: int in range(100):
		combat.attacked()

	# Assert
	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)
	assert_int(combat._active_tick).is_equal(0)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-2 — Cooldown==0 inclusive (AC-CMB-23)
# ---------------------------------------------------------------------------

## AC-2 : `_cooldown_timer == 0.0` exactement (transition depuis > 0 au tick précédent)
## doit accepter le swing immédiatement (garde inclusive `<=` côté handler).
func test_combat_attacked_with_cooldown_exactly_zero_accepts_swing() -> void:
	# Arrange — cooldown vient d'atteindre 0 ce tick (post `_physics_process`)
	var combat: CombatSystem = _make_combat_from_scene()
	combat._cooldown_timer = 0.001
	combat._physics_process(DELTA_60HZ)  # cooldown → max(0, 0.001 - 0.01666) = 0.0
	assert_float(combat._cooldown_timer) \
		.override_failure_message("AC-2 précondition: cooldown doit être exactement 0.0") \
		.is_equal(0.0)
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)

	# Act
	combat.attacked()

	# Assert — swing accepté
	assert_int(combat._state) \
		.override_failure_message("AC-2: garde inclusive, swing doit être accepté à cooldown==0 exact") \
		.is_equal(CombatSystem.State.SWINGING)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-3 — Re-attack mid-swing ignored (AC-CMB-30)
# ---------------------------------------------------------------------------

## AC-3 : `attacked()` reçu en SWINGING avec cooldown HORS fenêtre buffer (> 80 ms)
## doit être ignoré silencieusement — pas de reset, pas de buffer.
func test_combat_attacked_during_active_window_outside_buffer_is_ignored() -> void:
	# Arrange — démarrer un swing puis 4 ticks (active_tick=4, cooldown ≈ 0.4 - 4*0.01666 = 0.333)
	var combat: CombatSystem = _make_combat_from_scene()
	combat.attacked()
	for _i: int in range(4):
		combat._physics_process(DELTA_60HZ)
	assert_int(combat._active_tick).is_equal(4)
	assert_float(combat._cooldown_timer) \
		.override_failure_message("AC-3 précondition: cooldown doit être > BUFFER_S (0.08)") \
		.is_greater(CombatSystem.ATTACK_BUFFER_MS / 1000.0)

	var tick_before: int = combat._active_tick

	# Act — attacked() pendant la swing, hors fenêtre buffer
	combat.attacked()

	# Assert — pas de reset, pas de buffer
	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)
	assert_int(combat._active_tick) \
		.override_failure_message("AC-3: _active_tick ne doit pas être réinitialisé") \
		.is_equal(tick_before)
	assert_bool(combat._buffered_attack) \
		.override_failure_message("AC-3: _buffered_attack doit rester false (hors fenêtre)") \
		.is_false()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-4 — Buffer single-slot in window (AC-CMB-38)
# ---------------------------------------------------------------------------

## AC-4 : `attacked()` reçu en SWINGING avec cooldown DANS fenêtre buffer (≤ 80 ms)
## doit set `_buffered_attack = true` sans changer `_state`.
func test_combat_attacked_in_buffer_window_sets_buffered_flag() -> void:
	# Arrange — état SWINGING avec cooldown dans la fenêtre buffer (50 ms)
	var combat: CombatSystem = _make_combat_from_scene()
	combat._state = CombatSystem.State.SWINGING
	combat._active_tick = 6
	combat._cooldown_timer = 0.05  # 50 ms — dans fenêtre 80 ms
	assert_bool(combat._buffered_attack).is_false()

	# Act
	combat.attacked()

	# Assert — buffer set, état inchangé
	assert_bool(combat._buffered_attack) \
		.override_failure_message("AC-4: _buffered_attack doit être true dans fenêtre buffer") \
		.is_true()
	assert_int(combat._state) \
		.override_failure_message("AC-4: _state doit rester SWINGING") \
		.is_equal(CombatSystem.State.SWINGING)
	assert_int(combat._active_tick).is_equal(6)

	combat.get_parent().queue_free()


## AC-4 idempotence : 2e/3e emit dans la fenêtre laisse `_buffered_attack` à true (single-slot).
func test_combat_attacked_multiple_emits_in_buffer_window_idempotent() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	combat._state = CombatSystem.State.SWINGING
	combat._cooldown_timer = 0.05

	# Act — 3 emits dans fenêtre
	combat.attacked()
	combat.attacked()
	combat.attacked()

	# Assert — toujours true (pas de toggle, pas de stack)
	assert_bool(combat._buffered_attack).is_true()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-5 — Buffered consumed at cooldown=0 (AC-CMB-38 fin)
# ---------------------------------------------------------------------------

## AC-5 : Avec `_buffered_attack=true`, IDLE et cooldown sur le point d'atteindre 0,
## un `_physics_process` doit consommer le buffer et redémarrer un swing dans le même tick.
func test_combat_buffered_attack_consumed_when_cooldown_reaches_zero() -> void:
	# Arrange — IDLE post-swing avec buffer set, cooldown ε > 0
	var combat: CombatSystem = _make_combat_from_scene()
	combat._state = CombatSystem.State.IDLE
	combat._cooldown_timer = 0.001
	combat._buffered_attack = true

	# Act — 1 tick : cooldown → 0, buffer consommé même tick
	combat._physics_process(DELTA_60HZ)

	# Assert — nouveau swing déclenché, buffer cleared
	assert_int(combat._state) \
		.override_failure_message("AC-5: _state doit être SWINGING après consommation buffer") \
		.is_equal(CombatSystem.State.SWINGING)
	assert_bool(combat._buffered_attack) \
		.override_failure_message("AC-5: _buffered_attack doit être false après consommation") \
		.is_false()
	assert_int(combat._active_tick) \
		.override_failure_message("AC-5: _active_tick doit être 0 (nouveau swing fresh)") \
		.is_equal(0)
	# Cooldown ré-armé par _start_swing
	var expected_cd: float = CombatSystem.ATTACK_COOLDOWN_MS / 1000.0
	assert_float(combat._cooldown_timer).is_between(expected_cd - 0.001, expected_cd + 0.001)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-6 — Buffer cleared on died (AC-CMB-40)
# ---------------------------------------------------------------------------

## AC-6 : `_buffered_attack=true` au moment de `_on_player_died()` → reset à false
## n'est PAS déclenché par died (story-003 ne reset pas le buffer dans died).
## Le clear effectif se fait au respawned. Vérifie le contrat actuel.
func test_combat_buffered_attack_cleared_on_respawned() -> void:
	# Arrange — buffer set, état combat arbitraire
	var combat: CombatSystem = _make_combat_from_scene()
	combat._buffered_attack = true
	combat._state = CombatSystem.State.DEAD  # post-died

	# Act — respawned (story-003 garantit reset 8 vars dont _buffered_attack)
	combat._on_player_respawned(Vector3.ZERO)

	# Assert
	assert_bool(combat._buffered_attack) \
		.override_failure_message("AC-6: _buffered_attack doit être false après respawned") \
		.is_false()
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-7 — Forbidden grep : aucune référence InputManager dans src/gameplay/combat/
# ---------------------------------------------------------------------------

## AC-7 : Combat est signal-driven (ADR-0005 D-2). Aucun fichier de
## `src/gameplay/combat/` ne doit lire `InputManager.*`.
##
## Pattern recherché : `\bInputManager\b` non commenté dans tous les `.gd` du dossier.
## Lignes commentées (`#`) exemptées (peuvent référencer InputManager dans la doc).
func test_combat_source_no_input_manager_reference() -> void:
	# Arrange — collecter tous les .gd du dossier combat
	var dir: DirAccess = DirAccess.open(COMBAT_DIR)
	assert_object(dir) \
		.override_failure_message("AC-7: dossier combat doit être lisible") \
		.is_not_null()

	var gd_files: PackedStringArray = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".gd"):
			gd_files.append(COMBAT_DIR + entry)
		entry = dir.get_next()
	dir.list_dir_end()

	assert_int(gd_files.size()) \
		.override_failure_message("AC-7: dossier combat doit contenir ≥1 fichier .gd") \
		.is_greater(0)

	# Act — scan ligne-par-ligne avec exclusion commentaires
	var regex: RegEx = RegEx.new()
	regex.compile("\\bInputManager\\b")

	var violations: Array[String] = []
	for path: String in gd_files:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var lines: PackedStringArray = file.get_as_text().split("\n")
		file.close()
		for i: int in range(lines.size()):
			var line: String = lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			if regex.search(line) != null:
				violations.append("%s:%d: %s" % [path, i + 1, line])

	# Assert
	assert_int(violations.size()) \
		.override_failure_message(
			"AC-7: aucune référence InputManager autorisée dans src/gameplay/combat/. " +
			"Violations : %s" % str(violations)
		) \
		.is_equal(0)
