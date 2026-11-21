import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/proposal_repository.dart';
import '../../professional/presentation/professional_badge.dart';

// A single live check for the visible list. Hide stale badges while rechecking,
// on backgrounding, and after errors; never infer certification from a role.
class LiveProposalCertifications extends StatefulWidget {
  const LiveProposalCertifications({
    super.key,
    required this.repository,
    required this.ids,
    required this.builder,
  });
  final ProposalRepository repository;
  final List<String> ids;
  final Widget Function(BuildContext, Map<String, bool>) builder;
  @override
  State<LiveProposalCertifications> createState() =>
      _LiveProposalCertificationsState();
}

class _LiveProposalCertificationsState extends State<LiveProposalCertifications>
    with WidgetsBindingObserver {
  Map<String, bool> _values = {};
  Timer? _timer;
  int _generation = 0;
  String get _signature => (widget.ids.toSet().toList()..sort()).join('|');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _refresh());
  }

  @override
  void didUpdateWidget(LiveProposalCertifications old) {
    super.didUpdateWidget(old);
    final oldSignature = (old.ids.toSet().toList()..sort()).join('|');
    if (old.repository != widget.repository || oldSignature != _signature) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    } else {
      _generation++;
      setState(() => _values = {});
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() => _values = {});
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final repository = widget.repository;
    if (repository is! ProposalCertificationRepository || widget.ids.isEmpty) {
      return;
    }
    try {
      final result = await (repository as ProposalCertificationRepository)
          .resolveCertifications(widget.ids.toSet().take(30).toList())
          .timeout(const Duration(seconds: 20));
      if (mounted && generation == _generation) {
        setState(() => _values = result);
      }
    } catch (_) {
      /* Fail closed; a later refresh can restore eligible badges. */
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _values);
}

Widget proposalBadge(Map<String, bool> values, String id) =>
    values[id] == true ? const ProfessionalBadge() : const SizedBox.shrink();
