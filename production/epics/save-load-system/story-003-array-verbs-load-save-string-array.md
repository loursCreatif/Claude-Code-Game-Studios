# Story 003: Array verbs load_string_array / save_string_array + String→StringName normalization

> **Epic**: Save/Load System
> **Status**: Ready
> **Layer**: Foundation / Persistence
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: ~2-3h — t-shirt S
> **Risk**: LOW

## Context

**GDD**: `design/gdd/save-load-system.md` r1
**Requirement**: R-SAV-4 (MVP arrays verbs), R-SAV-12 (type-safe load via Variant validation, normalisation `String → StringName`)

**ADR Governing Implementation**: ADR-0010 — Accepted 2026-04-27
**ADR Decision Summary**: D-2 sémantique `load_string_array` normalise `String → StringName` au load (ConfigFile sérialise `StringName` comme `String` entre quotes, R-SAV-12). Validation partielle au load : éléments Array invalides skip + push_warning, pas de crash.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**:
- ConfigFile sérialise `StringName` Godot comme `&"value"` syntaxe Godot 4.x (vérifier sortie `_config.save()`).
- À la lecture (`get_value`), le typing peut être perdu : un `Array[StringName]` peut revenir `Array[Variant]` ou `Array[String]` selon comment ConfigFile stocke. **D-2 verrouille la normalisation** — store côté save, normalize côté load.
- `typeof(value) != TYPE_ARRAY` check global ; itération `for elem in value: if typeof(elem) != TYPE_STRING_NAME and typeof(elem) != TYPE_STRING:` skip avec push_warning.
- `StringName` cast depuis `String` : `&str` ou `StringName(str)`.

