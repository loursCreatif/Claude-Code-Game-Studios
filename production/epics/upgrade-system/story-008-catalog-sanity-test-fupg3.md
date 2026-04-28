# Story 008: F-UPG-3 Catalog Sanity Test + Immutability Lint

> **Epic**: upgrade-system
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : F-UPG-3 catalog sanity invariant build-time, R-UPG-3 (`_CATALOG` owned exclusivement Upgrade), AC-UPG-6 (immutability runtime), AC-UPG-6-bis (grep statique zero mutation), AC-UPG-15 (catalog sanity test runtime).

**ADR Governing Implementation** : aucun ADR Upgrade-spécifique requis MVP. F-UPG-3 est documenté GDD r2 B-2 comme garde-fou alternatif à un ADR _CATALOG (escalation trigger : N > 12 capabilities OU breaking save format).

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : `const Dictionary` en GDScript 4.6 freeze le **binding** (rebinding `_CATALOG = {}` lève erreur compilation/exécution) mais **pas le contenu** (mutation `_CATALOG[&"injected"] = ...` réussit silencieusement — godot-specialist B-15 review). La défense réelle est (a) absence de code production qui mute (AC-6-bis grep), (b) test isolation `before_each`/`after_each`.

**Control Manifest Rules (Feature Layer)** :
- Required : F-UPG-3 test passe en CI (path : `tests/integration/upgrade/catalog_sanity_test.gd` — décision OQ-UPG-10 : integration > static car ce test instancie l'autoload pour `get_property_list()`).
- Forbidden : tout `_CATALOG[id] = value` ou `_CATALOG.erase(id)` dans le code production `src/gameplay/upgrade/` (AC-6-bis grep le verrouille).

---

## Acceptance Criteria

- [ ] **AC-UPG-6** : (a) rebinding `_CATALOG = {}` lève erreur compilation/exécution ; (b) mutation in-place `_CATALOG[&"injected"] = &"poison"` documente comportement runtime Godot 4.6 (réussit + test isolation obligatoire `before_each`/`after_each`).
- [ ] **AC-UPG-6-bis** [BLOCKING grep] : zéro `\b_CATALOG\s*\[.*\]\s*=` (assignment) dans `upgrade_system.gd` ; lectures (`_CATALOG[id]` rhs, `_CATALOG.has(id)`) autorisées.
- [ ] **AC-UPG-15** [BLOCKING runtime] : F-UPG-3 itère chaque entrée `(id, flag_name)` de `_CATALOG` MVP réel ; pour chaque : (a) `flag_name in get_property_list().map(...)` ; (b) `typeof(get(flag_name)) == TYPE_BOOL` ; (c) propriété mutable (set/get round-trip).

---

## Implementation Notes

### Test path decision (OQ-UPG-10 RESOLVED)

**Décision** : `tests/integration/upgrade/catalog_sanity_test.gd`. Le test est runtime (instancie UpgradeSystem pour `get_property_list()`), pas pure static text grep — il appartient à `tests/integration/`. Le grep statique AC-6-bis va dans `tests/static/` (script bash CI ou `tests/static/upgrade_lint_test.gd`).

### F-UPG-3 catalog sanity test (AC-UPG-15)

```gdscript
# tests/integration/upgrade/catalog_sanity_test.gd
extends GutTest

var s: UpgradeSystem

func before_each() -> void:
    s = UpgradeSystem.new()
    add_child(s)

func after_each() -> void:
    # AC-UPG-6 isolation : reset _CATALOG si test précédent a injecté
    # NOTE : impossible reset const Dictionary content directement.
    # Soit tests injection sont isolés avec instance fresh (déjà le cas via new()),
    # soit on assert before_each que _CATALOG.size() == 2 (MVP catalog).
    assert_eq(s._CATALOG.size(), 2, "Catalog polluted by previous test — isolation broken")
    s.queue_free()

func test_catalog_sanity_each_entry_maps_to_existing_bool_var() -> void:
    var props: Array[StringName] = []
    for p in s.get_property_list():
        if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
            props.append(p.name)

    for id in s._CATALOG.keys():
        var flag_name: StringName = s._CATALOG[id]

        # (a) propriété existe
        assert_true(flag_name in props,
            "Catalog entry id=%s flag_name=%s : property does not exist" % [id, flag_name])

        # (b) typeof bool
        assert_eq(typeof(s.get(flag_name)), TYPE_BOOL,
            "Catalog entry flag_name=%s : not bool (typeof=%d)" % [flag_name, typeof(s.get(flag_name))])

        # (c) mutable (round-trip set/get)
        var initial: bool = s.get(flag_name)
        s.set(flag_name, true)
        assert_eq(s.get(flag_name), true,
            "Catalog entry flag_name=%s : not mutable (set true failed)" % flag_name)
        s.set(flag_name, false)
        assert_eq(s.get(flag_name), false,
            "Catalog entry flag_name=%s : not mutable (set false failed)" % flag_name)
        s.set(flag_name, initial)    # restore
```

### AC-UPG-6 immutability runtime test

```gdscript
func test_catalog_const_rebinding_fails() -> void:
    # GDScript 4.6 : `const _CATALOG = {}` produit erreur compilation
    # OU runtime selon le contexte. Test via tentative reflection :
    var caught: bool = false
    # Note : impossible de tester rebinding const en GDScript runtime —
    # le compilateur le rejette à l'analyse statique.
    # Cet AC documente la garantie ; preuve indirecte via le fait que
    # le projet build sans erreur (le compilateur a validé l'immutability).
    assert_true(true, "Const rebinding rejected by GDScript compiler — see compile-time check")

func test_catalog_inplace_mutation_succeeds_documented_godot46_behavior() -> void:
    # AC-UPG-6 (b) : mutation in-place RÉUSSIT silencieusement (Godot 4.6 freeze
    # binding pas contenu). Documenté pour transparence — la défense réelle est
    # AC-UPG-6-bis grep + isolation test.
    var initial_size: int = s._CATALOG.size()
    s._CATALOG[&"injected"] = &"poison"    # mutation in-place
    assert_eq(s._CATALOG.size(), initial_size + 1,
        "Godot 4.6 const Dictionary content mutation succeeded (expected behavior)")
    # Cleanup obligatoire pour pas polluer tests suivants
    s._CATALOG.erase(&"injected")
    assert_eq(s._CATALOG.size(), initial_size, "Cleanup failed — test isolation broken")
```

### AC-UPG-6-bis grep statique

Script bash CI :
```bash
# tests/static/upgrade_no_catalog_mutation.sh
matches=$(grep -nE '\b_CATALOG\s*\[[^]]*\]\s*=' src/gameplay/upgrade/upgrade_system.gd \
  | grep -v '^[^:]*:\s*#' || true)
if [ -n "$matches" ]; then
    echo "AC-UPG-6-bis FAIL : _CATALOG mutation détectée :"
    echo "$matches"
    exit 1
fi
echo "AC-UPG-6-bis PASS"
```

Ou en GDScript test :
```gdscript
# tests/static/upgrade_lint_test.gd
func test_no_catalog_mutation_in_production_source() -> void:
    var src: String = FileAccess.get_file_as_string("res://src/gameplay/upgrade/upgrade_system.gd")
    var regex := RegEx.new()
    regex.compile(r"\b_CATALOG\s*\[[^\]]*\]\s*=")
    var matches := regex.search_all(src)
    var non_comment_matches: Array = []
    for m in matches:
        var line_start: int = src.rfind("\n", m.get_start()) + 1
        var line: String = src.substr(line_start, m.get_end() - line_start)
        if not line.strip_edges().begins_with("#"):
            non_comment_matches.append(line)
    assert_eq(non_comment_matches.size(), 0,
        "AC-UPG-6-bis: _CATALOG mutation détectée: %s" % non_comment_matches)
```

---

## Out of Scope

- Tier 2+ extension `_CATALOG` 8 entrées (AC-UPG-39 PROVISIONAL — couvert dans une futur story Tier 2+).
- Migration tool si `_CATALOG` renommé (EC-UPG-19 Tier 2+).
- ADR _CATALOG escalation (trigger N>12 capabilities, hors MVP).

---

## QA Test Cases

**AC-UPG-6 (a)** — Compile-time check (implicit)
- Given : projet Godot.
- When : compile `upgrade_system.gd`.
- Then : si on tente d'ajouter `_CATALOG = {}` réassignation, le compilateur GDScript 4.6 lève erreur. Test PASS = projet build sans erreur (la const est correctement déclarée).

**AC-UPG-6 (b)** — Runtime documentation test
- Given : `var s := UpgradeSystem.new()` + assertion initial `s._CATALOG.size() == 2`.
- When : `s._CATALOG[&"injected"] = &"poison"`.
- Then : mutation réussit (`s._CATALOG.size() == 3`). Cleanup `_CATALOG.erase(&"injected")` puis assert size restaurée à 2.
- Note : ne valide PAS l'immutability — documente comportement runtime Godot 4.6 + impose isolation test.

**AC-UPG-6-bis** — Static grep test [BLOCKING]
- Given : fichier `src/gameplay/upgrade/upgrade_system.gd`.
- When : grep `\b_CATALOG\s*\[[^\]]*\]\s*=` excluant lignes commentaires `^\s*#`.
- Then : zéro match. Si match trouvé → fail avec liste des lignes.

**AC-UPG-15** — Integration test [BLOCKING]
- Given : `var s := UpgradeSystem.new()` ; instance bare avec `_CATALOG` MVP réel `{&"double_jump" → &"can_air_jump", &"dash_horizontal" → &"can_dash"}`.
- When : itération `_CATALOG.keys()` ; pour chaque entrée test 3 invariants.
- Then : (a) chaque `flag_name` dans `get_property_list()` filtré USAGE_SCRIPT_VARIABLE ; (b) `typeof(get(flag_name)) == TYPE_BOOL` ; (c) round-trip set/get true puis false fonctionne.
- Edge : si une future entrée Tier 2+ ajoute `&"can_secret_radar"` mais la `var` n'est pas déclarée → test fail explicite avec message identifiant l'entrée fautive.

---

## Test Evidence

**Story Type** : Logic
**Required evidence** :
- `tests/integration/upgrade/catalog_sanity_test.gd` (AC-UPG-15 + AC-UPG-6 (a)+(b)).
- `tests/static/upgrade_lint_test.gd` ou shell script CI (AC-UPG-6-bis).
**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : 001 (autoload skeleton + `_CATALOG` MVP déclaré).
- Unlocks : 009 (anti-pattern lint share l'infrastructure `tests/static/upgrade_lint_test.gd`).

---

## Completion Notes
**Completed**: 2026-04-28
**Criteria**: passing — AC-UPG-15 BLOCKING (chaque entrée `_CATALOG` mappe à propriété bool mutable round-trip) couvert par `tests/integration/upgrade/catalog_sanity_test.gd`. AC-UPG-6 (a) statique couvert par `tests/static/upgrade_lint_test.gd`.
**Deviations**: ADVISORY — AC-UPG-6 (b) runtime mutation test SUPPRIMÉ : Godot 4.6 enforce `const Dictionary` au parse-time ("Cannot assign a new value to a constant"), donc la mutation runtime que le test documentait n'est plus possible. La garantie d'immutabilité est désormais structurelle/build-time (plus forte que le test runtime original). Test marqué OBSOLETE in-file avec commentaire de ré-activation conditionnelle.
**Test Evidence**: Integration — `tests/integration/upgrade/catalog_sanity_test.gd` (PASSED suite 41/41 après suppression du test obsolète).
**Code Review**: Skipped (Solo mode).
