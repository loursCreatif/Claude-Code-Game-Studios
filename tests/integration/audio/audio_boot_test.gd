# Tests intégration Story-001 — Boot bus structure + pool sizing.
#
# Couvre AC-AUD-01 (bus count, noms, parents, sidechain compressor) +
# AC-AUD-02 (pool sizing : 5×2D + 12×3D + 1×Music + 2×Ambience = 20).
#
# Pattern : AudioSystem est un autoload, accessible via get_tree().root.get_node("AudioSystem").
# Les tests vérifient l'état post-boot (_ready() déjà exécuté).
#
# Framework : GdUnit4 v5 (extends GdUnitTestSuite).
# Story   : production/epics/audio-system/story-001-autoload-skeleton-bus-layout-pool-sidechain.md
# ADR     : ADR-0009 D-1 (bus hierarchy) + D-2 (pool sizing)
# GDD     : design/gdd/audio-system.md AC-AUD-01 / AC-AUD-02

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


# ---------------------------------------------------------------------------
# AC-AUD-01 (a) — bus count
# ---------------------------------------------------------------------------

## AudioServer doit exposer exactement 7 buses après boot.
func test_bus_count_is_7() -> void:
	# Assert
	assert_int(AudioServer.bus_count).is_equal(7)


# ---------------------------------------------------------------------------
# AC-AUD-01 (b) — noms UPPER_SNAKE_CASE dans le bon ordre
# ---------------------------------------------------------------------------

## Les noms de buses doivent respecter l'ordre et le casing ADR-0009 D-1.
## Convention : PascalCase pour buses natifs (Master/Music/SFX/Ambience/UI),
## snake_case pour buses enfants SFX (swing_active/combat_kill).
## Note : Godot 4.6 force bus 0 = "Master" silently — story AC-AUD-01 amendment
## recommandé pour aligner sur cette contrainte engine.
func test_bus_names_correct_order() -> void:
	# Arrange
	var expected_names: Array[StringName] = [
		&"Master",
		&"Music",
		&"SFX",
		&"swing_active",
		&"combat_kill",
		&"Ambience",
		&"UI",
	]

	# Assert
	for i: int in range(7):
		var actual: StringName = AudioServer.get_bus_name(i)
		assert_str(actual).is_equal(expected_names[i])


# ---------------------------------------------------------------------------
# AC-AUD-01 (c) — parents corrects
# ---------------------------------------------------------------------------

## Vérifie les sends (parents) de chaque bus per ADR-0009 D-1.
## Master → send "Master" (convention AudioServer bus 0).
## Music/SFX/Ambience/UI → Master. swing_active/combat_kill → SFX.
func test_bus_parents_correct() -> void:
	# Arrange — (bus_index, expected_send)
	var expected_sends: Array = [
		[0, &"Master"],       # Master — send vers lui-même (convention)
		[1, &"Master"],       # Music → Master
		[2, &"Master"],       # SFX → Master
		[3, &"SFX"],          # swing_active → SFX
		[4, &"SFX"],          # combat_kill → SFX
		[5, &"Master"],       # Ambience → Master
		[6, &"Master"],       # UI → Master
	]

	# Assert
	for pair: Array in expected_sends:
		var idx: int = pair[0]
		var expected: StringName = pair[1]
		var actual: StringName = AudioServer.get_bus_send(idx)
		assert_str(actual).is_equal(expected)


# ---------------------------------------------------------------------------
# AC-AUD-01 (d) — sidechain compressor sur MUSIC
# ---------------------------------------------------------------------------

## Bus Music doit porter exactement 1 AudioEffectCompressor avec les bonnes props.
func test_music_bus_has_exactly_one_compressor() -> void:
	# Arrange
	var music_idx: int = AudioServer.get_bus_index(&"Music")

	# Assert — exactement 1 effet
	assert_int(AudioServer.get_bus_effect_count(music_idx)).is_equal(1)


## Propriétés du compressor doivent correspondre aux valeurs ADR-0009 D-1.
func test_music_bus_compressor_properties_match_spec() -> void:
	# Arrange
	var music_idx: int = AudioServer.get_bus_index(&"Music")
	var effect: AudioEffect = AudioServer.get_bus_effect(music_idx, 0)

	# Assert — type correct
	assert_object(effect).is_instanceof(AudioEffectCompressor)

	var compressor: AudioEffectCompressor = effect as AudioEffectCompressor

	# Assert — threshold -24.0 dB
	assert_float(compressor.threshold).is_equal_approx(-24.0, 0.001)

	# Assert — ratio 4.0
	assert_float(compressor.ratio).is_equal_approx(4.0, 0.001)

	# Assert — attack_us 5000 (5 ms en microsecondes — gotcha nommage asymétrique)
	assert_float(compressor.attack_us).is_equal_approx(5000.0, 1.0)

	# Assert — release_ms 200.0
	assert_float(compressor.release_ms).is_equal_approx(200.0, 0.1)

	# Assert — sidechain = "combat_kill" (ADR-0009 D-1 native bus name)
	assert_str(compressor.sidechain).is_equal("combat_kill")


# ---------------------------------------------------------------------------
# AC-AUD-02 — pool sizing
# ---------------------------------------------------------------------------

## AudioSystem doit avoir exactement 20 enfants (pool complet).
func test_pool_total_child_count_is_20() -> void:
	# Arrange
	var audio: Node = _get_audio_system()

	# Assert
	assert_int(audio.get_child_count()).is_equal(20)


## Répartition interne : 5 AudioStreamPlayer (2D) + 12 AudioStreamPlayer3D + 1 Music + 2 Ambience.
func test_pool_breakdown_5_2d_12_3d_1_music_2_ambience() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var count_2d: int = 0
	var count_3d: int = 0

	for child: Node in audio.get_children():
		if child is AudioStreamPlayer3D:
			count_3d += 1
		elif child is AudioStreamPlayer:
			count_2d += 1

	# Assert — 5 (SFX pool) + 1 (Music) + 2 (Ambience) = 8 AudioStreamPlayer
	# + 12 AudioStreamPlayer3D = 20 total
	assert_int(count_2d).is_equal(8)   # 5 + 1 + 2
	assert_int(count_3d).is_equal(12)


## Vérifie les variables internes du pool (pas seulement structural via get_children).
## Ferme le gap où _setup_pool() ajoute bien comme enfants mais oublie d'appender
## dans les arrays internes — play_2d crasherait à l'index 0.
func test_pool_internal_arrays_match_children_count() -> void:
	# Arrange
	var audio: Node = _get_audio_system()

	# Assert — variables internes pool peuplées correctement
	assert_int(audio._2d_pool.size()).is_equal(5)
	assert_int(audio._3d_pool.size()).is_equal(12)
	assert_int(audio._ambience_pool.size()).is_equal(2)
	assert_object(audio._music_player).is_not_null()
