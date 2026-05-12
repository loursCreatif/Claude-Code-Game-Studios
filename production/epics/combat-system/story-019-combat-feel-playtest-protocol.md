# Story 019: Combat feel playtest protocol + Visual/Feel ACs

> **Epic**: Player Combat System
> **Status**: **Ready** (Gap 5 résolu 2026-05-04 — protocole publié `production/qa/protocols/combat-feel-interview.md`. Reste : Martin recrute panel ≥ 5 testeurs naïfs × 3 sessions pour produire evidence ADVISORY.)
> **Layer**: Feature
> **Type**: Visual/Feel
> **Manifest Version**: 2026-04-23

> **UNBLOCKED 2026-05-04** : Gap 5 résolu — protocole d'entretien playtest publié à `production/qa/protocols/combat-feel-interview.md`. Le doc contient : 15 questions structurées en 5 axes (description spontanée → kill mouvement vs statique → slow-mo perception → Likert r6 REC-02 → open-ended), listes lexicales canoniques (IN-FLOW rythmique × 6, VIDE-OU-MANQUE × 8, MOTS BANNIS × 7), procédure codage verbatim, critères pass/fail quantifiés par AC (AC-CMB-31 : ≥ 4 IN-FLOW distincts par testeur + ≥ 80% panel utilise ≥ 2 spontanément + 0 mot banni ; AC-CMB-32 : ≥ 80% décrit kill-mouvement contexte mouvement, 3 sessions distinctes ; AC-CMB-33 : ≥ 80% utilise ≥ 1 mot vide-ou-manque sur kill statique ; AC-CMB-34 : médiane Likert ≥ 4, ≥ 70% testeurs ≥ 4/5), template evidence doc, anti-références red flags creative-director. Pattern hérité `feel-movement-session.md` story-017 Pillar 1.
>
> **Reste à exécuter** (hors blocker — coordination Martin) : recruter panel ≥ 5 testeurs naïfs francophones natifs × 3 sessions distinctes (~5h coordination + ~2h codage post). Evidence livrée dans `production/qa/evidence/combat-feel-playtest-[YYYY-MM-DD]-session-N.md`. AC-CMB-31/32/33/34 fermés à 3 sessions PASS sur les 4 ACs, sign-off qa-lead + creative-director.

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: AC-CMB-31/32/33/34 (Visual/Feel ADVISORY playtest signoff)

**ADR Governing Implementation**: aucun ADR architectural — relève du Player Fantasy + design feel
**ADR Decision Summary**: les 4 ACs Visual/Feel exigent un protocole d'entretien playtest reproductible. Mots bannis (combat-classique + Fantasy B récompense isolée) liste unifiée AC-CMB-31 r6 REC-01 = `combo, finisher, engagement, affrontement, satisfaisant, récompense, impressionnant`. Mots de codage "in-flow rythmique" = `beat, tempo, staccato, traverser, enchaîner, cadence`. Mots de codage "vide-ou-manque" hors-flow = `plat, vide, sans intérêt, basique, ça passe, mécanique, bof, ok quoi`. Likert item r6 REC-02 reformulé "Le ralenti m'a semblé faire partie du rythme de jeu, pas une pause séparée" (Fantasy A perception, pas Fantasy B récompense).

**Engine**: Godot 4.6 | **Risk**: LOW (humain qualitatif, pas code)
**Engine Notes**: aucun engine-spec impliqué.

**Control Manifest Rules (Feature layer)**:
- Required: panel ≥ 5 testeurs ; ≥ 80% accord pour ACs ADVISORY
- Forbidden: pas de test automatisé pour Visual/Feel — playtest manuel uniquement
- Guardrail: signoff QA Lead par evidence doc daté

---

## Acceptance Criteria

*From GDD AC-CMB-31/32/33/34 + Gap 5 :*

- [ ] **Gap 5 résolu** : `production/qa/protocols/combat-feel-interview.md` créé par qa-lead — script entretien 10-15 questions, codage verbatims (in-flow vs out-of-flow), échelle Likert 3-item slow-mo, critères pass/fail quantifiés
- [ ] **AC-CMB-31** : 5 minutes session MVP avec ≥ 10 kills, panel ≥ 5 testeurs → ≥ 4 descripteurs distincts vocabulaire rythmique (`beat, tempo, staccato, traverser, enchaîner, cadence`) par tester ; ≥ 80% des testeurs utilisent spontanément ≥ 2 descripteurs rythmiques distincts ; **AUCUN** verbatim contient les 7 mots bannis. Evidence : `production/qa/evidence/combat-feel-playtest-[date].md` notes horodatées + codage intervieweur
- [ ] **AC-CMB-32** : kill pendant dash → playtester décrit dans contexte mouvement (ex : "j'ai traversé en même temps") et NON événement isolé. 3 sessions, 5 testeurs, ≥ 80% accord
- [ ] **AC-CMB-33** : kill hors-mouvement → playtester utilise spontanément ≥ 1 mot "vide-ou-manque" (`plat, vide, sans intérêt, basique, ça passe, mécanique, bof, ok quoi`). Evidence comparaison verbatim in-flow vs out-of-flow
- [ ] **AC-CMB-34** : Likert ≥ 4/5 obtenu par ≥ 70% testeurs panel ≥ 5, médiane ≥ 4 sur item r6 "Le ralenti m'a semblé faire partie du rythme de jeu, pas une pause séparée"

