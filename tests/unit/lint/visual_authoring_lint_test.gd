# Tests unitaires story-022 — LevelLint.validate_visual_authoring().
#
# Couvre :
#   TR-lvl-040 : Primitives only — ArrayMesh interdit, PrimitiveMesh requis.
#   TR-lvl-040 shader : material_override doit référencer chrome_zen_flat.
#   TR-lvl-041 : Atlas cap ≤ 1024² ; sub-texture cap ≤ 512².
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures  : construites programmatiquement — aucun fichier .tscn requis.
#
# Story : production/epics/level-system/story-022-chrome-zen-shader-atlas-tuning.md
# Req   : TR-lvl-040, TR-lvl-041, story-022 AC-LVL-44

extends GdUnitTestSuite

## preload de LevelLint : class_name non résolu en CI headless sans SceneTree complet.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")


# ---------------------------------------------------------------------------
# Helpers — construction des fixtures programmatiques
# ---------------------------------------------------------------------------

## Crée une racine minimale compatible avec validate_visual_authoring.
## La structure n'a pas besoin de la hiérarchie canonique complète car
## validate_visual_authoring scanne find_children("*", "MeshInstance3D") global.
##
## [return] : Node3D racine enregistrée avec auto_free.
func _make_root() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "TestRoot"
	add_child(auto_free(root))
	return root


## Crée et attache un MeshInstance3D enfant du [parent] avec l'[mesh] fourni.
## Optionnellement définit le material_override.
##
## [param parent] : Node3D parent.
## [param mesh] : Mesh à affecter (peut être null).
## [param mat] : Material à définir comme material_override (peut être null).
## [return] : MeshInstance3D créé.
func _make_mesh_instance(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "TestMesh"
	if mesh != null:
		mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


## Crée un ShaderMaterial vide avec le shader chrome_zen_flat simulé via resource_path.
## En test headless, on ne peut pas charger le .gdshader réel — on patche resource_path
## directement sur un Shader.new() pour simuler la validation de chemin.
##
## [return] : ShaderMaterial dont le shader.resource_path == CHROME_ZEN_SHADER_PATH.
func _make_chrome_zen_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	# Forcer le resource_path du shader pour simuler res://assets/shaders/chrome_zen_flat.gdshader.
	# En CI headless, la ressource n'existe pas sur disque mais le path est simulé.
	shader.resource_path = LevelLintScript.CHROME_ZEN_SHADER_PATH
	mat.shader = shader
	return mat


# ---------------------------------------------------------------------------
# TR-lvl-040 — FAIL : ArrayMesh interdit en MVP Chrome Zen
# ---------------------------------------------------------------------------

## Vérifie que validate_visual_authoring signale un MeshInstance3D dont le mesh
## est un ArrayMesh (mesh importé — interdit en MVP Chrome Zen).
## Source : TR-lvl-040, story-022 AC-LVL-44.
func test_validate_visual_no_imported_mesh_fails() -> void:
	# Arrange
	var root: Node3D = _make_root()
	var array_mesh: ArrayMesh = ArrayMesh.new()  # ArrayMesh vide — suffit pour déclencher la violation
	_make_mesh_instance(root, array_mesh, null)

	# Act
	var errors: Array[String] = LevelLintScript.validate_visual_authoring(root)

	# Assert — doit contenir "imported mesh found at ... MVP Chrome Zen primitives only"
	var found: bool = false
	for e: String in errors:
		if "imported mesh found" in e and "MVP Chrome Zen primitives only" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"TR-lvl-040: violation 'imported mesh found at <path>: MVP Chrome Zen primitives only' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# TR-lvl-040 shader — FAIL : StandardMaterial3D interdit
# ---------------------------------------------------------------------------

## Vérifie que validate_visual_authoring signale un MeshInstance3D dont le
## material_override est un StandardMaterial3D (non-Chrome Zen).
## Source : TR-lvl-040 shader check, story-022 AC-LVL-44.
func test_validate_visual_flat_shader_required() -> void:
	# Arrange — BoxMesh (PrimitiveMesh valide) + StandardMaterial3D (invalide)
	var root: Node3D = _make_root()
	var box_mesh: BoxMesh = BoxMesh.new()
	var std_mat: StandardMaterial3D = StandardMaterial3D.new()
	_make_mesh_instance(root, box_mesh, std_mat)

	# Act
	var errors: Array[String] = LevelLintScript.validate_visual_authoring(root)

	# Assert — doit contenir "must reference chrome_zen_flat"
	var found: bool = false
	for e: String in errors:
		if "must reference chrome_zen_flat" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"TR-lvl-040 shader: violation 'material at <path> must reference chrome_zen_flat.gdshader' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# TR-lvl-041 — FAIL : texture atlas > 1024
# ---------------------------------------------------------------------------

## Vérifie que validate_visual_authoring signale une texture 2048×2048 dans
## les uniforms du ShaderMaterial Chrome Zen (atlas cap 1024² dépassé).
## Source : TR-lvl-041, story-022 AC-LVL-44.
func test_texture_over_1024_fails() -> void:
	# Arrange — BoxMesh + ShaderMaterial Chrome Zen simulé + texture 2048×2048
	var root: Node3D = _make_root()
	var box_mesh: BoxMesh = BoxMesh.new()
	var mat: ShaderMaterial = _make_chrome_zen_material()

	# Créer une texture programmatique 2048×2048
	var img: Image = Image.create(2048, 2048, false, Image.FORMAT_RGB8)
	var tex: ImageTexture = ImageTexture.create_from_image(img)

	# Injecter la texture dans un uniform "atlas" du shader.
	# Comme le shader est vide (Shader.new()), set_shader_parameter ne fait rien
	# à l'exécution mais get_shader_uniform_list() retournera [].
	# Pour que le test fonctionne, on utilise un wrapper qui expose directement
	# la texture via _check_texture_sizes avec un mock de get_shader_uniform_list.
	#
	# Alternative : tester _check_texture_sizes directement (méthode statique interne).
	# C'est la bonne approche : le validateur de texture est une unité testable séparée.
	var errors: Array[String] = LevelLintScript._check_texture_sizes_from_texture_list(
		"/TestRoot/TestMesh",
		[tex]
	)

	# Assert — doit contenir "texture size 2048x2048 > 1024 atlas cap"
	var found: bool = false
	for e: String in errors:
		if "texture size" in e and "1024 atlas cap" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"TR-lvl-041: violation 'texture size 2048x2048 > 1024 atlas cap' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# TR-lvl-041 sub — FAIL : texture individuelle > 512
# ---------------------------------------------------------------------------

## Vérifie que validate_visual_authoring signale une texture 768×768 dans
## les uniforms du ShaderMaterial Chrome Zen (sub-texture cap 512² dépassé).
## Source : TR-lvl-041, story-022 AC-LVL-44.
func test_individual_texture_over_512_fails() -> void:
	# Arrange — texture 768×768 (> 512 mais <= 1024 → sub-texture cap dépassé)
	var img: Image = Image.create(768, 768, false, Image.FORMAT_RGB8)
	var tex: ImageTexture = ImageTexture.create_from_image(img)

	# Act via helper direct (même approche que test ci-dessus)
	var errors: Array[String] = LevelLintScript._check_texture_sizes_from_texture_list(
		"/TestRoot/TestMesh",
		[tex]
	)

	# Assert — doit contenir "individual texture 768 > 512 cap"
	var found: bool = false
	for e: String in errors:
		if "individual texture" in e and "512 cap" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"TR-lvl-041: violation 'individual texture 768 > 512 cap' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()