**Control Manifest Rules (Foundation Persistence)**:
- **Required**: Sémantique D-2 — load_string_array normalise String → StringName (R-SAV-12) ; save_string_array typed `Array[StringName]` only.
- **Forbidden**: typing laxiste sur retour load (jamais `Array` sans contrainte d'élément — toujours `Array[StringName]`).
- **Guardrail**: cohérence avec AC-SHP-* Shop owned_upgrades (Array[StringName] flat ids tels que `&"double_jump"`, `&"dash_horizontal"`).

---

## Acceptance Criteria

*From GDD `design/gdd/save-load-system.md`, scoped to this story:*

- [ ] **AC-SAV-10** [Logic] [BLOCKING] : GIVEN `save_string_array("upg", [&"double_jump", &"dash_horizontal"])`, WHEN `load_string_array("upg", [])`, THEN retour `Array[StringName]([&"double_jump", &"dash_horizontal"])` (taille=2, types StringName).
- [ ] **AC-SAV-11** [Logic] [BLOCKING] : GIVEN array vide saved, WHEN reload, THEN `[]` retourné (pas null).
- [ ] **AC-SAV-12** [Logic] [BLOCKING] : GIVEN clé existe avec int (corruption), WHEN `load_string_array("k", [])`, THEN retour `[]` + warning.
- [ ] **AC-SAV-13** [Logic] [BLOCKING] : GIVEN array contient `[StringName, int, null, String]`, WHEN load, THEN retour `[StringName, StringName(String)]` (2 elements valides), 2 warnings émis. Couvre Shop EC-SHP-7.
- [ ] **AC-SAV-14** [Logic] [BLOCKING] : GIVEN array de 100 StringName saved, WHEN load, THEN retour identique (taille=100, ordre préservé, tous StringName).

---

## Implementation Notes

*Derived from ADR-0010 D-2 sémantique arrays + R-SAV-12:*

1. **`save_string_array(key: String, value: Array[StringName]) -> void`** :
   ```gdscript
   func save_string_array(key: String, value: Array[StringName]) -> void:
       _assert_main_thread()
       if not _config_loaded:
           push_error("SaveLoadSystem: save_string_array('%s') called before _config_loaded" % key)
           return
       _config.set_value("data", key, value)
       var err: int = _config.save(SAVE_FILE_PATH)
       if err != OK:
           push_error("SaveLoadSystem: save_string_array('%s') failed err=%d" % [key, err])
   ```

2. **`load_string_array(key: String, default: Array[StringName]) -> Array[StringName]`** avec normalisation R-SAV-12 :
   ```gdscript
   func load_string_array(key: String, default: Array[StringName]) -> Array[StringName]:
       _assert_main_thread()
       if not _config_loaded:
           return default
       var raw: Variant = _config.get_value("data", key, default)
       if typeof(raw) != TYPE_ARRAY:
           if raw != default:
               push_warning("SaveLoadSystem: load_string_array('%s') expected Array, got %s — return default" % [key, type_string(typeof(raw))])
           return default
       var result: Array[StringName] = []
       for elem: Variant in raw:
           var t: int = typeof(elem)
           if t == TYPE_STRING_NAME:
               result.append(elem)
           elif t == TYPE_STRING:
               result.append(StringName(elem))  # R-SAV-12 normalisation
           else:
               push_warning("SaveLoadSystem: load_string_array('%s') skip element type=%s" % [key, type_string(t)])
       return result
   ```

3. **AC-SAV-13 partial validation** : itération preserve l'ordre, skip les invalides en émettant warning par élément invalide. Element `null` → skip + warning. Element `int`/`Dictionary`/`Array` imbriqué → skip + warning. Couverture explicite dans test GUT.

4. **AC-SAV-11 array vide** : `_config.get_value("data", "k", [])` retourne `[]` valide quand stocké `[]`. Vérifier que typeof(`[]`) == TYPE_ARRAY (oui) et que itération boucle 0 fois (résultat = []).

5. **Compatibilité Shop EC-SHP-7** : Shop GDD R-SHP-3/8 stipule que owned_upgrades est `Array[StringName]` flat. Le pattern ici doit honorer cette contrainte exactement.

---

## Out of Scope

- **Story 002**: scalar verbs (déjà livrés)
- **Story 004**: `_save_version` lazy init lors du premier save_string_array (story-004 va wrapper toutes les writes)
- **Story 006**: `load_int_array` / `save_int_array` Tier 2+ stubs (verbes Array[int], pas StringName)

---

## QA Test Cases

**AC-SAV-10** — roundtrip Array[StringName] avec types préservés :
- Given : `_config_loaded == true`
- When : `save_string_array("upg", [&"double_jump", &"dash_horizontal"])` puis `load_string_array("upg", [])`
- Then : retour size==2, retour[0] == `&"double_jump"`, retour[1] == `&"dash_horizontal"`, `typeof(retour[0]) == TYPE_STRING_NAME` ET `typeof(retour[1]) == TYPE_STRING_NAME`
- Edge cases : ordre préservé, casing préservé.

**AC-SAV-11** — array vide round-trip :
- Given : `save_string_array("empty_key", [])` (Array[StringName] vide explicite)
- When : `load_string_array("empty_key", [&"fallback"])`
- Then : retour `[]` (size==0), pas le fallback `[&"fallback"]`
- Edge cases : tester aussi `save_string_array` jamais appelé puis `load_string_array("never_saved", [])` retourne `[]` (ou le default).

**AC-SAV-12** — type mismatch (int au lieu d'Array) :
- Given : `_config.set_value("data", "k", 42)` (int direct, pas Array)
- When : `load_string_array("k", [])`
- Then : retour `[]` (default), `push_warning` capturé contenant `"expected Array, got int"`
- Edge cases : valeurs String simple (pas Array), Dictionary, null.

**AC-SAV-13** — partial validation array hétérogène :
- Given : `_config.set_value("data", "mix", [&"valid_a", 42, null, "string_b"])` (4 éléments, 2 valides)
- When : `load_string_array("mix", [])`
- Then : retour size==2, retour[0] == `&"valid_a"`, retour[1] == `&"string_b"` (normalisé String→StringName), 2 push_warning capturés
- Edge cases : Array vide après skip total `[42, null, {}]` → retour `[]` + 3 warnings ; ordre préservé sur le subset valide.

**AC-SAV-14** — array de 100 StringName :
- Given : `save_string_array("big", [&"id_0", &"id_1", ..., &"id_99"])` (100 elements)
- When : `load_string_array("big", [])`
- Then : retour size==100, retour[i] == `&("id_" + str(i))`, tous TYPE_STRING_NAME, ordre préservé
- Edge cases : perf < 5 ms (sanity Pillar 1 — 100 elements String→StringName cast ne doit pas drop frame).

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/save_load/array_verbs_test.gd` — must exist and pass (5 tests AC-SAV-10/11/12/13/14)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **story-001** (skeleton autoload obligatoire)
- Unlocks:
  - shop-system story-001 (Shop boot hydrate `owned_upgrades` via `load_string_array`)
  - upgrade-system story-005 (Upgrade boot hydration via Shop indirect — Shop fournit `get_owned_upgrades()`)
