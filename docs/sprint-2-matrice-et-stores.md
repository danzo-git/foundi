# Inventaire final et préparation des déclarations stores

Cette matrice complète la carte des 39 supports de `sprint-2-audit-initial.md`. Les chemins exacts, producteurs, dépendances et purges constatées y sont détaillés. Les bases proposées ci-dessous ne sont pas adoptées : revue Côte d’Ivoire/France requise. Responsable annoncé pour toutes les lignes : l’éditeur, dont la dénomination sociale complète reste à confirmer ; exploitation par les intervenants autorisés, contrôlés par rôles et IAM.

| Groupe / supports réels | Finalité et base proposée à confirmer | Accès / destinataires | Lieu vérifié ou à vérifier | Durée et purge |
| --- | --- | --- | --- | --- |
| Auth : UID, e-mail, nom, fournisseurs et session | Compte, exécution du service ; sécurité, base distincte à examiner | Titulaire, Firebase Auth, backend habilité | Auth/Google : lieux et transferts à confirmer | Vie du compte ; désactivation/révocation puis suppression Auth après effacement actif |
| `users` : nom, téléphone, profession, mode | Profil et usages du service demandé | Propriétaire ; Admin habilité | Firestore `eur3` | Vie du compte ; arbre purgé, durées d’inactivité à décider |
| `legalAcceptances`, références du profil | Preuve de l’acceptation, obligations applicables à confirmer | Propriétaire ; backend | Firestore `eur3` | Registre immuable en activité, effacé avec le compte ; éventuelle conservation légale distincte à justifier avant tout ajout |
| `requests`, photos publiques | Publication demandée, information proportionnée sur la visibilité | Public sans compte, y compris nom du compte automatiquement publié | Firestore `eur3`, fichiers `EUROPE-WEST1` | Retrait au début du traitement, effacement avec le compte ; copies fournisseur séparées |
| `userRequests`, `directRequests`, ownership et décisions | Gestion de demandes privées ou propres | Auteur et destinataire autorisé, Admin selon rôle | Firestore `eur3` | Propres demandes effacées ; demandes de B à A refermées sans effacer le texte de B |
| `professionalProfiles`, vitrine et galerie | Présentation professionnelle et mise en relation | Vitrine publique ; dossier privé | Firestore `eur3` | Vitrine retirée puis arbre effacé ; durée des dossiers inactifs à définir |
| `professionalDocuments` et métadonnées | Vérification professionnelle, nécessité/base à confirmer selon les pièces | Titulaire et examinateurs habilités ; pas de publication | Fichiers `EUROPE-WEST1` | Effacement avec contrôle de propriété ; durée propre à chaque justificatif à adopter |
| `professionalAudit` | Traçabilité des décisions et contrôle des abus | Examinateurs habilités | Firestore `eur3` | Archives éventuelles bornées par la politique adoptée ; identités de l’Admin supprimé neutralisées |
| `proposals` | Réponses et négociation | Participants ; noms/compteurs de répondants dans certains écrans | Firestore `eur3` | Propositions de A effacées ; celles de B conservées avec client effacé et état indisponible |
| `conversations`, messages et pièces jointes | Échanges privés et partage volontaire | Participants ; preuve limitée dans un signalement autorisé | Firestore `eur3`, fichiers `EUROPE-WEST1` | Messages et fichiers propres effacés ; texte de B conservé, identité A neutralisée, conversation en lecture seule |
| Engagement, J’aime, recommandations | Interactions, intérêt et nécessité à examiner | Compteurs/relations selon écran ; backend | Firestore `eur3` | Relations de A retirées, agrégats corrigés ; données de B préservées |
| Notifications, états de lecture, jobs et outbox | Information d’activité et sécurité | Titulaire, backend ; FCM pour push | Firestore `eur3`, FCM/transport à confirmer | Propres données effacées ; notifications chez B neutralisées si contenu supprimé ; tokens retirés |
| Jetons d’appareil, préférences push | Livraison demandée et choix de confidentialité | Titulaire, backend, FCM | Appareil + Firebase/Google | Retrait au départ et dans la purge ; expiration fournisseur à documenter |
| OTP, e-mail, empreintes et budgets | Vérification d’identité, prévention des abus | Backend et relais SMTP, pas public | Firestore `eur3`, SMTP à confirmer | Code 10 min, traces d’échéance 24 h dans le code ; purge des défis/quotas liés ; budgets IP partagés non effacés aveuglément |
| Annuaire, curseurs et limites | Recherche et protection du service | Backend, résultats publics filtrés | Firestore `eur3` | Curseurs 10 min et budgets 24 h dans le code ; nouveaux marqueurs UID purgés ; anciens condensats IP+UID non réidentifiables depuis le seul UID, TTL à vérifier |
| `userBlocks`, `accountSafety`, `safetyContent` | Empêcher les contacts et contournements, sécurité | Serveur, propriétaire via API limitée | Firestore `eur3` | Blocages entrants/sortants retirés ; aucune levée de sanction B ; nouvelle barrière A de fermeture |
| Signalements, preuves, commentaires et `safetyAudit` | Examen, protection des personnes, justification des décisions | Modération habilitée ; déclarant confidentiel dans les avis | Firestore `eur3` ; preuve issue du média privé | Sprint 1 : 90/365 j à réexaminer ; effacement A : archives bornées selon choix explicite, mesure B poursuivie sans identité A |
| `accountDeletionJobs`, holds, audit et lifecycle | Exécuter et prouver la demande de droits | Serveur ; Admin via API privée ; suivi avec secret opaque | Firestore `eur3` | Échéances explicites requises ; archives TTL privées, UID du job retiré à la fin ; marqueur minimum technique 65 min |
| Cache Firestore, session, PDF temporaire, imagecache, reçu | Fonctionnement local, sécurité et suivi | Appareil / SDK | Appareil ; sauvegardes OS à vérifier | Déconnexion même si retrait push échoue, cacheimages vidé, fichiers PDF gérés nettoyés à changement d’identité ; cacheFirestore nettoyé au prochain démarrage avec reçu ; fichiers originaux choisis et copies du destinataire non supprimés |
| Journaux Cloud, SMTP, sauvegardes et télémétrie fournisseur | Exploitation/sécurité, nécessité/base à établir | Prestataires et exploitants limités | Lieux à confirmer service par service | Durées et accès à vérifier, pas de promesse de disparition instantanée ; soft delete GCS vérifié sept jours |

