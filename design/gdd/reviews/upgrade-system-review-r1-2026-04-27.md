# Upgrade System r1 — Review Report (2026-04-27)

> **Target** : `design/gdd/upgrade-system.md` (r1, 719 lignes, 14 R-UPG + 4 F-UPG + 35 EC + 43 ACs + 10 OQ)
> **Mode** : full (4 specialists adversariaux + creative-director synthèse)
> **Verdict** : **NEEDS REVISION** (15 BLOCKING + 18 RECOMMENDED + 7 NICE-TO-HAVE)
> **Scope** : M (~3-4h editorial r2 design session focalisée)
> **Reviewer** : Claude (Opus 4.7) + game-designer + systems-designer + qa-lead + godot-specialist + creative-director
> **Branch** : `chore/story-014-tech-debt-cleanup`
> **Trigger** : user explicit `/design-review upgrade-system fresh session pour valider 14 R-UPG + 43 ACs + résoudre OQ-UPG-2`

---

## 1. Specialists invoked

| Agent | Role | Findings |
|-------|------|----------|
| `game-designer` | Player Fantasy + Rules adversarial | 4 BLOCKING + 4 RECOMMENDED + 1 NICE-TO-HAVE |
| `systems-designer` | Formulas boundary + state machine | 5 BLOCKING + 4 RECOMMENDED + 1 NICE-TO-HAVE |
| `qa-lead` | 43 ACs testability | 7 BLOCKING + 7 RECOMMENDED + 4 NICE-TO-HAVE |
| `godot-specialist` | Godot 4.6 / GDScript engine patterns | 4 BLOCKING + 3 RECOMMENDED + 2 NICE-TO-HAVE |
| `creative-director` | Senior synthesis + adjudications | 5 décisions cross-domain |

Total raw findings = 24 BLOCKING + 18 RECOMMENDED + 8 NICE-TO-HAVE. Après déduplication des convergences (3+ specialists) : **15 BLOCKING uniques + 18 RECOMMENDED + 7 NICE-TO-HAVE**.

---

## 2. Convergences cross-specialist (priorité critique)

Findings où 2+ specialists indépendants pointent le même problème depuis leur domaine — signal de fiabilité élevé.

### C-1 — `set(flag_name, true)` via reflection unsafe (3 axes)

**Source** : game-designer B3 + godot-specialist B1.

R-UPG-4 step 4 (ligne 121) appelle `set(flag_name, true)` où `flag_name` est lu depuis `_CATALOG`. Trois problèmes documentés indépendamment :

- **(a) Type safety bypass** : `set("can_air_jump", "true")` (String) coerce silencieusement à `true` (truthy). La déclaration `var can_air_jump: bool = false` n'enforce pas le type checker statique GDScript sur `Object.set()` qui passe par C++ runtime. Le test idempotence ne détectera pas une coercion erronée d'`Int → bool`.
- **(b) Performance** : `set()` réflexion ~5-10× plus lent que property access direct. Au MVP (N=2 boot, ~1 µs), négligeable. À N=8 Tier 2+ ou N=1M corrupted save, devient bloquant (voir aussi C-4 / B-6 save bloat).
- **(c) Property existence silent fail** : `set()` sur propriété inconnue retourne `false` silencieusement (EC-UPG-9 acknowledges). F-UPG-3 catalog test build-time est insuffisant si le test `get_property_list()` ne distingue pas `var` mutable de `const` immuable.

**Adjudication creative-director** : garder `set()` (Pillar 2 catalog data-driven préservé) MAIS via helper `_apply_flag(flag_name: StringName)` :

```gdscript
func _apply_flag(flag_name: StringName) -> void:
    assert(flag_name in get_property_list().map(func(p): return p.name),
           "UpgradeSystem: catalog points to unknown property '%s'" % flag_name)
    var current_type := typeof(get(flag_name))
    assert(current_type == TYPE_BOOL,
           "UpgradeSystem: catalog target '%s' is not bool (typeof=%d)" % [flag_name, current_type])
    set(flag_name, true)
    assert(get(flag_name) == true,
           "UpgradeSystem: set(%s, true) failed silently" % flag_name)
```

Compromise accepté : data-driven catalog OK pour Pillar 2 designer iteration ; runtime guards ajoutés via helper pour absorber B3 (a/b/c).

### C-2 — EC-UPG-14 contredit R-UPG-4 step 2 idempotence

**Source** : game-designer B4 + systems-designer B3.

R-UPG-4 step 2 (ligne 119) : "vérifier `_owned.has(id)` → si vrai, return" (early return strict).
EC-UPG-14 (ligne 319) : "guard doit vérifier `not _owned.has(id) OR not get(flag_name)` pour forcer re-synchronisation".

