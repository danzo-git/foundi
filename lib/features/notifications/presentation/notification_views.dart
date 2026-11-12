import 'package:flutter/material.dart';
import '../domain/notification_repository.dart';

class NotificationIntent {
  const NotificationIntent(this.uid, this.id);
  final String uid, id;
}

class NotificationScope extends InheritedWidget {
  const NotificationScope({
    super.key,
    required this.repository,
    required this.intent,
    this.permission,
    required super.child,
  });
  final NotificationRepository repository;
  final ValueNotifier<NotificationIntent?> intent;
  final PushPermission? permission;
  static NotificationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationScope>();
  @override
  bool updateShouldNotify(NotificationScope oldWidget) =>
      repository != oldWidget.repository || intent != oldWidget.intent;
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.repository,
    required this.uid,
    required this.onOpen,
  });
  final NotificationRepository repository;
  final String uid;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: repository.watchUnread(uid),
    builder: (context, s) => IconButton(
      tooltip: 'Notifications',
      key: const ValueKey('notificationBell'),
      onPressed: onOpen,
      icon: Badge(
        isLabelVisible: (s.data ?? 0) > 0,
        label: Text((s.data ?? 0) > 99 ? '99+' : '${s.data ?? 0}'),
        child: const Icon(Icons.notifications_outlined),
      ),
    ),
  );
}

class MessageUnreadIcon extends StatefulWidget {
  const MessageUnreadIcon({
    super.key,
    required this.repository,
    required this.uid,
    this.selected = false,
  });
  final MessageReadRepository repository;
  final String uid;
  final bool selected;
  @override
  State<MessageUnreadIcon> createState() => _MessageUnreadIconState();
}

class _MessageUnreadIconState extends State<MessageUnreadIcon> {
  late Stream<int> _stream = widget.repository.watchUnreadMessages(widget.uid);
  @override
  void didUpdateWidget(MessageUnreadIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.repository != widget.repository) {
      _stream = widget.repository.watchUnreadMessages(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    key: ValueKey((widget.uid, widget.repository)),
    stream: _stream,
    builder: (context, s) {
      final count = s.data ?? 0;
      return Semantics(
        container: true,
        label: count > 0
            ? 'Messages, $count messages non lus'
            : 'Messages, aucun message non lu',
        child: ExcludeSemantics(
          child: Badge(
            key: const ValueKey('messageUnreadBadge'),
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 23,
              color: widget.selected
                  ? const Color(0xFF107865)
                  : const Color(0xFF70857F),
            ),
          ),
        ),
      );
    },
  );
}

class NotificationInbox extends StatefulWidget {
  const NotificationInbox({
    super.key,
    required this.repository,
    required this.uid,
    required this.onOpen,
    this.permission,
  });
  final NotificationRepository repository;
  final String uid;
  final Future<void> Function(String id) onOpen;
  final PushPermission? permission;
  @override
  State<NotificationInbox> createState() => _NotificationInboxState();
}

class _NotificationInboxState extends State<NotificationInbox> {
  final _loaded = <String, FoundiNotification>{};
  bool _more = true;
  String _filter = 'all';
  bool _busy = false;
  String? _error;
  late Stream<List<FoundiNotification>> _stream = widget.repository.watchInbox(
    widget.uid,
  );
  Future<void> _read(String id) async {
    await widget.repository.markRead(widget.uid, id);
    final n = _loaded[id];
    if (n != null) {
      _loaded[id] = FoundiNotification(
        id: n.id,
        type: n.type,
        category: n.category,
        title: n.title,
        body: n.body,
        createdAt: n.createdAt,
        readAt: DateTime.now(),
      );
    }
  }

