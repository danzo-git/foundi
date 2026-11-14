# Décisions à valider avant activation

> Mise à jour du 14 novembre 2026 : les réglages techniques appliqués au backend sont décrits dans [l’état d’activation](activation-suppression-2026-11-14.md) et `config/privacy-policy.json`. Les éléments juridiques et le site public restent à compléter ; le présent document conserve les décisions et limites de la livraison initiale.

Cette livraison est locale. Aucun texte nouveau n’est publié, aucune configuration Firebase n’est écrite et aucun compte réel n’est supprimé. La branche est `codex/foundi-sprint-2-confidentialite-suppression`, issue du Sprint 1 poussé au commit `f17cb54`.

## Identité et cadre juridique

Informations confirmées par l’éditeur : Denzel Kouamé ; kouamedenzel09@gmail.com ; SARL ; 10 rue Gaston Tardif ; pays visés Côte d’Ivoire et France. Restent nécessaires : dénomination sociale exacte, immatriculation/RCCM, représentant, adresse complète avec ville/code postal/pays, éventuelles coordonnées fiscales et contact chargé de la protection des données. Le nom d’une personne n’est pas présumé être la dénomination de la SARL.

Faire relire les projets par une personne compétente en droit ivoirien et pour la diffusion en France : bases des traitements, droits et délais, formalités auprès de l’autorité, transferts internationaux, rôle de la plateforme, éventuelles obligations de représentant, mineurs/âge, droit applicable, recours et médiation. Aucun contrôle d’âge ni certification juridique n’est ajouté par une phrase dans les CGU. Les projets contiennent ces points à valider et ne sont pas publiables tels quels.

## Politique d’effacement proposée, sans adoption automatique des durées

| Données | Traitement technique proposé | Décision attendue |
| --- | --- | --- |
| Compte Auth, profil, téléphone, demandes, vitrine, photos, justificatifs, tokens, préférences, propres messages | Effacement actif par étapes ; Auth supprimé après vérification des autres données | Confirmer le périmètre et les délais de traitement annoncés ; définir les durées en activité/inactivité |
| Messages écrits par les autres membres | Conservés chez leur auteur/correspondant, conversation en lecture seule ; identité et contenus du compte supprimé effacés | Valider cette règle de conversation et son information aux membres |
| Propositions d’autres professionnels sur une demande supprimée | Texte de leur auteur conservé ; client remplacé par « Compte supprimé », titre personnel retiré, état indisponible | Valider l’intérêt et la durée de cet historique chez l’autre membre |
| Preuves et commentaires de signalement | Archive privée séparée, échéance bornée, jamais affichée publiquement | Choisir et justifier `moderationEvidenceDays`, de 0 à 90 ; 0 signifie aucun maintien dans cette archive après suppression |
| Métadonnées, décisions et traces de modération | Archive privée bornée, sans changement de la sanction d’un tiers | Choisir et justifier `moderationMetadataDays`, de 0 à 365 ; ces maxima viennent du Sprint 1, ce ne sont pas des durées légalement adoptées |
| Mesure active concernant un autre membre | Nouveau dossier technique contenant seulement sa mesure ; aucune identité/commentaire/preuve du déclarant supprimé ; restauration toujours possible | Valider la continuité de la mesure et la revue de sa nécessité ; ne pas transformer ce dossier en rétention illimitée des anciennes preuves |
| Suivi de suppression | Référence opaque, empreinte du secret, dates/étapes, état et échéances ; UID retiré à la fin | Choisir `receiptSeconds`, puis informer clairement de l’expiration du suivi |
| Audit de consultation/reprise du dossier | Journal privé à échéance ; reprise d’un dossier existant uniquement, motif obligatoire | Choisir `auditSeconds`, rôle responsable et contrôle périodique |
| Barrière technique contre les anciens jetons | Marqueur `accountLifecycle` sans contenu du profil, TTL après achèvement | Choisir `tombstoneSeconds` ; minimum technique 3 900 secondes pour couvrir les jetons Firebase d’une heure, pas une obligation juridique |
| Stockage fournisseur | Objets actifs supprimés avec contrôle de génération ; récupération fournisseur séparée | Reconnaître le paramètre vérifié de sept jours de soft delete et contrôler les autres copies fournisseur |
| Journaux, SMTP, Authentication/FCM et sauvegardes | Informations fournisseur à compléter ; aucune promesse de purge instantanée | Vérifier contrats, emplacements, durées et mécanismes de purge ; adopter les informations à communiquer |

Le fichier `config/privacy-policy.draft.json` contient des durées `null`, `enabled:false` et `approved:false`. Le service refuse d’initier une suppression tant que les valeurs et validations requises ne sont pas renseignées. Le paramètre de Functions `ACCOUNT_DELETION_ENABLED` vaut également `false` par défaut. Les valeurs courtes utilisées dans les tests sont des fixtures de `demo-foundi`, sans valeur de décision métier.

Le tableau de l’audit initial décrit les données déjà en production. Les paramètres 90 jours/365 jours du Sprint 1 restent un constat du code à revoir juridiquement, et non une validation implicite. Les TTL sont asynchrones : l’échéance rend une archive inaccessible aux clients et déclenche une suppression gérée par Firebase ; le délai effectif de service doit être surveillé. Aucun accès client n’est accordé aux archives, même avec un claim Admin. La console cloud et les comptes de service doivent également être restreints par IAM.

