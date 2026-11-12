const {createHash} = require('node:crypto');
const key = (...parts) => createHash('sha256').update(parts.join('\0')).digest('hex');
const internalId = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
const isPrivateMessage = value => ['message.created','chat_message'].includes(value?.type);
function cleanPreview(value, length = 100) {
  const text = String(value || '').replace(/\s+/gu,' ').replace(/[\p{Cc}\u061c\u200b\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]/gu,'').trim();
  const parts = [...new Intl.Segmenter('fr',{granularity:'grapheme'}).segment(text)].map(s=>s.segment);
  return parts.length > length ? parts.slice(0,length-1).join('')+'…' : text;
}
function messagePushContent(message, name, preview) {
  const title = cleanPreview(name,80) || 'Un utilisateur Foundi';
  const body = !preview ? 'Nouveau message' : ({image:'📷 Photo',pdf:'📄 Document PDF',contact:'📞 Contact partagé'}[message.type] || cleanPreview(message.text,100) || 'Nouveau message');
  return {title,body};
}
const catalog = Object.freeze({
  'professional.approved': ['account', 'Profil professionnel approuvé', 'Ton statut professionnel a été mis à jour.'],
  'professional.rejected': ['account', 'Décision concernant ton dossier', 'Consulte le suivi de ton dossier professionnel.'],
  'professional.more_info_requested': ['account', 'Dossier à compléter', 'Consulte le suivi de ton dossier professionnel.'],
  'professional.suspended': ['account', 'Statut professionnel mis à jour', 'Consulte le suivi de ton dossier professionnel.'],
  'proposal.created': ['proposals', 'Nouvelle proposition', 'Un professionnel a répondu à ta demande.'],
  'request.direct_received': ['proposals', 'Nouvelle demande directe', 'Une personne t’a envoyé une demande privée sur Foundi.'],
  'request.recommended': ['proposals', 'Professionnel recommandé', 'Un professionnel vérifié a été recommandé pour ta demande.'],
  'request.recommendation_received': ['proposals', 'On t’a recommandé pour une demande', 'Consulte la demande dans Explorer.'],
  'proposal.retained': ['proposals', 'Proposition retenue', 'Le client a retenu ta proposition.'],
  'proposal.rejected': ['proposals', 'Proposition refusée', 'Le client a décliné ta proposition.'],
  'conversation.opened': ['messages', 'Discussion ouverte', 'Un client souhaite discuter de ta proposition.'],
  'message.created': ['messages', 'Nouveau message', 'Tu as reçu un nouveau message.'],
  'request.closed': ['proposals', 'Demande clôturée', 'La demande est clôturée. Les historiques restent accessibles.'],
  'request.matched': ['opportunities', 'Nouvelles opportunités pour toi', 'De nouvelles demandes correspondent à tes spécialités et zones.'],
});

// This is deliberately the exact FOUN-52 policy (zone IDs, not GPS or ancestor expansion).
function matchesOpportunity(request, profile, catalogData) {
  if (request?.status !== 'published' || profile?.status !== 'approved') return false;
  const category = catalogData?.categories?.find(c => c.id === request.categoryId);
  if (!category || !profile.categoryIds?.includes(request.categoryId) || !profile.zoneIds?.includes(request.zoneId)) return false;
  return category.specialties?.length
    ? category.specialties.some(s => s.id === request.specialtyId) && !!profile.specialtyIds?.includes(request.specialtyId)
    : request.specialtyId === '';
}

function professionalType(audit) {
  if (audit.from === 'pending') return ({approved:'professional.approved', rejected:'professional.rejected', needs_changes:'professional.more_info_requested'})[audit.to];
  if (audit.from === 'approved' && audit.to === 'suspended') return 'professional.suspended';
  return undefined;
}
function decisionType(audit) {
  if (audit.action === 'retain' && audit.status === 'retained' && audit.previousRetainedProposalId !== audit.proposalId) return 'proposal.retained';
  if (audit.action === 'reject' && audit.status === 'rejected') return 'proposal.rejected';
  return undefined;
}
module.exports = {key, internalId, catalog, matchesOpportunity, professionalType, decisionType, isPrivateMessage, cleanPreview, messagePushContent};
