# Sprint 2 — audit initial avant implémentation

Base constatée : `f17cb54af267fd0240ccab0e0db1e8041b4e7bda`, arbre propre, branche de travail `codex/foundi-sprint-2-confidentialite-suppression`. Aucun compte réel ni contenu utilisateur de production n’est lu pour cet audit : les schémas viennent du code ; seuls les paramètres d’infrastructure peuvent être vérifiés en lecture seule.

## Constats initiaux

- Aucune suppression de compte orchestrée n’existe. `account-service.js` ne traite que le changement d’e-mail de l’inscription.
- Les paramètres ouvrent `LegalAcceptanceScreen` : la consultation des textes est mélangée à une nouvelle acceptation. `users.termsVersion/termsAcceptedAt` remplace la référence courante sans registre d’acceptations immuable.
- Le nom du client est publié automatiquement dans la projection de demande. Les demandes directes restent privées ; la vitrine professionnelle et ses photos sont publiques, les justificatifs ne le sont pas.
- Les conversations et propositions partagent des snapshots nominatifs. Effacer uniquement Auth ou `users/{uid}` laisserait des contenus publics, des médias, des tokens et des identités dans les dossiers d’autres utilisateurs.
- Le Sprint 1 conserve des preuves 90 jours, des métadonnées/audits 365 jours et maintient certains dossiers de mesure active avec `deleteAt:null`. Ces valeurs décrivent le code existant, pas une validation juridique. L’effacement doit distinguer la preuve à conservation bornée du dossier technique de la mesure d’un autre membre.
- Les codes OTP expirent après dix minutes ; les traces portent un `deleteAfter` à 24 h. Une expiration logique ne prouve pas à elle seule l’activation d’un TTL distant.
- Il existe un Hosting Admin ; aucun domaine public de confidentialité/suppression n’est présumé autorisé ou publié. Les textes et `config/legal-documents.json` actuels restent intacts.
- L’ancien contact juridique comporte `kouamdenzel09@gmail.com`, distinct du contact confirmé au Sprint 1 et reconfirmé au Sprint 2 : `kouamedenzel09@gmail.com`. Les nouveaux brouillons utiliseront le contact confirmé sans réécrire les textes historiques.

## Carte initiale des données et dépendances

Toutes les bases légales et exceptions ci-dessous sont **à confirmer par l’éditeur et son conseil**. « Sans purge » signifie absence de purge identifiée dans le code audité, pas une conservation autorisée sans limite.

