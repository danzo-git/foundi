# Sprint 2 — résultats et limites de validation

Branche locale : `codex/foundi-sprint-2-confidentialite-suppression`, base Sprint 1 `f17cb54`. Vérifications des 13–14 novembre 2026. Aucun déploiement Firebase, aucune publication juridique, aucun APK et aucune suppression de compte réel. Les comptes et fichiers supprimés pendant les tests appartiennent uniquement aux émulateurs `demo-foundi`.

## Résultats

| Vérification | Résultat | Trace locale complète |
| --- | --- | --- |
| `npm --prefix functions test` | 185 tests réussis, 0 échec | `.dart_tool/sprint2-node-delivery.log` |
| `npm --prefix functions run check` | Syntaxe serveur, règles-tests, intégration et scripts Web validée ; le module navigateur est contrôlé en mode ES module | `.dart_tool/sprint2-check-delivery.log` |
| `flutter test --no-pub --concurrency=1` | Suite complète : 188 tests réussis, 0 échec | `.dart_tool/sprint2-flutter-validation.log` |
| `flutter test --no-pub --concurrency=1` dans `admin` | 15 tests réussis, 0 échec | `.dart_tool/sprint2-admin-full.log` |
| Parcours Flutter final avec captures | 6 tests ciblés réussis : confirmation, échec d’identité, suivi, reprise, fermeture locale et lecture sans consentement | `.dart_tool/sprint2-flutter-delivery.log` |
| Capture Admin avec polices/thème réels | 1 test réussi, reprise impossible sans motif | `.dart_tool/sprint2-admin-capture-final.log` |
| `flutter analyze --no-pub` | Aucune anomalie | `.dart_tool/sprint2-analyze-validation.log` |
| Analyse ciblée des derniers ajustements du suivi/cache | Contrôle complémentaire après la suite générale | `.dart_tool/sprint2-analyze-delivery.log` |
| `npm --prefix functions run test:sprint2:emulators` | 39 tests de règles et 3 scénarios d’intégration réussis ensemble, 0 échec | `.dart_tool/sprint2-emulators-delivery.log` |
| `npm --prefix functions run test:moderation:emulators` | 39 tests de règles et 2 scénarios d’intégration réussis, 0 échec | `.dart_tool/sprint2-moderation-regression.log` |
| `node scripts/validate-privacy-release.cjs` | Refus attendu du passage : textes/identité, conservation, runtime anti-énumération et target public non validés | `.dart_tool/sprint2-release-gate.log` |
| `git diff --check` | Aucun défaut d’espace signalé | Contrôle local |

La suite complète Flutter précède le dernier ajout du bouton permettant de quitter un suivi indisponible sans annuler la demande serveur ; ce dernier est couvert par les tests ciblés finaux. Les nombres ne doivent pas être additionnés comme s’il s’agissait de tests tous distincts. Les premières exécutions ont permis de corriger un rafraîchissement asynchrone du suivi, d’adapter le test de navigation aux deux liens juridiques et de protéger un déclencheur de notification contre un snapshot supprimé. Les résultats retenus ci-dessus sont ceux des exécutions corrigées.

La recette combinée finale `npm --prefix functions run test:sprint2:emulators` réunit les **39 tests de règles et 3 scénarios d’intégration** sur le même état des émulateurs (`.dart_tool/sprint2-emulators-delivery.log`). Elle vérifie aussi qu’un ancien fichier sans preuve de propriétaire impose une revue, reste intact, puis que la reprise Admin justifiée permet de terminer après attribution démontrée dans la fixture. La preuve de propriétaire provient de la création contrôlée de la fixture, jamais d’une supposition du worker. Le chemin de l’objet à examiner reste privé à l’Admin ; le suivi du titulaire ne le divulgue pas.

[Relevé compact des sorties de validation](sprint-2-validation.txt).

## Ce que vérifie réellement l’émulateur

