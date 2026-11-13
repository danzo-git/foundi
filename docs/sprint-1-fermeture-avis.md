# Fermer un avis après lecture

Un avis de modération dans le profil propose désormais **J’ai compris**. La confirmation est enregistrée côté serveur, puis le message disparaît du profil. Il reste fermé après une nouvelle ouverture et sur un autre appareil qui recharge les avis. Un lien **Historique des avis** permet de consulter les derniers avis, y compris ceux dont la lecture a été confirmée.

La fermeture est propre à chaque avis : elle ne ferme pas les décisions suivantes, ne supprime pas la notification et n’efface ni la décision ni le journal Admin. Elle ne lève aucune suspension et ne restaure aucun contenu masqué. Une erreur réseau conserve l’avis et permet de réessayer.

## Serveur

- `acknowledgeSafetyNotice` n’accepte qu’un identifiant d’avis et déduit le propriétaire de l’authentification. Aucun UID de destinataire n’est accepté en entrée.
- La transaction modifie seulement `acknowledgedAt` dans l’avis privé de ce membre. Les réessais conservent la première date de lecture. Les avis historiques sans ce champ restent compatibles.
- La notification associée est marquée comme lue si elle existe. Le mécanisme existant décrémente le compteur une seule fois. L’historique reste ouvrable.
- Les push de modération encore en attente sont ignorés si leur notification a déjà été lue ; un push déjà transmis au téléphone ne peut pas être rappelé par cette confirmation.
- Un membre suspendu peut confirmer ses propres avis sans retrouver ses droits d’activité. Firebase Auth désactivé reste refusé. Les règles SDK continuent d’interdire toute écriture directe sur les avis.
- `listSafetyNotices` conserve le champ historique `items`, qui contient les textes non fermés. Le nouveau champ `notices` fournit les identifiants stables et les dates de lecture pour le client mis à jour. La consultation des derniers avis conserve la limite existante de dix résultats.

## Client

Le profil n’affiche que les avis dont la lecture n’est pas encore confirmée. Le bouton reste occupé pendant la requête et l’avis disparaît uniquement après succès. L’historique conserve le texte et affiche « Lecture confirmée ». Les paramètres isolent leur panneau par identifiant de session utilisateur.

La modification mobile nécessite une nouvelle version de l’application. Aucun APK n’est généré ou distribué. La publication de Foundi Admin demandée précédemment reste en attente d’accord et n’est pas incluse dans ce correctif.

## Validation

**175 tests Node**, **30 tests Flutter ciblés**, **36 tests de règles** et **2 parcours Firebase Emulator** réussis. Analyse Flutter : aucun problème. Les cas vérifiés couvrent l’isolation entre comptes, une session suspendue, la fermeture d’un ancien avis, les réessais, l’échec réseau, le maintien de l’historique, le compteur lu décrémenté une seule fois et l’apparition d’une nouvelle décision.

Une tentative de suite Flutter complète a été interrompue par un manque de mémoire Windows. Quatre anciens émulateurs Firestore Foundi dont les lanceurs avaient disparu ont été arrêtés, libérant près de 2 Go de mémoire engagée. Les tests Flutter ciblés et la passe finale Firebase ont ensuite réussi ; le lanceur Firebase a terminé avec le code 0 et la configuration locale a été restaurée. Cette validation ciblée ne constitue pas une nouvelle exécution complète de tous les tests Flutter.

Captures de vrais widgets, avec données fictives de test :

- [Avis avec le bouton J’ai compris](sprint-1-securite-captures/16-avis-fermeture.png).
- [Avis refermé conservé dans l’historique](sprint-1-securite-captures/17-historique-avis-ferme.png).

## Publication serveur vérifiée

Projet `foundi-7c837`, région `europe-west1` : `acknowledgeSafetyNotice` créée ; `listSafetyNotices`, `deliverNotificationPush` et `drainNotifications` mises à jour. **77 Functions actives**, les **73 autres empreintes inchangées**, paramètres de production et secrets préservés. Quatre contrôles HTTP ont confirmé les refus 401 sans authentification et les prévols CORS 204.

Aucune règle, aucun index ou TTL modifié pour ce correctif. Aucun avis de production n’a été fermé pour fabriquer un test. Les sauvegardes et vérifications restent privées dans `.dart_tool/sprint1-ack-*`.

Le code mobile est validé ; le bouton apparaîtra après une mise à jour de l’application. Aucun APK ni nouvelle version Hosting Admin ne sont publiés. Voir [l’inventaire complet des fichiers du sprint](sprint-1-fichiers.md).
