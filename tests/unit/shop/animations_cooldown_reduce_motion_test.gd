# Unit test Story-013 — Animations cooldown + reduce motion + AC-SHP-31 lint.
# Couvre :
# - AC-SHP-31 lint statique (count create_tween() == count set_pause_mode TWEEN_PAUSE_PROCESS)
# - EC-SHP-30 cooldown shake 400 ms (10 clicks rapides → 1 shake + 9 cooldown skip)
# - EC-SHP-29 reduce motion hook (counter/pulse/shake skip si _reduce_motion=true)
# - Counter tween appelé à chaque credits_changed (delta non-nul)
# Framework : GdUnit4 (extends GdUnitTestSuite). Type : Logic.
extends GdUnitTestSuite

const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")
const _SHOP_CONTROLLER_PATH: String = "res://src/ui/shop/shop_controller.gd"
const _SAVE_KEY: String = "owned_upgrades"
const _CREDIT_KEY: String = "total_credits"


func before_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_KEY, 0)
	CreditEconomy._total_credits = 0
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false


func after_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_KEY, 0)
	CreditEconomy._total_credits = 0
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false


# =============================================================================
# AC-SHP-31 — lint statique : count create_tween() == count set_pause_mode TWEEN_PAUSE_PROCESS
# =============================================================================

