# Tests unitaires story-010 — Contrat des signaux de LevelSystemScript.
# Couvre AC-LVL-43 : get_signal_list() correspond à la liste contractuelle.
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# ÉTAT ACTUEL : 7 signaux implémentés (stories 002-004 + 005 + 007 + 008 done).
# Le set complet cible (GDD) = 7 signaux est atteint.
#
# Story   : production/epics/level-system/story-010-canonical-hierarchy-validate-scene.md
# GDD     : design/gdd/level-system.md — contrat 7 signaux total (post stories 005/007/008)
# Req     : TR-lvl-006 (AC-LVL-43)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Contract
# ---------------------------------------------------------------------------

## Ensemble contractuel des 7 signaux LevelSystemScript (stories 002-004 + 005/007/008).
## Tout ajout/retrait de signal doit être reflété ici (test gate AC-LVL-43).
const CONTRACT_SIGNALS: Array[String] = [
	"level_active",
	"level_unloading",
	"level_load_failed",
	"level_load_slow",
	"etage_completed",
	"room_entered",
	"player_out_of_world",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Filtre get_signal_list() pour ne garder que les signaux déclarés dans
## LevelSystemScript lui-même (exclut les signaux hérités de Node).
## Technique : on compare avec les signaux d'un Node vide pour extraire uniquement
## les signaux propres à la classe.
func _get_own_signal_names(obj: Object) -> Array[String]:
	var base_signals: Array[String] = []
	var base: Node = Node.new()
	for sig: Dictionary in base.get_signal_list():
		base_signals.append(sig["name"] as String)
	base.free()

	var own: Array[String] = []
	for sig: Dictionary in obj.get_signal_list():
		var sig_name: String = sig["name"] as String
		if not base_signals.has(sig_name):
			own.append(sig_name)
	return own


# ---------------------------------------------------------------------------
# AC-LVL-43 — Contrat de signaux
# ---------------------------------------------------------------------------

## Vérifie que les signaux propres à LevelSystemScript correspondent exactement
## au contrat défini dans CONTRACT_SIGNALS (set exact — ni plus, ni moins).
func test_level_signal_list_matches_contract() -> void:
	# Arrange
	var level: LevelSystemScript = LevelSystemScript.new()
	add_child(auto_free(level))
	await get_tree().process_frame

	# Act : récupérer les signaux propres à LevelSystemScript
	var own_signals: Array[String] = _get_own_signal_names(level)
	own_signals.sort()

	var expected: Array[String] = CONTRACT_SIGNALS.duplicate()
	expected.sort()

	# Assert — set exact : aucun signal manquant, aucun signal non-documenté
	assert_array(own_signals) \
		.override_failure_message(
			"AC-LVL-43: get_signal_list() ne correspond pas au contrat.\n"
			+ "  Attendu  : %s\n" % str(expected)
			+ "  Reçu     : %s\n" % str(own_signals)
			+ "  Manquants : %s\n" % str(_missing(expected, own_signals))
			+ "  En trop   : %s" % str(_missing(own_signals, expected))
		) \
		.is_equal(expected)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Retourne les éléments de `expected` absents de `actual`.
func _missing(expected: Array[String], actual: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for item: String in expected:
		if not actual.has(item):
			result.append(item)
	return result
