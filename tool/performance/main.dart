// Run only in profile mode with --dart-define=FOUNDI_PERF_HARNESS=true.
// Real Foundi widgets, synthetic data and fixed repository delays. No Firebase
// calls from these repositories; this is not the connected app bootstrap.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/presentation/explorer_view.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/professional/domain/professional_directory.dart';
import 'package:foundi/features/professional/presentation/professional_directory_view.dart';

void main() {
  const enabled = bool.fromEnvironment('FOUNDI_PERF_HARNESS');
  if (!enabled) {
    throw StateError('Diagnostic entry point requires explicit opt-in');
  }
  runApp(const MaterialApp(home: Scaffold(body: Benchmark())));
}

class RequestsFixture implements RequestRepository {
  int subscriptions = 0, cancellations = 0;
  @override
  Stream<List<FoundiRequest>> watchPublic() {
    subscriptions++;
    return Stream<List<FoundiRequest>>.multi((sink) {
      final timer = Timer(const Duration(milliseconds: 80), () {
        sink.add(
          List.generate(
            30,
            (i) => FoundiRequest(
              id: 'fixture-$i',
              title: 'PERFORMANCE_FIXTURE_$i',
              description: 'Données synthétiques de diagnostic',
              categoryLabel: 'Service',
              specialtyLabel: '',
              zoneLabel: 'Zone test',
              status: 'published',
              createdAt: DateTime(2026, 1, 1),
            ),
          ),
        );
      });
      sink.onCancel = () {
        timer.cancel();
        cancellations++;
      };
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CatalogFixture implements ProfessionalRepository {
  int reads = 0;
  @override
  Future<ProfessionalCatalog> loadCatalog() async {
    reads++;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return const ProfessionalCatalog(enabled: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DirectoryFixture implements ProfessionalDirectoryRepository {
  DirectoryFixture(this.bytes, {this.expiringMedia = false});
  final Uint8List bytes;
  final bool expiringMedia;
  int thumbnails = 0, manifests = 0;
  int invalidations = 0;
  @override
  Future<ProfessionalDirectoryPage> searchProfessionals(
    ProfessionalDirectoryFilters filters, {
    String? cursor,
  }) async => ProfessionalDirectoryPage([
    const ProfessionalListing(
      professionalId: 'fixture',
      name: 'Professionnel test',
      trade: 'Service',
      zones: ['Zone test'],
      categories: [],
      specialties: [],
    ),
  ]);
  @override
  Future<Set<String>> checkDirectoryProfessionals(List<String> ids) async =>
      ids.toSet();
  @override
  Future<ProfessionalMediaManifest> directoryMediaManifest(String id) async {
    manifests++;
    return ProfessionalMediaManifest(
      cacheExpiresAt: expiringMedia
          ? DateTime.now().add(const Duration(seconds: 30))
          : null,
      portraitId: 'portrait',
      galleryIds: ['a', 'b', 'c'],
    );
  }

  @override
  Future<Uint8List> readDirectoryThumbnail(String id, String photoId) async {
    thumbnails++;
    return bytes;
  }

  @override
  void clearDirectoryMedia(String id) {
    invalidations++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Benchmark extends StatefulWidget {
  const Benchmark({super.key});
  @override
  State<Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<Benchmark> {
  final root = GlobalKey();
  final requests = RequestsFixture();
  final catalog = CatalogFixture();
  final timings = <ui.FrameTiming>[];
  Widget scene = const Text('Diagnostic Foundi — données synthétiques');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  void onTimings(List<ui.FrameTiming> batch) => timings.addAll(batch);
  bool visible(String text) {
    var found = false;
    void visit(Element element) {
      if (element.widget case Text(data: final data) when data == text) {
        found = true;
      }
      element.visitChildren(visit);
    }

    root.currentContext?.visitChildElements(visit);
    return found;
  }

  Future<void> frame() async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> run() async {
    final samples = <double>[];
    for (var i = 0; i < 21; i++) {
      setState(() => scene = const SizedBox.shrink());
      await frame();
      final watch = Stopwatch()..start();
      setState(
        () => scene = ExplorerView(
          key: ValueKey(i),
          repository: requests,
          catalog: catalog,
          onOpen: (_) {},
          onPublish: () {},
        ),
      );
      while (!visible('PERFORMANCE_FIXTURE_0') &&
          watch.elapsedMilliseconds < 5000) {
        await frame();
      }
      await WidgetsBinding.instance.endOfFrame;
      samples.add(watch.elapsedMicroseconds / 1000);
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 640, 640),
      Paint()..color = Colors.green,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(640, 640);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final directory = DirectoryFixture(data!.buffer.asUint8List());
    final dirKey = GlobalKey();
    Widget directoryView() => ProfessionalDirectoryView(
      key: dirKey,
      repository: directory,
      catalog: catalog,
      heading: const Text('Diagnostic annuaire'),
    );
    setState(() => scene = directoryView());
    for (var i = 0; i < 35; i++) {
      await frame();
    }
    final initialThumbnails = directory.thumbnails;
    for (var i = 0; i < 20; i++) {
      setState(() => scene = directoryView());
      await frame();
      await frame();
    }
    setState(() => scene = const Text('Diagnostic terminé'));
    await frame();
    await Future<void>.delayed(const Duration(seconds: 1));
    final warm = samples.skip(1).toList()..sort();
    double p95(List<double> values) => values[(values.length * .95).ceil() - 1];
    final build =
        timings.map((t) => t.buildDuration.inMicroseconds / 1000).toList()
          ..sort();
    final raster =
        timings.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()
          ..sort();
    final result = jsonEncode({
      'kind': 'physical_profile_synthetic_repositories',
      'label': const String.fromEnvironment(
        'PERF_LABEL',
        defaultValue: 'baseline',
      ),
      'explorer': {
        'samplesMs': samples,
        'warmMedianMs': (warm[9] + warm[10]) / 2,
        'warmP95Ms': p95(warm),
        'catalogCalls': catalog.reads,
        'subscriptions': requests.subscriptions,
        'cancellations': requests.cancellations,
        'fixtureCatalogDelayMs': 250,
        'fixtureRequestDelayMs': 80,
      },
      'directory': {
        'initialThumbnailCalls': initialThumbnails,
        'thumbnailCallsAfter20Rebuilds': directory.thumbnails,
        'manifestCalls': directory.manifests,
      },
      'frames': {
        'count': timings.length,
        'buildP95Ms': p95(build),
        'rasterP95Ms': p95(raster),
      },
      'firestoreReads': null,
      'networkBytes': null,
      'serverMs': null,
    });
    // Numeric aggregates and synthetic scenario labels only; never user data.
    developer.log(result, name: 'FOUNDI_PERF');
    // ignore: avoid_print
    print('FOUNDI_PERF $result');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(onTimings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(key: root, child: scene);
}
