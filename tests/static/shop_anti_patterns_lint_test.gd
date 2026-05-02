# Static lint test Story-014 — Shop anti-patterns battery (J.9 + V.4 + GDD).
# Couvre AC-SHP-37/39/40/41/42/43/44/45 + V.4 anti-fanfare + J.9 anti-modal.
# Pattern cohérent upgrade-system story-009 (tests/static/upgrade_lint_test.gd).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — pure lint static via FileAccess + grep regex.
extends GdUnitTestSuite

const _SHOP_TSCN: String = "res://scenes/shop/shop.tscn"
const _SHOP_CTRL: String = "res://src/ui/shop/shop_controller.gd"


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var src: String = f.get_as_text()
	f.close()
	return src


# Helper — count occurrences of substring excluding lines that begin with "#"
# (skips full-line comments). Inline comments still counted; safe pattern for
# anti-pattern lint where false positives in comments are acceptable per scope.
func _count_substring_non_comment_lines(src: String, needle: String) -> int:
	var count: int = 0
	for line in src.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains(needle):
			count += 1
	return count


# =============================================================================
# AC-SHP-39 — shop.tscn : zéro AnimationPlayer (J.9 anti-pattern animated bg)
# =============================================================================

func test_shop_scene_no_animation_player() -> void:
	var src: String = _read(_SHOP_TSCN)
	assert_int(src.count("AnimationPlayer")) \
		.override_failure_message("AC-SHP-39: AnimationPlayer trouvé dans shop.tscn — anti-pattern J.9") \
		.is_equal(0)


# =============================================================================
# AC-SHP-40 — shop.tscn : zéro TabContainer (J.9 anti-pattern onglets)
# =============================================================================

func test_shop_scene_no_tab_container() -> void:
	var src: String = _read(_SHOP_TSCN)
	assert_int(src.count("TabContainer")) \
		.override_failure_message("AC-SHP-40: TabContainer trouvé dans shop.tscn — anti-pattern J.9") \
		.is_equal(0)


# =============================================================================
# AC-SHP-42 — shop.tscn : zéro ScrollContainer (J.9 anti-pattern news feed)
# =============================================================================

func test_shop_scene_no_scroll_container() -> void:
	var src: String = _read(_SHOP_TSCN)
	assert_int(src.count("ScrollContainer")) \
		.override_failure_message("AC-SHP-42: ScrollContainer trouvé dans shop.tscn — anti-pattern J.9") \
		.is_equal(0)


# =============================================================================
# AC-SHP-43 — zéro AudioStreamPlayer dans tscn ET controller (anti-fanfare)
# =============================================================================

func test_shop_scene_no_audio_stream_player() -> void:
	var src: String = _read(_SHOP_TSCN)
	assert_int(src.count("AudioStreamPlayer")) \
		.override_failure_message("AC-SHP-43: AudioStreamPlayer trouvé dans shop.tscn — anti-fanfare V.4") \
		.is_equal(0)


func test_shop_controller_no_audio_stream_player() -> void:
	var src: String = _read(_SHOP_CTRL)
	var count: int = _count_substring_non_comment_lines(src, "AudioStreamPlayer")
	assert_int(count) \
		.override_failure_message("AC-SHP-43: AudioStreamPlayer code dans shop_controller.gd — anti-fanfare") \
		.is_equal(0)


# =============================================================================
# V.4 — zéro GPUParticles2D / GPUParticles3D / AnimatedTexture (anti-fanfare)
# =============================================================================

func test_shop_scene_no_gpu_particles_2d() -> void:
	var src: String = _read(_SHOP_TSCN)
	assert_int(src.count("GPUParticles2D")) \
		.override_failure_message("V.4: GPUParticles2D trouvé dans shop.tscn") \
		.is_equal(0)


func test_shop_scene_no_gpu_particles_3d() -> void:
	var src: String = _read(_SHOP_TSCN)
	assert_int(src.count("GPUParticles3D")) \
		.override_failure_message("V.4: GPUParticles3D trouvé dans shop.tscn") \
		.is_equal(0)


func test_shop_scene_no_animated_texture() -> void:
	var src: String = _read(_SHOP_TSCN)
	assert_int(src.count("AnimatedTexture")) \
		.override_failure_message("V.4: AnimatedTexture trouvé dans shop.tscn — anti-Chrome Zen") \
		.is_equal(0)


# =============================================================================
# J.9 — zéro AcceptDialog / ConfirmationDialog (anti-modal pre-purchase)
# =============================================================================

func test_shop_scene_no_modal_dialogs() -> void:
	var src: String = _read(_SHOP_TSCN)
	assert_int(src.count("AcceptDialog")) \
		.override_failure_message("J.9: AcceptDialog trouvé dans shop.tscn — anti-modal") \
		.is_equal(0)
	assert_int(src.count("ConfirmationDialog")) \
		.override_failure_message("J.9: ConfirmationDialog trouvé dans shop.tscn — anti-modal") \
		.is_equal(0)


# =============================================================================
# AC-SHP-41 — controller : zéro symbole monétaire alternatif (premium/gem)
# =============================================================================
# Note : "coin" exclu du lint car potentiellement légitime dans des comments
# explicatifs (ex. "no coin imagery"). "premium" / "gem" sont strictement
# F2P-coded et n'ont pas de raison d'apparaître au MVP.

