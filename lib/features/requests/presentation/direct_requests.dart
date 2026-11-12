import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../professional/domain/professional_repository.dart';
import '../domain/request_repository.dart';
import 'request_composer.dart';
import 'request_views.dart';

class DirectRequestIntent {
  const DirectRequestIntent({required this.uid, this.requestId});
  final String uid;
  final String? requestId;
}

class DirectRequestsScope extends InheritedWidget {
  const DirectRequestsScope({
    super.key,
    required super.child,
    required this.auth,
    required this.onRequest,
    required this.navigation,
  });
  final AuthRepository auth;
  final ValueChanged<DirectProfessionalTarget>? onRequest;
  final ValueNotifier<DirectRequestIntent?> navigation;
  static DirectRequestsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DirectRequestsScope>();
  @override
  bool updateShouldNotify(DirectRequestsScope oldWidget) =>
      auth != oldWidget.auth ||
      onRequest != oldWidget.onRequest ||
      navigation != oldWidget.navigation;
}

class DirectRequestFormPage extends StatelessWidget {
  const DirectRequestFormPage({
    super.key,
    required this.repository,
    required this.catalog,
    required this.target,
    required this.user,
    required this.navigation,
  });
  final RequestRepository repository;
  final ProfessionalRepository catalog;
  final DirectProfessionalTarget target;
  final FoundiUser user;
  final ValueNotifier<DirectRequestIntent?> navigation;
  @override
  Widget build(BuildContext context) {
    void open({String? id}) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      navigation.value = DirectRequestIntent(uid: user.id, requestId: id);
    }

    return Scaffold(
      backgroundColor: FoundiUi.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: RequestComposer(
              repository: repository,
              catalog: catalog,
              directTarget: target,
              accountName: user.profile.fullName.trim().isEmpty
                  ? user.displayName
                  : user.profile.fullName,
              onExit: () => Navigator.of(context).pop(),
              onMine: () => open(),
              onOpen: (request) => open(id: request.id),
            ),
          ),
        ),
      ),
    );
  }
}

class DirectRequestsInbox extends StatefulWidget {
  const DirectRequestsInbox({
    super.key,
    required this.repository,
    required this.uid,
    required this.onBack,
    required this.onOpen,
  });
  final DirectRequestRepository repository;
  final String uid;
  final VoidCallback onBack;
  final ValueChanged<FoundiRequest> onOpen;
  @override
  State<DirectRequestsInbox> createState() => _DirectRequestsInboxState();
}

class _DirectRequestsInboxState extends State<DirectRequestsInbox> {
  late Stream<List<FoundiRequest>> _requests = widget.repository
      .watchDirectRequests(widget.uid);
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
    children: [
      RequestHeading('Demandes directes reçues', onBack: widget.onBack),
      const Text(
        'Ces demandes te sont adressées personnellement et ne sont pas publiées dans Explorer.',
        style: TextStyle(color: FoundiUi.muted, height: 1.5),
      ),
      const SizedBox(height: 16),
      StreamBuilder<List<FoundiRequest>>(
        stream: _requests,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                const AuthNotice('Les demandes directes sont indisponibles.'),
                OutlinedButton(
                  onPressed: () => setState(
                    () => _requests = widget.repository.watchDirectRequests(
                      widget.uid,
                    ),
                  ),
                  child: const Text('Réessayer'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData
              .where((r) => r.status != 'deleted')
              .toList();
          if (items.isEmpty) {
            return const RequestNotice(
              'Aucune demande directe',
              'Tes nouvelles demandes privées apparaîtront ici.',
            );
          }
          return Column(
            children: [
              for (final request in items) ...[
                RequestCard(
                  request,
                  showStatus: true,
                  showDescription: true,
                  onTap: () => widget.onOpen(request),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    ],
  );
}