- Demande avec identité récente, UID authentifié uniquement, confirmation et schéma stricts ; refus d’un UID tiers ajouté au payload.
- Barrière immédiate contre un ancien jeton : accès aux données et tentative d’envoi de message refusés pendant la fermeture.
- Suivi avec secret opaque après désactivation/suppression Auth ; mauvais secret refusé, aucune identité du titulaire renvoyée.
- Retrait des projections publiques, effacement des arbres privés et des objets Storage réels, y compris des fichiers orphelins dans les espaces de propriété établis.
- Conservation des messages écrits par B et de ses propres fichiers ; messages de A neutralisés, conversation en lecture seule, proposition de B préservée avec client effacé.
- Mesure de suspension de B maintenue après effacement du déclarant A, nouveau dossier technique sans identité A et restauration toujours possible par un Admin courant.
- Copie privée d’une preuve PDF avant suppression du fichier source, découpage borné, empreinte et échéance TTL sur chaque fragment ; aucune archive Storage sans échéance.
- Demande possible pour un compte suspendu ; un conflit de génération d’objet interrompt le traitement, conserve le fichier et le compte Auth désactivé, et ne renvoie pas « terminé ».
- Voie Web sans application : authentification e-mail/mot de passe par l’API REST Firebase, soumission du protocole callable et suivi HTTP sans session.
- Références d’acceptation explicites immuables et copie fidèle d’une ancienne date ; création de fausse date, modification ou effacement client du journal refusés.

Le worker est désactivé par défaut. Les tests emploient une politique explicitement marquée comme fixture ; les durées d’un jour dans le scénario de preuve ne constituent pas une décision de conservation pour la production.

## Captures réelles du code rendu

Les PNG du dossier `sprint-2-captures` sont produits par les widgets Flutter exécutés, avec les thèmes Foundi/Admin et des polices lisibles, et par Chrome sans fenêtre sur les pages HTTP locales. Les données sont fictives. Ce sont des rendus du code livré, pas des maquettes générées. Aucun APK n’a été construit pour les obtenir.

- [Application : confirmation et réauthentification](sprint-2-captures/app-suppression-confirmation.png)
- [Application : identité refusée](sprint-2-captures/app-verification-refusee.png)
- [Application : traitement en cours](sprint-2-captures/app-suppression-en-cours.png)
- [Application : reprise après interruption](sprint-2-captures/app-suppression-reprise.png)
- [Application : suppression terminée](sprint-2-captures/app-suppression-terminee.png)
- [Application : suivi indisponible](sprint-2-captures/app-suivi-indisponible.png)
- [Application : consultation d’un texte sans nouvelle acceptation](sprint-2-captures/app-confidentialite-lecture.png)
- [Admin : file privée des suppressions](sprint-2-captures/admin-suppressions.png)
- [Web : demande sans réinstallation, largeur 520 px](sprint-2-captures/web-suppression-520.png)
- [Web : politique de confidentialité en prévisualisation](sprint-2-captures/web-confidentialite.png)

Le pilotage interactif du navigateur s’est arrêté faute d’identification fiable de l’URL Windows. Il n’a pas été utilisé pour supprimer un compte ni transmettre des identifiants. Les captures Web proviennent ensuite d’un rendu automatique séparé sur `127.0.0.1`, sans toucher aux onglets de l’utilisateur.

## Limites à prendre en compte avant production

Les émulateurs ne valident pas l’activation des index/TTL de production, les IAM distants, la durée effective des purges TTL, les copies fournisseur, un domaine HTTPS réel, les quotas/coûts ni la délivrabilité des e-mails et push réels. Leur arrêt peut afficher un avertissement Java du runtime de règles ; les résultats TAP et le code de sortie du runner sont contrôlés séparément. Le soft delete de sept jours provient d’une lecture de métadonnées de production, pas d’une simulation de suppression réelle.

La réauthentification Google native et Web est implémentée avec le SDK existant, une initialisation native unique et un contrôle serveur de l’identité récente. L’annulation et l’erreur sont testées par les interfaces ; aucun compte Google réel n’a été supprimé pour une recette OAuth. Un essai de bout en bout sur un compte fictif de préproduction et un domaine autorisé reste dans le plan de déploiement. Le nettoyage de cache Firestore et des fichiers PDF gérés doit également être vérifié sur les appareils cibles ; les copies choisies par un destinataire ou les sauvegardes OS ne sont pas promises effacées.

Les fichiers sans preuve de propriété, conflits de génération ou autres vérifications incomplètes doivent garder le dossier ouvert pour reprise/revue. Les anciennes limites d’annuaire condensées à partir d’une IP et d’un UID n’ont pas de relation inverse certaine : leur expiration technique et le TTL distant doivent être contrôlés. Les textes et choix juridiques ne sont pas certifiés ; ils sont soumis à validation de l’éditeur et à relecture compétente.
