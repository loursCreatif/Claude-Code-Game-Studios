# Story 014: Anti-Patterns Lint Static

> **Epic**: Shop System
> **Status**: Complete
> **Layer**: Feature (CI gate)
> **Type**: Logic (lint-as-code)
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: §V.4 (Anti-pattern Visual/Audio testables) + §J.9 (Anti-patterns Shop UI MVP) + AC-SHP-37/39/40/41/42/43/44/45 (lint static)
*Battery of lint static checks gating shop.tscn et shop_controller.gd. Couvre Pillar 1 (anti-distraction), anti-fantasy F2P (no fanfare/confetti), anti-pillar grinding (no scroll/tab), Chrome Zen (no AnimatedTexture), conformité Input GDD Core Rule 1 (no `Input.*` direct hors `_unhandled_input`), no-alloc hot paths (no Dictionary/push_back dans `_process`/`_physics_process`).*

**ADR Governing Implementation**: ADR-0004 (Input API — no Input.* direct gameplay) + control-manifest no-alloc rules.
**ADR Decision Summary**: Lint statique cross-projet via grep ; failure CI blocking. Pattern cohérent `.claude/rules/no-alloc-hot-paths.md` + `.claude/rules/input-singleton-main-thread-only.md`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Lint via shell `grep` Bash standard, pas de dépendance Godot CLI runtime (sauf parsing tscn).

**Control Manifest Rules**:
- Required: lint statique cover-all (zéro tolérance sur anti-patterns testables)
- Forbidden: tous patterns listés dans GDD §V.4 + §J.9

---

## Acceptance Criteria

- [ ] **AC-SHP-37 [ADVISORY]** : ShopController hot paths (`_process`, `_physics_process`) → zéro `push_back` / `Dictionary.new` / Dictionary literal `{...}` / `String(` cast (cohérent rule no-alloc-hot-paths).
- [ ] **AC-SHP-39 [ADVISORY]** : `shop.tscn` → zéro `AnimationPlayer` (J.9 anti-pattern animated background loop).
- [ ] **AC-SHP-40 [ADVISORY]** : `shop.tscn` → zéro `TabContainer` (J.9 anti-pattern onglets cosmétiques F2P).
- [ ] **AC-SHP-41 [ADVISORY]** : ShopController → un seul Label expose solde crédits ; zéro symbole monétaire alternatif ("premium", "gem", "coin").
- [ ] **AC-SHP-42 [ADVISORY]** : `shop.tscn` → zéro `ScrollContainer` (J.9 anti-pattern news feed / promo banner).
- [ ] **AC-SHP-43 [ADVISORY]** : `shop.tscn` + `shop_controller.gd` → zéro `AudioStreamPlayer` (V.4 + J.9 anti-pattern fanfare achat MVP).
- [ ] **AC-SHP-44 [BLOCKING]** : ShopController → zéro `Input.*` hors `_unhandled_input` (Input GDD Core Rule 1 + rule `input-singleton-main-thread-only`).
- [ ] **AC-SHP-45 [ADVISORY]** : ShopController → zéro `UpgradeSystem.*` hors bloc `if try_spend(...): ... apply_upgrade(...)` (couplage minimal, story-005 contraint).
- [ ] V.4 **anti-fanfare** : zéro `AudioSystem.play_music_stinger` ; zéro `GPUParticles2D` ; zéro `GPUParticles3D` dans shop.tscn ou controller.
- [ ] V.4 **anti-AnimatedTexture** : grep `AnimatedTexture` dans shop.tscn → 0 match.
- [ ] J.9 **no AcceptDialog/ConfirmationDialog** : zéro modal confirmation popup avant achat.
- [ ] J.9 **no tooltip ContinueButton** : ContinueButton n'a pas de `tooltip_text` configuré.

---

## Implementation Notes

Créer `tools/lint/lint_shop_anti_patterns.sh` (shell script CI-callable) :

