# Lint static Story-012 — Chrome Zen palette compliance + scene constraints.
# Couvre : §J.7 (zéro gradient / zéro corner_radius / zéro shader),
# AC-SHP-32 ADVISORY (Background statique sans AnimationPlayer),
# §J.4 (ContinueButton custom_minimum_size Vector2(200, 48)).
# Framework : GdUnit4 (extends GdUnitTestSuite). Type : Lint static.
# Source : design/gdd/shop-system.md §J.2/J.4/J.7/J.8.
extends GdUnitTestSuite

const _SHOP_SCENE_PATH: String = "res://scenes/shop/shop.tscn"


func _read_scene_source() -> String:
	var f: FileAccess = FileAccess.open(_SHOP_SCENE_PATH, FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()
	return src


# =============================================================================
# §J.7 — zéro gradient (interdit Chrome Zen lignes droites)
# =============================================================================

## GIVEN shop.tscn,
## WHEN grep "gradient" (case-insensitive),
## THEN 0 match (Chrome Zen interdit gradient — palette uniquement).
func test_shop_scene_chrome_zen_no_gradient() -> void:
	var src: String = _read_scene_source()
	var lower: String = src.to_lower()
	assert_bool(lower.contains("gradient")) \
		.override_failure_message("§J.7: 'gradient' interdit dans shop.tscn (Chrome Zen palette stricte, lignes droites)") \
		.is_false()


# =============================================================================
# §J.7 — zéro corner_radius non-nul (interdit Chrome Zen)
# =============================================================================

## GIVEN shop.tscn,
## WHEN grep "corner_radius",
## THEN 0 match — toute déclaration corner_radius (même = 0) interdite par lint
## strict (Chrome Zen lignes droites = StyleBoxFlat sans corner_radius du tout).
func test_shop_scene_chrome_zen_no_corner_radius() -> void:
	var src: String = _read_scene_source()
	assert_bool(src.contains("corner_radius")) \
		.override_failure_message("§J.7: 'corner_radius' interdit dans shop.tscn (Chrome Zen lignes droites)") \
		.is_false()


# =============================================================================
# §J.7 — zéro shader (interdit Chrome Zen)
# =============================================================================

## GIVEN shop.tscn,
## WHEN grep "shader" (case-insensitive — couvre ShaderMaterial / shader_parameter),
## THEN 0 match — Chrome Zen interdit shader background.
func test_shop_scene_chrome_zen_no_shader() -> void:
	var src: String = _read_scene_source()
	var lower: String = src.to_lower()
	assert_bool(lower.contains("shader")) \
		.override_failure_message("§J.7: 'shader' interdit dans shop.tscn (Chrome Zen palette uniquement, no shader background)") \
		.is_false()


# =============================================================================
# AC-SHP-32 ADVISORY — Background sans AnimationPlayer
# =============================================================================

## GIVEN shop.tscn,
## WHEN grep "AnimationPlayer",
## THEN 0 match (Background statique, pas d'animation arrière-plan Chrome Zen).
func test_shop_scene_ac_shp_32_no_animation_player() -> void:
	var src: String = _read_scene_source()
	assert_bool(src.contains("AnimationPlayer")) \
		.override_failure_message("AC-SHP-32: AnimationPlayer interdit dans shop.tscn (Chrome Zen background statique)") \
		.is_false()


# =============================================================================
# §J.4 — ContinueButton custom_minimum_size Vector2(200, 48)
# =============================================================================

## GIVEN shop.tscn (ContinueButton declaration),
## WHEN scan section,
## THEN custom_minimum_size = Vector2(200, 48) présent.
func test_shop_scene_section_j4_continue_button_custom_minimum_size() -> void:
	var src: String = _read_scene_source()
	# Localiser section ContinueButton
	var marker: String = "[node name=\"ContinueButton\""
	var start: int = src.find(marker)
	assert_int(start) \
		.override_failure_message("§J.4: section ContinueButton manquante dans shop.tscn") \
		.is_greater_equal(0)
	# Section continue jusqu'au prochain [node ou EOF
	var rest: String = src.substr(start)
	var next_node: int = rest.find("\n[node ", 1)
	var section: String = rest.substr(0, next_node) if next_node >= 0 else rest
	# Vérifier custom_minimum_size = Vector2(200, 48)
	assert_bool(section.contains("custom_minimum_size = Vector2(200, 48)")) \
		.override_failure_message("§J.4: ContinueButton.custom_minimum_size doit être Vector2(200, 48), section observée :\n%s" % section) \
		.is_true()


# =============================================================================
# §J.4 — ContinueButton text == "CONTINUER" (capitales)
# =============================================================================

## GIVEN shop.tscn (ContinueButton declaration),
## WHEN scan section,
## THEN text = "CONTINUER" (capitales sémantique R-SHP-10).
func test_shop_scene_section_j4_continue_button_text_capitales() -> void:
	var src: String = _read_scene_source()
	var marker: String = "[node name=\"ContinueButton\""
	var start: int = src.find(marker)
	var rest: String = src.substr(start)
	var next_node: int = rest.find("\n[node ", 1)
	var section: String = rest.substr(0, next_node) if next_node >= 0 else rest
	assert_bool(section.contains("text = \"CONTINUER\"")) \
		.override_failure_message("§J.4: ContinueButton.text doit être \"CONTINUER\" (capitales)") \
		.is_true()


# =============================================================================
# Chrome Zen — MarginContainer marges généreuses (≥ 64 px à 1080p)
# =============================================================================

## GIVEN shop.tscn,
## WHEN scan MarginContainer override constants,
## THEN margin_left/right/top/bottom ≥ 64 (Chrome Zen marges respiration).
func test_shop_scene_margin_container_generous_padding() -> void:
	var src: String = _read_scene_source()
	# Quatre marges déclarées explicitement
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		var pattern: String = "theme_override_constants/%s = " % side
		var idx: int = src.find(pattern)
		assert_int(idx) \
			.override_failure_message("Chrome Zen: MarginContainer %s manquant" % side) \
			.is_greater_equal(0)
		# Extraire la valeur après "= " jusqu'au newline
		var after: String = src.substr(idx + pattern.length())
		var nl: int = after.find("\n")
		var val_str: String = after.substr(0, nl).strip_edges()
		var val: int = int(val_str)
		assert_int(val) \
			.override_failure_message("Chrome Zen: MarginContainer %s doit être ≥ 64 (got %d)" % [side, val]) \
			.is_greater_equal(64)