---

## Implementation Notes

*Derived from GDD §Acceptance Criteria Playtest/Feel + Gap 5 r1 :*

- **Pré-requis (qa-lead) — Gap 5** : créer `production/qa/protocols/combat-feel-interview.md` avec :
  1. Script entretien 10-15 questions ouvertes (e.g. "Décrivez votre dernier kill", "Quel mot vous vient pour décrire le ressenti du katana ?")
  2. Codage verbatims : tagger chaque mot rythmique vs "vide-ou-manque" vs banni
  3. Likert 3-item slow-mo : Fantasy A perception (item r6 REC-02), pas Fantasy B
  4. Critères pass/fail per AC : taux ≥ 80% panel etc.
  5. Section "Reproductibilité" : conditions de jeu standardisées (5 min, MVP build hash, niveau de référence)
- **Exécution playtest** :
  - 5+ testeurs minimum recrutés (mix profils : casual, FPS-experienced, speedrun)
  - Session 5 min in-flow (combat actif, kills réguliers) + section dédiée hors-flow (1 ennemi statique face joueur immobile pour AC-33)
  - Intervieweur = qa-lead ou délégué entraîné au protocole
  - Verbatims notés horodatés par testeur dans `production/qa/evidence/combat-feel-playtest-[date].md`
  - Codage post-session (intervieweur) : tagging mots rythmiques vs vide-ou-manque vs banni
  - Likert form séparé : 1 réponse / testeur, agrégation médiane + pourcentage
- Sign-off final : qa-lead signe le evidence doc avec verdict PASS/FAIL per AC

---

## Out of Scope

- Code Combat (livré stories 001-018)
- Audio playtest (story-020 BLOCKED Audio System)
- VFX decal cap (AC-CMB-42 BLOCKED VFX)

---

## QA Test Cases (Manual checks)

- **Manual check AC-CMB-31** : Vocabulaire rythmique
  - Setup: 5 min session MVP, ≥ 10 kills, panel ≥ 5 testeurs, intervieweur applique protocole Gap 5
  - Verify: codage verbatims — chaque tester a ≥ 2 mots rythmiques distincts ; ≥ 80% panel ; aucun mot banni
  - Pass condition: tous 3 critères vérifiés, evidence doc signée qa-lead

- **Manual check AC-CMB-32** : Kill pendant dash = syllabe mouvement
  - Setup: 3 sessions, 5 testeurs, kill explicitement déclenché pendant dash (briefing testeur "fais un dash et tue en même temps"), interview immediat
  - Verify: codage verbatims — kill décrit dans contexte mouvement (e.g. "j'ai traversé"), PAS isolé ("c'était un kill mémorable")
  - Pass condition: ≥ 80% testeurs accord (4/5)

- **Manual check AC-CMB-33** : Kill hors-flow = vide
  - Setup: kill statique (joueur immobile, ennemi face), interview comparée AC-32
  - Verify: codage verbatims — ≥ 1 mot "vide-ou-manque" présent
  - Pass condition: ≥ 80% testeurs ; si `satisfaisant/récompense/impressionnant` apparaissent → flag Fantasy B (intervieweur demande contexte)

- **Manual check AC-CMB-34** : Slow-mo perception rythmique
  - Setup: questionnaire post-session, item Likert r6 "Le ralenti m'a semblé faire partie du rythme de jeu, pas une pause séparée"
  - Verify: ≥ 70% panel ≥ 4/5 ; médiane ≥ 4
  - Pass condition: deux critères ; evidence : `production/qa/evidence/combat-slomo-feel-[date].md` + signature QA Lead

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**:
- `production/qa/protocols/combat-feel-interview.md` (créé par qa-lead — Gap 5 résolu)
- `production/qa/evidence/combat-feel-playtest-[date].md` (notes horodatées + codage)
- `production/qa/evidence/combat-slomo-feel-[date].md` (Likert questionnaire) + signature QA Lead

**Status**: [ ] Not yet created (BLOCKED Gap 5)

---

## Dependencies

- Depends on: Stories 001-018 (Combat code livré + jouable), **Gap 5 résolu** (qa-lead protocole)
- Unlocks: gate-check pre-production playtest sign-off
