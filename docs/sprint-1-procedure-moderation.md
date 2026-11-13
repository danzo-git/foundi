# Procédure humaine proposée — Foundi V1

Cette procédure doit être attribuée à des personnes et validée avant distribution. Les objectifs ci-dessous sont internes ; l’application ne promet aucun délai garanti. Foundi n’est pas un service d’urgence.

## Triage et protection des personnes

- Le responsable consulte les Nouveaux au début et à la fin de chaque journée ouvrée, avec un remplaçant identifié. Objectif interne proposé : prise en charge sous un jour ouvré, revue initiale sous deux jours ouvrés. Ces objectifs exigent une organisation réelle avant activation publique.
- Les signalements fraude/menaces sont visuellement prioritaires ; examiner également immédiatement toute mention de danger imminent, atteinte aux mineurs ou divulgation de données privées, quel que soit le motif choisi. En cas de danger immédiat, orienter vers les services d’urgence locaux et suivre les obligations applicables avec un responsable habilité.
- Prendre en charge un dossier, vérifier la cible réelle et les preuves minimales privées, comparer aux règles d’utilisation. Ne jamais demander le mot de passe ni des justificatifs professionnels sans nécessité et hors de cette procédure.
- Le signalant n’est jamais nommé au compte signalé, ni dans un avertissement ni dans une notification. Ne pas exporter une capture Admin contenant son identité pour contacter la personne visée. Limiter les accès administrateurs et réexaminer leurs claims.
- Un signalement unique n’entraîne aucune sanction automatique. Le classement sans suite ne modifie aucun droit. Consigner le raisonnement, y compris les limites des preuves et les doublons.

## Décisions

- **Commencer l’examen** (ancien « Prendre en charge ») : attribue le suivi à l’administrateur et passe En cours d’examen ; révision et audit conservés. Aucune sanction et aucune notification. Ce suivi n’est pas un verrou exclusif empêchant un autre administrateur de décider.
- **Classer sans suite** : absence de violation établie, explication obligatoire ; aucune pénalité.
- **Masquer** : demande publique ou profil seulement. Préserver le cycle métier ; vérifier le retrait par lecture serveur. La preuve reste privée. Les messages historiques ne sont pas supprimés par cette action.
- **Avertir / masquer / suspendre / restaurer** : avis privé, notification dans la cloche et push selon les préférences/appareils du compte concerné. Aucun signalant ou texte privé de preuve dans ces communications. La justification détaillée reste dans l’audit admin. Voir le [correctif des notifications](sprint-1-notifications-moderation.md) pour le périmètre des clients installés et le cas des comptes suspendus.
- **Suspendre** : mesure applicative au compte entier, distincte du statut professionnel ; se référer au plan de déploiement pour les effets Auth et les sessions. Ne pas sanctionner un administrateur via cette UI : procédure d’habilitation séparée.
- **Restaurer** : après examen/contestation, depuis le dossier de la mesure actuellement en vigueur. Justification et audit nouveaux. Ne jamais bricoler les états depuis le navigateur ou effacer une proposition.
- En cas de révision concurrente, actualiser et relire avant de confirmer. Ne pas répéter avec une révision arbitrairement modifiée. Les réessais d’une même décision conservent leur identifiant.

## Contestations et assistance

Contact validé par le propriétaire : **kouamedenzel09@gmail.com**. Le lien figure dans Paramètres → Aide / Signaler un problème. L’aide distingue les problèmes techniques et contestations des signalements ciblés. Aucun e-mail n’est envoyé automatiquement par ce sprint.

Demander uniquement une référence de compte/décision nécessaire au traitement, jamais un mot de passe. Un autre administrateur examine une contestation quand l’équipe le permet. Conserver la décision initiale et ajouter une restauration motivée si elle est justifiée ; ne pas exposer la plainte initiale à la personne sanctionnée.

## Preuves et conservation proposées

- Les textes et références utiles sont figés dans un dossier privé. Les images sont réduites à des miniatures privées bornées (8 au plus pour un profil, 3 pour une demande, 1 pour un message). Ce sont des preuves visuelles, pas une classification automatique. Un échec média laisse une mention explicite et les références ; il n’empêche pas le dépôt de plainte.
- Un PDF/pièce jointe historique peut être consulté par un admin courant via l’API HTTP liée au **signalement**, à sa référence serveur et à sa génération de fichier. Aucun chemin libre, URL permanente ou jeton Storage n’est exposé. Une pièce supprimée n’est pas recréée ; l’Admin affiche une erreur explicite si la preuve n’est plus disponible.
- Purge serveur proposée des commentaires et preuves copiées après **90 jours**, y compris miniatures ; la consultation d’un fichier de preuve est refusée après ce délai. Le job quotidien traite au plus 100 dossiers par exécution ; surveiller ce débit et l’augmenter/adapter avant une charge qui le dépasserait. Le job de purge est testé comme service ; son déclenchement Scheduler doit être vérifié en recette.
- Métadonnées et audit : TTL technique proposé à **365 jours après la création/dernière décision**, sauf mesure active. Les dossiers et audits portant une mesure active ont un maintien de conservation pour garder la restauration possible. Après restauration, le dossier retrouve un TTL ; le nettoyage supprime aussi l’ancienne entrée maintenue après expiration de la conservation d’archive. Vérifier le suivi humain des mesures actives et la proportionnalité de ce maintien.
- Les blocages restent jusqu’au déblocage ; les compteurs anti-spam conservent seulement le budget courant du compte. La suppression de compte, les demandes d’exercice des droits, les exceptions de conservation et les obligations de signalement légal devront être formalisées au Sprint 2.
- Aucun de ces choix techniques ne remplace la validation juridique des finalités, accès et durées. La diffusion sur store reste conditionnée à cette validation.

## Prévention réellement livrée

Les validations existantes et quotas V9.2 (60 secondes, 5 créations/24 h, 20/7 jours) restent appliqués. Les réessais de même identifiant sont idempotents. Un texte de publication comportant 80 caractères identiques consécutifs ou une répétition mécanique très longue du même mot est refusé au serveur avec explication. Il n’existe pas de liste opaque de mots interdits.

Ce contrôle ne reconnaît ni toutes les escroqueries, ni le harcèlement contextuel, ni les images illicites. Les signalements, le retrait public et la suspension humaine assurent le traitement après publication. Aucun fournisseur payant, antivirus supplémentaire ou analyseur automatique d’images n’a été activé.
