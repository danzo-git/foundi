# Foundi — livraison locale Sprint 2.5

> Mise à jour du 15 novembre 2026 : le volet photo personnelle des demandes a depuis été déployé à la demande de l’éditeur. Voir [le périmètre et les vérifications du déploiement ciblé](deploiement-photos-demandes-2026-11-15.md). Les autres évolutions restent locales.

Branche créée avant l’implémentation : `codex/foundi-sprint-2-5-finitions`. Base locale : `66839dc`. Aucun déploiement Firebase/Hosting, aucune publication juridique, aucune modification de compte réel et aucune distribution d’APK pendant ce sprint.

## Fonctionnement livré

### Photo personnelle

Le parcours photo a été revu selon la demande du 15 novembre : toucher directement l’avatar dans Mon compte ouvre le choix/remplacement/suppression, même sans compte professionnel ou avec dossier incomplet. Une photo de compte unique est utilisée pour les demandes et le portrait professionnel. Le portrait Foundi existant est repris automatiquement côté serveur, sans nouvel envoi de l’utilisateur ; ni la couverture, ni les réalisations, ni Google ne sont utilisés comme source. Une photo personnelle existante reste prioritaire. Le même écran sert aux professionnels approuvés. L’éditeur d’activité ne propose plus un second envoi de portrait.

La reprise est progressive lors de la consultation du compte ou des cartes existantes, sans migration de masse. Une suppression conserve un marqueur privé pour empêcher la réimportation d’un ancien portrait. Un nouveau profil professionnel reçoit la photo déjà choisie sans création anticipée de dossier ni changement de statut. Les textes, couverture et réalisations existants sont conservés. Le serveur valide JPEG/PNG/WebP, 5 Mio maximum, applique la normalisation existante puis produit une image WebP de 256 × 256 pixels sans métadonnées. Les fichiers restent privés et sans jeton permanent de téléchargement. Voir [la recette de l’identité commune](photo-identite-compte-2026-11-15.md).

Les cartes Explorer résolvent leurs auteurs par lots bornés à 50 demandes. Les documents `users` restent privés ; seuls un identifiant opaque et une version d’image sont publics. Les documents historiques sans `requestOwnership` utilisent la résolution canonique bornée existante par identifiant/date, sans migration de masse. Une propriété ambiguë donne l’icône par défaut.

La projection publique est observée par les cartes : une révocation ou un remplacement invalide l’image affichée et son cache mémoire. L’API média contrôle à nouveau la publication et la version après le téléchargement. Une erreur réseau revient à l’icône. Les données de résolution ne sont pas mises en cache durablement ; une projection provenant uniquement du cache local revient à l’icône tant que le serveur ne la confirme pas. Les fils déjà chargés se rafraîchissent aussi après une modification locale de la photo ; la révocation d’une photo déjà affichée est observée directement.

La purge Sprint 2 retire la projection à l’étape de retrait du profil, efface les fichiers et mappings privés, puis vérifie l’absence d’objets résiduels. Les indices des phases existantes n’ont pas été changés pour préserver les dossiers déjà ouverts. Les copies précédemment sauvegardées par un tiers ne sont pas rappelables ; le stockage fournisseur garde ses propres conditions de récupération.

### Zones et classification

Le sélecteur manuel recherche, ajoute et retire de une à trois zones actives. La zone n’est jamais étendue à ses parents/enfants. L’aperçu affiche toutes les zones choisies. Les documents historiques singuliers restent lisibles.

Une catégorie connue accepte `specialtyId=''`, sans exiger une spécialité du professionnel pour cette demande. L’Admin dispose d’une opération dédiée pour créer/activer `foundi_other`, une référence stable marquée `requestOnly:true`. Elle ne figure pas parmi les activités professionnelles et ne peut pas recevoir de spécialités. L’application ne crée aucune catégorie localement ; l’option n’apparaît que si le catalogue serveur la contient et l’active.

Un besoin non classé exige une précision de service de 3 à 120 caractères, nettoyée côté serveur. Les demandes directes conservent leur catégorie et leur spécialité vérifiées et verrouillées. Les quotas, identifiants, révisions, photos de demandes, propositions et protections de modération restent appliqués.

### Notifications

