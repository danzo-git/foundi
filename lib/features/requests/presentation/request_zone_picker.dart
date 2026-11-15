import 'package:flutter/material.dart';
import '../domain/request_location_repository.dart';
import '../data/device_request_location_repository.dart';
import '../../professional/domain/professional_repository.dart';
import '../../navigation/presentation/space_widgets.dart';
import 'request_address_editor.dart';

class RequestZonePicker extends StatefulWidget {
  const RequestZonePicker({
    super.key,
    required this.choices,
    required this.selected,
    required this.onChanged,
    this.locationRepository,
    this.interventionAddress,
    this.onAddressChanged,
    this.publicAddress = true,
  });
  final List<ReferenceChoice> choices;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final RequestLocationRepository? locationRepository;
  final RequestInterventionAddress? interventionAddress;
  final ValueChanged<RequestInterventionAddress?>? onAddressChanged;
  final bool publicAddress;
  @override
  State<RequestZonePicker> createState() => _RequestZonePickerState();
}

class _RequestZonePickerState extends State<RequestZonePicker> {
  bool _locating = false;
  List<ReferenceChoice> get choices => widget.choices;
  List<String> get selected => widget.selected;
  ValueChanged<List<String>> get onChanged => widget.onChanged;
  late final _device = DeviceRequestLocationRepository();
  RequestLocationRepository get _location =>
      widget.locationRepository ?? _device;
  Future<void> _editAddress({RequestDetectedLocation? detected}) async {
    final result = await editRequestAddress(
      context,
      initial: widget.interventionAddress,
      detected: detected,
      selectedZones: List.of(selected),
      publicAddress: widget.publicAddress,
    );
    if (!mounted || result == null) return;
    final id = result.zoneId;
    if (id != null &&
        choices.any(
          (z) =>
              z.id == id &&
              (z.countryCode ?? 'CI') == result.address.countryCode,
        ) &&
        !selected.contains(id) &&
        selected.length < 3) {
      onChanged([...selected, id]);
    }
    widget.onAddressChanged?.call(result.address);
  }

