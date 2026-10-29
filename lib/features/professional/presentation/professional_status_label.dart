import '../domain/professional_repository.dart';

String professionalStatusLabel(ProfessionalStatus status) => switch (status) {
  ProfessionalStatus.none => 'Compte client',
  ProfessionalStatus.draft => 'Dossier à compléter',
  ProfessionalStatus.pending => 'Vérification en attente',
  ProfessionalStatus.needsChanges => 'Corrections demandées',
  ProfessionalStatus.approved => 'Professionnel vérifié',
  ProfessionalStatus.rejected => 'Dossier refusé',
  ProfessionalStatus.suspended => 'Accès professionnel suspendu',
};
