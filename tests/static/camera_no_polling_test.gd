# Test de lint statique story-006 — Camera ne polle pas l'état Movement (AC-CAM-20b).
#
# Ce test lit le source de camera_system.gd via FileAccess et applique une regex
# pour détecter le forbidden pattern camera_polls_movement_state_transitions.
#
#   AC-CAM-20b — Manifest 2026-04-23 ligne 161 / ADR-0002 Amendment A-1 VC-7 :
#     Aucun grep player.is_dashing, player.state ==, player.state !=, match player.state
#     dans src/gameplay/camera/camera_system.gd (hors lignes commentaires).
#     Camera consomme les transitions Movement EXCLUSIVEMENT via signaux ADR-0005.
#     Polling player.state couplerrait Camera à l'enum interne State de MovementController.
#
# CI command équivalente :
#   grep -rE '(player\.state\s*[!=]=|player\.is_dashing|match\s+player\.state)' \
#     src/gameplay/camera/ | grep -v '^[^:]*:\s*#'
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story     : production/epics/camera-system/story-006-fov-dash-pulse.md
# ADR       : ADR-0002 Amendment A-1 (VC-7) + Control Manifest 2026-04-23 ligne 161

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const CAMERA_PATH: String = "res://src/gameplay/camera/camera_system.gd"

## Pattern interdit : polling de l'état interne du Movement depuis Camera.
## ADR-0002 Amendment A-1 VC-7 + Manifest 2026-04-23 ligne 161.
## Whitelist : handlers _on_*() peuvent lire leurs payloads typés — ils ne matchent
## aucun de ces patterns (les payloads sont Vector3/float, pas player.state).
const POLLING_PATTERN: String = r"(player\.state\s*[!=]=|player\.is_dashing|match\s+player\.state)"


# ---------------------------------------------------------------------------
# AC-CAM-20b — Aucun polling de l'état Movement depuis Camera
# ---------------------------------------------------------------------------

func test_camera_does_not_poll_movement_state() -> void:
	# Arrange — lecture du source camera_system.gd
	var file: FileAccess = FileAccess.open(CAMERA_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message(
			"Lint setup error: cannot open %s — vérifier que le fichier existe" % CAMERA_PATH
		) \
		.is_not_null()

	var source: String = file.get_as_text()
	file.close()

	# Filtrage des lignes commentaires : on retire toute ligne dont le premier
	# caractère non-whitespace est '#'. Cela exclut les faux positifs dans les
	# doc comments (ex : "# player.is_dashing interdit ici").
	var lines: PackedStringArray = source.split("\n")
	var stripped_lines: PackedStringArray = PackedStringArray()
	for line in lines:
		var stripped: String = line.strip_edges(true, false)  # leading whitespace only
		if not stripped.begins_with("#"):
			stripped_lines.append(line)

	var stripped_content: String = "\n".join(stripped_lines)

	# Act — recherche du pattern interdit
	var regex: RegEx = RegEx.new()
	var compile_err: int = regex.compile(POLLING_PATTERN)
	assert_int(compile_err) \
		.override_failure_message(
			"Lint setup error: regex compile failed (err=%d) — pattern: %s"
			% [compile_err, POLLING_PATTERN]
		) \
		.is_equal(OK)

	var match_result: RegExMatch = regex.search(stripped_content)

	# Assert — zéro match (AC-CAM-20b)
	assert_object(match_result) \
		.override_failure_message(
			"AC-CAM-20b VIOLATION : %s contient du polling de l'état Movement.\n"
			% CAMERA_PATH
			+ "Pattern interdit : %s\n" % POLLING_PATTERN
			+ "Match trouvé : '%s'\n" % (match_result.get_string() if match_result != null else "")
			+ "Manifest 2026-04-23 ligne 161 / ADR-0002 Amendment A-1 VC-7 :\n"
			+ "Camera consomme les transitions Movement UNIQUEMENT via signaux ADR-0005.\n"
			+ "Utiliser le flag _is_dashing mis à jour par _on_dash_started / _on_dash_ended."
		) \
		.is_null()
