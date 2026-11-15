const UNCLASSIFIED_CATEGORY = 'foundi_other';
function requestZones(request) {
  return Array.isArray(request?.zoneIds) ? request.zoneIds : request?.zoneId ? [request.zoneId] : [];
}
function unclassified(category) {
  return category?.id === UNCLASSIFIED_CATEGORY && category?.requestOnly === true;
}
function matchesOpportunity(request, profile, catalog) {
  if (request?.status !== 'published' || profile?.status !== 'approved') return false;
  const category = catalog?.categories?.find(c => c.id === request.categoryId && c.active !== false);
  if (!category || !requestZones(request).some(id => profile.zoneIds?.includes(id))) return false;
  if (unclassified(category)) return request.specialtyId === '';
  if (!profile.categoryIds?.includes(category.id)) return false;
  if (request.specialtyId === '') return true;
  return !!category.specialties?.some(s => s.id === request.specialtyId && s.active !== false) && !!profile.specialtyIds?.includes(request.specialtyId);
}
module.exports = {UNCLASSIFIED_CATEGORY, requestZones, unclassified, matchesOpportunity};
