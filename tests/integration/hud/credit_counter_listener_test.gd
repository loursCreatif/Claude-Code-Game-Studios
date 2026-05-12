# Tests d'intégration Story-002 — HUDSystem credits_changed listener pull pattern SYNC.
# Couvre AC-HUD-05/06/07/08/09/10/11/19/20/21/22/24 (12 ACs).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — real CreditEconomy + real HUDSystem autoloads.
# Naming : test_hud_[scenario]_[expected_result] (test-standards.md).
#
# GDD   : design/gdd/hud-system.md R-HUD-3/5/6/7
# Story : production/epics/hud-system/story-002-pull-pattern-credits-changed-listener.md

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Setup / teardown — réinitialise les autoloads réels entre chaque test.
# ---------------------------------------------------------------------------

func before_test() -> void:
	# Reset CreditEconomy state (pattern existant — credit_economy_kill_integration_test.gd)
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = true
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	# GSM PLAYING requis pour Combat handler (HUD ne gate pas sur state ici)
	GameStateManager._current_state = GameStateManager.State.PLAYING
	# Reset HUD state
	HUDSystem._credit_counter_label.text = "0"
	HUDSystem._credit_counter_label.scale = Vector2.ONE
	if HUDSystem._active_pulse_tween != null and HUDSystem._active_pulse_tween.is_valid():
		HUDSystem._active_pulse_tween.kill()
	HUDSystem._active_pulse_tween = null


func after_test() -> void:
	# Nettoyage tween résiduel pour éviter interférence cross-tests
	if HUDSystem._active_pulse_tween != null and HUDSystem._active_pulse_tween.is_valid():
		HUDSystem._active_pulse_tween.kill()
	HUDSystem._active_pulse_tween = null
	HUDSystem._credit_counter_label.scale = Vector2.ONE
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	CreditEconomy._credited_this_run.clear()


# =============================================================================
# AC-HUD-05 — KILL increment SYNC same-frame
# =============================================================================