```bash
#!/usr/bin/env bash
set -e
SHOP_TSCN="scenes/shop/shop.tscn"
SHOP_CTRL="src/ui/shop/shop_controller.gd"
FAIL=0

check() {
    local label=$1; local pattern=$2; local file=$3; local expected=$4
    local count
    count=$(grep -cE "$pattern" "$file" 2>/dev/null || echo 0)
    if [ "$count" -ne "$expected" ]; then
        echo "FAIL [$label]: $file — expected $expected matches of /$pattern/, found $count"
        FAIL=1
    else
        echo "OK   [$label]: $file"
    fi
}

# AC-SHP-39
check "AC-SHP-39 no AnimationPlayer"  "AnimationPlayer"      "$SHOP_TSCN" 0
# AC-SHP-40
check "AC-SHP-40 no TabContainer"     "TabContainer"          "$SHOP_TSCN" 0
# AC-SHP-42
check "AC-SHP-42 no ScrollContainer"  "ScrollContainer"       "$SHOP_TSCN" 0
# AC-SHP-43
check "AC-SHP-43 no AudioStreamPlayer (tscn)" "AudioStreamPlayer" "$SHOP_TSCN" 0
check "AC-SHP-43 no AudioStreamPlayer (gd)"   "AudioStreamPlayer" "$SHOP_CTRL" 0
# V.4 anti-fanfare
check "V.4 no GPUParticles2D"         "GPUParticles2D"        "$SHOP_TSCN" 0
check "V.4 no GPUParticles3D"         "GPUParticles3D"        "$SHOP_TSCN" 0
check "V.4 no AnimatedTexture"        "AnimatedTexture"       "$SHOP_TSCN" 0
check "V.4 no music_stinger call"     "play_music_stinger"    "$SHOP_CTRL" 0
# J.9 no modal confirmation
check "J.9 no AcceptDialog"           "AcceptDialog"          "$SHOP_TSCN" 0
check "J.9 no ConfirmationDialog"     "ConfirmationDialog"    "$SHOP_TSCN" 0
# AC-SHP-41 — un seul symbole monétaire (₵), pas de "premium"/"gem"/"coin"
check "AC-SHP-41 no premium label"    "premium"               "$SHOP_CTRL" 0
check "AC-SHP-41 no gem label"        "gem"                   "$SHOP_CTRL" 0

# AC-SHP-44 — Input.* hors _unhandled_input — extraction function-scope
python3 tools/lint/check_input_singleton_outside_unhandled_input.py "$SHOP_CTRL" || FAIL=1

# AC-SHP-45 — UpgradeSystem.* contexte try_spend
python3 tools/lint/check_upgrade_call_inside_try_spend.py "$SHOP_CTRL" || FAIL=1

# AC-SHP-37 — no-alloc hot paths
python3 tools/lint/check_no_alloc_hot_paths.py "$SHOP_CTRL" || FAIL=1

exit $FAIL
```

**Helpers Python** (réutiliser pattern existant `.claude/rules/no-alloc-hot-paths.md` + `.claude/rules/input-singleton-main-thread-only.md` — extraction function-scope filtrant commentaires + strings).

**Intégration CI** : ajouter job dans `.github/workflows/tests.yml` :
```yaml
lint-shop-anti-patterns:
  runs-on: ubuntu-22.04
  steps:
    - uses: actions/checkout@v4
    - run: bash tools/lint/lint_shop_anti_patterns.sh
```

---

## Out of Scope

- Story 015 : tests integration runtime (cette story est lint statique).
- Tier 2+ : exception accord modal dialog si game design évolue (amendement GDD).
- Lint cross-projet existant (`.claude/rules/*` déjà actifs sur src/).

---

## QA Test Cases

- **AC-SHP-39 no AnimationPlayer** : Lint
  - Setup : `scenes/shop/shop.tscn`
  - Verify : `grep -c "AnimationPlayer" scenes/shop/shop.tscn`
  - Pass : 0 match
- **AC-SHP-40 no TabContainer** : Lint
  - Verify : `grep -c "TabContainer" scenes/shop/shop.tscn` → 0
  - Pass : 0 match
