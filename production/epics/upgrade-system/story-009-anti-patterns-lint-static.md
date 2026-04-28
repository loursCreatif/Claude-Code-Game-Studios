# Story 009: Anti-Patterns Lint Static (Zero Signal/UI/Audio/Revoke/Persist)

> **Epic**: upgrade-system
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : R-UPG-6 (zéro signal outbound MVP), R-UPG-10 (Upgrade ne persiste jamais), R-UPG-12 (pas de revoke MVP), R-UPG-14 (single responsibility — pas de UI/Audio).

**ADR Governing Implementation** : ADR-0005 Movement Signal Architecture (cross-ref pour l'absence de signal Upgrade — Movement r3 + Camera A-1 documentent les seuls signaux gameplay actifs).
**ADR Decision Summary** : aucun ADR signal Upgrade — la décision GDD R-UPG-6 est suffisante. Les anti-patterns sont enforced exclusivement par grep statique CI.

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : `get_signal_list()` filter requires whitelist explicite des signaux Object/Node Godot 4.6 (R-16 amendement r2). Whitelist à ré-valider à chaque migration mineure (4.6 → 4.7).

**Control Manifest Rules (Feature Layer)** :
- Required : grep tests passent en CI sur `src/gameplay/upgrade/upgrade_system.gd` pour les 7 patterns interdits ci-dessous.
- Forbidden : tout signal custom dans `upgrade_system.gd` (`signal capability_unlocked` etc.) ; tout `SaveLoad.save_*`/`SaveLoad.write_*` ; toute référence aux nodes UI ; toute API audio ; tout `revoke_upgrade`.

---

## Acceptance Criteria

- [ ] **AC-UPG-27** : `get_signal_list()` filtré whitelist Object/Node Godot 4.6 → liste vide.
- [ ] **AC-UPG-28** : grep `SaveLoad.save_` ou `SaveLoad.write_` dans `upgrade_system.gd` → zéro match.
- [ ] **AC-UPG-29** : test cross-GDD simulant achat shop → écriture clé `"owned_upgrades"` provient de Shop (mock counts caller), pas Upgrade.
- [ ] **AC-UPG-34** : grep nodes UI (`Control|Label|CanvasLayer|Button|Panel|RichTextLabel|Container|VBoxContainer|HBoxContainer|TextureRect|NinePatchRect|Sprite2D|Sprite3D`) avec word-boundary `\b...\b` + filtre `^[0-9]*:\s*#` → zéro match non-commenté.
- [ ] **AC-UPG-35** : grep API audio (`AudioStreamPlayer|AudioStreamPlayer2D|AudioStreamPlayer3D|AudioServer|AudioBus|play\s*\(|stream\s*=|audio_`) word-boundary + filter commentaires → zéro match.
- [ ] **AC-UPG-36** : grep `\brevoke_upgrade\b` filter commentaires → zéro match.
- [ ] **AC-UPG-38** : forward-compat — mock SaveLoad return `[&"double_jump", &"wall_run_extended", &"tier2_special"]` build MVP → ids inconnus skip avec warning, `&"double_jump"` appliqué, no crash.
- [ ] **AC-UPG-39** [PROVISIONAL Tier 2+] : `_CATALOG` Tier 2+ 8 entrées branch test → F-UPG-3 sanity passe sur catalog étendu. Deferred Tier 2+ implementation.

---

## Implementation Notes

### Whitelist signaux Object/Node Godot 4.6 (R-UPG-6)

```gdscript
# tests/static/upgrade_no_signal_test.gd
const GODOT_46_INHERITED_SIGNALS: Array[StringName] = [
    # Object
    &"script_changed",
    &"property_list_changed",
    # Node
    &"ready",
    &"renamed",
    &"tree_entered",
    &"tree_exiting",
    &"tree_exited",
    &"child_entered_tree",
    &"child_exiting_tree",
    &"child_order_changed",
    &"replacing_by",
]

func test_no_outbound_signal_on_upgrade() -> void:
    var s := UpgradeSystem.new()
    add_child_autofree(s)
    var custom_signals: Array = []
    for sig in s.get_signal_list():
        if not (StringName(sig.name) in GODOT_46_INHERITED_SIGNALS):
            custom_signals.append(sig.name)
    assert_eq(custom_signals.size(), 0,
        "AC-UPG-27 FAIL : signaux custom détectés sur UpgradeSystem : %s" % custom_signals)
```

Note : si Godot 4.7 ajoute des signaux Object/Node, mettre à jour la whitelist (PR coordonnée avec migration `docs/engine-reference/godot/VERSION.md`).

### Grep tests AC-28/34/35/36 (mutualisés)

```gdscript
# tests/static/upgrade_lint_test.gd
extends GutTest

const SOURCE_PATH := "res://src/gameplay/upgrade/upgrade_system.gd"

func _grep_non_comment(pattern: String) -> Array[String]:
    var src: String = FileAccess.get_file_as_string(SOURCE_PATH)
    var regex := RegEx.new()
    regex.compile(pattern)
    var hits: Array[String] = []
    for line in src.split("\n"):
        if line.strip_edges().begins_with("#"):
            continue
        if regex.search(line):
            hits.append(line)
    return hits

func test_AC_UPG_28_no_saveload_write() -> void:
    var hits := _grep_non_comment(r"SaveLoad\.(save|write)_")
    assert_eq(hits.size(), 0, "AC-UPG-28 FAIL : SaveLoad.save_*/write_* trouvé : %s" % hits)

func test_AC_UPG_34_no_ui_nodes() -> void:
    var hits := _grep_non_comment(r"\b(Control|Label|CanvasLayer|Button|Panel|RichTextLabel|Container|VBoxContainer|HBoxContainer|TextureRect|NinePatchRect|Sprite2D|Sprite3D)\b")
    assert_eq(hits.size(), 0, "AC-UPG-34 FAIL : UI nodes trouvés : %s" % hits)

func test_AC_UPG_35_no_audio() -> void:
    var hits := _grep_non_comment(r"\b(AudioStreamPlayer|AudioStreamPlayer2D|AudioStreamPlayer3D|AudioServer|AudioBus|play\s*\(|stream\s*=|audio_)")
    assert_eq(hits.size(), 0, "AC-UPG-35 FAIL : audio API trouvée : %s" % hits)

func test_AC_UPG_36_no_revoke_upgrade() -> void:
    var hits := _grep_non_comment(r"\brevoke_upgrade\b")
    assert_eq(hits.size(), 0, "AC-UPG-36 FAIL : revoke_upgrade trouvé : %s" % hits)
```

### AC-UPG-29 cross-GDD shop integration

Test integration coordonné Shop epic — Upgrade-side seulement assert que `SaveLoad.save_string_array` n'est jamais appelé depuis `upgrade_system.gd` :

```gdscript
func test_AC_UPG_29_shop_owns_save_write() -> void:
    # Mock SaveLoad with caller stack inspection
    var mock_save_load := MockSaveLoadWithCallerTracking.new()
    Engine.register_singleton("SaveLoad", mock_save_load)

    # Simulate full shop purchase cycle
    Shop.try_buy(&"double_jump")    # Shop story side — coordonné epic shop

    var write_callers: Array[String] = mock_save_load.get_write_callers("owned_upgrades")
    var upgrade_callers := write_callers.filter(func(c): return c.contains("upgrade_system.gd"))
    assert_eq(upgrade_callers.size(), 0,
        "AC-UPG-29 FAIL : upgrade_system.gd a écrit owned_upgrades : %s" % upgrade_callers)

    Engine.unregister_singleton("SaveLoad")
```

Le mock track les caller scripts via `print_stack()` ou inspection `get_stack()`. Si pas implémentable Sprint 1 (Shop pas encore mergé), downgrader AC-29 à grep statique (déjà couvert par AC-28) + assertion postponed Shop epic story coordonnée.

### AC-UPG-38 forward-compat

```gdscript
func test_AC_UPG_38_forward_compat_unknown_tier2_ids() -> void:
    var mock := MockSaveLoad.new()
    mock.return_value = [&"double_jump", &"wall_run_extended", &"tier2_special"]
    Engine.register_singleton("SaveLoad", mock)

    var s := UpgradeSystem.new()
    s._logger = TestUpgradeLogger.new()
    add_child(s)
    # _ready() exécuté

    assert_true(s.can_air_jump, "Known id should apply")
    assert_eq(s.get_owned_count(), 1, "Only known id counted")
    assert_gte(s._logger.captured_warnings.filter(func(m): return m.contains("unknown")).size(), 2,
        "≥2 warnings for unknown ids")
    # No crash : implicit (test reach here)

    s.queue_free()
    Engine.unregister_singleton("SaveLoad")
```

### AC-UPG-39 PROVISIONAL Tier 2+

Test marqué `pending` ou `skip` MVP, à activer Tier 2+ :

```gdscript
func test_AC_UPG_39_tier2_catalog_sanity() -> void:
    pending("Deferred Tier 2+ implementation — see F-UPG-4")
    # Implementation future :
    # var s := TestTier2UpgradeSystem.new()    # subclass with extended _CATALOG
    # ... F-UPG-3 sanity sweep on Tier 2+ catalog
```

---

## Out of Scope

- AC-UPG-37 / AC-UPG-37-bis playtest novice 80% understanding (couvert story 011 Visual/Feel).
- Tier 2+ catalog implementation (AC-UPG-39 PROVISIONAL).
- ADR-0005 amendement si signal `capability_unlocked` introduit Tier 2+ (OQ-UPG-5).

---

## QA Test Cases

**AC-UPG-27** — Static lint test [BLOCKING]
- Given : autoload UpgradeSystem instancié.
- When : `get_signal_list()` filtré contre whitelist Object/Node Godot 4.6.
- Then : liste résultante size == 0.
- Edge : si Godot 4.7 migration ajoute signaux Node, whitelist à ré-valider — test fail explicite + PR à coordonner.

**AC-UPG-28** — Static lint test [BLOCKING]
- Given : fichier source `upgrade_system.gd`.
- When : grep `SaveLoad\.(save|write)_` excluant commentaires.
- Then : zéro match.

**AC-UPG-29** — Integration test [BLOCKING] (deferred si Shop pas mergé)
- Given : mock SaveLoad with caller tracking.
- When : Shop story full purchase cycle exécuté.
- Then : aucun write `owned_upgrades` ne provient de `upgrade_system.gd`.
- Fallback Sprint 1 : downgrade à grep statique (AC-28 couvre 90% du contrat).

**AC-UPG-34 / AC-UPG-35 / AC-UPG-36** — Static lint tests [BLOCKING]
- Pattern grep word-boundary + filter commentaires (cf. impl détails ci-dessus).
- Then chaque : zéro match. Pass message inclut liste lines fautives si fail.

**AC-UPG-38** — Integration test [BLOCKING]
- Given : Logger DI + mock SaveLoad return MVP+Tier2 mixed array.
- When : `_ready()`.
- Then : known ids appliqués, unknown ids warn+skip, no crash.

**AC-UPG-39** — Static + Integration test [PROVISIONAL Tier 2+]
- Marked `pending` MVP — to activate Tier 2+.

---

## Test Evidence

**Story Type** : Logic
**Required evidence** :
- `tests/static/upgrade_lint_test.gd` (AC-UPG-27/28/34/35/36) — single test file mutualisant grep helpers.
- `tests/integration/upgrade/forward_compat_test.gd` (AC-UPG-38).
- `tests/integration/upgrade/shop_owns_save_test.gd` (AC-UPG-29 — coordination Shop epic, downgrade fallback à grep si Shop pas mergé).
**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : 001 (autoload skeleton), 002 (Logger DI pour AC-38), 005 (boot hydration pour AC-38).
- Soft : Shop epic story `try_buy` body pour AC-29 integration version. Sprint 1 fallback : grep statique seul.
- Unlocks : aucune story directement bloquée.