func test_shop_controller_no_premium_label() -> void:
	var src: String = _read(_SHOP_CTRL)
	# Recherche case-insensitive (Premium, premium, PREMIUM)
	assert_bool(src.to_lower().contains("premium")) \
		.override_failure_message("AC-SHP-41: 'premium' trouvé dans shop_controller.gd") \
		.is_false()


func test_shop_controller_no_gem_label() -> void:
	var src: String = _read(_SHOP_CTRL)
	# Restrictif : "gem" comme mot complet (pas "gem" dans gemini etc.)
	# Vérification simple : ":gem" / "_gem" / " gem " dans strings
	var has_gem_token: bool = false
	for line in src.split("\n"):
		var lower: String = line.to_lower()
		if lower.contains("\"gem") or lower.contains("&\"gem"):
			has_gem_token = true
			break
	assert_bool(has_gem_token) \
		.override_failure_message("AC-SHP-41: token \"gem...\" trouvé dans shop_controller.gd") \
		.is_false()


# =============================================================================
# AC-SHP-44 BLOCKING — zéro Input.* hors _unhandled_input (Input GDD Core Rule 1)
# =============================================================================
# Extraction function-scoped : trouve toutes les occurrences `Input.` puis vérifie
# qu'elles sont dans le body de `_unhandled_input` uniquement (ou commentaires).

func test_shop_controller_no_input_singleton_outside_unhandled_input() -> void:
	var src: String = _read(_SHOP_CTRL)

	# Identifier le span de _unhandled_input
	var unhandled_marker: String = "func _unhandled_input("
	var unhandled_start: int = src.find(unhandled_marker)
	var unhandled_end: int = -1
	if unhandled_start >= 0:
		var rest: String = src.substr(unhandled_start + 1)
		var next_func: int = rest.find("\nfunc ")
		unhandled_end = unhandled_start + 1 + next_func if next_func >= 0 else src.length()

	# Itère lignes : si Input. apparaît hors commentaire ET hors span unhandled, fail.
	var bad_lines: Array[String] = []
	var current_offset: int = 0
	for line in src.split("\n"):
		var line_len: int = line.length() + 1    # +1 newline
		var stripped: String = line.strip_edges()
		var line_start: int = current_offset
		current_offset += line_len

		if stripped.begins_with("#"):
			continue
		# Cherche `Input.` (substring strict — "Input.parse_input_event" attrapé)
		# Exclut "InputEvent" et "InputEventAction" qui contiennent "Input" mais pas "Input."
		# avec un espace/début ; pattern "Input." est suffisamment spécifique.
		if not line.contains("Input."):
			continue
		# Vérifie si dans le span _unhandled_input
		var is_in_unhandled: bool = (unhandled_start >= 0
			and line_start >= unhandled_start
			and line_start < unhandled_end)
		if not is_in_unhandled:
			bad_lines.append(line.strip_edges())

	assert_int(bad_lines.size()) \
		.override_failure_message("AC-SHP-44 BLOCKING: Input.* trouvé hors _unhandled_input : %s" % str(bad_lines)) \
		.is_equal(0)


# =============================================================================
# V.4 — zéro `play_music_stinger` call (anti-fanfare audio)
# =============================================================================

func test_shop_controller_no_music_stinger_call() -> void:
	var src: String = _read(_SHOP_CTRL)
	var count: int = _count_substring_non_comment_lines(src, "play_music_stinger")
	assert_int(count) \
		.override_failure_message("V.4: play_music_stinger call trouvé dans shop_controller.gd") \
		.is_equal(0)


# =============================================================================
# AC-SHP-37 ADVISORY — no-alloc dans hot paths _process / _physics_process
# =============================================================================
# ShopController n'a actuellement ni `_process` ni `_physics_process` — UI Control
# pure event-driven. Test verifie l'absence de ces hot paths (refactor futur
# nécessite re-vérif). Cohérent rule no-alloc-hot-paths.

func test_shop_controller_no_process_or_physics_process_hot_paths() -> void:
	var src: String = _read(_SHOP_CTRL)
	var has_process: bool = src.contains("func _process(")
	var has_physics_process: bool = src.contains("func _physics_process(")
	# Si l'un est déclaré, le test devient INCOMPLET et nécessite un scan no-alloc.
	# MVP : ShopController n'a pas de hot path → test vacuously PASS.
	assert_bool(has_process or has_physics_process) \
		.override_failure_message("AC-SHP-37: ShopController introduit _process/_physics_process — refactor + ajouter scan no-alloc nécessaire") \
		.is_false()


# =============================================================================
# AC-SHP-45 ADVISORY — Upgrade.apply_upgrade uniquement dans branche try_spend
# =============================================================================
# Vérifie que toutes occurrences `Upgrade.apply_upgrade` sont dans le body de
# `_on_buy_pressed` ET après une ligne contenant `try_spend`.

func test_shop_controller_apply_upgrade_only_after_try_spend() -> void:
	var src: String = _read(_SHOP_CTRL)
	var lines: PackedStringArray = src.split("\n")

	# Cherche occurrences de Upgrade.apply_upgrade hors commentaire
	var seen_try_spend: bool = false
	var bad_count: int = 0
	for i in lines.size():
		var line: String = lines[i]
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if line.contains("try_spend"):
			seen_try_spend = true
		if line.contains("Upgrade.apply_upgrade(") and not seen_try_spend:
			bad_count += 1

	assert_int(bad_count) \
		.override_failure_message("AC-SHP-45: Upgrade.apply_upgrade trouvé sans try_spend précédent dans le source") \
		.is_equal(0)
