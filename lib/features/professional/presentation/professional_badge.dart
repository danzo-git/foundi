import 'package:flutter/material.dart';
import '../../navigation/presentation/space_widgets.dart';

const badgeExplanation = 'Profil professionnel vérifié par Foundi';
const badgeDisclaimer =
    'Le badge indique une vérification, mais ne garantit pas la qualité ou la sécurité d’une prestation.';

class ProfessionalBadge extends StatelessWidget {
  const ProfessionalBadge({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Professionnel vérifié. Comprendre le badge Foundi',
    button: true,
    child: Tooltip(
      message: badgeExplanation,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          useSafeArea: true,
          isScrollControlled: true,
          builder: (context) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified, color: FoundiUi.green, size: 36),
                SizedBox(height: 16),
                Text(
                  badgeExplanation,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(badgeDisclaimer),
              ],
            ),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Icon(Icons.verified, color: FoundiUi.green, size: 22),
        ),
      ),
    ),
  );
}

class CertificationInfoCard extends StatelessWidget {
  const CertificationInfoCard({super.key, required this.onDismiss});
  final VoidCallback onDismiss;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('certificationInfoCard'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD8F5DF), Color(0xFFDCF5EF), Color(0xFFF7FAE9)],
      ),
      border: Border.all(color: const Color(0xFFB3DBC5)),
      boxShadow: [
        BoxShadow(
          color: FoundiUi.green.withValues(alpha: .08),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: FoundiUi.ink, height: 1.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFEDAD),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD66F).withValues(alpha: .3),
                      blurRadius: 16,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 30,
                  color: FoundiUi.green,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Comprendre le badge Foundi',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF275A43),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fermer l’explication',
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close,
                  size: 19,
                  color: Color(0xFF275A43),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Pourquoi choisir un professionnel certifié ?',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sur Foundi, tout le monde peut vous proposer une solution. Certains profils disposent d’un badge de certification.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final blocks = [
                const _ProfileBlock(professional: true),
                const _ProfileBlock(professional: false),
              ];
              if (constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19) {
                return Column(
                  children: [blocks[0], const SizedBox(height: 8), blocks[1]],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: blocks[0]),
                  const SizedBox(width: 8),
                  Expanded(child: blocks[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 17, color: Color(0xFF275A43)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(badgeDisclaimer, style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileBlock extends StatelessWidget {
  const _ProfileBlock({required this.professional});
  final bool professional;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: professional ? const Color(0xFFC0EED5) : const Color(0xFFFFFDF5),
      border: Border.all(
        color: professional ? const Color(0xFF89CDA8) : const Color(0xFFE4E8DD),
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          professional ? Icons.verified : Icons.person_outline,
          color: professional ? FoundiUi.green : const Color(0xFF52616A),
          size: 24,
        ),
        const SizedBox(height: 6),
        Text(
          professional ? 'Professionnel vérifié' : 'Particulier',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          professional
              ? 'Son profil a été vérifié par Foundi : un repère de confiance supplémentaire.'
              : 'Il peut aussi répondre à vos demandes, sans cette vérification professionnelle.',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