Mutuellement exclusif. Aucun AC ne teste le cas `_owned.has(id)=true` + `flag=false` (désync via mutation externe ou hot-reload).

**Adjudication creative-director** : **EC-UPG-14 wins**. Re-sync nécessaire pour absorber :
- Hot-reload Godot editor (EC-UPG-5)
- Mutation externe test/mod (EC-UPG-13)
- Race conditions intra-tick (EC-UPG-23)

R-UPG-4 step 2 réécrit r2 :
```
2. Vérifier `_owned.has(id) AND get(flag_name) == true` → si vrai, return (early return).
   Sinon : appliquer step 3-4 (re-set ou first-set, idempotent par invariant final).
```

AC ajouté r2 : `GIVEN _owned[&"x"]=true ET can_air_jump=false (désync injecté), WHEN apply_upgrade(&"x"), THEN can_air_jump=true (resync)`.

### C-3 — AC-UPG-22 coercion silencieuse, pas filtre

**Source** : systems-designer B4 + qa-lead B5 + godot-specialist B4 (3 specialists).

AC-UPG-22 actuel (ligne 613) affirme "éléments non-StringName filtrés avec warning". Mais GDScript 4.6 coerce silencieusement :
- `42` (int) → `StringName("42")`
- `null` → `StringName("")`
- `"string_plain"` (String) → `StringName("string_plain")`

Aucun filtre type explicite n'existe dans R-UPG-5 ou EC-UPG-15. Le rejet vient via R-UPG-9 (catalog miss → `push_warning` + skip) **par accident**, pas par design.

**Fix r1.1 appliqué** : AC-UPG-22 reformulé pour documenter la coercion + chemin R-UPG-9. EC-UPG-15 garde la même formulation (déjà cohérente avec R-UPG-9 path). Pas de filtre type ajouté (R-UPG-9 absorbe by construction, ajout filtre redondant).

---

## 3. BLOCKING findings (15 uniques)

### B-1 [game-designer] — R-UPG-12 no-revoke design intent vs feature manquante

R-UPG-12 (ligne 144) interdit `revoke_upgrade` MVP. Justification donnée : "applique anti-pilier pas de skill tree + simplifie contrat Save/Load". Ce sont des arguments d'implémentation, pas de fantasy. Un joueur qui achète `dash_horizontal` par erreur ne peut pas corriger.

**Adjudication CD** : MVP scope OK car anti-pilier "NOT skill tree" rend respec UI hors-scope (économie de complexité). MAIS :
- Reframer R-UPG-12 honnêtement : "MVP scope decision — respec UI implies skill tree mental model, contradicts anti-pilier. Tier 2+ may revisit if playtest demande."
- Retirer analogie Hollow Knight (charms = REVOCABLE, analogie mécaniquement fausse).
- Conserver Ghostrunner ref + ajouter SuperHot (capabilities permanentes, zéro UI).

**Status** : reportée r2 (rewriting needed).

### B-2 [game-designer] — R-UPG-3 ADR pour modification catalogue = over-governance

R-UPG-3 (ligne 115) : "Toute modification du mapping nécessite un ADR". Pour solo team en playtest itératif Tier 2+, exiger un ADR pour ajouter `&"wall_run_long"` est friction disproportionnée. Le vrai garde-fou est F-UPG-3 catalog sanity test en CI.

**Adjudication CD** : retirer requirement ADR. Remplacer par : "Toute modification de `_CATALOG` requiert mise à jour F-UPG-3 + CI green. Ajout > 12 entrées déclenche review architecture (migration `var → Dictionary[StringName, bool]`)."

**Status** : reportée r2.

### B-3 [game-designer + godot-specialist] — `set()` reflection (voir C-1)
**Status** : reportée r2 — helper `_apply_flag()` design + R-UPG-4 step 4 amendement.

### B-4 [game-designer + systems-designer] — EC-UPG-14 contredit R-UPG-4 (voir C-2)
**Status** : reportée r2 — EC-UPG-14 wins, AC ajouté.

### B-5 [systems-designer] — F-UPG-1 bound check `n >= 0` (cross-system)

F-UPG-1 cost lookup délégué à Credit F-CRD-3. À `n=-1` produit `cost=0`, à `n=999` produit `cost=19980`. Aucune assertion `n >= 0` documentée côté Credit ou Shop. Hors-scope Upgrade lui-même mais doit être tracé.

**Status** : flag pour `/consistency-check` Credit r3 amendement ou ajout EC dans Shop. Pas blocker Upgrade r2.

