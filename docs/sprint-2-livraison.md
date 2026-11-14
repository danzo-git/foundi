# Sprint 2 — livraison locale à valider

> Mise à jour du 14 novembre 2026 : le backend de suppression a depuis été déployé et activé. Voir [l’état d’activation et les vérifications](activation-suppression-2026-11-14.md). Le texte ci-dessous décrit la livraison initiale ; les pages Web et nouveaux textes juridiques restent non publiés.

Branche : `codex/foundi-sprint-2-confidentialite-suppression`, issue du dernier état du Sprint 1 (`f17cb54`). Les fonctions existantes jusqu’au volet Professionnels et la modération sont conservées. Aucun nouveau texte n’est publié, aucun déploiement n’est effectué, aucun APK n’est produit et aucun compte réel n’est supprimé. Le Sprint 2 reste local, sans push.

## Implémentation livrée

La suppression demande une confirmation et une identité récente par mot de passe ou Google. Le serveur utilise uniquement l’UID authentifié. Un marqueur de fermeture interdit immédiatement les opérations et les contacts, y compris avec les anciens jetons ; le retrait et la purge se poursuivent par étapes paginées et reprenables. Les fichiers sont réellement supprimés avec contrôle de propriété et de génération. Auth est supprimé après vérification des données actives. Une interruption ne produit pas un faux état « terminé ».

Le suivi utilise un code opaque conservé localement et reste consultable après déconnexion. Il distingue la reprise automatique et la revue nécessaire. Un suivi indisponible peut être fermé localement après confirmation sans annuler la demande ni affirmer que le serveur a terminé. Le nettoyage du cache au redémarrage reste prévu même après cette fermeture locale.

Les messages et fichiers du membre supprimé sont effacés ; les contenus rédigés par l’autre membre sont préservés avec identité neutralisée et conversation en lecture seule. Les mesures de modération visant un autre membre restent actives et réversibles depuis un dossier technique sans identité du déclarant effacé. Les éventuelles preuves conservées ont une échéance explicite, y compris chaque fragment d’un PDF. Les archives et dossiers restent inaccessibles aux clients ; l’Admin utilise des API avec vérification du rôle courant, journalisation et motif de reprise.

Les paramètres séparent la lecture des CGU et de la politique de confidentialité de leur acceptation. Les anciennes références ne sont pas réécrites ni antidatées ; les nouvelles acceptations sont immuables. Les projets Web et le payload pour l’application sont générés depuis les mêmes sources et la même version. Le parcours Web prépare une demande sans réinstallation, une vérification du titulaire et un suivi sans session, avec un runtime désactivé par défaut.

## Dossier à examiner

- [Résultats des tests, captures et limites de validation](sprint-2-tests-resultats.md)
- [Audit initial des données](sprint-2-audit-initial.md) et [matrice finale / préparation des stores](sprint-2-matrice-et-stores.md)
- [Projet de CGU](legal/sprint-2/cgu-v1-projet.md) et [projet de politique de confidentialité](legal/sprint-2/confidentialite-v1-projet.md)
- [Décisions de l’éditeur et conservation](sprint-2-decisions-et-conservation.md)
- [Plan de déploiement et d’exploitation à valider](sprint-2-deploiement-a-valider.md)
- [Liste des fichiers modifiés et créés](sprint-2-fichiers.md)

## Points restant à approuver avant activation

Compléter la dénomination et l’immatriculation de la SARL ainsi que la ville, le code postal et le pays de l’adresse communiquée. Valider les textes pour la Côte d’Ivoire et la France, les bases et transferts, les durées, la conservation des justificatifs et preuves, les conditions d’accès des mineurs, les droits et recours. Choisir et autoriser le domaine public, vérifier les contrats et traitements des fournisseurs et la protection Auth contre l’énumération des e-mails.

`config/privacy-policy.draft.json` reste non approuvé et inactif, les durées restent `null`, `ACCOUNT_DELETION_ENABLED` vaut `false` par défaut et le payload juridique a `published:false`. Le contrôle `node scripts/validate-privacy-release.cjs` refuse donc actuellement la publication, comme prévu. Ces décisions peuvent être examinées sans autoriser une mise en production.

La recette OAuth Google réelle sur compte fictif de préproduction, les caches sur appareils cibles, les IAM, les index/TTL distants et le domaine HTTPS font partie du plan de déploiement. Les tests locaux ne sont ni une certification juridique ni une validation automatique des stores.
