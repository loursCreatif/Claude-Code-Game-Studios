# Tests unitaires Story-001 — HUDSystem autoload skeleton + CanvasLayer + pull boot.
# Couvre AC-HUD-01/02/03/04/17/18.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — automated unit tests (coding-standards.md §Test Evidence).
#
# Pattern : injection de dépendances via _inject_dependencies(gsm, credit)
# pour bypasser l'assert autoload order sans les vrais singletons.
# Référence : tests/integration/save_load/autoload_skeleton_test.gd.
#
# Naming : test_hud_[scenario]_[expected_result] (test-standards.md).

extends GdUnitTestSuite

const _HUD_SCRIPT_PATH: String = "res://src/gameplay/hud/hud_system.gd"
const _MOCK_GSM_PATH: String = "res://tests/unit/hud/mock_gsm.gd"
const _MOCK_CREDIT_PATH: String = "res://tests/unit/hud/mock_credit_economy.gd"

# Préchargés une fois — évite preload répété dans chaque test.
var _MockGSM: GDScript = preload("res://tests/unit/hud/mock_gsm.gd")
var _MockCredit: GDScript = preload("res://tests/unit/hud/mock_credit_economy.gd")
var _HUDScript: GDScript = preload("res://src/gameplay/hud/hud_system.gd")

# =============================================================================
# Helpers — instanciation hermétique
# =============================================================================

## Instancie HUD + mocks avec l'état initial souhaité.
## add_child(hud) déclenche _ready() une fois les dépendances injectées.
func _make_hud(gsm_state: int, credit_total: int) -> Array:
	var mock_gsm: Node = _MockGSM.new() as Node
	var mock_credit: Node = _MockCredit.new() as Node
	add_child(mock_gsm)
	add_child(mock_credit)
	mock_gsm.set_state(gsm_state)
	mock_credit.set_total(credit_total)

	var hud: Node = _HUDScript.new() as Node
	hud._inject_dependencies(mock_gsm, mock_credit)
	add_child(hud)  # déclenche _ready()

	return [hud, mock_gsm, mock_credit]


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()

# =============================================================================
# AC-HUD-01 — MENU boot → canvas caché, aucune erreur
# =============================================================================

## GIVEN HUD instancié, WHEN _ready() exécuté avec State.MENU,
## THEN _canvas_layer.visible == false.
## Source : AC-HUD-01 [BLOCKING][AUTO].
func test_hud_boot_menu_state_canvas_hidden() -> void:
	# Arrange + Act
	var nodes: Array = _make_hud(0, 0)  # State.MENU = 0
	var hud: Node = nodes[0]

	# Assert
	var canvas: CanvasLayer = hud._canvas_layer
	assert_bool(canvas.visible) \
		.override_failure_message("AC-HUD-01: _canvas_layer.visible doit être false quand état=MENU(0)") \
		.is_false()

	_free_all(nodes)

# =============================================================================
# AC-HUD-02 — Boot pull total hard set avant tout signal
# =============================================================================

## GIVEN CreditEconomy.get_total() retourne 47,
## WHEN _ready() s'exécute (AVANT tout signal credits_changed),
## THEN _credit_counter_label.text == "47".
## Source : AC-HUD-02 [BLOCKING][AUTO].
func test_hud_boot_pull_total_hard_sets_label_text() -> void:
	# Arrange + Act
	var nodes: Array = _make_hud(1, 47)  # State.PLAYING = 1

	var hud: Node = nodes[0]

	# Assert
	var label: Label = hud._credit_counter_label
	assert_str(label.text) \
		.override_failure_message("AC-HUD-02: label.text doit valoir '47' après pull boot (avant tout signal)") \
		.is_equal("47")

	_free_all(nodes)

# =============================================================================
# AC-HUD-03 — CanvasLayer.layer == 50 ET < 100
# =============================================================================

## GIVEN HUD instancié, WHEN _ready() complet,
## THEN _canvas_layer.layer == 50 ET < 100 (HUD_LAYER_MAX réservé GSM).
## Source : AC-HUD-03 [BLOCKING][AUTO].
func test_hud_canvas_layer_equals_50_under_max_100() -> void:
	# Arrange + Act
	var nodes: Array = _make_hud(0, 0)
	var hud: Node = nodes[0]

	var layer: int = hud._canvas_layer.layer

	# Assert — double assert (valeur exacte + garde < 100)
	assert_int(layer) \
		.override_failure_message("AC-HUD-03 (exact): _canvas_layer.layer doit être 50 (HUD_CANVAS_LAYER)") \
		.is_equal(50)
	assert_int(layer) \
		.override_failure_message("AC-HUD-03 (max): _canvas_layer.layer doit être < 100 (GSM layer_max réservé)") \
		.is_less(100)

	_free_all(nodes)

# =============================================================================
# AC-HUD-04 — connexions signals correctement établies
# =============================================================================

