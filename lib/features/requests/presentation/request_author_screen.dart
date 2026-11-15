import 'dart:async';
import 'package:flutter/material.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../auth/presentation/personal_avatar.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../professional/presentation/professional_showcase_screen.dart';
import '../domain/request_author_repository.dart';

class RequestAuthorScreen extends StatefulWidget {
  const RequestAuthorScreen({
    super.key,
    required this.repository,
    required this.requestId,
  });
  final RequestAuthorRepository repository;
  final String requestId;
  @override
  State<RequestAuthorScreen> createState() => _RequestAuthorScreenState();
}

class _RequestAuthorScreenState extends State<RequestAuthorScreen>
    with WidgetsBindingObserver {
  late Future<RequestAuthorProfile> _profile = _load();
  Timer? _lease;
  bool _professional = false, _paused = false;
  Future<RequestAuthorProfile> _load() {
    final future = widget.repository.readRequestAuthor(widget.requestId).then((
      result,
    ) {
      _professional = result.professional != null;
      return result;
    });
    // Timer refreshes can finish before the next frame attaches FutureBuilder.
    future.ignore();
    return future;
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        _profile = _load();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lease = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_paused && !_professional) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _paused = false;
        _profile = _load();
      });
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      setState(() => _paused = true);
    }
  }

  @override
  void dispose() {
    _lease?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RequestAuthorProfile>(
    future: _profile,
    builder: (context, snapshot) {
      final author = snapshot.data;
      if (!_paused &&
          snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError &&
          author?.professional != null) {
        final id = author!.professional!.professionalId;
        return ProfessionalShowcaseScreen.recommended(
          professionalId: id,
          loadRecommended: () async {
            final current = (await widget.repository.readRequestAuthor(
              widget.requestId,
            )).professional;
            if (current == null || current.professionalId != id) {
              throw const AuthFailure(
                'Ce profil professionnel n’est plus disponible.',
              );
            }
            return current;
          },
          checkAvailability: () async {
            try {
              final current = await widget.repository.readRequestAuthor(
                widget.requestId,
              );
              return current.professional?.professionalId == id;
            } on RequestAuthorUnavailable {
              return false;
            }
          },
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Profil du demandeur')),
        body: _paused || snapshot.connectionState != ConnectionState.done
            ? const Center(child: CircularProgressIndicator())
            : snapshot.hasError
            ? ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  AuthNotice(
                    snapshot.error is AuthFailure
                        ? (snapshot.error as AuthFailure).message
                        : 'Impossible de charger ce profil.',
                  ),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Réessayer'),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  FoundiPanel(
                    child: Column(
                      children: [
                        Transform.scale(
                          scale: 2,
                          child: PersonalAvatar(publicId: author!.avatarKey),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          author.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: FoundiUi.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Membre Foundi'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Ce membre n’a pas d’activité professionnelle publique à afficher.',
                  ),
                ],
              ),
      );
    },
  );
}
