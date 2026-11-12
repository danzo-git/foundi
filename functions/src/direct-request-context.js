// Only public activity references are exposed by professional profile reads.
// Use the professional's configured order, never the client's selections.
function directRequestActivity(profile, catalog) {
  if (catalog?.enabled !== true) return null;
  for (const categoryId of profile?.categoryIds ?? []) {
    const category = catalog.categories?.find(c => c.id === categoryId && c.active !== false);
    if (!category) continue;
    const specialties = (category.specialties ?? []).filter(s => s.active !== false);
    const specialty = (profile.specialtyIds ?? [])
      .map(id => specialties.find(s => s.id === id)).find(Boolean);
    if (specialties.length && !specialty) continue;
    return { categoryId, categoryLabel: category.label,
      specialtyId: specialty?.id ?? '', specialtyLabel: specialty?.label ?? '' };
  }
  return null;
}

function accountRequesterName(profile, account) {
  for (const value of [profile?.fullName, account?.displayName]) {
    if (typeof value !== 'string') continue;
    const name = value.trim().normalize('NFC').replace(/\s+/gu, ' ');
    if (name.length >= 2 && name.length <= 100 && /\p{L}/u.test(name) &&
        !/[@\p{C}]|(?<!\p{Nd})(?:\p{Nd}[\s().+\-]*){7}\p{Nd}/u.test(name)) return name;
  }
  return null;
}

module.exports = { directRequestActivity, accountRequesterName };