La même règle de correspondance sert aux opportunités et aux notifications :

| Demande | Professionnels concernés |
| --- | --- |
| Catégorie + spécialité | Approuvés dans cette catégorie/spécialité, avec au moins une zone commune |
| Catégorie, sans spécialité | Approuvés dans cette catégorie, avec au moins une zone commune |
| Non classée | Tous les professionnels approuvés et actifs avec au moins une zone commune |

La requête de candidats utilise `status='approved'` et `zoneIds array-contains-any` sur les zones exactes de la demande. Firestore renvoie un seul document professionnel même si deux ou trois zones correspondent. Toutes les pages de 40 destinataires sont traitées ; aucun plafond métier de destinataires n’est ajouté. La file existante conserve curseur, bail et reprise planifiée. Les comptes désactivés/suspendus/en suppression, l’auteur et les blocages dans les deux sens sont exclus ; l’éligibilité est revérifiée dans la transaction d’émission.

L’identifiant d’alerte est déterministe par demande/destinataire, indépendant de la révision. Une reclassification relance une tâche paginée pour atteindre les nouveaux destinataires sans réavertir les précédents. Le format historique basé sur la date de publication est également vérifié pour ne pas doubler une alerte de l’ancien backend. Les notifications dans l’application sont créées même si le push est refusé ; les préférences, appareils et limitations push existants restent applicables. Le message indique un nouveau besoin dans la zone, sans promettre une correspondance de spécialité.

## Contrats et migration

| Surface | Contrat |
| --- | --- |
| Publication/édition | `zoneIds: String[1..3]` distincts ; `zoneId` reste obligatoire et égal au premier élément |
| Projections | `zoneLabels` calculés par le serveur ; `zoneLabel` conserve le premier libellé pour les anciens clients |
| Spécialité | Chaîne vide explicitement autorisée pour une demande publique |
| Non classé | `categoryId='foundi_other'` seulement avec référence active `requestOnly:true` ; `serviceDetail` nettoyé, 3–120 caractères |
| Client ancien | Sans tableaux : lecture d’une zone ; édition de texte préserve les zones multiples et la précision existante ; changement ambigu de la première zone refusé avec invitation à actualiser Foundi |
| Catalogue Admin | `updateProfessionalCatalog` avec `operation:'enableUnclassified'`, `expectedVersion` ; journal d’audit existant |
| Photo personnelle | `readPersonalAvatarState`, `savePersonalAvatar({image?,contentType?,publish:boolean})`, `removePersonalAvatar` ; auteur authentifié exclusivement |
| Résolution | `resolveRequestAvatars({requestIds:≤50})` → `{avatars:{requestId:publicId}}`, sans UID ou données de compte |
| Média | GET `readPublicPersonalAvatar?id=…&version=…`, `Cache-Control: private, no-store` ; ancienne version ou publication révoquée refusée |
| Stockage | `personalAvatars/{uid}/{revision}.webp` privé ; Firestore privé `personalAvatars`, `personalAvatarLookup`, `personalAvatarLimits` et `personalAvatarGarbage` ; projection `publicPersonalAvatars/{opaqueId}` en lecture unitaire uniquement |

Les filtres Explorer fusionnent les requêtes historiques et multi-zones et dédupliquent par identifiant. Les opportunités affectent chaque demande à une seule unité de pagination correspondant à sa première zone commune dans le périmètre professionnel. Le client conserve également sa déduplication entre pages. Aucune écriture de migration n’a été exécutée sur des données distantes.

## Préparation Firebase, volumes et limites