## GIVEN shop_controller.gd source,
## WHEN scan all `create_tween()` calls et `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)`,
## THEN counts égaux (chaque Tween créé set_pause_mode TWEEN_PAUSE_PROCESS).
func test_ac_shp_31_create_tween_matches_set_pause_mode_count() -> void:
	var f: FileAccess = FileAccess.open(_SHOP_CONTROLLER_PATH, FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()

	var lines: PackedStringArray = src.split("\n")
	var create_count: int = 0
	var pause_count: int = 0
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		# Compter create_tween() (mais pas dans le commentaire de doc)
		if stripped.contains("create_tween()") and not stripped.begins_with("#"):
			create_count += 1
		if stripped.contains("set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)"):
			pause_count += 1

	assert_int(create_count) \
		.override_failure_message("AC-SHP-31: at least 3 create_tween() expected (counter/pulse/shake), got %d" % create_count) \
		.is_greater_equal(3)
	assert_int(pause_count) \
		.override_failure_message("AC-SHP-31: count create_tween()=%d != count set_pause_mode TWEEN_PAUSE_PROCESS=%d (chaque Tween doit set_pause_mode)" % [create_count, pause_count]) \
		.is_equal(create_count)


# =============================================================================
# EC-SHP-29 — reduce motion : counter skip
# =============================================================================

## GIVEN _reduce_motion=true,
## WHEN _on_credits_changed handler invoque _animate_credit_counter(0, 50),
## THEN log contient "counter_skip_reduce_motion" PAS "counter".
func test_ec_shp_29_reduce_motion_counter_skipped() -> void:
	# Arrange
	CreditEconomy._total_credits = 0
	var s: Control = _ShopControllerScript.new()
	s._ready()
	s.set_reduce_motion_for_test(true)
	s.reset_animation_log_for_test()

	# Act
	s._on_credits_changed(50, 50, 0)    # delta non-nul attendu

	# Assert
	var log: Array[String] = s.get_animation_log()
	assert_bool(log.has("counter_skip_reduce_motion")) \
		.override_failure_message("EC-SHP-29: counter_skip_reduce_motion attendu, log=%s" % str(log)) \
		.is_true()
	assert_bool(log.has("counter")) \
		.override_failure_message("EC-SHP-29: 'counter' interdit quand reduce_motion=true, log=%s" % str(log)) \
		.is_false()

	s.free()


# =============================================================================
# EC-SHP-29 — reduce motion : pulse skip
# =============================================================================

## GIVEN _reduce_motion=true + cycle achat success,
## WHEN _animate_purchase_pulse appelé via _on_buy_pressed,
## THEN log contient "pulse_skip_reduce_motion".
func test_ec_shp_29_reduce_motion_pulse_skipped() -> void:
	# Arrange
	CreditEconomy._total_credits = 50
	var s: Control = _ShopControllerScript.new()
	s._ready()
	s.set_reduce_motion_for_test(true)
	s.reset_animation_log_for_test()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert
	var log: Array[String] = s.get_animation_log()
	assert_bool(log.has("pulse_skip_reduce_motion")) \
		.override_failure_message("EC-SHP-29: pulse_skip_reduce_motion attendu, log=%s" % str(log)) \
		.is_true()
	assert_bool(log.has("pulse")) \
		.override_failure_message("EC-SHP-29: 'pulse' interdit quand reduce_motion=true, log=%s" % str(log)) \
		.is_false()

	s.free()


# =============================================================================
# EC-SHP-29 — reduce motion : shake skip
# =============================================================================

## GIVEN _reduce_motion=true + click DISABLED (solde insuffisant),
## WHEN _animate_disabled_shake appelé via _on_buy_pressed,
## THEN log contient "shake_skip_reduce_motion".
func test_ec_shp_29_reduce_motion_shake_skipped() -> void:
	# Arrange
	CreditEconomy._total_credits = 5    # solde insuffisant pour cost=20
	var s: Control = _ShopControllerScript.new()
	s._ready()
	s.set_reduce_motion_for_test(true)
	s.reset_animation_log_for_test()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert
	var log: Array[String] = s.get_animation_log()
	assert_bool(log.has("shake_skip_reduce_motion")) \
		.override_failure_message("EC-SHP-29: shake_skip_reduce_motion attendu, log=%s" % str(log)) \
		.is_true()
	assert_bool(log.has("shake")) \
		.override_failure_message("EC-SHP-29: 'shake' interdit quand reduce_motion=true, log=%s" % str(log)) \
		.is_false()

	s.free()


# =============================================================================
# EC-SHP-30 — cooldown shake 400 ms : 10 clicks rapides → 1 shake + 9 skip
# =============================================================================

## GIVEN solde insuffisant (cost > total) + reduce_motion=false,
## WHEN 10 clicks DISABLED rapides (intra-frame, mêmes ticks_msec),
## THEN log contient 1 "shake" + 9 "shake_skip_cooldown" (cooldown 400 ms anti-spam).
func test_ec_shp_30_shake_cooldown_anti_spam_3hz() -> void:
	# Arrange
	CreditEconomy._total_credits = 5    # solde insuffisant
	var s: Control = _ShopControllerScript.new()
	s._ready()
	s.set_reduce_motion_for_test(false)
	s.reset_animation_log_for_test()
	s.reset_shake_cooldown_for_test()

	# Act — 10 clicks rapides intra-frame
	for i in range(10):
		s._on_buy_pressed(&"double_jump", 0)

	# Assert
	var log: Array[String] = s.get_animation_log()
	var shake_count: int = log.count("shake")
	var shake_skip_cooldown_count: int = log.count("shake_skip_cooldown")
	# Note : 1er shake passe en "shake_skip_no_card" si pas dans scene tree.
	# Test bare instance (sans scene) : log contient soit "shake" soit "shake_skip_no_card" pour le 1er,
	# puis "shake_skip_cooldown" pour les 9 suivants (cooldown set même en skip_no_card).
	var first_event_count: int = log.count("shake") + log.count("shake_skip_no_card")
	assert_int(first_event_count) \
		.override_failure_message("EC-SHP-30: exactement 1 shake event initial attendu (shake ou shake_skip_no_card), got %d (log=%s)" % [first_event_count, str(log)]) \
		.is_equal(1)
	assert_int(shake_skip_cooldown_count) \
		.override_failure_message("EC-SHP-30: 9 shake_skip_cooldown attendus (clicks 2-10), got %d (log=%s)" % [shake_skip_cooldown_count, str(log)]) \
		.is_equal(9)

	# Cooldown deadline doit être > now (active 400 ms)
	var deadline: int = s.get_shake_cooldown_until_ms_for_test(&"double_jump")
	assert_int(deadline) \
		.override_failure_message("EC-SHP-30: cooldown deadline doit être set > 0 (got %d)" % deadline) \
		.is_greater(Time.get_ticks_msec() - 1)

	s.free()


# =============================================================================
# Counter tween — appelé à chaque credits_changed avec delta non-nul
# =============================================================================

## GIVEN _reduce_motion=false + handler _on_credits_changed,
## WHEN credits_changed(50, 50, 0) émis (delta non-nul),
## THEN log contient "counter".
func test_counter_tween_triggered_on_credits_changed_with_delta() -> void:
	# Arrange
	CreditEconomy._total_credits = 0
	var s: Control = _ShopControllerScript.new()
	s._ready()
	s.set_reduce_motion_for_test(false)
	s.reset_animation_log_for_test()

	# Act
	s._on_credits_changed(50, 50, 0)

	# Assert
	var log: Array[String] = s.get_animation_log()
	assert_bool(log.has("counter")) \
		.override_failure_message("Counter tween: 'counter' attendu dans log post-credits_changed, log=%s" % str(log)) \
		.is_true()

	s.free()


# =============================================================================
# Counter tween — pas appelé si delta nul
# =============================================================================

## GIVEN _displayed_credit_value initial == new_value (delta = 0),
## WHEN _animate_credit_counter(50, 50),
## THEN log NE contient PAS "counter" (no-op si delta nul, économie cycles).
func test_counter_tween_skipped_if_delta_zero() -> void:
	# Arrange
	CreditEconomy._total_credits = 50
	var s: Control = _ShopControllerScript.new()
	s._ready()    # initial value = 50
	s.set_reduce_motion_for_test(false)
	s.reset_animation_log_for_test()

	# Act — credits_changed(50, 0, 0) : delta = 0 (callbacks defensive)
	s._on_credits_changed(50, 0, 0)

	# Assert
	var log: Array[String] = s.get_animation_log()
	assert_bool(log.has("counter")) \
		.override_failure_message("Counter tween: pas d'anim attendue si delta nul, log=%s" % str(log)) \
		.is_false()

	s.free()


# =============================================================================
# AC-SHP-31 — chaque helper anim contient set_pause_mode AVANT toute property tween
# =============================================================================

## GIVEN shop_controller.gd source,
## WHEN scan section function bodies (animate_credit_counter / pulse / shake),
## THEN chaque body contient set_pause_mode AVANT tween_property/tween_method.
func test_ac_shp_31_set_pause_mode_before_tween_property_in_each_helper() -> void:
	var f: FileAccess = FileAccess.open(_SHOP_CONTROLLER_PATH, FileAccess.READ)
	var src: String = f.get_as_text()
	f.close()

	for fn_name in ["_animate_credit_counter", "_animate_purchase_pulse", "_animate_disabled_shake"]:
		var marker: String = "func %s(" % fn_name
		var start: int = src.find(marker)
		assert_int(start) \
			.override_failure_message("AC-SHP-31: helper %s manquant dans shop_controller.gd" % fn_name) \
			.is_greater_equal(0)
		var rest: String = src.substr(start + marker.length())
		var next_func: int = rest.find("\nfunc ")
		var body: String = rest.substr(0, next_func) if next_func >= 0 else rest

		var pause_idx: int = body.find("set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)")
		var tween_prop_idx: int = body.find("tween_property(")
		var tween_method_idx: int = body.find("tween_method(")
		var first_tween_call: int = -1
		if tween_prop_idx >= 0 and (first_tween_call == -1 or tween_prop_idx < first_tween_call):
			first_tween_call = tween_prop_idx
		if tween_method_idx >= 0 and (first_tween_call == -1 or tween_method_idx < first_tween_call):
			first_tween_call = tween_method_idx
		# Si la fonction crée un tween, set_pause_mode doit précéder le 1er tween_*
		if first_tween_call >= 0:
			assert_int(pause_idx) \
				.override_failure_message("AC-SHP-31: %s doit appeler set_pause_mode AVANT tween_property/tween_method (pause_idx=%d, first_tween=%d)" % [fn_name, pause_idx, first_tween_call]) \
				.is_greater_equal(0)
			assert_bool(pause_idx < first_tween_call) \
				.override_failure_message("AC-SHP-31: %s : set_pause_mode (%d) doit précéder tween_* (%d)" % [fn_name, pause_idx, first_tween_call]) \
				.is_true()