### B-6 [systems-designer] — F-UPG-2 save bloat defense

F-UPG-2 affirme O(N) bounded by max 8. Save corrompue avec N=1M produit 2-10s freeze main thread (set() reflection cost). Aucun EC ne défend.

**Status** : reportée r2 — ajouter EC-UPG-X :
```
EC-UPG-X — Save bloat (N > MAX_CATALOG_SIZE × 2):
  SI owned_array.size() > MAX_CATALOG_SIZE_TIER_2 × 2 (=16) ALORS
    push_warning("UpgradeSystem: save bloat detected (size=%d), truncating" % size)
    owned_array = owned_array.slice(0, MAX_CATALOG_SIZE_TIER_2 × 2)
    continuer hydration normale.
```

### B-7 [3 specialists] — AC-UPG-22 coercion (voir C-3)
**Status** : appliqué r1.1.

### B-8 [systems-designer] — F-UPG-4 Tier 2+ flags non-déclarés

F-UPG-4 (ligne 256) liste 8 capabilities incluant 5 vars (`can_triple_jump`, `can_dash_vertical`, `can_slow_mo_aerial`, `can_katana_extended`, `can_secret_radar`) absentes de la source MVP (lignes 64-66 ne déclarent que 3). Cross-ref EC-UPG-9 absent.

**Status** : reportée r2 — ajouter note explicite "ajout de `_CATALOG` Tier 2+ entry requiert déclaration var préalable, sinon `set()` no-op via EC-UPG-9 path".

### B-9 [qa-lead] — AC-UPG-3 autoload order test mécanisme

Parser `project.godot` fragile, `Engine.get_singleton_list()` ne garantit pas l'ordre.

**Status** : reportée r2 — réécrire AC : `GIVEN UpgradeSystem._ready() exécuté, WHEN on lit SaveLoad (autoload), THEN référence non-null ET SaveLoad._boot_complete == true`.

### B-10 [qa-lead] — AC-UPG-5 GUT instrumentation impossible

Autoloads init avant tests GUT. Impossible d'observer `_boot_complete = false` avant `_ready()`.

**Status** : reportée r2 — réécrire AC pour instance bare `var s = UpgradeSystem.new()` (pas autoload).

### B-11 [qa-lead] — AC-UPG-10/11/19/20 push_warning non-capturable

GUT n'a pas de mécanisme natif de capture `push_warning`. 4 ACs reposent sur "mock/capture push_warning" non spécifié.

**Status** : reportée r2 — soit (a) supprimer assertion warning, garder seulement état observable ; soit (b) documenter Logger injection technique requise (sous-classer + monkey-patch).

### B-12 [qa-lead] — AC-UPG-15 const injection impossible

Test injecte `{&"test_id": &"typo_flag"}` dans `const _CATALOG` — impossible runtime.

**Status** : reportée r2 — réécrire F-UPG-3 spec pour valider catalogue existant, pas test entries injection.

### B-13 [qa-lead] — AC-UPG-27/33 doublon
**Status** : appliqué r1.1 — AC-UPG-33 supprimé.

### B-14 [godot-specialist] — R-UPG-5 Array typage manquant
**Status** : appliqué r1.1 — `var owned: Array → Array[StringName]`.

### B-15 [godot-specialist] — `const _CATALOG` contenu mutable

`const` freeze le binding pas le contenu. `_CATALOG[&"injected"] = &"any"` est légal runtime. AC-UPG-6 ne couvre que rebinding.

**Status** : reportée r2 — étendre AC-UPG-6 : `GIVEN _CATALOG, WHEN on tente _CATALOG[&"x"] = &"y" runtime, THEN aucune erreur (Godot le permet) MAIS test isolation : reset state avant chaque test pour absorber pollution`.

---

## 4. RECOMMENDED findings (18 — important non-bloquant)

