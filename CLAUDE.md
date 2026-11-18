# CLAUDE.md — Micro Racer

Jeu de course vue de dessus, Godot 4.7, GDScript. Code, commentaires et
textes du jeu en français (avec les accents).

Skill de référence pour les patrons Godot : `.claude/skills/godot-gdscript-patterns`.

## Organisation

| Dossier | Contenu |
|---|---|
| `level/map/` | **Cartes** : décor et physique d'un lieu (tuiles, obstacles, eau). Aucune logique de course. Aujourd'hui : Brissac. |
| `level/track/` | **Circuits** : intègrent une carte (nœud nommé d'après le lieu, ex. « Brissac ») et portent leur logique : `Sections`, `SpawnPoints`, `PitStop` (zones d'arrêt), `PitLane` (vitesse limitée), `RaceStartLightsMap`, `RacingLine` (facultatif). Catalogue : `TrackCatalog.gd`. |
| `level/script/` | Course : `RaceController`, `TrackProgress` (parcours A*), stand (`PitStopManager`, `PitStop`, `PitLane`), élimination, fantômes. |
| `level/script/ai/` | IA : `AIDriver` (pilote), `RacingLine` (trajectoire), `AIPitStrategy` (pneus), `AILearning` + `ai_learning.json` (virages appris, livré). |
| `perso/car/` | Voiture (`Car.gd`) et définitions (`definition/*.tres`). |
| `ui/` | Menus. Parcours de course : Mode (`RaceModeSelect`) → Joueurs (`CarSelection`) → IA (`AISetup`, classique et élimination) → Circuit (`RaceSetup`) → Course. |
| `tools/track/` | Générateurs lancés sans fenêtre (variantes de Brissac, élargissement des portes, séparation carte / circuit, aperçus). |

## Règles

- **Une carte = un lieu, un circuit = un tracé.** Plusieurs circuits
  partagent une carte ; ne jamais intégrer un circuit dans un autre (les
  sections et le stand seraient en double). Nouveau circuit : nouvelle
  scène dans `level/track/` qui instancie la carte, plus sa logique.
- Portes (`Sections`) : elles se franchissent dans le sens de la course,
  donné par le `RespawnPoint` de chaque section. Une porte posée dans
  une trouée de mur impose de passer par cette trouée.
- Passages hors piste : le parcours de l'IA peut traverser l'herbe ou le
  gravier quand le tracé l'impose (coût élevé), jamais l'eau. Le
  balisage posé à la racine d'un circuit (couche `Pneu_sac`...) est
  épaissi pour former des barrières continues ; la voie `PitLane` est
  évitée par le tracé de course.
- Le code trouve les nœuds de logique à la racine du circuit
  (`get_node("Sections")`, `"PitStop"`, `"PitLane"`, `"SpawnPoints"`) et la
  carte par `find_child("Map")`.
- Typage statique partout ; une variable statique se règle par une
  fonction statique.
- Réutiliser l'existant (`TrackProgress`, `RaceConfig`, `MenuFocusManager`,
  `NavigationManager`) plutôt que dupliquer.

## Lancer et tester

```bash
godot --headless --path . --import          # après l'ajout d'un class_name (registre des classes)
godot --headless --fixed-fps 60 --path . -s <script.gd> -- <args>   # essais sans fenêtre
```

- Un script d'essai charge les classes du projet par `load()` (pas par
  `class_name`, inconnu à la compilation du script).
- Sans fenêtre, les sons d'explosion ne finissent jamais : appeler
  `car._on_audio_finished()` pour que la réapparition ait lieu.
- Un essai d'IA règle `AILearning.save_path = ""` : il ne doit jamais
  écrire dans les données du joueur.
- L'import peut réécrire des `.tscn` (uid ajoutés) : ne committer que ce
  qui a été modifié volontairement.

## Données du joueur

`user://` = `~/.local/share/godot/app_userdata/Micro Racer/` :
`best_times.json` (chronos), `ghosts/` (fantômes), `profile.cfg`
(profil, commandes, réglages), `ai_learning.json` (virages appris en jeu).
Ne jamais les supprimer ni les modifier sans demande explicite.

## Git

- `develop` : branche d'intégration. Une sous-branche par sujet, partie
  de `develop` (`feature/*`, `fix/*`, `refacto/*`), fusionnée au fur et
  à mesure puis supprimée.
- Ne jamais pousser sans demande.
- Ne jamais committer les fichiers d'export locaux : `export_presets.cfg`,
  `Micro Racer.pck`, `Micro Racer.sh`, `Micro Racer.x86_64`.