Les PDF dont la conservation est justifiée sont copiés avant effacement du fichier actif, en fragments privés `accountDeletionHoldChunks` de taille bornée, avec la même échéance TTL que la preuve et une empreinte d’intégrité. Les images et textes figés restent dans l’archive privée. Un fichier source déjà absent est déclaré indisponible ; aucune preuve inexistante n’est annoncée comme conservée. Aucun fichier de preuve n’est maintenu sans échéance dans un répertoire Storage orphelin.

## Infrastructure : faits et limites de vérification

Métadonnées vérifiées en lecture seule le 13 novembre 2026 à 21:00 UTC : Firestore `eur3`, mode natif, PITR désactivé ; bucket `EUROPE-WEST1`, versioning désactivé, aucune politique de rétention bucket déclarée, soft delete 604 800 secondes ; Functions utilisées en `europe-west1`. Ce contrôle n’a lu aucun document métier ni compte client. L’absence de PITR n’établit pas l’absence de sauvegardes planifiées ou d’exports. Le lieu des Functions ne prouve pas le lieu de tous les traitements Auth, FCM ou SMTP.

La correspondance documentaire des régions a également été vérifiée : `eur3` associe des répliques de lecture/écriture en Belgique et aux Pays-Bas et une région témoin en Finlande ; `europe-west1` / `EUROPE-WEST1` correspond à la Belgique. Il s’agit d’une interprétation des codes effectivement relevés, selon les [emplacements Firestore](https://firebase.google.com/docs/firestore/locations?hl=en), les [régions Functions](https://firebase.google.com/docs/functions/locations) et les [emplacements Storage](https://docs.cloud.google.com/storage/docs/locations). Cela ne localise pas tous les traitements des prestataires.

Les jetons, adresses et clés secrètes ne doivent pas figurer dans ce dossier ni dans les captures. La configuration publique Firebase n’est pas une clé d’administration. Activer la protection contre l’énumération des e-mails du projet Auth avant publication du formulaire : masquer les erreurs dans l’interface ne suffit pas à protéger l’API du fournisseur. Vérifier également les domaines Auth autorisés, les quotas, le coût des scans de stockage, la protection contre les abus des points HTTP et la politique CORS/CSP sur le domaine retenu.

## Validation des textes et versions

La prévention de la récidive après recréation d’un compte doit également être décidée : les restrictions du Sprint 1 portent sur un UID. Le Sprint 2 bloque cet UID pendant la fermeture et préserve les mesures concernant les tiers ; il ne rattache pas automatiquement une nouvelle inscription à une personne dont le compte a été effacé. Une interdiction visant la même personne au-delà de la suppression exigerait un dispositif distinct, proportionné, avec base, identifiants strictement nécessaires, durée, accès et recours validés. Aucun fichier permanent d’e-mails ou d’empreintes de personnes supprimées n’est créé silencieusement. Cette limite doit être prise en compte avant activation si une sanction doit suivre une personne au-delà de son ancien compte.

Les sources sont `docs/legal/sprint-2/*-projet.md`. `node scripts/build-privacy-pages.cjs` produit le même contenu dans les pages HTML et `config/legal-documents.sprint-2.draft.json`, avec `published:false`. L’ancien `config/legal-documents.json` et les anciens textes restent intacts. La nouvelle version n’est pas acceptée automatiquement par les comptes existants.

Après relecture, renseigner la date d’effet, retirer les mentions de projet et les points non résolus, générer les pages et le payload identiques, puis décider si `requiresAcceptance:true` est requis. Le client propose alors une acceptation explicite depuis les paramètres. La lecture ordinaire d’un texte n’écrit rien. Le registre `users/{uid}/legalAcceptances/{version}` est immuable côté client ; une ancienne référence est copiée avec sa date ancienne ou `null`, jamais une date inventée. Prévoir l’information des membres pour un changement majeur.

## Sources officielles consultées le 13 novembre 2026

- [Google Play : suppression des comptes](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en) : chemin interne et ressource Web, suppression effective et exceptions de conservation expliquées.
- [Google Play : données des utilisateurs](https://support.google.com/googleplay/android-developer/answer/10144311) : politique et déclarations cohérentes avec les pratiques et SDK.
- [Apple : suppression du compte](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion) : chemin dans l’app et traitement des données associées ; la réauthentification peut protéger l’opération.
- [Autorité ivoirienne : FAQ protection des données](https://www.autoritedeprotection.ci/faqdcp/) et [loi n° 2013-450, PDF officiel](https://www.autoritedeprotection.ci/docs/Loi-2013-450.pdf) : faire confirmer les droits, formalités et transferts par le conseil compétent. Le PDF a été identifié ; son interprétation article par article ne constitue pas cette implémentation.
- [CNIL : droits des personnes](https://www.cnil.fr/fr/les-droits-pour-maitriser-vos-donnees-personnelles) : source à relire avec le conseil pour la diffusion en France ; l’applicabilité exacte n’est pas présumée.
- [Firebase : gestion des sessions](https://firebase.google.com/docs/auth/admin/manage-sessions), [confidentialité des services](https://firebase.google.com/support/privacy), [réauthentification](https://firebase.google.com/docs/auth/web/manage-users#re-authenticate_a_user).
- [Google Cloud Storage : soft delete](https://docs.cloud.google.com/storage/docs/soft-delete) : distinction entre objet actif supprimé et copie fournisseur de récupération.

Les liens ne valent ni approbation des textes ni certification des stores. Les règles des stores et les services doivent être revérifiés à la date de soumission.
