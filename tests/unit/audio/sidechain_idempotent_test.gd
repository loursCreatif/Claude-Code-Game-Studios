# Tests unitaires Story-001 — Sidechain compressor idempotent guard.
#
# Couvre AC-AUD-20 :
#   - double-call _setup_sidechain_compressor() → get_bus_effect_count(Music) == 1 (PAS 2)
#   - propriétés inchangées après double-call (attack_us=5000, release_ms=200.0, sidechain="combat_kill")
#
# Pattern : accéder à AudioSystem via get_tree().root.get_node("AudioSystem") et
# appeler directement _setup_sidechain_compressor() une deuxième fois.
# Le premier appel est fait au boot dans _ready() — le test simule le cas pathologique
# (re-instanciation autoload, scene reload, fixture réutilisée).
#
# Framework : GdUnit4 v5 (extends GdUnitTestSuite).
# Story   : production/epics/audio-system/story-001-autoload-skeleton-bus-layout-pool-sidechain.md
# ADR     : ADR-0009 D-1 Phase D.2 (idempotent guard)
# GDD     : design/gdd/audio-system.md AC-AUD-20

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _get_music_idx() -> int:
	return AudioServer.get_bus_index(&"Music")


# ---------------------------------------------------------------------------
# AC-AUD-20 — idempotent guard
# ---------------------------------------------------------------------------

## Précondition : boot AudioSystem a déjà appelé _setup_sidechain_compressor() une fois.
## Le bus MUSIC doit avoir exactement 1 effet après le boot normal.
func test_precondition_music_bus_has_one_effect_after_boot() -> void:
	# Assert
	assert_int(AudioServer.get_bus_effect_count(_get_music_idx())).is_equal(1)


## Double-call _setup_sidechain_compressor() → effect_count reste 1, PAS 2.
## Régression : si le guard est absent, effect_count == 2 (cascade 16:1 au lieu de 4:1).
func test_double_call_idempotent_guard_no_duplicate_compressor() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var music_idx: int = _get_music_idx()

	# Précondition
	assert_int(AudioServer.get_bus_effect_count(music_idx)).is_equal(1)

	# Act — deuxième appel (cas pathologique)
	audio._setup_sidechain_compressor()

	# Assert — toujours 1 effet, PAS 2
	assert_int(AudioServer.get_bus_effect_count(music_idx)).is_equal(1)


## Après double-call, les propriétés du compressor doivent être inchangées.
func test_double_call_properties_unchanged() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var music_idx: int = _get_music_idx()

	# Act — deuxième appel
	audio._setup_sidechain_compressor()

	# Assert — l'effet 0 doit toujours être un AudioEffectCompressor avec les bonnes valeurs
	var effect: AudioEffect = AudioServer.get_bus_effect(music_idx, 0)
	assert_object(effect).is_instanceof(AudioEffectCompressor)

	var compressor: AudioEffectCompressor = effect as AudioEffectCompressor
	assert_float(compressor.attack_us).is_equal_approx(5000.0, 1.0)
	assert_float(compressor.release_ms).is_equal_approx(200.0, 0.1)
	assert_str(compressor.sidechain).is_equal("combat_kill")


## Appels multiples (N > 2) ne produisent qu'un seul compressor.
func test_triple_call_still_one_effect() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var music_idx: int = _get_music_idx()

	# Act — 3e et 4e appels
	audio._setup_sidechain_compressor()
	audio._setup_sidechain_compressor()

	# Assert
	assert_int(AudioServer.get_bus_effect_count(music_idx)).is_equal(1)
