import 'dart:async';
import 'package:flutter/material.dart';
import '../../conversations/domain/conversation_repository.dart';
import '../domain/notification_repository.dart';
import 'notification_views.dart';

/// Reads are an independent, post-frame effect. Never awaited by message sends.
class ConversationReadTracker extends StatefulWidget {
  const ConversationReadTracker({
    super.key,
    required this.conversationId,
    required this.uid,
    required this.batch,
    required this.scroll,
    required this.active,
    required this.child,
  });
  final String conversationId, uid;
  final MessageBatch batch;
  final ScrollController scroll;
  final bool active;
  final Widget child;
  @override
  State<ConversationReadTracker> createState() =>
      _ConversationReadTrackerState();
}

class _ConversationReadTrackerState extends State<ConversationReadTracker>
    with WidgetsBindingObserver {
  MessageReadRepository? _repository;
  int _confirmedAt = -1;
  bool _inFlight = false, _scheduled = false;
  Timer? _retry;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.scroll.addListener(_schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = NotificationScope.maybeOf(context)?.repository;
    _repository = repository is MessageReadRepository
        ? repository as MessageReadRepository
        : null;
    ModalRoute.of(
      context,
    ); // Recheck when this route becomes covered/uncovered.
    _schedule();
  }

  @override
  void didUpdateWidget(ConversationReadTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.conversationId != widget.conversationId) {
      _confirmedAt = -1;
    }
    if (oldWidget.scroll != widget.scroll) {
      oldWidget.scroll.removeListener(_schedule);
      widget.scroll.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void _schedule() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_read());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _read() async {
    final repository = _repository;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (repository == null ||
        _inFlight ||
        !widget.active ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        ModalRoute.of(context)?.isCurrent == false ||
        !widget.scroll.hasClients ||
        widget.scroll.offset > 24 ||
        !widget.batch.messages.any((m) => m.senderUid != widget.uid)) {
      return;
    }
    final latest = widget.batch.messages.reduce(
      (a, b) => a.createdAt > b.createdAt ? a : b,
    );
    if (latest.createdAt <= _confirmedAt) return;
    final conversationId = widget.conversationId, uid = widget.uid;
    _inFlight = true;
    try {
      await repository.markConversationRead(conversationId, latest.id);
      if (mounted &&
          conversationId == widget.conversationId &&
          uid == widget.uid) {
        _confirmedAt = latest.createdAt;
      }
    } catch (_) {
      _retry?.cancel();
      if (mounted) _retry = Timer(const Duration(seconds: 2), _schedule);
      return;
    } finally {
      _inFlight = false;
    }
    if (mounted) _schedule();
  }

  @override
  void dispose() {
    _retry?.cancel();
    widget.scroll.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
