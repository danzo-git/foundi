# Complément : profils et professionnels ayant répondu

Ces corrections complètent le premier passage du Sprint 2.6. Elles restent locales jusqu’à un déploiement autorisé. Les interfaces des fonctions et les limites d’instances, de mémoire et de quotas sont inchangées.

## Causes corrigées

- `listRequestRespondents` vérifiait jusqu’à 20 professionnels l’un après l’autre. Les trois lectures de sécurité d’un professionnel étaient déjà parallèles, mais le professionnel suivant attendait la fin du précédent. Quatre validations sont maintenant traitées à la fois. Le résultat conserve l’ordre de la requête ; la demande publique est toujours relue avant retour. Une erreur ne renvoie pas une page partielle.
- Le contexte des profils publics lit maintenant seulement les champs nécessaires du dossier professionnel, avec le `fieldMask` déjà utilisé par l’annuaire. Le lookup Auth peut chevaucher le chargement des métadonnées ; les restrictions sont ensuite vérifiées, y compris dans le contexte final après lecture des photos. Aucune décision n’est conservée entre les appels.
- Le profil de l’auteur regroupe les lectures indépendantes et les requêtes dupliquées d’une même phase de vérification. Chaque contexte initial/final possède son propre lecteur. L’import/résolution d’identité reste terminé avant lecture du profil professionnel, afin de ne pas récupérer un portrait précédent pendant l’import.
- La lecture du profil d’un répondant conserve sa transaction, la vérification de la proposition, l’approbation, l’état Auth et les restrictions. L’appel Auth chevauche les documents indépendants ; les restrictions sont vérifiées après cette phase.

La liste des répondants n’incluait déjà pas les photos : sa requête sélectionne uniquement les identifiants professionnels, puis un masque de champs du dossier. La sérialisation des vérifications expliquait donc une partie concrète de sa latence, sans qu’un cache des profils privés soit nécessaire.

## Mesures contrôlées

Source avant : commit `b8546e888d1f2ff7c057a03db0895d78ce461d50`. Source après : fichiers locaux, SHA-256 dans le JSON. 21 mesures par version dont la première isolée ; médiane et p95 sur les 20 suivantes. Les versions sont exécutées successivement dans un ordre alterné, avec des dépôts mémoire et 3 ms de délai demandé par opération. Les timers Windows et la charge de la machine influencent leur durée réelle.

| Service / scénario fictif | Médiane avant → après | p95 avant → après | Lectures du faux store |
|---|---:|---:|---:|
| Page de 20 répondants | 388,3 → 150,3 ms | 406,1 → 167,4 ms | 104 → 104 |
| Profil public professionnel | 130,9 → 96,3 ms | 133,8 → 100,0 ms | 11 → 11 |
| Auteur professionnel | 266,4 → 183,6 ms | 283,3 → 200,0 ms | 26 → 22 |

Les octets de documents synthétiques retournés au backend passent de 2 769 à 683 pour le profil public dans ce jeu de données, qui contient volontairement un champ interne supplémentaire de 1 Kio pour exercer le masque de champs. **Ce ne sont ni les octets HTTP au téléphone, ni un volume Firestore mesuré.** La réponse publique du profil, photos comprises, reste identique. Les coûts d’agrégation, des contrôles de quotas, du protocole et des requêtes internes aux services délégués ne sont pas modélisés comme des lectures facturées. En particulier, le scénario auteur simule l’appel aux services d’avatars et d’annuaire par une opération chacun ; les lectures de ces services ne sont pas comprises dans son compteur.

Les pics simultanés des lectures de restrictions de répondants passent de 3 à 12 : quatre professionnels, chacun avec trois documents de sécurité. Le volume total du test est inchangé ; le gain vient du chevauchement des attentes. Aucune mesure de cold start, de réseau réel ni de facturation en production n’est déduite de ces résultats.

Résultats bruts : `backend-loading-comparison.json`. Reproduction depuis la racine :

```powershell
node tool/performance/backend-loading-benchmark.cjs
node --test --test-concurrency=1 functions/test/backend-loading.test.js functions/test/request-author.test.js functions/test/professional-directory.test.js
```

Les 31 tests ciblés passent, dont 8 nouveaux cas : parallélisme borné, ordre conservé malgré une réponse retardée, pagination, masques de champs, comptes désactivés, suspension/suppression/masquage, retrait de demande pendant la lecture, erreur sans page partielle, restrictions apparues pendant Auth et import d’identité avant lecture du portrait. Le runner Emulator des interactions, auteurs et profils publics reste pertinent pour la validation globale.

## Limites restantes

Les profils complets contiennent encore leurs photos base64 ; leur téléchargement peut dominer le temps sur une connexion lente. Un chargement des photos séparé du texte demanderait une évolution coordonnée du protocole et des écrans ; ce complément conserve le contrat actuel. La pagination des répondants utilise encore un offset et une agrégation de comptage. Enfin, le profil auteur pro consomme toujours les deux charges de quota existantes (auteur, puis annuaire interne) : elles n’ont pas été désactivées pour accélérer le parcours.

Fonctions à mettre à jour après autorisation pour activer ces corrections serveur : `listRequestRespondents`, `readRequestRespondentProfile`, `readRequestAuthorProfile`, `readPublicProfessionalProfile` et `readPublicProfessionalMedia`. Les parcours de recherche et de validation de l’annuaire ne changent pas leur logique, bien qu’ils partagent le même module.