## GIVEN HUD instancié, WHEN _ready() complet,
## THEN credits_changed connecté (1 connexion, pas de flag DEFERRED) ET
##      state_changed connecté avec flag CONNECT_DEFERRED.
## Source : AC-HUD-04 [BLOCKING][AUTO].
func test_hud_boot_connects_credits_changed_and_state_changed_deferred() -> void:
	# Arrange + Act
	var nodes: Array = _make_hud(0, 0)
	var hud: Node = nodes[0]
	var mock_gsm: Node = nodes[1]
	var mock_credit: Node = nodes[2]

	# Assert credits_changed — 1 connexion SYNC (pas de CONNECT_DEFERRED)
	var credit_connections: Array = mock_credit.credits_changed.get_connections()
	assert_int(credit_connections.size()) \
		.override_failure_message("AC-HUD-04: credits_changed doit avoir exactement 1 connexion") \
		.is_equal(1)
	assert_object(credit_connections[0]["callable"].get_object()) \
		.override_failure_message("AC-HUD-04: credits_changed doit être connecté au HUD") \
		.is_equal(hud)

	# Assert state_changed — 1 connexion avec flag CONNECT_DEFERRED
	var state_connections: Array = mock_gsm.state_changed.get_connections()
	assert_int(state_connections.size()) \
		.override_failure_message("AC-HUD-04: state_changed doit avoir exactement 1 connexion") \
		.is_equal(1)
	assert_object(state_connections[0]["callable"].get_object()) \
		.override_failure_message("AC-HUD-04: state_changed doit être connecté au HUD") \
		.is_equal(hud)
	var flags: int = state_connections[0]["flags"]
	assert_bool((flags & CONNECT_DEFERRED) != 0) \
		.override_failure_message("AC-HUD-04: state_changed doit être connecté avec CONNECT_DEFERRED") \
		.is_true()

	_free_all(nodes)

# =============================================================================
# AC-HUD-17 — pull boot appelle chaque dep exactement 1×
# =============================================================================

## GIVEN spy sur MockGSM.get_current_state() + MockCreditEconomy.get_total(),
## WHEN _ready() s'exécute,
## THEN chaque méthode appelée exactement 1× (pull pattern, jamais signal game_booted).
## Source : AC-HUD-17 [BLOCKING][AUTO].
func test_hud_boot_pull_calls_each_dependency_exactly_once() -> void:
	# Arrange — reset compteurs (défaut 0 à la construction)
	var mock_gsm: Node = _MockGSM.new() as Node
	var mock_credit: Node = _MockCredit.new() as Node
	add_child(mock_gsm)
	add_child(mock_credit)
	mock_gsm.set_state(0)
	mock_credit.set_total(0)

	# Compteurs sont déjà à 0 — _ready() non encore appelé
	assert_int(mock_gsm.get_current_state_call_count) \
		.override_failure_message("AC-HUD-17 (pre-ready): get_current_state_call_count doit être 0 avant _ready()") \
		.is_equal(0)
	assert_int(mock_credit.get_total_call_count) \
		.override_failure_message("AC-HUD-17 (pre-ready): get_total_call_count doit être 0 avant _ready()") \
		.is_equal(0)

	# Act — add_child déclenche _ready()
	var hud: Node = _HUDScript.new() as Node
	hud._inject_dependencies(mock_gsm, mock_credit)
	add_child(hud)

	# Assert — exactement 1 appel chacun
	assert_int(mock_gsm.get_current_state_call_count) \
		.override_failure_message("AC-HUD-17: get_current_state() doit être appelé exactement 1× au boot") \
		.is_equal(1)
	assert_int(mock_credit.get_total_call_count) \
		.override_failure_message("AC-HUD-17: get_total() doit être appelé exactement 1× au boot") \
		.is_equal(1)

	hud.queue_free()
	mock_gsm.queue_free()
	mock_credit.queue_free()

# =============================================================================
# AC-HUD-18 — BOOT_HYDRATE signal post-ready ne crash pas
# =============================================================================

## GIVEN HUD _ready() terminé (label.text="0"), mock CreditEconomy émet credits_changed(15, 0, BOOT_HYDRATE),
## WHEN await 1 idle frame,
## THEN no crash + label hard-set à "15" (story-002 — delta==0 → hard set, aucun tween).
## Source : AC-HUD-18 [BLOCKING][AUTO]. Mis à jour story-002 (stub no-op remplacé par impl réelle).
func test_hud_boot_hydrate_signal_no_crash() -> void:
	# Arrange
	var nodes: Array = _make_hud(0, 0)
	var hud: Node = nodes[0]
	var mock_credit: Node = nodes[2]

	# Vérification état initial
	assert_str(hud._credit_counter_label.text) \
		.override_failure_message("AC-HUD-18 (pre-signal): label.text doit être '0' après boot") \
		.is_equal("0")

	# Act — émet BOOT_HYDRATE (SourceKind=3)
	mock_credit.emit_credits_changed(15, 0, 3)  # SourceKind.BOOT_HYDRATE = 3
	await get_tree().process_frame

	# Assert — no crash + hard-set à "15" (story-002 R-HUD-3 + R-HUD-7 delta==0 guard)
	assert_bool(is_instance_valid(hud)) \
		.override_failure_message("AC-HUD-18: HUD doit être valide après réception du signal BOOT_HYDRATE") \
		.is_true()
	assert_str(hud._credit_counter_label.text) \
		.override_failure_message("AC-HUD-18: label.text doit être '15' (hard-set story-002, delta==0 no tween)") \
		.is_equal("15")

	_free_all(nodes)
