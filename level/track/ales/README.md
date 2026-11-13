# Circuit de vitesse — Pôle Mécanique Alès Cévennes

Données de référence pour modéliser le circuit dans le jeu.
Le dossier contient un `.gdignore` : Godot n'importe pas ces fichiers.

## Fichiers

| Fichier | Contenu |
|---|---|
| `ales_circuit_osm.csv` | Points du tracé (OpenStreetMap) : `way_id, idx, node_id, lat, lon, x_east_m, y_north_m, cum_m`. Origine locale 44.1569 N, 4.0720 E ; x vers l'est, y vers le nord, en mètres. Way principal **196899326** : idx 0 en bas de la ligne droite, ordre = sens horaire. Les autres `way_id` sont les raccords (variantes / voie des stands). |
| `ales_osm_track.png` | Rendu du tracé (rouge), raccords (bleu), bacs à graviers (beige), bâtiments. Nord en haut, grille 50 m. |
| `ales_plan_officiel.png` | Plan officiel avec les noms de virages — **pivoté : nord à gauche**. |

## Chiffres clés

C = confirmé par une source, D = déduit (calcul OSM / IGN, lecture du plan).

| Donnée | Valeur | |
|---|---|---|
| Longueur homologuée | 2520 m (OSM : 2498 m) | C / D |
| Tracé technique / rapide | 2,5 km / 2 km (variante rapide non identifiée) | C |
| Boucles indépendantes | nord 1040 m, sud 1379 m | C |
| Largeur | 13 m (ligne droite des stands : 14 m) | C |
| Ligne droite des stands | 380 m (« ligne d'accélération » 600 m) | C |
| Emprise | ~240 m (E-O) × 805 m (N-S), ligne droite à l'ouest | D |
| Dénivelé | ~32 m : bas au sud (~189 m), haut au nord (~221 m) | D |
| Sens | réversible (horaire et antihoraire) | C |
| Virages nommés | La Parabolique (épingle nord), L'Épingle (sud-est), Mutuelle des Motards (épingle sud, bosse) | C (noms) / D (positions) |
| Départ / arrivée | côté ouest, moitié sud de la ligne droite — OSM node 10264875195 (44.1550768 N, 4.0714602 E) | C |
| Revêtement | enrobé 0/10, bitume élastomère | C |
| Stands / paddock | 20 stands, paddock 15 000 m², à l'ouest de la ligne droite | C |

À l'échelle du jeu (34 px/m) : ~8 200 × 27 400 px, piste ~440 px de large.

Non trouvés : origine du nom « virage à Tom » (probablement un surnom local de
La Parabolique), emplacement d'une tribune (le site officiel parle de 2 terrasses).

## Sources

- Page officielle : https://www.pole-mecanique.fr/nos-circuits/circuit-vitesse/
- Plan officiel (PDF, 2018) : https://www.pole-mecanique.fr/wp-content/uploads/2019/07/Piste-Vitesse-Pôle-Mécanique-Alès-Cévennes.pdf
- OpenStreetMap, way 196899326 : https://www.openstreetmap.org/way/196899326
- Altimétrie IGN (RGE ALTI) : https://data.geopf.fr/altimetrie/

Données du tracé © les contributeurs d'OpenStreetMap, sous licence ODbL
(https://www.openstreetmap.org/copyright) : l'attribution est obligatoire si
elles sont utilisées dans le jeu.
