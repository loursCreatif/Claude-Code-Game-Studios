# Story 003: Boot Hydrate `_owned_upgrades` from SaveLoad

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

> ✅ **ADR-0010 Accepted** (promu 2026-04-27) : SaveLoad signature `load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` verrouillée par GDD Save/Load r1 + ADR-0010 D-2.

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-4`, `R-SHP-7` (re-entry idempotence niveau Save/Load), `EC-SHP-6/7/8/39`
*Au `_ready()`, le shop charge l'état owned via `SaveLoad.load_string_array("owned_upgrades", [])`. Filtre élément par élément (cast `String → StringName` — EC-SHP-39) avec validation typée robuste. IDs inconnus (catalogue retiré) conservés silencieusement (forward-safe Tier 2+).*

**ADR Governing Implementation**: ADR-0010 (Save/Load Serialization Format) — D-2 verrouille API `load_string_array`.
**ADR Decision Summary**: SaveLoad expose `load_string_array(key: String, default: Array[StringName]) -> Array[StringName]`. Sur fichier absent/corrompu/type mismatch → retourne `default`. Normalisation `String → StringName` au load (R-SAV-12).

**Engine**: Godot 4.6 | **Risk**: MEDIUM (Godot 4.4 `FileAccess.store_*` breaking change abstrait par ConfigFile, voir ADR-0010 Engine Compatibility).
**Engine Notes**: ConfigFile API stable depuis 3.x. `Array[StringName]` typed-array introspection disponible Godot 4.4+.

**Control Manifest Rules**:
- Required: typed signals strictes ; `Array[StringName]` typed
- Required: SaveLoad accédé uniquement via verbes publics (`load_string_array`/`save_string_array`) — pas d'accès `_config` direct
- Forbidden: appel SaveLoad depuis Thread / WorkerThreadPool (ADR-0010 D-7 main-thread only)

---

## Acceptance Criteria

- [ ] **AC-SHP-1** : `_owned_upgrades` contient exactement les ids retournés par `SaveLoad.load_string_array("owned_upgrades", [])`.
- [ ] **AC-SHP-2** : `load_string_array` retourne `[]` (key absente) → `_owned_upgrades == []`.
- [ ] **AC-SHP-15** : save existante `["double_jump", "dash_horizontal"]` → 2 BuyButtons disabled OWNED dès premier frame rendu.
- [ ] **AC-SHP-23** : `load_string_array` retourne valeur non-Array (null, "corrupt") → `_owned_upgrades = []` + `push_warning`.
- [ ] **AC-SHP-24** : `load_string_array` retourne `["triple_jump"]` (id inconnu) → id conservé silencieusement, 2 upgrades MVP affichées NORMAL.
- [ ] **EC-SHP-7** : éléments non-StringName/non-String filtrés via `if elem is StringName or elem is String` ; warning par élément rejeté.
- [ ] **EC-SHP-39** : Strings castées en StringName (`StringName("double_jump")`).

---

## Implementation Notes

```gdscript
func _ready() -> void:
    # ... (asserts story-002) ...
    _hydrate_owned_upgrades()
    _render_initial_catalogue()  # appelle story-005 logic

func _hydrate_owned_upgrades() -> void:
    var raw: Array = SaveLoad.load_string_array(&"owned_upgrades", [] as Array[StringName])
    if raw == null or not (raw is Array):
        push_warning("ShopSystem: owned_upgrades save corrupted — resetting to empty")
        _owned_upgrades = []
        return
    _owned_upgrades = []
    for elem in raw:
        if elem is StringName:
            _owned_upgrades.append(elem)
        elif elem is String:
            _owned_upgrades.append(StringName(elem))
        else:
            push_warning("ShopSystem: owned_upgrades contains invalid element type: %s" % typeof(elem))
```

**Filtrage IDs inconnus** : ne PAS purger (`EC-SHP-8` forward-safe). Les boutons rendus ne référencent que `_CATALOG` ; les IDs inconnus dans `_owned_upgrades` sont invisibles côté UI mais persistés inchangés au prochain save.

---

## Out of Scope

- Story 004 : credit display init (`get_total()` pull pattern).
- Story 005 : `_render_initial_catalogue()` (purchase + button state logic).
- Story 010 : SaveLoad write SYNC post-purchase.

---

## QA Test Cases

- **AC-SHP-1** : Logic
  - Given: mock SaveLoad retourne `[&"double_jump"]`
  - When: ShopController `_ready()` exécuté
  - Then: `_owned_upgrades == [&"double_jump"]` (assert via getter `get_owned_upgrades()`)
- **AC-SHP-2** : Logic
  - Given: mock SaveLoad retourne `[]`
  - When: `_ready()` exécuté
  - Then: `_owned_upgrades == []` ; aucun bouton OWNED
- **AC-SHP-15** : Integration scene
  - Given: mock SaveLoad retourne `[&"double_jump", &"dash_horizontal"]`
  - When: shop.tscn instancié
  - Then: 2 BuyButtons `disabled == true` OWNED dès `_ready()` complet
- **AC-SHP-23** : Logic
  - Given: mock SaveLoad retourne `null` (corruption)
  - When: `_ready()` exécuté
  - Then: `_owned_upgrades == []` + `push_warning` capturé
  - Edge: tester aussi avec `"corrupt_string"`, `42`, `{}`
- **AC-SHP-24** : Logic
  - Given: mock SaveLoad retourne `[&"triple_jump"]`
  - When: `_ready()` exécuté
  - Then: `_owned_upgrades == [&"triple_jump"]` ; 2 BuyButtons MVP non-disabled
  - Edge: ID conservé pour re-save (vérifié story-010)
- **EC-SHP-39 cross-type cast** : Logic
  - Given: mock SaveLoad retourne `["double_jump"]` (Array[String], pas StringName)
  - When: `_ready()` exécuté
  - Then: `_owned_upgrades == [&"double_jump"]` (cast appliqué) ; `&"double_jump" in _owned_upgrades`

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/shop/boot_hydrate_owned_upgrades_test.gd` — must exist and pass
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (ShopController + catalogue)
- Unlocks: Story 005 (cycle achat lit `_owned_upgrades`), Story 010 (write back symétrique), Story 015 (bidirectional)