| Chemin réel / support | Données et lien à la personne | Création et accès | Conservation constatée | Traitement requis lors de l’effacement |
| --- | --- | --- | --- | --- |
| Firebase Auth | UID, e-mail, nom, fournisseurs, mot de passe géré par Firebase, dates et sessions | SDK e-mail/Google ; backend Admin | Jusqu’à action explicite ; aucune suppression actuelle | Réauthentifier, bloquer/révoquer, supprimer Auth après les autres étapes |
| `users/{uid}` | Nom, téléphone facultatif, profession, parcours, préférences, référence CGU | `firebase_auth_repository.dart` ; propriétaire/Admin | Sans purge | Supprimer le document après ses sous-collections ; garder seulement les exceptions validées |
| `legalDocuments/current` | Textes publiés et version, sans identité de membre | Client en lecture ; publication via outil autorisé | Version courante | Ne pas supprimer ; ne pas remplacer automatiquement au Sprint 2 |
| `professionalProfiles/{uid}` | Nom commercial, type d’activité, catégories, spécialités, zones, description, état et décision | `professional-service.js` ; propriétaire/Admin ; projection publique sélectionnée | Sans purge | Retirer la visibilité puis effacer activité et sous-documents |
| `professionalProfiles/{uid}/documents/{kind}` | Nom, type, taille, génération et chemin des justificatifs | Backend validé ; propriétaire/Admin | Sans purge complète | Supprimer le fichier réel et les métadonnées, y compris fichiers orphelins du préfixe propriétaire |
| Storage `professionalDocuments/{uid}/{kind}/{file}` | Pièces confidentielles | Backend ; lecture propriétaire autorisée par règles | Remplacement avec nettoyage ; pas de durée globale | Effacement avec contrôle de préfixe/génération et réconciliation |
| `professionalProfiles/{uid}/showcase/profile` | Portrait/couverture/galerie encodés, bio, métier et nom publics sélectionnés | `professional-showcase-service.js` | Sans purge | Effacer les blobs Firestore et la projection publique |
| `professionalAudit/{id}` | UID professionnel/Admin, décision, raison, date | Backend ; Admin | Sans purge | Effacer/pseudonymiser suivant une exception précise et bornée validée |
| `requests/{requestId}` | Nom public automatique, titre, description, catégorie, zone, budget, photos et dates | `request-service.js` ; public | Cycle métier, pas de suppression de compte | Retirer la projection avant les phases privées |
| `userRequests/{uid}/items/{requestId}` | Copie d’auteur, compteurs, proposition retenue | Backend ; propriétaire/Admin | Sans purge globale | Effacer le sous-arbre propriétaire ; retirer références de personne supprimée chez les autres sans effacer leur demande |
| `.../items/{requestId}/decisions/{id}` | Décisions de propositions, acteur, raison et références | `conversation-service.js` ; serveur | Sans purge | Supprimer celles du propriétaire ; préserver les décisions propres d’un correspondant avec minimisation |
| `requestOwnership/{id}` | UID propriétaire | Backend seul | Sans purge | Effacer après les traitements dépendant de ce lien |
| `directRequests/{id}` | Demande et UID client/professionnel destinataire | Backend ; auteur/destinataire approuvé | Cycle métier | Effacer la demande du partant ; conserver/minimiser la demande propre du correspondant lorsque le destinataire part |
| `requestPhotoDrafts/{id}` | Manifeste, UID, IDs de photos | `request-photo-service.js` ; serveur | État temporaire/nettoyage | Effacer manifestes et toutes les photos attribuées au compte |
| `requestPhotoFiles/{requestId}_{photoId}` | UID, objet, génération, état, liens et délais | Backend seul | Brouillons abandonnés nettoyés ; médias liés sans échéance générale | Effacer les objets avant les métadonnées finales ; vérifier les générations |
| Storage `requestPhotos/{uid}/{requestId}/{photoId}/{objectId}.webp` | Photos publiques ou privées selon demande | HTTP contrôlé ; SDK interdit | Selon manifeste et état | Nettoyer le préfixe exact d’UID, y compris orphelins, sans toucher un préfixe voisin |
| `requestEngagement/{id}/likes/{uid}` et parent | Réaction, date, compteur | Backend ; réaction propre uniquement | Sans purge | Retirer la réaction du partant et ajuster le compteur une seule fois ; conserver celles des autres |
| `requestRecommendations/{id}` | `actorUid`, `ownerUid`, `professionalUid`, demande et date | Backend ; API autorisée | Sans purge | Retirer les recommandations impliquant le membre et recalculer les projections |
| `proposals/{id}` | UID des parties, nom pro, titre de demande, offre, prix, délai, état | Backend ; parties | Historique métier | Effacer le contenu rédigé par le partant ; minimiser les copies de son identité chez l’autre partie |
| `conversations/{id}` | Parties, noms, demande/proposition, snapshots, aperçu, dates | Backend ; parties | Historique conservé après modération | Lecture seule et identités retirées ; préserver le contenu propre de l’autre partie selon politique à valider |
| `.../messages/{id}` | Auteur, texte, contact volontaire, image/PDF, métadonnées | Backend ; parties | Historique sans échéance globale | Effacer le contenu rédigé par le partant et ses copies ; conserver un marqueur technique seulement si nécessaire |
| `.../attachments/{messageId}` | Auteur, fichier, empreinte, génération, état, bail et échéance | `attachment-service.js` ; serveur | Réservations 24 h ; baux techniques 120 s ; fichiers confirmés sans purge globale | Nettoyer uniquement les fichiers du partant, y compris quarantaine et orphelins identifiables |
| Storage `conversations/{cid}/attachments/...`, `/quarantine/...` | Images/PDF privés | HTTP contrôlé ; SDK interdit | Nettoyage des fichiers non confirmés ; actifs sans échéance globale | Ne jamais effacer le préfixe d’une conversation partagée sans preuve de propriété de chaque objet |
| `users/{uid}/notifications`, `notificationState`, `notificationPreferences` | Avis, références d’activité, lecture, compteur et préférences | Backend ; propriétaire | Sans purge | Effacer les propres données et les copies de l’identité du partant dans les notifications d’autrui |
| `users/{uid}/messageInbox`, `messageReads`, `messageState` | Réceptions, expéditeur, curseurs et compteurs privés | Backend seul / état propre en lecture | Sans purge | Effacer les propres données ; retirer/anonymiser les reçus de l’autre partie avec compteur cohérent |
| `users/{uid}/devices`, `notificationTokens/{hash}` | Token FCM, appareil aléatoire, plateforme, UID et activation | Backend seul | Jusqu’au remplacement/invalidation ; pas de purge de compte | Désenregistrer et supprimer les associations avant Auth |
| `notificationOutbox/{id}/deliveries/{device}` | Destinataire/acteur dans parent, états et tentatives par appareil | Backend seul | Envoi ignoré après 24 h, mais pas de purge complète | Supprimer/neutraliser les files concernant le partant et leurs sous-documents |
| `notificationJobs/{id}`, `notificationReceipts/{id}` | UID, snapshots de demande, curseurs, reçus de décompte | Backend seul | Pas de purge globale | Empêcher nouveaux fanouts puis effacer les jobs et références liés au compte |
| `authEmailChallenges/{id}` | `userId`, e-mail, HMAC du code, état, tentatives | `otp-service.js` ; serveur | Code 10 min ; `deleteAfter` 24 h | Effacer les challenges et budgets d’e-mail liés ; ne pas effacer les budgets d’IP partagés |
| `authEmailRateLimits/{HMAC}` | HMAC d’e-mail/IP, compteurs, lien challenge | Backend seul | Fenêtre 15 min ; `deleteAfter` 24 h | Effacer les clés attribuables au compte ; préserver les limites partagées jusqu’à leur purge prévue |
| Limites `requestPublicationLimits`, `requestPhotoLimits`, `conversationAttachmentRates`, `safetyReportLimits` | UID, budgets, dates et compteurs | Backend seul | Fenêtres logiques ; purge physique pas toujours définie | Effacer les clés propres au compte |
| `requestInteractionLimits/{hash}` | Budgets dérivés d’UID ou de demande | Backend seul | Fenêtres logiques | Dériver et effacer seulement les clés attribuables |
| `professionalDirectoryLimits`, `professionalDirectoryCursors` | Identifiant d’acteur / IP protégée, pagination, filtres | API annuaire ; serveur | Délais techniques/TTL à vérifier | Retirer les curseurs et clés de l’acteur authentifié ; ne pas assimiler toute navigation anonyme au compte |
| `userBlocks/{uid}/items/{otherUid}` | Relation privée de blocage | `safety-service.js` ; serveur | Jusqu’au déblocage | Effacer les relations sortantes et entrantes sans modifier les sanctions d’autrui |
| `accountSafety/{uid}`, `safetyContent/{type}_{id}` | Mesure de suspension/masquage et dossier source | Backend seul | Mesure active | Remplacer la barrière par le cycle de fermeture ; ne pas lever une mesure d’un autre membre |
| `safetyReports`, `safetyAudit` | Parties, cible, commentaire, preuves figées, images, acteur Admin et décisions | Admin via API courante seulement | Preuve 90 j, métadonnées 365 j ; maintien de mesures actives | Politique d’exception explicite et bornée ; retirer les identités et préserver une restauration légitime d’autrui |
| `users/{uid}/safetyNotices` | Décision contextualisée, extrait propre, notification liée, lecture | Propriétaire, même suspendu | Pas de purge globale | Effacer les avis propres avec le sous-arbre du compte |
| Journaux Functions/Cloud et prestataire SMTP | Traces techniques, IDs de message, codes d’erreur ; métadonnées réseau chez prestataires | Exploitants/prestataires | À vérifier dans les ressources réelles | Pas de fausse promesse d’effacement des journaux/sauvegardes ; accès limité et durée à documenter |
| Appareil | Session Firebase, cache Firestore, ID appareil, réception FCM, PDF temporaire | SDK et fichiers privés de l’application | Cache/session/OS ; aucun délai global garanti | Déconnexion, retrait push, nettoyage des fichiers gérés et cache au démarrage suivant ; ne pas supprimer les originaux choisis sur l’appareil |

