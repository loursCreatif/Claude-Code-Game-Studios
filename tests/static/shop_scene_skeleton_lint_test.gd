# Tests static Story-001 — `scenes/shop/shop.tscn` skeleton parse-clean + R-SHP-2.
# Couvre AC-SHP-29 (CanvasLayer.layer == 60) + AC-SHP-30 (ShopRoot.process_mode == 3) +
# hierarchy R-SHP-2 (15 nœuds attendus, ordre figé) + Background.color == #0A0A12.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Source : ADR-0007 D-5 (Shop = scène container) + R-SHP-1/2/16 (shop-system.md).

extends GdUnitTestSuite

const _SHOP_SCENE_PATH: String = "res://scenes/shop/shop.tscn"
const _EXPECTED_BG_COLOR_HEX: String = "0a0a12"


# =============================================================================
# Parse-clean : load + instantiate
# =============================================================================

## GIVEN res://scenes/shop/shop.tscn,
## WHEN load() puis instantiate(),
## THEN root non-null, type CanvasLayer, name == "ShopCanvas".
func test_shop_scene_parse_clean_root_is_canvaslayer() -> void:
	var scene: PackedScene = load(_SHOP_SCENE_PATH) as PackedScene
	assert_object(scene) \
		.override_failure_message("AC-SHP final: %s ne charge pas comme PackedScene" % _SHOP_SCENE_PATH) \
		.is_not_null()

	var root: Node = scene.instantiate()
	assert_object(root) \
		.override_failure_message("AC-SHP final: instantiate() retourne null") \
		.is_not_null()
	assert_str(root.name) \
		.override_failure_message("AC-SHP final: root name doit être 'ShopCanvas' (got '%s')" % root.name) \
		.is_equal("ShopCanvas")
	assert_bool(root is CanvasLayer) \
		.override_failure_message("AC-SHP final: root doit être CanvasLayer (got %s)" % root.get_class()) \
		.is_true()

	root.queue_free()


# =============================================================================
# AC-SHP-29 — CanvasLayer.layer == 60
# =============================================================================

## GIVEN ShopCanvas instance,
## WHEN lecture .layer,
## THEN == 60 (R-SHP-2 layer convention HUD=50 / Shop=60 / GSM=100).
func test_shop_scene_ac_shp_29_canvas_layer_is_60() -> void:
	var scene: PackedScene = load(_SHOP_SCENE_PATH) as PackedScene
	var root: CanvasLayer = scene.instantiate() as CanvasLayer

	assert_int(root.layer) \
		.override_failure_message("AC-SHP-29: ShopCanvas.layer doit être 60 (got %d)" % root.layer) \
		.is_equal(60)

	root.queue_free()


# =============================================================================
# AC-SHP-30 — ShopRoot.process_mode == PROCESS_MODE_ALWAYS (3)
# =============================================================================

## GIVEN ShopRoot Control,
## WHEN lecture .process_mode,
## THEN == PROCESS_MODE_ALWAYS (3) — ATTENTION : 4 = PROCESS_MODE_DISABLED bug runtime SHIP-CRITICAL.
## Source : R-SHP-16 + erratum 2026-04-28 evidence doc story-001.
func test_shop_scene_ac_shp_30_shop_root_process_mode_is_always() -> void:
	var scene: PackedScene = load(_SHOP_SCENE_PATH) as PackedScene
	var root: CanvasLayer = scene.instantiate() as CanvasLayer
	var shop_root: Control = root.get_node("ShopRoot") as Control

	assert_object(shop_root) \
		.override_failure_message("AC-SHP-30: ShopRoot child manquant sous ShopCanvas") \
		.is_not_null()
	assert_int(shop_root.process_mode) \
		.override_failure_message("AC-SHP-30: ShopRoot.process_mode doit être PROCESS_MODE_ALWAYS=%d (got %d — si 4, c'est PROCESS_MODE_DISABLED, bug SHIP-CRITICAL)" % [Node.PROCESS_MODE_ALWAYS, shop_root.process_mode]) \
		.is_equal(Node.PROCESS_MODE_ALWAYS)

	root.queue_free()


# =============================================================================
# Hierarchy R-SHP-2 — 15 nœuds attendus, ordre figé
# =============================================================================