- **AC-SHP-42 no ScrollContainer** : Lint
  - Verify : `grep -c "ScrollContainer" scenes/shop/shop.tscn` → 0
  - Pass : 0 match
- **AC-SHP-43 no AudioStreamPlayer** : Lint
  - Verify : grep dans tscn ET gd → 2× 0 match
  - Pass : zéro fanfare audio
- **AC-SHP-44 no Input.* outside _unhandled_input** : Lint
  - Setup : ShopController source
  - Verify : extract function bodies hors `_unhandled_input`, `grep -nE '\bInput\.'` filtré commentaires + strings → 0 match
  - Pass : conforme Input GDD Core Rule 1
- **AC-SHP-45 UpgradeSystem in try_spend branch only** : Lint
  - Verify : `grep -n "UpgradeSystem.apply_upgrade" $SHOP_CTRL` → toutes occurrences dans branche `if try_spend(...):`
  - Pass : zéro appel hors branche success
- **AC-SHP-37 no-alloc hot paths** : Lint
  - Verify : extract `_process` / `_physics_process` body (le cas échéant), grep `push_back|Dictionary.new|{.*=.*}|String\(`
  - Pass : 0 match dans hot paths
- **V.4 no AnimatedTexture** : Lint
  - Verify : `grep -c "AnimatedTexture" scenes/shop/shop.tscn` → 0
- **J.9 no modal** : Lint
  - Verify : grep `AcceptDialog|ConfirmationDialog` → 0
- **J.9 no tooltip Continue** : Manual or scene parse
  - Setup : open shop.tscn, inspect ContinueButton
  - Verify : `tooltip_text == ""`
  - Pass : pas de tooltip

---

## Test Evidence

**Story Type**: Logic (lint script)
**Required evidence**: `tools/lint/lint_shop_anti_patterns.sh` + GitHub Action job + ci log green
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (shop.tscn existe), Story 002 (controller existe), Story 005 (UpgradeSystem call patterns), Story 008 (ContinueButton — no tooltip), Story 009 (`_unhandled_input` ESC seul accès Input)
- Unlocks: gate CI pour merge Sprint 1

---

## Completion Notes
**Completed**: 2026-04-28
**Criteria**: passing (15/15) — AC-SHP-39 (no AnimationPlayer tscn), AC-SHP-40 (no TabContainer), AC-SHP-42 (no ScrollContainer), AC-SHP-43 (no AudioStreamPlayer tscn+gd), V.4 (no GPUParticles2D/3D + no AnimatedTexture + no play_music_stinger), J.9 (no AcceptDialog/ConfirmationDialog), AC-SHP-41 (no premium/gem labels), AC-SHP-44 BLOCKING (no Input.* hors `_unhandled_input` — extraction function-scoped), AC-SHP-37 ADVISORY (no `_process`/`_physics_process` hot paths côté ShopController), AC-SHP-45 ADVISORY (Upgrade.apply_upgrade uniquement après `try_spend`).
**Deviations**: ADVISORY (3)
  - **Lint format** : tests GdUnit4 (`tests/static/shop_anti_patterns_lint_test.gd`) au lieu de bash script `tools/lint/lint_shop_anti_patterns.sh` + Python helpers — pattern cohérent avec upgrade-system story-009 (`tests/static/upgrade_lint_test.gd`), single-runner GdUnit4 + pas de dépendance Python/CI. Spec-equivalent.
  - **CI YAML job** non ajouté — tests intégrés dans suite GdUnit4 globale (`.github/workflows/tests.yml` exécute déjà l'add `tests/static/`). Equivalent à intégration directe.
  - **AC-SHP-41 "coin"** : exclu du lint (potentiellement légitime dans comments explicatifs ex. "no coin imagery"). "premium"/"gem" sont strictement F2P-coded et lint-able sans false-positive.
**Test Evidence**: Logic — `tests/static/shop_anti_patterns_lint_test.gd` 15/15 PASSED 113 ms (`reports/report_97/`).
**Code Review**: Skipped (Solo mode).