## SDK et prestataires observés

`pubspec.yaml/lock` : Firebase Core, Auth, Firestore, Functions et Messaging ; Google Sign-In ; file/image picker, ouverture de fichier, accès temporaire, préférences locales et HTTP. Aucun SDK Analytics, Crashlytics, Sentry, publicité ou GPS n’est identifié dans les dépendances applicatives examinées. Cela n’exclut pas la télémétrie opérationnelle des fournisseurs. Les zones sont choisies dans le catalogue, pas obtenues par GPS. Backend : Firebase Admin/Functions, Nodemailer, Sharp, pdf-lib. Le mécanisme antivirus configurable existe ; son activation réelle n’est pas présumée.

## Éditeur et décisions ouvertes

Déclarations reçues : Denzel Kouamé ; `kouamedenzel09@gmail.com` ; forme annoncée SARL ; adresse « 10 rue Gaston Tardif » ; Côte d’Ivoire et France visées. Dénomination sociale, immatriculation, représentant, ville/code postal/pays de l’adresse, autorité/juridiction et éventuelles formalités restent à valider. Aucune de ces données ne sera publiée automatiquement.

Les durées des justificatifs, conversations partagées, demandes de suppression, traces minimales et sauvegardes ne sont pas adoptées par cet audit. L’exécution destructive devra rester désactivée tant qu’une configuration de conservation explicitement validée n’est pas fournie. Les fixtures d’émulateur pourront activer une politique uniquement locale et clairement identifiée comme telle.

Sources produit : fichiers mentionnés dans le tableau, règles Firestore/Storage et configuration des index. Références officielles juridiques/stores et vérification des emplacements d’infrastructure à consigner séparément avant finalisation.
