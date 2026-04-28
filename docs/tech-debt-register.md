# Technical Debt Register

> Registre des dettes techniques identifiées en cours de développement.
> Chaque entrée note l'origine (story, code review, ADR), la sévérité (BLOCKING / ADVISORY / TRIVIAL),
> le coût estimé de remboursement, et le déclencheur de re-priorisation.
>
> Mise à jour : alimentée par `/story-done`, `/code-review`, `/architecture-review`, `/tech-debt`.

## Format

| ID | Date | Origine | Sévérité | Coût | Description | Action |
|----|------|---------|----------|------|-------------|--------|

---

## TD-001 — ADR-0007 VC-6 : amender pour 3 writes `get_tree().paused`

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 |
| **Origine** | `/story-done` story-001 menu-system |
| **Sévérité** | ADVISORY |
| **Coût** | XS (1-2h) — amendement texte ADR + bump VC-6 lint expected count à 3 |
| **Fichier** | `docs/architecture/adr-0007-game-state-manager.md` (VC-6 ligne 436) |

**Description** : VC-6 stipule "exactement 2 matches attendus pour `get_tree().paused =`" dans `game_state_manager.gd`. Implémentation contient **3 writes légitimes** :
- Ligne 57 : `get_tree().paused = true` (request_pause)
- Ligne 64 : `get_tree().paused = false` (request_resume)
- Ligne 72 : `get_tree().paused = false` (request_scene_transition — libère pause flag avant Pause→MainMenu, anti-flicker)

Le 3e write est une nécessité fonctionnelle non anticipée par la rédaction initiale de l'ADR. Autorité unique D-4 respectée (tous les writes restent dans GSM).

**Action** : amendement ADR-0007 VC-6 — passer expected count de 2 à 3, documenter le 3e write au D-4. Pourrait être groupé dans le prochain `/architecture-review`.

**Trigger re-prio** : si un 4e write apparaît, escalader (signal d'authority drift).

---

## TD-002 — main_menu_controller.gd : version_label.visible redondant

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 |
| **Origine** | `/code-review` story-001 menu-system |
| **Sévérité** | TRIVIAL (cosmétique) |
| **Coût** | XS (5 min) |
| **Fichier** | `src/gameplay/menu/main_menu_controller.gd` ligne 38 |

**Description** : `version_label.visible = DEBUG_SHOW_VERSION` au runtime alors que `main_menu.tscn` ligne 54 fige déjà `visible = false`. Comportement identique, ligne supprimable.

**Action** : supprimer ligne 38 OU remplacer par commentaire `# visible déjà figé dans .tscn — gate runtime via DEBUG_SHOW_VERSION constant si besoin futur`.

**Trigger re-prio** : aucun — opportuniste lors de prochaine édition du fichier.

---

## TD-003 — GSM `_ready` : ajouter assert R-3 mitigation autoload order

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 |
| **Origine** | `/code-review` story-001 menu-system |
| **Sévérité** | ADVISORY |
| **Coût** | XS (5 min) — 1 ligne |
| **Fichier** | `src/core/game_state_manager.gd` ligne ~40 (avant connect ligne 42) |

**Description** : ADR-0007 R-3 ligne 384 mitigation : `assert InputManager != null` en début de GSM `_ready` pour crash explicite si `project.godot` autoload réordonné par erreur. Story-001 n'imposait pas ce guard, mais c'est une mitigation explicite de l'ADR.

**Action** :
```gdscript
func _ready() -> void:
    assert(InputManager != null, "GSM autoload order violation: InputManager must precede GameStateManager (project.godot [autoload])")
    process_mode = Node.PROCESS_MODE_ALWAYS
    InputManager.application_focus_lost.connect(_on_application_focus_lost)
```

**Trigger re-prio** : escalader BLOCKING si un dev modifie `project.godot [autoload]` ordering sans review.

---
