# Story 011: Playtest Pillar 2 Understanding Evidence

> **Epic**: upgrade-system
> **Status**: Ready (AC-UPG-37 (a) (b) ✅ Complete 2026-05-04 — `tests/integration/upgrade/no_upgrade_scene_during_purchase_test.gd` 2/2 PASS exit 0 ; AC-UPG-37-bis playtest humain ≥10 novices DEFERRED — non-blocker MVP code, evidence doc à produire post-build playable)
> **Layer**: Feature
> **Type**: Visual/Feel
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : Pillar 2 LA PROGRESSION SE VOIT ET SE SENT (Section B.1 Player Fantasy "Le crédit n'est plus un nombre, c'est une nouvelle façon de toucher l'air"). AC-UPG-37 (no scene/UI nodes from upgrade owner during purchase) + AC-UPG-37-bis (NEW r1.2 — playtest novice 80% understanding 30s post-shop).

**ADR Governing Implementation** : aucun ADR direct. Pillar 2 validation est playtest empirique.
**ADR Decision Summary** : la décision GDD R-UPG-6 "zéro signal outbound MVP" + Pillar 1 "FLOW AVANT TOUT" (anti-friction modal/UI) crée un risque sur Pillar 2 (le joueur peut ne pas comprendre qu'une nouvelle capacité a été débloquée). AC-UPG-37-bis est le test empirique anti-régression de cette décision.

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : pas d'API engine — c'est un test playtest manuel. Critère pass : 80% des sessions enregistrées (échantillon ≥10 novices) comprennent la nouvelle capacité dans les 30s post-shop.

**Control Manifest Rules (Feature Layer)** :
- Required : evidence doc dans `production/qa/evidence/` avec sign-off lead (game-designer + creative-director).
- Forbidden : ajouter du feedback in-world au moment de `apply_upgrade` (violerait Pillar 1 et la décision R-UPG-6 — si playtest fail, ouvrir OQ-UPG-3 SFX d'unlock latent Tier 2+, pas un fix MVP).

---

## Acceptance Criteria

- [x] **AC-UPG-37** [ADVISORY automated 2026-05-04] : pendant `apply_upgrade(&"double_jump")` + `apply_upgrade(&"dash_horizontal")`, (a) aucune nouvelle scène instanciée avec root node ownership `src/gameplay/upgrade/` ; (b) aucun nœud Control nouveau contenant substring `"skill"|"tree"|"talent"|"perk"|"respec"` dans son `name`. Test : `tests/integration/upgrade/no_upgrade_scene_during_purchase_test.gd` 2/2 PASS, 20 ms.
- [ ] **AC-UPG-37-bis** [ADVISORY PLAYTEST DEFERRED] : ≥10 sessions playtest novice ; ≥80% comprennent qu'une nouvelle capacité est débloquée dans les 30s post-shop, sans intervention extérieure. Pré-requis : build MVP playable (Shop epic complete) ; evidence doc à produire post-vertical-slice.

---

## Implementation Notes

### AC-UPG-37 protocole — SceneTree inspector hook

```gdscript
# tests/integration/upgrade/no_upgrade_scene_during_purchase_test.gd
func test_AC_UPG_37_no_upgrade_scene_during_purchase() -> void:
    var nodes_before: Array = _collect_all_nodes(get_tree().root)

    # Simulate shop purchase
    Shop.try_buy(&"double_jump")    # Coordination Shop epic
    await get_tree().process_frame

    var nodes_after: Array = _collect_all_nodes(get_tree().root)
    var new_nodes := nodes_after.filter(func(n): return not (n in nodes_before))

    # (a) aucun root node owned par src/gameplay/upgrade/
    var upgrade_owned := new_nodes.filter(func(n):
        var script := n.get_script()
        return script != null and str(script.resource_path).begins_with("res://src/gameplay/upgrade/")
    )
    assert_eq(upgrade_owned.size(), 0, "AC-UPG-37 (a) FAIL : nodes owned by upgrade/ : %s" % upgrade_owned)

    # (b) aucun Control name contains "skill|tree|talent|perk|respec"
    var forbidden_substrings := ["skill", "tree", "talent", "perk", "respec"]
    var ui_violators := new_nodes.filter(func(n):
        if not (n is Control):
            return false
        var nm: String = n.name.to_lower()
        return forbidden_substrings.any(func(s): return s in nm)
    )
    assert_eq(ui_violators.size(), 0, "AC-UPG-37 (b) FAIL : UI nodes skill/tree/talent : %s" % ui_violators)
```

Cette automatisation peut être intégrée à AC-UPG-29 cross-GDD shop integration test (story 009 dependency Shop epic).

### AC-UPG-37-bis protocole playtest

**Setup** :
1. Build MVP avec catalog `&"double_jump"` (premier upgrade testé) + `&"dash_horizontal"` (deuxième).
2. Playtest pool ≥ 10 personnes "novices" (n'ont jamais joué le jeu, ne savent rien sur le système upgrade).
3. Session : laisser jouer Étage 1 + Shop + début Étage 2. Filmer écran + voix.

**Mesure** :
- Time to first awareness : combien de secondes après sortie du shop avant que le playtester verbalise/utilise la nouvelle capacité ?
- Compréhension explicite : à 30s post-shop, demander "Qu'est-ce que tu as débloqué ?" — répons correct = comprend.
- Compréhension implicite : à 30s post-shop, le playtester a-t-il **utilisé** la capacité (essayé un double-jump après upgrade) sans qu'on lui demande ?

**Pass criteria** : ≥80% des 10+ sessions ont compréhension explicite OU implicite dans les 30s.

**Fail action** :
- Si fail : ouvrir OQ-UPG-3 promotion (SFX d'unlock latent Tier 2+) + amender Audio r2.2 + HUD pulse différencié.
- **NE PAS** ajouter UI/feedback MVP — violerait R-UPG-6.

### Evidence doc location

`production/qa/evidence/upgrade-pillar2-playtest-evidence.md` :

```markdown
# Upgrade System — Pillar 2 Playtest Evidence

**Date** : YYYY-MM-DD
**Build** : MVP commit-hash
**Pool** : N novice playtesters
**Sessions enregistrées** : `production/qa/evidence/upgrade/playtest-N-NN.mp4` (lien)

## Résultats

| Session | Time to awareness | Compréhension explicite (30s) | Compréhension implicite (30s) | Pass |
|---------|-------------------|------------------------------|------------------------------|------|
| 1 | 12s | OUI | OUI | ✅ |
| 2 | ... | ... | ... | ... |

## Verdict

Pass rate : N/M (XX%)
- Pass criteria : ≥ 80%.
- Result : PASS / FAIL
- Action si FAIL : ...

## Sign-off

- [ ] game-designer
- [ ] creative-director
```

---

## Out of Scope

- Tier 2+ SFX d'unlock (OQ-UPG-3) — déclenché si AC-UPG-37-bis FAIL régulièrement.
- HUD indicator capability owned (Tier 2+ — voir Cousins HUD GDD).
- Analytics post-launch instrumentation (Tier 2+, hors MVP scope).

---

## QA Test Cases

**AC-UPG-37** — Integration test [ADVISORY automated]
- Given : shop scene + Upgrade autoload.
- When : full purchase cycle exécuté.
- Then : (a) zéro nouveau node owned par `src/gameplay/upgrade/` ; (b) zéro Control name contient `skill|tree|talent|perk|respec`.
- Pass condition : assertion automated en CI integration test (couplé Shop epic story).

**AC-UPG-37-bis** — Manual playtest evidence [ADVISORY]
- Setup : build MVP + ≥10 novice playtesters + recording.
- Verify : sessions filmées + tableau résultats + verbatim comprehension check à 30s.
- Pass condition : ≥80% sessions comprennent (explicite ou implicite) la nouvelle capacité dans 30s.
- Sign-off : game-designer + creative-director sur evidence doc.

---

## Test Evidence

**Story Type** : Visual/Feel
**Required evidence** :
- `tests/integration/upgrade/no_upgrade_scene_during_purchase_test.gd` (AC-UPG-37 auto) — **[x] Created 2026-05-04, 2/2 PASS exit 0, 20 ms**.
- `production/qa/evidence/upgrade-pillar2-playtest-evidence.md` + recordings (AC-UPG-37-bis manual) — **[ ] DEFERRED post-vertical-slice playable build**.
- Sign-off : game-designer + creative-director.
**Status** : [~] Partial — AC-UPG-37 automated cover ; AC-UPG-37-bis playtest evidence DEFERRED (Shop epic + build MVP pré-requis)

---

## Dependencies

- Depends on : 005 (boot hydration shop→level scenario), 007 (pull pattern Movement reads flags) ; Shop epic story `try_buy` mergé pour playtest scenario complet.
- Unlocks : aucune story bloquée. C'est le gate empirique Pillar 2 epic Definition of Done.
