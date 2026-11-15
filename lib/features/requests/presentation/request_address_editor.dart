import 'package:flutter/material.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../professional/domain/professional_repository.dart';
import '../domain/request_location_repository.dart';

class RequestAddressChoice {
  const RequestAddressChoice(this.address, this.zoneId);
  final RequestInterventionAddress address;
  final String? zoneId;
}

Future<RequestAddressChoice?> editRequestAddress(
  BuildContext context, {
  RequestInterventionAddress? initial,
  RequestDetectedLocation? detected,
  List<String> selectedZones = const [],
  bool publicAddress = true,
}) => showModalBottomSheet<RequestAddressChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _RequestAddressEditor(
    initial: initial,
    detected: detected,
    selectedZones: selectedZones,
    publicAddress: publicAddress,
  ),
);

class _RequestAddressEditor extends StatefulWidget {
  const _RequestAddressEditor({
    this.initial,
    this.detected,
    required this.selectedZones,
    required this.publicAddress,
  });
  final RequestInterventionAddress? initial;
  final RequestDetectedLocation? detected;
  final List<String> selectedZones;
  final bool publicAddress;
  @override
  State<_RequestAddressEditor> createState() => _RequestAddressEditorState();
}

class _RequestAddressEditorState extends State<_RequestAddressEditor> {
  final _form = GlobalKey<FormState>();
  late final _line = TextEditingController(
    text: widget.detected?.addressLine ?? widget.initial?.line ?? '',
  );
  late String? _country =
      widget.detected?.countryCode ?? widget.initial?.countryCode;
  String? _zone;
  List<ReferenceChoice> get _zones => (widget.detected?.zones ?? [])
      .where((z) => (z.countryCode ?? 'CI') == _country)
      .toList();
  bool _canAdd(String id) =>
      widget.selectedZones.contains(id) || widget.selectedZones.length < 3;
  @override
  void initState() {
    super.initState();
    if (!const ['CI', 'FR'].contains(_country)) _country = null;
    final zones = _zones.where((z) => _canAdd(z.id)).toList();
    if (zones.length == 1) _zone = zones.single.id;
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      22,
      8,
      22,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.detected == null
                      ? 'Adresse d’intervention'
                      : 'Confirme ton adresse',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: FoundiUi.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.publicAddress
                ? 'Cette adresse sera visible sur les cartes publiques et le détail de ta demande, même sans compte Foundi. Vérifie-la et choisis uniquement les informations que tu souhaites publier.'
                : 'Cette adresse sera visible uniquement par toi et le professionnel destinataire de ta demande privée.',
          ),
          if (widget.detected != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.detected!.hasStreet && widget.detected!.hasNumber
                  ? 'Vérifie le numéro et la rue avant de confirmer.'
                  : 'Le numéro ou la rue n’a pas pu être identifié. Complète ou corrige l’adresse.',
            ),
            if (widget.detected!.accuracyMeters > 0)
              Text(
                'Précision estimée : ±${widget.detected!.accuracyMeters.ceil()} m. L’adresse proposée peut être approximative.',
                style: const TextStyle(fontSize: 12, color: FoundiUi.muted),
              ),
          ],
          const SizedBox(height: 18),
          TextFormField(
            key: const ValueKey('requestInterventionAddressLine'),
            controller: _line,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Adresse d’intervention',
              hintText: 'Numéro, rue, quartier ou repère, ville',
            ),
            validator: (v) => v == null || v.trim().length < 5
                ? 'Complète l’adresse.'
                : v.length > 500
                ? 'L’adresse est trop longue.'
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('requestInterventionAddressCountry'),
            initialValue: _country,
            decoration: const InputDecoration(labelText: 'Pays'),
            items: const [
              DropdownMenuItem(value: 'CI', child: Text('Côte d’Ivoire')),
              DropdownMenuItem(value: 'FR', child: Text('France')),
            ],
            validator: (v) => v == null ? 'Choisis le pays.' : null,
            onChanged: (v) => setState(() {
              _country = v;
              _zone = null;
            }),
          ),
          if (widget.detected != null) ...[
            const SizedBox(height: 18),
            const Text(
              'Zone proposée pour ta demande',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (_zones.isEmpty)
              const Text(
                'Aucune zone du catalogue ne correspond à cette position. Tu pourras choisir les zones de recherche manuellement.',
              ),
            for (final zone in _zones)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(zone.label),
                leading: Icon(
                  _zone == zone.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: FoundiUi.green,
                ),
                enabled: _canAdd(zone.id),
                onTap: _canAdd(zone.id)
                    ? () => setState(() => _zone = zone.id)
                    : null,
              ),
            if (widget.selectedZones.length >= 3)
              const Text(
                'Tes trois zones sont conservées. Retire une zone dans le formulaire pour en ajouter une autre.',
              ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            key: const ValueKey('confirmRequestInterventionAddress'),
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(
                context,
                RequestAddressChoice(
                  RequestInterventionAddress(
                    line: _line.text.trim(),
                    countryCode: _country!,
                  ),
                  _zone,
                ),
              );
            },
            child: const Text('Confirmer l’adresse'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    ),
  );
}
