# Story-001 — Scene Skeleton : QA Evidence

**Date** : 2026-04-27
**Story** : story-001 (Shop scene skeleton)
**Type** : UI — ADVISORY (non-blocking per testing grid)

## Fichier créé

`scenes/shop/shop.tscn`

## AC-SHP-29 — layer = 60

```
grep "layer = 60" scenes/shop/shop.tscn
```

Output (1 match) :
```
layer = 60
```

## AC-SHP-30 — process_mode = 3 (PROCESS_MODE_ALWAYS)

> **Erratum 2026-04-28** : la version initiale de ce fichier (et l'AC-SHP-30 d'origine) asseyait `process_mode = 4`. Vérification croisée docs Godot 4.6 (`Node.ProcessMode`) : `ALWAYS = 3`, `DISABLED = 4`. Le scene-fichier contenait donc `PROCESS_MODE_DISABLED` — bug runtime SHIP-CRITICAL (`_process`/`_input`/tweens désactivés) faussement validé par grep. Corrigé : `process_mode = 3`. Cause racine : table d'enum erronée propagée depuis `menu-system.md` r2 cosmetic — corrigée en parallèle.

```
grep "process_mode = 3" scenes/shop/shop.tscn
```

Output (1 match) :
```
process_mode = 3
```

## Listing des nœuds (R-SHP-2)

```
grep '\[node name=' scenes/shop/shop.tscn
```

Output :
```
[node name="ShopCanvas" type="CanvasLayer"]
[node name="ShopRoot" type="Control" parent="ShopCanvas"]
[node name="Background" type="ColorRect" parent="ShopCanvas/ShopRoot"]
[node name="MarginContainer" type="MarginContainer" parent="ShopCanvas/ShopRoot"]
[node name="VBoxContainer" type="VBoxContainer" parent="ShopCanvas/ShopRoot/MarginContainer"]
[node name="ShopTitle" type="Label" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer"]
[node name="HSeparator" type="HSeparator" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer"]
[node name="CreditDisplay" type="HBoxContainer" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer"]
[node name="CreditLabel" type="Label" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer/CreditDisplay"]
[node name="CreditValueLabel" type="Label" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer/CreditDisplay"]
[node name="UpgradeList" type="VBoxContainer" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer"]
[node name="UpgradeCard_0" type="PanelContainer" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer/UpgradeList"]
[node name="UpgradeCard_1" type="PanelContainer" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer/UpgradeList"]
[node name="FooterRow" type="HBoxContainer" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer"]
[node name="ContinueButton" type="Button" parent="ShopCanvas/ShopRoot/MarginContainer/VBoxContainer/FooterRow"]
```

## Notes

- Aucun script attaché (story-002 owne ShopController).
- Aucun styling custom au-delà de la couleur Background (story-012 owne Chrome Zen styling).
- Background color = `Color(0.0392157, 0.0392157, 0.0705882, 1)` = #0A0A12 SHOP_BG token.

## Erratum 2026-04-28 — Bug structurel scene + parse-clean test

**Bug identifié** : la version initiale de `shop.tscn` utilisait `parent="ShopCanvas"` (et chemins composés `"ShopCanvas/..."`) — paths absolus invalides en convention Godot 4. Les enfants étaient orphelins : `get_node("ShopRoot")` retournait null malgré scene parse-clean au load. Symptôme : test skeleton initial 1/3 PASSED + 15 orphan nodes warning + crash AC-SHP-30 runtime.

**Fix** : `parent="ShopCanvas"` → `parent="."` ; `parent="ShopCanvas/<path>"` → `parent="<path>"` (convention Godot 4 root-relative). Aligné `scenes/menus/main_menu.tscn` (référence).

**Test parse-clean automatisé** : `tests/static/shop_scene_skeleton_lint_test.gd` GdUnit4 — **5/5 PASSED 51 ms** (0 orphans) :

| Test | Couvre |
|---|---|
| `test_shop_scene_parse_clean_root_is_canvaslayer` | scene load + instantiate non-null + root type CanvasLayer |
| `test_shop_scene_ac_shp_29_canvas_layer_is_60` | AC-SHP-29 |
| `test_shop_scene_ac_shp_30_shop_root_process_mode_is_always` | AC-SHP-30 (Node.PROCESS_MODE_ALWAYS=3 enum-named, anti-bug `=4`) |
| `test_shop_scene_hierarchy_rshp2_all_nodes_present` | 14 nœuds R-SHP-2 walk + type check |
| `test_shop_scene_background_color_is_shop_bg_token` | Background.color ≈ #0A0A12 (tolerance 1.5/255) |

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add res://tests/static/shop_scene_skeleton_lint_test.gd --ignoreHeadlessMode
# Statistics: 5 test cases | 0 errors | 0 failures | 0 orphans | PASSED 51ms
```