Les nouveaux index sont déclarés dans `firestore.indexes.json` conformément aux [modes d’indexation Firestore](https://firebase.google.com/docs/firestore/query-data/index-overview) : variantes `zoneIds CONTAINS` des filtres de demandes, catégorie/zone/date pour les opportunités et statut/zones/identifiant pour les candidats professionnels. Les règles interdisent toute écriture client des projections d’avatar et toute lecture des mappings privés. Le refus Storage existant couvre aussi le nouveau préfixe ; les médias passent uniquement par le serveur. La résolution des anciennes demandes utilise l’index de groupe `items.createdAt` déjà nécessaire aux anciens parcours de propriété.

Pour M professionnels approuvés ayant une zone commune : environ `ceil(M/40)` pages (une page terminale supplémentaire si M est un multiple exact de 40), puis trois écritures par alerte nouvelle — notification, compteur et outbox. Le contrôle transactionnel complet représente un ordre de grandeur d’une vingtaine de lectures Firestore par destinataire éligible, hors push/reprises ; les profils non correspondants coûtent moins. À 1 000 destinataires éligibles, prévoir environ 25 pages, 3 000 écritures et 20 000 lectures, à mesurer dans un environnement dédié avant de convertir en coût monétaire. Les reprises ajoutent des lectures mais ne recréent pas les alertes.

Le drain existant traite au maximum dix pages de tâches par minute. Une tâche de 1 000 professionnels peut donc nécessiter environ 25 passages planifiés ; de nombreux besoins simultanés allongent l’attente. La règle « tous les destinataires » est préservée. Pour un lancement à volume important : métriques âge du plus ancien job/retries/échecs et continuation paginée via une file de tâches à débit global contrôlé, en conservant curseurs, baux et identifiants stables. Aucun service supplémentaire n’a été activé ici.

La résolution des avatars est bornée par page, utilise des lectures groupées et réutilise les lectures d’un même auteur pendant une résolution. Les lecteurs visibles surveillent uniquement les projections opaques de leur page. Une photo privée révoquée est gardée pour permettre sa republication volontaire ; Supprimer ma photo efface aussi le fichier. Une file privée durable `personalAvatarGarbage` est réservée avant l’envoi d’un fichier et écrite atomiquement lors d’un remplacement ou d’une suppression. Le retrait public est immédiat ; si Storage échoue, le nettoyage horaire reprend avec contrôle du propriétaire et de la génération, sans toucher à l’image courante. Le worker traite jusqu’à 200 objets par passage et journalise les totaux de succès/échec. La purge du compte retire également les entrées de cette file. Les tentatives de changement de photo sont bornées à 20 par jour par compte, avant le traitement de l’image.

Ordre de future recette, uniquement après autorisation distincte : projet dédié et données fictives ; déployer les index et attendre leur disponibilité ; déployer les Functions et règles ; activer la référence Admin ; construire et recetter le client. Un ancien backend peut ignorer les zones supplémentaires, donc le client ne doit pas être distribué avant la mise à jour serveur. Les émulateurs ne certifient pas la disponibilité effective des index, les quotas, les coûts ou les autorisations IAM distantes.

## Sous-fonctionnalités différées lors de la recette initiale

> Révision ultérieure du 15 novembre : le parcours auteur et la suggestion GPS native à confirmer sont désormais implémentés localement. Voir [la recette dédiée](profils-auteurs-localisation-2026-11-15.md). Le paragraphe GPS ci-dessous décrit uniquement l’état initial du sprint.

- GPS → zone : aucun catalogue géométrique ou service approuvé disponible. L’action secondaire explique cette indisponibilité, ne demande aucune permission et conserve la sélection manuelle. Refus, précision insuffisante, hors Côte d’Ivoire et ambiguïtés de géocodage restent à recetter quand un vrai mécanisme sera choisi. Aucun SDK, aucune coordonnée et aucun service payant ajoutés.
- Publication des textes, Hosting, recette sur appareils physiques et distribution : pas exécutées. La politique enrichie et les pages générées restent des projets non publiés.
- L’accélération de la diffusion à très fort volume reste un point d’exploitation explicité ci-dessus ; aucun destinataire n’est silencieusement ignoré. La réconciliation des fichiers privés est implémentée et testée avec une panne Storage simulée.

## Vérifications et captures

Les résultats définitifs sont consignés dans `sprint-2-5-tests.md`. Les captures se trouvent dans `sprint-2-5-captures/` : rendu Flutter réel des widgets de production avec données fictives et thème Foundi, sans compte réel. La photo utilisée dans la capture est un bitmap de test synthétique, pas une photo Google ni celle d’une personne.

Voir aussi la [carte des dépendances initiale et le plan de migration](sprint-2-5-plan-migration.md).

[Liste des fichiers et index](sprint-2-5-fichiers.md) · [Résultats des tests](sprint-2-5-tests.md) · [Captures Flutter](sprint-2-5-captures/README.md).
