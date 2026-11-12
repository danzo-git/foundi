# Déploiement du nom de compte imposé sur les demandes publiques

Déploiement autorisé et terminé le 12 novembre 2026 sur `foundi-7c837`, région `europe-west1`, codebase `auth`.

Contrôle final : **14:20:34 Europe/Paris**, soit `2026-11-12T13:20:34.418Z`.

| Fonction | État | Révision active |
| --- | --- | --- |
| `publishRequest` | ACTIVE | `publishrequest-00008-daf` |
| `manageRequest` | ACTIVE | `managerequest-00010-kuw` |

La création et la modification des demandes publiques utilisent désormais le nom du compte, dérivé du profil utilisateur ou d’un nom Auth exploitable. Le nom envoyé par une ancienne application dans `authorPublicName` est ignoré. Le formulaire Flutter corrigé ne transmet plus de nom éditable. Le comportement complet, les limites et les captures sont décrits dans [le compte rendu d’implémentation](demandes-identite-compte.md).

Les hooks de prédéploiement ont exécuté les **131 tests serveur avec succès**, puis les vérifications syntaxiques. Aucun code métier n’a été modifié pendant le déploiement.

Le contrôle final confirme :

- seules les deux fonctions autorisées ont changé de révision ; les 58 autres sont inchangées et aucune fonction n’a été créée ou supprimée ;
- leurs comptes de service sont identiques à ceux d’avant le déploiement ;
- les deux adresses Firebase utilisées par les clients refusent un appel anonyme avec **HTTP 401 / UNAUTHENTICATED** ;
- la version des règles Firestore et les 23 index sont inchangés, avec l’index `directRequests` toujours `READY` ;
- les paramètres de livraison des notifications sont conservés.

Les contrôles en production sont des lectures de configuration et des appels anonymes refusés : ils ne créent pas de demande réelle et n’envoient aucune notification. Les tests métier authentifiés, dont les tentatives de nom falsifié et la correction d’un ancien alias, ont été validés localement et dans Firestore en émulateur avant le déploiement. Aucune réécriture massive d’anciens documents n’a été exécutée.

Les preuves sont conservées dans `.dart_tool/account-name-deploy-before.json`, `.dart_tool/account-name-deploy-after.json` et `.dart_tool/account-name-deploy-functions.log`. Le contrôle se reproduit en lecture seule avec `node functions/scripts/verify-direct-requests-deploy.cjs --account-name --before .dart_tool/account-name-deploy-before.json --output .dart_tool/account-name-deploy-after.json`.

**Aucun APK n’a été généré ou distribué.** Aucun déploiement Hosting, changement de règles Firestore ou Storage, ni déploiement d’index n’a été réalisé.