  Future<void> _locate() async {
    if (_locating) return;
    FocusScope.of(context).unfocus();
    setState(() => _locating = true);
    try {
      final location = _location;
      if (widget.onAddressChanged != null &&
          location is RequestAddressLocationRepository) {
        final result = await (location as RequestAddressLocationRepository)
            .locateAddress(choices);
        if (mounted) await _editAddress(detected: result);
        return;
      }
      final suggestions = await _location.suggest(choices);
      if (!mounted) return;
      String? choice = suggestions.length == 1 ? suggestions.first.id : null;
      final id = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Confirme ta zone'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cette zone est suggérée d’après ta position. Vérifie qu’elle correspond à ta recherche.',
                ),
                for (final zone in suggestions)
                  ListTile(
                    title: Text(zone.label),
                    leading: Icon(
                      choice == zone.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onTap: () => update(() => choice = zone.id),
                  ),
                if (selected.length >= 3)
                  const Text(
                    'Tu as déjà choisi trois zones. Retire une zone pour en ajouter une autre.',
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed:
                    choice == null ||
                        (!selected.contains(choice) && selected.length >= 3)
                    ? null
                    : () => Navigator.pop(context, choice),
                child: const Text('Utiliser cette zone'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || id == null || !choices.any((z) => z.id == id)) return;
      if (!selected.contains(id) && selected.length < 3) {
        onChanged([...selected, id]);
      }
    } catch (error) {
      if (!mounted) return;
      final failure = error is RequestLocationFailure
          ? error
          : const RequestLocationFailure(
              'Impossible de trouver ta zone. Choisis-la manuellement.',
            );
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choisis ta zone manuellement'),
          content: Text(failure.message),
          actions: [
            if (widget.onAddressChanged != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _editAddress();
                },
                child: const Text('Saisir une adresse'),
              ),
            if (failure.settings)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _location.openSettings();
                },
                child: const Text('Ouvrir les réglages'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _choose(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final next = [...selected];
    String search = '';
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.all(16),
          title: const Text('Zones de recherche'),
          content: SizedBox(
            width: 400,
            height: 380,
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('zoneSearch'),
                  decoration: const InputDecoration(
                    labelText: 'Rechercher une zone',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => update(() => search = v.toLowerCase()),
                ),
                const SizedBox(height: 8),
                Text('${next.length}/3 zones sélectionnées'),
                Expanded(
                  child: ListView(
                    children: [
                      for (final zone in choices.where(
                        (z) => z.label.toLowerCase().contains(search),
                      ))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(zone.label),
                          value: next.contains(zone.id),
                          onChanged: !next.contains(zone.id) && next.length >= 3
                              ? null
                              : (checked) => update(() {
                                  if (checked == true) {
                                    if (!next.contains(zone.id) &&
                                        next.length < 3) {
                                      next.add(zone.id);
                                    }
                                  } else {
                                    next.remove(zone.id);
                                  }
                                }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, next),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) => FormField<List<String>>(
    key: const ValueKey('requestZones'),
    initialValue: selected,
    validator: (_) =>
        selected.isEmpty ||
            selected.length > 3 ||
            selected.any((id) => !choices.any((z) => z.id == id))
        ? 'Choisis une à trois zones actives.'
        : widget.interventionAddress != null &&
              !selected.any(
                (id) => choices.any(
                  (z) =>
                      z.id == id &&
                      (z.countryCode ?? 'CI') ==
                          widget.interventionAddress!.countryCode,
                ),
              )
        ? 'Choisis au moins une zone dans le pays de ton adresse.'
        : null,
    builder: (field) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Zones de recherche *',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const Text('Choisis de 1 à 3 zones pour diffuser ta demande.'),
          Wrap(
            spacing: 8,
            children: [
              for (final id in selected)
                InputChip(
                  label: Text(
                    choices.where((z) => z.id == id).firstOrNull?.label ??
                        'Zone indisponible',
                  ),
                  onDeleted: () => onChanged([...selected]..remove(id)),
                ),
            ],
          ),
          OutlinedButton.icon(
            key: const ValueKey('chooseRequestZones'),
            onPressed: () => _choose(context),
            icon: const Icon(Icons.place_outlined),
            label: const Text('Choisir les zones'),
          ),
          if (field.hasError)
            Text(
              field.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextButton.icon(
            onPressed: _locating ? null : _locate,
            icon: const Icon(Icons.my_location),
            label: Text(
              _locating
                  ? 'Recherche de ta position…'
                  : 'Utiliser ma position actuelle',
            ),
          ),
          Text(
            widget.onAddressChanged == null
                ? 'Position utilisée uniquement pour cette suggestion. Seules les zones confirmées seront publiées.'
                : 'Vérifie l’adresse détectée avant de la confirmer. Tu peux aussi la saisir ou la corriger manuellement.',
            style: TextStyle(fontSize: 12),
          ),
          if (widget.onAddressChanged != null) ...[
            const SizedBox(height: 12),
            if (widget.interventionAddress != null)
              FoundiPanel(
                color: FoundiUi.tint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Adresse d’intervention',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(widget.interventionAddress!.line),
                    const SizedBox(height: 6),
                    Text(
                      widget.publicAddress
                          ? 'Visible sur les cartes publiques de ta demande.'
                          : 'Visible uniquement par toi et le professionnel destinataire.',
                      style: TextStyle(fontSize: 12),
                    ),
                    TextButton(
                      onPressed: () => widget.onAddressChanged!(null),
                      child: const Text('Retirer cette adresse'),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: _locating ? null : () => _editAddress(),
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: Text(
                widget.interventionAddress == null
                    ? 'Renseigner une adresse d’intervention'
                    : 'Modifier l’adresse d’intervention',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