| # | Source | Finding |
|---|--------|---------|
| R-1 | game-designer | `_boot_complete` exposé publicly betraye claim B.1 invisibility — renommer ou hide |
| R-2 | game-designer | R-UPG-7 scénario player-perspective non-documenté |
| R-3 | game-designer | "Zéro signal outbound" présenté comme philosophie, devrait être MVP-only |
| R-4 | game-designer | Analogie Hollow Knight retirer (mécaniquement fausse — voir B-1) |
| R-5 | systems-designer | F-UPG-3 test unidirectionnel Shop→Upgrade (ne teste pas inverse) |
| R-6 | systems-designer | F-UPG-3 `get_property_list()` insuffisant pour détecter `const` vs `var` |
| R-7 | systems-designer | EC-UPG-23 torn-read claim trop absolue (callback paths) |
| R-8 | systems-designer | F-UPG-2 set() coût absolu non-documenté (claim O(1) imprécise) |
| R-9 | qa-lead | AC-UPG-12 frame counter trivially true (ne teste rien) |
| R-10 | qa-lead | AC-UPG-24 mock vs real Movement scene non spécifié |
| R-11 | qa-lead | AC-UPG-26 torn-read sur bool impossible — appliqué r1.1 (downgrade ADVISORY) |
| R-12 | qa-lead | AC-UPG-30/42/43 PROVISIONAL → AUTO BLOCKING — appliqué r1.1 |
| R-13 | qa-lead | AC-UPG-37 PLAYTEST anti-pattern protocol undefined |
| R-14 | qa-lead | AC-UPG-40/41 hardware/headless context non spécifié |
| R-15 | godot-specialist | `await` interdit dans autoload chain (formaliser règle) |
| R-16 | godot-specialist | `get_signal_list()` filter ambigu |
| R-17 | godot-specialist | Hot-reload race avec SaveLoad re-instantiation |
| R-18 | godot-specialist | PROCESS_MODE_ALWAYS set location (vs scene file) |

**Status** : 3 RECOMMENDED appliqués r1.1 (R-11, R-12 ×3 ACs). 15 RECOMMENDED reportés r2.

---

## 5. NICE-TO-HAVE findings (7 — coverage gaps)

| # | Source | Coverage gap |
|---|--------|--------------|
| N-1 | qa-lead | R-UPG-7 dedicated AC missing (player-never-instantiated case) |
| N-2 | qa-lead | EC-UPG-13/14 desync no AC |
| N-3 | qa-lead | EC-UPG-19 catalog rename migration AC missing |
| N-4 | qa-lead | EC-UPG-24/25 crash atomicity characterization AC missing |
| N-5 | game-designer | push_warning boot cost on 8 stale ids |
| N-6 | godot-specialist | Setter Tier 2+ breakage doc |
| N-7 | systems-designer | State machine ERROR/PARTIAL_BOOT |

**Status** : reportés r2 (low priority, nice-to-have polish).

---

## 6. Adjudications creative-director (5 décisions clés)

1. **`set()` reste avec helper `_apply_flag()`** — Pillar 2 data-driven catalog préservé, runtime guards ajoutés (existence + type + assert).
2. **EC-UPG-14 wins sur R-UPG-4** — re-sync nécessaire (hot-reload + tests désync), AC ajouté.
3. **No-revoke MVP OK avec reframing** — anti-pilier "NOT skill tree" évite UI complexité respec, retirer analogie Hollow Knight (charm REVOCABLE), garder Ghostrunner + ajouter SuperHot.
4. **Reorder autoload Upgrade pos 2** — cosmétique zéro coût structurel, optionnel ADR-0007 amendement r3 (non-bloquant Sprint 1).
5. **Pillar 2 feedback design** — Shop card OWNED label ownership confirmé MVP, runtime VFX d'unlock = Tier 2+ (déjà aligné GDD actuel).

---

## 7. OQ-UPG-2 status (user explicit ask)

**PARTIALLY RESOLVED 2026-04-27** — Movement r3 actuel confirme pull pattern :
- Lignes 38, 44, 46, 52 (`can_air_jump == true`, `can_dash == true`, `can_wall_run` gates conditionnels)
- Ligne 69 (`Movement lit Upgrade.can_air_jump...interface unidirectionnelle via capability API`)
- Ligne 315 (`Movement n'appelle jamais Upgrade`)

Contrat Upgrade r1 ↔ Movement r3 verrouillé sur pull pattern au 2026-04-27. **Caveat résiduel** : si Movement r4 fresh re-review (pending) introduit pattern push (signal `capability_changed` ou similaire), Upgrade r1 nécessitera amendement R-UPG-6 + R-UPG-8 + EC-UPG-22/23.

**Action immédiate r1.1** : OQ-UPG-2 reformulé "VERROUILLÉ Movement r3, à re-vérifier post Movement r4".

**Action conditionnelle post-Movement r4** : si push introduit, ouvrir OQ-UPG-2-bis.

**Pas blocker r1**.

---

## 8. r1.1 cosmetic fixes appliqués (8)

