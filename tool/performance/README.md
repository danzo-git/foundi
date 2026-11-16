# Diagnostic local Sprint 2.6

Ce diagnostic utilise les vrais widgets avec des données fictives et des délais contrôlés. Il ne se connecte pas aux comptes Firebase. Les résultats sont séparés des mesures de production dans [le rapport](../../docs/sprint-2-6/rapport.md).

## Téléphone Android en mode profile

Depuis la racine du dépôt, préparer les deux vues de référence à partir du commit exact :

```powershell
./tool/performance/prepare-baseline.ps1
flutter build apk --profile --target-platform android-arm64 -t .dart_tool/sprint26-before/main.dart --dart-define=FOUNDI_PERF_HARNESS=true --dart-define=PERF_LABEL=before
```

Pour la version courante :

```powershell
flutter build apk --profile --target-platform android-arm64 -t tool/performance/main.dart --dart-define=FOUNDI_PERF_HARNESS=true --dart-define=PERF_LABEL=after
```

Le Gradle lit directement le `dart-define` et utilise `com.example.foundi.performance`. Ne pas utiliser une variable d’environnement Gradle pour choisir le package. **Avant chaque installation, vérifier l’identifiant réellement présent dans l’APK avec `aapt dump badging`. Refuser l’installation du diagnostic s’il ne correspond pas exactement au package distinct.** Ne pas remplacer l’application normale pour mesurer ces fixtures.

Après cette vérification, installer sur le téléphone de test avec `adb -s <device> install -r <apk>`, puis lancer explicitement :

```text
adb -s <device> shell am start -W -n com.example.foundi.performance/com.example.foundi.MainActivity
```

Garder l’écran déverrouillé pendant le scénario. Le diagnostic effectue 21 ouvertures Explorer, puis 20 reconstructions de l’annuaire. Extraire uniquement la ligne `FOUNDI_PERF {…}` du processus de diagnostic, avec le bon label et l’heure de cette exécution. Ne pas exporter le logcat général du téléphone. Conserver le JSON dans `docs/sprint-2-6/device-before.json` ou `device-after.json`. Les mesures initiales publiées utilisent la même version de fixtures et les deux vues originales du commit de référence.

Le catalogue répond en 250 ms et les demandes en 80 ms. Les compteurs du faux catalogue ne mesurent pas la déduplication du catalogue Firebase : celle-ci est validée séparément dans les tests de `PublicReferenceStore`. Les appels de miniatures comptent les méthodes du dépôt, pas les RPC ou lectures facturées. Les timings de frames incluent les frames de sonde ; le nombre total diffère lorsque le chargement finit plus vite. Ne pas interpréter leur p95 comme un benchmark de défilement à contenu et durée égaux.

Supprimer uniquement le package de diagnostic après les mesures. Ne pas distribuer ses APK.

## Service Node : comparaison contrôlée

```powershell
node tool/performance/avatar-benchmark.cjs before
node tool/performance/avatar-benchmark.cjs after
```

La version `before` est chargée directement depuis le même commit de référence, sans modifier les fichiers de travail. La version `after` utilise le module local. Douze conversations fictives, 21 exécutions, fausses lectures mémoire différées de 3 ms ; JSON écrits dans `docs/sprint-2-6`. Ces commandes remplacent les anciens résultats : conserver les originaux si l’on veut comparer plusieurs campagnes. L’ordre et la charge de la machine influencent les timers Windows. Ce test ne mesure ni TLS, ni cold start, ni facturation, ni backend déployé.

## Validation

```powershell
flutter analyze
flutter test --concurrency=2
node --test --test-concurrency=2 functions/test/*.test.js
npm --prefix functions run check
node --check functions/src/bounded-work.js
npm --prefix functions run test:conversation:cards:emulators
node functions/scripts/test-v82-emulators.cjs --safety-only --rules-only
```

Arrêter la compilation Gradle avant de démarrer les émulateurs sur une machine de 8 Go. Les runners Firebase utilisent exclusivement `demo-foundi` et restaurent les fichiers locaux de configuration. Aucun déploiement n’est requis pour ces tests.

## Mesures connectées restant à réaliser

Sur un environnement de recette et des comptes dédiés : profiler chaque parcours de la matrice du rapport, séparer première visite/retour, données froides/chaudes, espace client/pro, Wi-Fi/réseau lent/hors ligne/reconnexion. Relever le TTFB des requêtes dans DevTools et la durée serveur dans les métriques existantes, sans enregistrer les corps, URLs privées ou jetons. Pour le codec, utiliser la timeline DevTools et un jeu de photos de recette constant ; pour le rendu, mesurer un défilement identique et le budget de frame correspondant à la fréquence de l’écran. Répéter au moins 20 fois, idéalement davantage pour le p95. Mesurer les octets et les lectures depuis les outils existants du projet ; ne pas les déduire des seuls compteurs Dart.

Faire aussi des snapshots mémoire après une boucle de navigation et après GC, et vérifier que le nombre d’abonnements revient au niveau initial. Révoquer une photo, bloquer, suspendre ou supprimer un compte de recette pendant une requête lente : aucun résultat tardif ne doit rétablir l’accès. Cette recette connectée ne se substitue pas aux tests automatisés, et les résultats synthétiques ne s’y substituent pas non plus.
