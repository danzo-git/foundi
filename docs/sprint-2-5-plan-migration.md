# Sprint 2.5 — dépendances et migration

Branche : `codex/foundi-sprint-2-5-finitions`, issue du dernier état local `66839dc`. Aucune opération sur Firebase distant, les comptes réels, Hosting ou la distribution APK.

## Carte des dépendances avant implémentation

- Demande : composer → RequestDraft → request-service (catalogue, quotas, miroirs privés/publics) → Explorer, opportunités, propositions et notifications.
- Zones : catalogue Admin hiérarchique → sélection → `zoneIds/zoneLabels` ; lecture historique via `zoneId/zoneLabel`. Aucune extension parent/enfant.
- Classification : référence Admin réservée pour les besoins non classés ; service partagé de correspondance → opportunités et file notificationJobs → notifications déterministes → outbox/push existants.
- Photo personnelle : choix explicite Mon compte → normalisation serveur → stockage privé et projection publique minimale → résolution groupée des auteurs des cartes → révocation sans URL permanente → purge Sprint 2.
- Sécurité transversale : compte actif, lifecycle, blocages, modération, règles Firestore/Storage ; demandes directes strictement séparées et activité vérifiée inchangée.

## Migration prévue

Les nouvelles demandes écrivent les tableaux (1–3 zones) et les champs singuliers (première zone) pour les anciens clients. Les documents historiques restent lus sans écriture massive. Les filtres et opportunités interrogent séparément le schéma historique et le nouveau, avec affectation déterministe à une zone de pagination pour éviter les doublons. Les anciennes éditions doivent préserver les zones supplémentaires si le client ne sait pas les exprimer.

La catégorie non classée doit être créée/activée par une opération Admin explicite et stable. Elle ne constitue pas une activité professionnelle sélectionnable. Aucune référence n’est créée en production pendant ce sprint.

L’avatar n’utilise ni Google OAuth ni le portrait professionnel. Aucune image ni URL à jeton permanent dans les demandes. Le document utilisateur reste privé. L’absence, la révocation et les erreurs réseau donnent l’icône existante.

GPS différé : absence de géométries catalogue et de service approuvé de conversion coordonnées→zone. Aucun nouveau SDK de localisation, permission ou service externe ; la sélection manuelle reste pleinement utilisable.