## GIVEN State.PLAYING actif et counter affiche "10",
## WHEN credits_changed(11, +1, SourceKind.KILL) émis SYNC,
## THEN label.text == "11" immédiatement (même tick, avant await).
## Source : AC-HUD-05 [BLOCKING][AUTO].
func test_hud_kill_increment_sync_same_frame() -> void:
	# Arrange
	HUDSystem._credit_counter_label.text = "10"

	# Act — émission directe SYNC (test-only pattern, vérifie la réaction HUD)
	CreditEconomy.credits_changed.emit(11, 1, CreditEconomy.SourceKind.KILL)

	# Assert — AVANT await : même tick garanti (connexion SYNC sans CONNECT_DEFERRED)
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-05: label.text doit être '11' dans le même tick (SYNC)") \
		.is_equal("11")

	# Tween démarré (incrément positif)
	assert_bool(HUDSystem._active_pulse_tween != null and HUDSystem._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-05: un tween de pulse doit être actif après KILL increment") \
		.is_true()


# =============================================================================
# AC-HUD-06 — SECRET +5 hard set instantané
# =============================================================================

## GIVEN counter "10",
## WHEN credits_changed(15, +5, SourceKind.SECRET) émis,
## THEN label.text == "15" instantanément (pas d'intermédiaire "11".."14").
## Source : AC-HUD-06 [BLOCKING][AUTO].
func test_hud_secret_plus_5_hard_set_instant() -> void:
	# Arrange
	HUDSystem._credit_counter_label.text = "10"

	# Act
	CreditEconomy.credits_changed.emit(15, 5, CreditEconomy.SourceKind.SECRET)

	# Assert — hard set direct sans animation par étapes
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-06: label.text doit être '15' instantanément (hard set), pas d'intermédiaire") \
		.is_equal("15")


# =============================================================================
# AC-HUD-07 — Multi-kill collision : tween précédent killed
# =============================================================================

## GIVEN counter "10" et tween en cours (delta>0),
## WHEN second credits_changed arrive pendant tween actif,
## THEN tween précédent killed + nouveau démarre ; label.text == "12".
## Source : AC-HUD-07 [BLOCKING][AUTO].
func test_hud_multi_kill_collision_kills_previous_tween() -> void:
	# Arrange — premier increment, tween démarre
	HUDSystem._credit_counter_label.text = "10"
	CreditEconomy.credits_changed.emit(11, 1, CreditEconomy.SourceKind.KILL)
	var first_tween: Tween = HUDSystem._active_pulse_tween

	assert_bool(first_tween != null and first_tween.is_valid()) \
		.override_failure_message("AC-HUD-07 (pre): premier tween doit être actif") \
		.is_true()

	# 50ms : tween encore en cours (durée totale 100ms)
	await get_tree().create_timer(0.05).timeout

	assert_bool(first_tween.is_valid()) \
		.override_failure_message("AC-HUD-07 (mid): premier tween doit encore être valide à 50ms") \
		.is_true()

	# Act — second kill pendant que le premier tween tourne
	CreditEconomy.credits_changed.emit(12, 1, CreditEconomy.SourceKind.KILL)

	# Assert — premier tween killed, nouveau créé
	assert_bool(first_tween.is_valid()) \
		.override_failure_message("AC-HUD-07: premier tween doit être killed (is_valid==false) après second emit") \
		.is_false()

	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-07: label.text doit être '12' après collision") \
		.is_equal("12")

	assert_bool(HUDSystem._active_pulse_tween != null and HUDSystem._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-07: un nouveau tween doit être actif") \
		.is_true()

	# Attendre fin du nouveau tween — label stable à "12"
	await get_tree().create_timer(0.15).timeout
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-07: label.text doit rester '12' après fin tween") \
		.is_equal("12")


# =============================================================================
# AC-HUD-08 — SPEND_SHOP hard set sans tween
# =============================================================================

## GIVEN counter "20",
## WHEN credits_changed(15, -5, SourceKind.SPEND_SHOP) reçu,
## THEN label.text == "15" immédiat ; scale == Vector2.ONE ; aucun tween.
## Source : AC-HUD-08 [BLOCKING][AUTO].
func test_hud_spend_shop_hard_set_no_tween() -> void:
	# Arrange
	HUDSystem._credit_counter_label.text = "20"

	# Act
	CreditEconomy.credits_changed.emit(15, -5, CreditEconomy.SourceKind.SPEND_SHOP)

	# Assert — hard set sans animation
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-08: label.text doit être '15' après SPEND_SHOP") \
		.is_equal("15")

	assert_bool(HUDSystem._credit_counter_label.scale == Vector2.ONE) \
		.override_failure_message("AC-HUD-08: scale doit être Vector2.ONE après SPEND_SHOP (pas d'animation)") \
		.is_true()

	var tween_active: bool = HUDSystem._active_pulse_tween != null \
		and HUDSystem._active_pulse_tween.is_valid()
	assert_bool(tween_active) \
		.override_failure_message("AC-HUD-08: aucun tween ne doit être actif après SPEND_SHOP (delta<0)") \
		.is_false()


# =============================================================================
# AC-HUD-09 — SPEND_SHOP same-tick frame-synchronous
# =============================================================================

## GIVEN counter "20", WHEN credits_changed delta<0 reçu SYNC,
## THEN label.text mis à jour dans le même _physics_process tick.
## Source : AC-HUD-09 [BLOCKING][AUTO].
func test_hud_spend_shop_same_tick_sync() -> void:
	# Arrange
	CreditEconomy._total_credits = 20
	HUDSystem._credit_counter_label.text = "20"

	# Act — production path via try_spend (émet credits_changed SYNC)
	var spent: bool = CreditEconomy.try_spend(5)

	# Assert — AVANT await (même tick)
	assert_bool(spent) \
		.override_failure_message("AC-HUD-09: try_spend(5) avec total=20 doit réussir") \
		.is_true()
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-09: label.text doit être '15' dans le même tick (SYNC SPEND_SHOP)") \
		.is_equal("15")


# =============================================================================
# AC-HUD-10 — try_spend fail : label inchangé
# =============================================================================

## GIVEN total=5, try_spend(10) échoue (5<10),
## THEN counter reste "5", aucun tween déclenché dans 200ms.
## Source : AC-HUD-10 [BLOCKING][AUTO].
func test_hud_try_spend_fail_no_label_change() -> void:
	# Arrange
	CreditEconomy._total_credits = 5
	HUDSystem._credit_counter_label.text = "5"

	# Act — échec garanti (coût > total)
	var spent: bool = CreditEconomy.try_spend(10)

	# Assert immédiat
	assert_bool(spent) \
		.override_failure_message("AC-HUD-10: try_spend(10) avec total=5 doit échouer") \
		.is_false()
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-10: label.text doit rester '5' (aucun signal émis)") \
		.is_equal("5")

	# Vérification 200ms : toujours inchangé, pas de tween parasite
	await get_tree().create_timer(0.2).timeout
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-10: label.text doit rester '5' après 200ms") \
		.is_equal("5")


# =============================================================================
# AC-HUD-11 — try_spend fail : aucun signal credits_changed reçu
# =============================================================================

## GIVEN HUD connecté à credits_changed + spy,
## WHEN try_spend échoue,
## THEN spy ne reçoit aucun appel (no signal emitted).
## Source : AC-HUD-11 [BLOCKING][AUTO].
func test_hud_try_spend_fail_no_signal_received() -> void:
	# Arrange — spy sur credits_changed
	var emit_count: int = 0
	var _spy_capture := func(_t: int, _d: int, _s: int) -> void:
		emit_count += 1
	CreditEconomy.credits_changed.connect(_spy_capture)

	CreditEconomy._total_credits = 5
	HUDSystem._credit_counter_label.text = "5"

	# Act
	CreditEconomy.try_spend(10)

	# Assert — spy n'a reçu aucun appel
	assert_int(emit_count) \
		.override_failure_message("AC-HUD-11: credits_changed ne doit pas être émis si try_spend échoue") \
		.is_equal(0)

	# Cleanup spy
	if CreditEconomy.credits_changed.is_connected(_spy_capture):
		CreditEconomy.credits_changed.disconnect(_spy_capture)


# =============================================================================
# AC-HUD-19 — 3 emits same tick MAX_KILLS_PER_SWING : séquence correcte
# =============================================================================

## GIVEN counter "10", State.PLAYING,
## WHEN 3 signals credits_changed(+1, KILL) back-to-back sans await,
## THEN label saute 10→11→12→13 à chaque emit, jamais > 13.
## Source : AC-HUD-19 [BLOCKING][AUTO].
func test_hud_3_emits_same_tick_max_kills_per_swing() -> void:
	# Arrange
	HUDSystem._credit_counter_label.text = "10"

	# Act — 3 emits séquentiels, même tick
	CreditEconomy.credits_changed.emit(11, 1, CreditEconomy.SourceKind.KILL)
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-19 (emit 1): label.text doit être '11'") \
		.is_equal("11")

	CreditEconomy.credits_changed.emit(12, 1, CreditEconomy.SourceKind.KILL)
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-19 (emit 2): label.text doit être '12'") \
		.is_equal("12")

	CreditEconomy.credits_changed.emit(13, 1, CreditEconomy.SourceKind.KILL)
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-19 (emit 3): label.text doit être '13'") \
		.is_equal("13")

	# Post-300ms : valeur stable à "13"
	await get_tree().create_timer(0.3).timeout
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-19: label.text doit être '13' après 300ms") \
		.is_equal("13")


# =============================================================================
# AC-HUD-20 — 3 emits same tick : pas d'overshoot
# =============================================================================

## GIVEN 3 signals credits_changed séquentiels même tick,
## THEN HUD ne produit pas 3 tweens superposés ; label ne dépasse jamais "13".
## Source : AC-HUD-20 [BLOCKING][AUTO].
func test_hud_3_emits_no_overshoot() -> void:
	# Arrange
	HUDSystem._credit_counter_label.text = "10"

	# Act — 3 emits back-to-back
	CreditEconomy.credits_changed.emit(11, 1, CreditEconomy.SourceKind.KILL)
	CreditEconomy.credits_changed.emit(12, 1, CreditEconomy.SourceKind.KILL)
	CreditEconomy.credits_changed.emit(13, 1, CreditEconomy.SourceKind.KILL)

	# Assert immédiat — valeur finale correcte (pas d'overshoot)
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-20: label.text doit être '13' (pas d'overshoot)") \
		.is_equal("13")

	# Vérification qu'un seul tween est actif (les deux premiers ont été killed)
	assert_bool(HUDSystem._active_pulse_tween != null and HUDSystem._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-20: exactement 1 tween actif après 3 emits (collision kill pattern)") \
		.is_true()

	# Après 300ms : label stable "13", aucun overshoot possible
	await get_tree().create_timer(0.3).timeout
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-20: label.text doit rester '13' après 300ms (no overshoot)") \
		.is_equal("13")


# =============================================================================
# AC-HUD-21 — Idempotence respawn : counter stable post-RESPAWNING
# =============================================================================

## GIVEN counter "20" State.PLAYING, joueur meurt (RESPAWNING émis),
## WHEN aucun credits_changed n'est émis (Credit Rule 2 irréversibilité),
## THEN label.text reste "20" constant durant 200ms post-RESPAWNING.
## Source : AC-HUD-21 [BLOCKING][AUTO].
func test_hud_respawn_no_credits_change_label_stable() -> void:
	# Arrange
	HUDSystem._credit_counter_label.text = "20"
	var pre_death_text: String = HUDSystem._credit_counter_label.text

	# Act — simuler die → RESPAWNING (sans credits_changed)
	GameStateManager.state_changed.emit(GameStateManager.State.RESPAWNING)
	await get_tree().create_timer(0.05).timeout

	# Assert pendant RESPAWNING
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-21: label.text doit rester '%s' pendant RESPAWNING" % pre_death_text) \
		.is_equal(pre_death_text)

	# 200ms post-RESPAWNING
	await get_tree().create_timer(0.15).timeout
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-21: label.text doit rester '%s' 200ms post-RESPAWNING" % pre_death_text) \
		.is_equal(pre_death_text)


# =============================================================================
# AC-HUD-22 — Retour PLAYING après respawn : pas de re-pull get_total()
# =============================================================================

## GIVEN State PLAYING→RESPAWNING→PLAYING, counter "20",
## WHEN State.PLAYING restauré,
## THEN counter affiche toujours "20" — HUD ne re-pull pas get_total().
## Source : AC-HUD-22 [BLOCKING][AUTO].
## Note : vérification de l'absence de re-pull est heuristique (pas de spy
## sans mock — prouvé par absence de credits_changed entre transitions).
func test_hud_state_playing_restored_no_re_pull() -> void:
	# Arrange
	HUDSystem._credit_counter_label.text = "20"

	# Act — cycle complet PLAYING → RESPAWNING → PLAYING
	GameStateManager.state_changed.emit(GameStateManager.State.RESPAWNING)
	await get_tree().create_timer(0.05).timeout
	GameStateManager.state_changed.emit(GameStateManager.State.PLAYING)
	await get_tree().process_frame

	# Assert — label inchangé (pas de double-hydration)
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-22: label.text doit être '20' après retour PLAYING (pas de re-pull)") \
		.is_equal("20")

	# 200ms : toujours stable
	await get_tree().create_timer(0.2).timeout
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-22: label.text doit rester '20' 200ms post-PLAYING restauré") \
		.is_equal("20")


# =============================================================================
# AC-HUD-24 — BOOT_HYDRATE delta==0 : aucun tween lancé
# =============================================================================

## GIVEN _ready() terminé,
## WHEN credits_changed(15, 0, SourceKind.BOOT_HYDRATE) reçu,
## THEN label.text == "15" ; aucun tween actif.
## Source : AC-HUD-24 [BLOCKING][AUTO].
func test_hud_boot_hydrate_delta_zero_no_tween() -> void:
	# Arrange — état initial "0"
	HUDSystem._credit_counter_label.text = "0"

	# Act
	CreditEconomy.credits_changed.emit(15, 0, CreditEconomy.SourceKind.BOOT_HYDRATE)

	# Assert — hard set effectué
	assert_str(HUDSystem._credit_counter_label.text) \
		.override_failure_message("AC-HUD-24: label.text doit être '15' après BOOT_HYDRATE") \
		.is_equal("15")

	# Aucun tween lancé (delta == 0 → early return)
	var tween_active: bool = HUDSystem._active_pulse_tween != null \
		and HUDSystem._active_pulse_tween.is_valid()
	assert_bool(tween_active) \
		.override_failure_message("AC-HUD-24: aucun tween ne doit être actif après BOOT_HYDRATE (delta==0)") \
		.is_false()