## GIVEN scene instantiée,
## WHEN walk de l'arbre,
## THEN tous les nœuds R-SHP-2 présents (ShopCanvas → ShopRoot → Background, MarginContainer/VBoxContainer/{ShopTitle, HSeparator, CreditDisplay/{CreditLabel, CreditValueLabel}, UpgradeList/{UpgradeCard_0, UpgradeCard_1}, FooterRow/ContinueButton}).
func test_shop_scene_hierarchy_rshp2_all_nodes_present() -> void:
	var scene: PackedScene = load(_SHOP_SCENE_PATH) as PackedScene
	var root: CanvasLayer = scene.instantiate() as CanvasLayer

	# Map nodepath → expected type name (string compare via get_class()).
	var expected: Dictionary = {
		"ShopRoot": "Control",
		"ShopRoot/Background": "ColorRect",
		"ShopRoot/MarginContainer": "MarginContainer",
		"ShopRoot/MarginContainer/VBoxContainer": "VBoxContainer",
		"ShopRoot/MarginContainer/VBoxContainer/ShopTitle": "Label",
		"ShopRoot/MarginContainer/VBoxContainer/HSeparator": "HSeparator",
		"ShopRoot/MarginContainer/VBoxContainer/CreditDisplay": "HBoxContainer",
		"ShopRoot/MarginContainer/VBoxContainer/CreditDisplay/CreditLabel": "Label",
		"ShopRoot/MarginContainer/VBoxContainer/CreditDisplay/CreditValueLabel": "Label",
		"ShopRoot/MarginContainer/VBoxContainer/UpgradeList": "VBoxContainer",
		"ShopRoot/MarginContainer/VBoxContainer/UpgradeList/UpgradeCard_0": "PanelContainer",
		"ShopRoot/MarginContainer/VBoxContainer/UpgradeList/UpgradeCard_1": "PanelContainer",
		"ShopRoot/MarginContainer/VBoxContainer/FooterRow": "HBoxContainer",
		"ShopRoot/MarginContainer/VBoxContainer/FooterRow/ContinueButton": "Button",
	}

	for path: String in expected.keys():
		var node: Node = root.get_node_or_null(path)
		assert_object(node) \
			.override_failure_message("R-SHP-2: noeud manquant à %s" % path) \
			.is_not_null()
		assert_str(node.get_class()) \
			.override_failure_message("R-SHP-2: noeud %s doit être de type %s (got %s)" % [path, expected[path], node.get_class()]) \
			.is_equal(expected[path])

	root.queue_free()


# =============================================================================
# Background.color == #0A0A12 (SHOP_BG Chrome Zen token)
# =============================================================================

## GIVEN Background ColorRect,
## WHEN comparaison .color contre #0A0A12,
## THEN match (tolerance 1/255 par canal — encodage float Godot).
func test_shop_scene_background_color_is_shop_bg_token() -> void:
	var scene: PackedScene = load(_SHOP_SCENE_PATH) as PackedScene
	var root: CanvasLayer = scene.instantiate() as CanvasLayer
	var bg: ColorRect = root.get_node("ShopRoot/Background") as ColorRect

	assert_object(bg) \
		.override_failure_message("Background ColorRect manquant sous ShopRoot") \
		.is_not_null()

	var expected: Color = Color(_EXPECTED_BG_COLOR_HEX)
	var got: Color = bg.color
	# Tolerance 1.5/255 ≈ 0.006 par canal (float roundtrip ColorRect editor).
	var tolerance: float = 1.5 / 255.0
	assert_bool(absf(got.r - expected.r) <= tolerance) \
		.override_failure_message("Background.color.r mismatch: expected %f got %f" % [expected.r, got.r]) \
		.is_true()
	assert_bool(absf(got.g - expected.g) <= tolerance) \
		.override_failure_message("Background.color.g mismatch: expected %f got %f" % [expected.g, got.g]) \
		.is_true()
	assert_bool(absf(got.b - expected.b) <= tolerance) \
		.override_failure_message("Background.color.b mismatch: expected %f got %f" % [expected.b, got.b]) \
		.is_true()

	root.queue_free()
