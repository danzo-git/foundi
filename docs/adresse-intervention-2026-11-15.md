# Adresse d’intervention choisie — 15 novembre 2026

## Comportement livré localement

Le bouton « Utiliser ma position actuelle » recherche une adresse (numéro et rue lorsqu’ils sont disponibles, quartier, code postal, ville, pays) via les services du téléphone, en France et en Côte d’Ivoire. Il présente une feuille de confirmation modifiable avec la précision estimée. Une rue ou un numéro absent n’est pas inventé. La recherche ne publie rien et ne modifie pas le formulaire avant confirmation.

L’auteur peut aussi saisir une adresse sans autoriser le GPS, corriger la proposition, annuler ou retirer le champ. L’adresse d’intervention est facultative. Avant confirmation, le formulaire annonce explicitement qu’une demande publique affiche cette adresse sur ses cartes et son détail, même sans compte Foundi. La prévisualisation montre la même adresse avant la publication finale. Une demande directe affiche un texte distinct et conserve les droits privés du client et du destinataire professionnel approuvé.

Les cartes d’Explorer, les opportunités, Mes demandes et le détail utilisent le même champ. Les demandes historiques sans adresse restent inchangées. Une modification depuis un ancien client qui omet le champ conserve l’adresse ; un `null` explicite la retire. La suppression de la demande retire le champ des documents publics, directs et du miroir personnel. Aucun remplissage automatique des anciennes demandes ni migration de production n’a été effectué.

Les zones de diffusion restent distinctes du lieu précis : une à trois zones du catalogue. Cette évolution ne crée aucune commune supplémentaire. La France reste limitée à Rennes dans le catalogue déployé ; une adresse reconnue dans une autre ville française ne vaut pas activation de cette ville. Au moins une zone sélectionnée doit avoir le même pays que l’adresse confirmée.

## Données et compatibilité

- Entrée des fonctions : `request.interventionAddress = {line, countryCode, confirmed: true}` ; `line` de 5 à 500 caractères, pays `CI` ou `FR`. Champs supplémentaires, absence de confirmation et valeurs invalides sont refusés. Le serveur normalise les espaces et retire les caractères de contrôle.
- Valeur enregistrée : `{line, countryCode}` dans la demande publique `requests/{id}` ou la demande privée `directRequests/{id}`, et dans `userRequests/{uid}/items/{id}`. Ni coordonnées GPS, ni résultat natif brut, ni indicateur de confirmation ne sont enregistrés.
- Publication et adresse sont enregistrées dans une même transaction, avec les contrôles et quotas existants. Les réessais n’ajoutent pas de demande et vérifient l’adresse réellement enregistrée. L’empreinte d’une modification inclut l’adresse pour empêcher un réessai avec un contenu différent.
- L’adresse n’est pas recopiée dans les notifications ou les instantanés de conversation. Le retrait/restauration de modération conserve l’adresse canonique de la demande. Le parcours existant d’effacement du compte supprime les demandes et nettoie les instantanés associés.
- `getRequestAddressCapabilities` exige un compte actif et vérifié. Le nouveau client contrôle cette capacité avant une mutation explicite d’adresse, puis exige l’accusé de sauvegarde `interventionAddressSaved`. Un backend ancien ne peut donc pas ignorer silencieusement une adresse nouvellement confirmée.
- Aucun nouvel index, règle Firestore, secret, fournisseur de géocodage serveur ou tâche planifiée n’est nécessaire pour cette évolution.

## Validation

Les journaux de cette session sont conservés dans `.dart_tool/address-*.log` :

- Suite backend : 221 tests réussis. Après les derniers ajustements de validation et des textes locaux, 11 tests ciblés supplémentaires ont été relancés avec succès.
- Suite Flutter complète : 221 tests réussis. Après ajout du cas de coordonnées invalides et mise à jour des captures, les 20 tests ciblés de localisation/adresse ont été relancés avec succès.
- `flutter analyze --no-pub` : aucun problème signalé.
- `npm --prefix functions run check`, syntaxe des nouveaux fichiers et contrôle des pages locales : réussis.
- Firebase : deux scénarios d’intégration réussis, publication publique/directe et effacement du compte. Les essais ont confirmé le refus des écritures SDK, l’absence d’accès tiers à une demande directe, les réessais, la correction et le retrait de l’adresse, ainsi que le nettoyage de l’adresse et des instantanés lors de l’effacement. Les tests emploient exclusivement le projet local `demo-foundi`, avec les vrais transports callable, les règles Firestore et les émulateurs Auth/Firestore/Storage.

L’arrêt des émulateurs affiche un avertissement Java du moteur de règles après la réussite des tests ; la commande a terminé avec le code 0. Le fichier d’environnement local a été restauré par le lanceur et sa sauvegarde temporaire supprimée.

Les captures sont issues des widgets réels avec le thème Foundi et des données de recette fictives. Elles ne constituent pas une acquisition GPS réelle sur téléphone :

- [Confirmation GPS modifiable](sprint-2-5-captures/adresse-gps-confirmation.png)
- [Carte publique avec l’adresse](sprint-2-5-captures/adresse-carte-publique.png)
- [Détail de demande](sprint-2-5-captures/adresse-detail-demande.png)
- [Aperçu avant publication](sprint-2-5-captures/adresse-apercu-publication.png)

La disponibilité et l’exactitude du géocodeur dépendent du téléphone, de ses autorisations, de la couverture et des données géographiques. La reconnaissance du numéro/rue reste à vérifier sur un téléphone réel en France et en Côte d’Ivoire. Les textes locaux non publiés de confidentialité et des CGU ont été actualisés ; aucun texte juridique publié n’a été modifié.

## Mise en service

Les six fonctions ont été déployées après autorisation explicite et vérifiées actives le 15 novembre 2026 à 20 h 55, heure de Paris. Le [compte rendu du déploiement](deploiement-adresses-2026-11-15.md) contient les révisions et les vérifications distantes. Aucun APK n’a été distribué.

Les cinq fonctions `publishRequest`, `publishDirectRequest`, `manageRequest`, `listOpportunities`, `decideSafetyReport` ont été mises à jour en premier, puis `getRequestAddressCapabilities` a ouvert la capacité une fois tous les chemins serveur disponibles. La mise à disposition de la nouvelle application reste soumise à autorisation. Les fonctions de notification, le catalogue CI/Rennes et les tâches de suppression n’ont pas été redéployés pour ce champ.