## Préparation Google Play Data Safety

Déclarations à confirmer dans la console, en cohérence avec la version effectivement distribuée et les pratiques des prestataires :

| Catégorie probable | Données / usage à déclarer ou vérifier | Points d’attention |
| --- | --- | --- |
| Informations personnelles | Nom, e-mail, téléphone optionnel, identifiant du compte et activité professionnelle | Distinguer champs obligatoires, facultatifs et automatiquement publics |
| Photos / vidéos | Photos de demandes, portrait/couverture/galerie, images de conversation | Pas de collecte permanente de photothèque ; sélection explicite ; vidéo non implémentée dans le périmètre audité |
| Fichiers et documents | Justificatifs, PDF de conversation | Données potentiellement sensibles selon le contenu, accès privé nécessaire |
| Messages | Conversations et pièces/coordonnées partagées | Pas de prétention au chiffrement de bout en bout ; confidentialité contrôlée par règles et serveur |
| Activité dans l’app / contenus générés | Demandes, propositions, J’aime, recommandations, signalements et blocages | L’utilisateur peut saisir d’autres données dans un texte libre ; en informer sans présenter ces champs comme sans risque |
| Identifiants appareil et données techniques | Jeton FCM, plateforme, sessions, limites et traces d’erreurs | Vérifier les définitions et traitements des SDK, Auth, FCM, SMTP et journaux |
| Localisation | Zones déclaratives de service ; adresses contenues volontairement dans les textes | Aucun SDK GPS repéré ; ne pas assimiler cela à l’absence de toute donnée de lieu chez le fournisseur |

Recenser les destinataires et les conditions précises de « partage » selon les définitions du formulaire ; un sous-traitant ou une publication à la demande de l’utilisateur n’ont pas nécessairement la même qualification. Vérifier transport chiffré, protection Auth anti-énumération, caractère obligatoire/facultatif et liens finaux. Ne pas cocher une absence de collecte de télémétrie simplement parce qu’Analytics n’est pas installé. Le formulaire de suppression et son URL finale devront être testés depuis un navigateur sans application installée.

## Préparation Apple App Privacy

Vérifier les catégories coordonnées/identifiants, contenu utilisateur (photos, documents, messages), interactions et diagnostics réellement traités, et leur lien au compte. Les données liées à l’UID sont généralement associées à l’utilisateur dans le produit ; la qualification des traitements fournisseur reste à examiner. Aucun SDK publicitaire ni mécanisme de suivi inter-apps n’est identifié dans les dépendances auditées ; vérifier les déclarations des SDK et manifests de confidentialité embarqués avant d’annoncer « aucun tracking ». Foundi utilise Google et e-mail ; Sign in with Apple n’est pas implémenté, ne pas inventer une révocation de jeton Apple. La conformité de l’offre de connexion aux exigences Apple doit être revue séparément.

## Revue périodique et incidents

Responsable à nommer : référent données/éditeur, avec accès au journal Admin. Au minimum annuellement et à chaque changement majeur : refaire l’inventaire code/SDK, vérifier les métadonnées et contrats cloud, les TTL réellement actifs, les domaines/liens, la politique de conservation, l’information des personnes et les déclarations des stores. Conserver une trace de la version examinée et des décisions.

En cas d’effacement incomplet, contenu encore public ou fichier orphelin : arrêter l’exécution destructive avec le commutateur serveur si nécessaire, garder la barrière de fermeture, qualifier le dossier privé, vérifier propriété et génération du fichier et corriger la cause avant reprise motivée. Ne jamais lever la barrière pour « réparer » un dossier, ni annoncer la fin sans vérification. Informer le demandeur par le canal approprié sans exposer de données de tiers. Si une mauvaise suppression ou divulgation est suspectée, restreindre les accès, préserver les traces minimales nécessaires et faire qualifier les obligations de notification par le responsable et son conseil. Une restauration fournisseur ne doit jamais republier automatiquement les données d’un compte effacé : rejouer d’abord les marqueurs d’effacement et les contrôles de modération.

Les pays correspondant aux codes d’hébergement relevés sont précisés et sourcés dans le dossier de décisions : Belgique pour Functions/Storage ; Belgique et Pays-Bas pour les répliques Firestore, avec une région témoin en Finlande. Les lieux Auth/FCM/SMTP et autres traitements fournisseur restent à confirmer.