  Future<void> _allRead() async {
    await widget.repository.markAllRead(widget.uid);
    _loaded.clear();
    _stream = widget.repository.watchInbox(widget.uid);
    _more = true;
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Action indisponible. Vérifie ta connexion puis réessaie.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _icon(String category) => switch (category) {
    'messages' => Icons.chat_bubble_outline,
    'account' => Icons.verified_user_outlined,
    'opportunities' => Icons.explore_outlined,
    _ => Icons.mark_email_unread_outlined,
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        IconButton(
          tooltip: 'Préférences push',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => NotificationSettings(
                repository: widget.repository,
                uid: widget.uid,
                permission: widget.permission,
              ),
            ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final entry in {
                'all': 'Tout',
                'unread': 'Non lues',
                'messages': 'Discussions',
                'proposals': 'Propositions',
                'opportunities': 'Pour moi',
                'account': 'Compte',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    onSelected: (_) => setState(() => _filter = entry.key),
                  ),
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : () => _act(_allRead),
            child: const Text('Tout marquer comme lu'),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
          child: StreamBuilder<List<FoundiNotification>>(
            stream: _stream,
            builder: (context, s) {
              if (s.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Notifications indisponibles.'),
                      TextButton(
                        onPressed: () => setState(
                          () => _stream = widget.repository.watchInbox(
                            widget.uid,
                          ),
                        ),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              for (final n in s.requireData) {
                _loaded[n.id] = n;
              }
              final all = _loaded.values.where((n) => n.isGeneral).toList()
                ..sort((a, b) {
                  final date = b.createdAt.compareTo(a.createdAt);
                  return date == 0 ? b.id.compareTo(a.id) : date;
                });
              final items = all
                  .where(
                    (n) =>
                        _filter == 'all' ||
                        (_filter == 'unread'
                            ? n.unread
                            : n.category == _filter),
                  )
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: [
                          Icon(Icons.notifications_none, size: 48),
                          SizedBox(height: 16),
                          Text('Rien à afficher'),
                          Text('Ton activité apparaîtra ici.'),
                        ],
                      ),
                    ),
                  for (final (index, n) in items.indexed) ...[
                    if (index == 0 ||
                        _today(items[index - 1].createdAt) !=
                            _today(n.createdAt))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _today(n.createdAt) ? "Aujourd’hui" : 'Plus tôt',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    Card(
                      color: n.unread ? const Color(0xFFE9F6EF) : Colors.white,
                      child: ListTile(
                        leading: Icon(_icon(n.category)),
                        title: Text(
                          n.title,
                          style: TextStyle(
                            fontWeight: n.unread
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text('${n.body}\n${_date(n.createdAt)}'),
                        isThreeLine: true,
                        trailing: n.unread
                            ? const Icon(
                                Icons.circle,
                                size: 9,
                                color: Color(0xFF087D68),
                              )
                            : null,
                        onTap: _busy
                            ? null
                            : () => _act(() async {
                                await _read(n.id);
                                await widget.onOpen(n.id);
                              }),
                      ),
                    ),
                  ],
                  if (_more && all.length >= 30)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _act(() async {
                              final page = await widget.repository.loadOlder(
                                widget.uid,
                                all.last.id,
                              );
                              for (final n in page) {
                                _loaded[n.id] = n;
                              }
                              _more = page.length == 30;
                            }),
                      child: const Text('Afficher plus'),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
  bool _today(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({
    super.key,
    required this.repository,
    required this.uid,
    this.permission,
  });
  final NotificationRepository repository;
  final String uid;
  final PushPermission? permission;
  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings>
    with WidgetsBindingObserver {
  late final _stream = widget.repository.watchPreferences(widget.uid);
  late Future<String> _status =
      widget.permission?.status() ??
      Future.value('Push disponibles sur Android et iOS.');
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _status = widget.permission?.status() ?? _status;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() {
          _status = widget.permission?.status() ?? _status;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible d’enregistrer. Réessaie.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Préférences de notifications')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Ces réglages concernent les push. Ton activité reste toujours consultable dans Foundi.',
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: _busy ? 4 : 0,
          child: _busy ? const LinearProgressIndicator() : null,
        ),
        _error == null ? const SizedBox.shrink() : Text(_error!),
        StreamBuilder<Map<String, bool>>(
          stream: _stream,
          builder: (context, s) {
            if (s.hasError) {
              return const Text(
                'Préférences indisponibles. Réouvre cet écran pour réessayer.',
              );
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                for (final entry in {
                  'messages': 'Messages',
                  'proposals': 'Propositions, décisions et recommandations',
                  'opportunities': 'Opportunités « Pour moi »',
                  'account': 'Compte professionnel',
                  'messagePreview':
                      'Afficher l’aperçu des messages dans les notifications',
                }.entries)
                  SwitchListTile(
                    title: Text(entry.value),
                    value:
                        s.requireData[entry.key] ??
                        entry.key != 'messagePreview',
                    onChanged: _busy
                        ? null
                        : (v) => _run(
                            () => widget.repository.savePreferences(
                              widget.uid,
                              {...s.requireData, entry.key: v},
                            ),
                          ),
                  ),
              ],
            );
          },
        ),
        const Divider(height: 40),
        FutureBuilder<String>(
          future: _status,
          builder: (context, s) => Text(
            s.data ??
                (s.hasError
                    ? 'État du téléphone indisponible.'
                    : 'Lecture des autorisations…'),
          ),
        ),
        if (widget.permission != null) ...[
          const SizedBox(height: 16),
          const Text(
            'Les alertes de messages affichent le nom de l’expéditeur. Active l’aperçu uniquement si tu souhaites aussi afficher le contenu sur ton téléphone, y compris sur l’écran verrouillé.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => _run(widget.permission!.enable),
            child: const Text('Activer les alertes sur ce téléphone'),
          ),
        ],
      ],
    ),
  );
}