| # | Item | Action | Source finding |
|---|------|--------|----------------|
| 1 | AC-UPG-30 PROVISIONAL → AUTO BLOCKING | Edit | R-12 (Save/Load r1 unblock) |
| 2 | AC-UPG-42 PROVISIONAL → AUTO BLOCKING | Edit | R-12 |
| 3 | AC-UPG-43 PROVISIONAL → AUTO BLOCKING | Edit | R-12 |
| 4 | AC-UPG-33 SUPPRIMÉ doublon | Edit | B-13 |
| 5 | AC-UPG-22 reword coercion silencieuse | Edit | C-3 / B-7 |
| 6 | AC-UPG-26 downgrade BLOCKING → ADVISORY | Edit | R-11 |
| 7 | R-UPG-5 fix `Array → Array[StringName]` | Edit | B-14 |
| 8 | OQ-UPG-2 reformulation VERROUILLÉ Movement r3 | Edit | user explicit ask |

GDD status header bump : Designed r1 → Designed r1.1 (review fresh appliqué cosmetic).

---

## 9. r2 design session — 7 structural BLOCKING reportés

Effort estimé : ~3-4h editorial focalisée.

| Priority | Item | Effort | Owner |
|----------|------|--------|-------|
| Top 1 | B-3 helper `_apply_flag()` + R-UPG-4 step 4 | 30 min | game-designer + godot-specialist |
| Top 2 | B-4 EC-UPG-14 reconciliation R-UPG-4 + AC ajouté | 30 min | systems-designer + qa-lead |
| Top 3 | B-1 R-UPG-12 reframe + retirer analogie Hollow Knight | 20 min | game-designer + creative-director |
| Top 4 | B-2 retirer requirement ADR catalogue | 15 min | game-designer |
| 5 | B-6 ajouter EC-UPG-X save bloat defense | 20 min | systems-designer |
| 6 | B-8 F-UPG-4 cross-ref EC-UPG-9 + note vars | 15 min | systems-designer |
| 7 | B-9 à B-12 + B-15 ACs rewrite session | 1h | qa-lead + godot-specialist |

Plus 15 RECOMMENDED batchables pendant r2 (~30 min cumulés).

**Cross-system flag** : B-5 F-UPG-1 bound check `n >= 0` documentation côté Credit r3 amendement ou /consistency-check Credit Economy + Shop chain. Pas blocker Upgrade r2.

---

## 10. Verdict + Path to APPROVED

**Verdict** : **NEEDS REVISION** — 15 BLOCKING dont 3 convergences cross-specialist fortes (set() reflection, idempotence-desync, AC-UPG-22 coercion). Pas APPROVED, mais résoluble en 1 session r2 focalisée.

**Path to APPROVED** :
1. r2 design session focalisée (~3-4h) addressing 7 structural BLOCKING + 15 RECOMMENDED batchables.
2. Re-review fresh post r2 (5 minutes lean session, juste vérifier les 7 BLOCKING addressés).
3. APPROVED → unlock `/create-epics upgrade-system`.

**Status post-review fresh 2026-04-27** :
- 8 cosmetic fixes appliqués r1.1 (3 ACs promus AUTO BLOCKING + 1 AC supprimé doublon + 2 ACs reformulés + 1 type fix R-UPG-5 + 1 OQ-UPG-2 reformulation).
- 7 structural BLOCKING tracés pour r2 design session distincte.
- 1 cross-system B-5 flagué pour Credit r3 ou /consistency-check.

---

## 11. Files touched (review session)

- `design/gdd/upgrade-system.md` — 8 cosmetic edits r1 → r1.1 + status header bump.
- `design/gdd/reviews/upgrade-system-review-r1-2026-04-27.md` — NEW (this file).
- `design/gdd/reviews/upgrade-system-review-log.md` — NEW (continuous log).
- `design/gdd/systems-index.md` — Upgrade row status update Designed r1 → Designed r1.1 (NEEDS REVISION pending r2 design session).

---

## 12. Prior verdict resolved

**First review** — pas de prior verdict.

---

## 13. Next recommended

**A** : `/design-system upgrade-system r2` design session focalisée (~3-4h) addressing 7 structural BLOCKING + 15 RECOMMENDED batchables. Output : Designed r2 (pending re-review post-r2).

**B** : commit batch atomique r1.1 cosmetic + review files (4 fichiers : GDD r1.1 + review-r1 + review-log + systems-index update).

**C** : `/consistency-check` Credit ↔ Shop ↔ Upgrade pour B-5 bound check `n >= 0` ownership (parallel work, non-bloquant Upgrade r2).

**D** : continuer Sprint A backbone — `/design-review save-load-system` fresh (OQ-SAV-1 maintenant RESOLVED via Upgrade r1) ou `/design-system menu-system` r2 (si pending) pour fermer Sprint A pre-`/create-epics`.

**Recommandation** : option A immédiatement (r2 design session) + option B en parallèle (commit r1.1 cosmetic atomique pour préserver l'état actuel avant r2). Si scope serré : option B seul, r2 attend la prochaine session.
