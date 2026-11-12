const { createHash } = require('node:crypto');
const sharp = require('sharp');
const { OtpError, requireUid } = require('./auth-validation');

const maxInputBytes = 2 * 1024 * 1024;
// Eight base64 photos at this cap leave room under Firestore's 1 MiB limit.
const maxPhotoBytes = 80 * 1024;
const maxGallery = 6;
const idPattern = /^[a-zA-Z0-9_-]{1,128}$/;
const contactPattern = /@|(?<!\d)(?:\d[\s().+-]*){7}\d/u;
const pathFor = (uid) => `professionalProfiles/${uid}/showcase/profile`;

function fail(code, message) {
  throw new OtpError(code, message);
}

function publicText(value, maximum, required = false) {
  if (typeof value !== 'string' || value.trim().length > maximum ||
      (required && value.trim().length < 2)) {
    fail('invalid-argument', 'Vérifie les champs de ton profil.');
  }
  const text = value.trim();
  if (contactPattern.test(text)) {
    fail('invalid-argument', 'Garde ton e-mail et ton numéro dans les informations personnelles.');
  }
  return text;
}

function photoInput(value) {
  if (value && typeof value === 'object') {
    if (Object.keys(value).length === 1 && typeof value.id === 'string' && /^[a-f0-9]{64}$/.test(value.id)) {
      return { id: value.id };
    }
    if (Object.keys(value).length === 1 && typeof value.base64 === 'string' &&
        value.base64.length <= Math.ceil(maxInputBytes / 3) * 4) {
      return { base64: value.base64 };
    }
  }
  fail('invalid-argument', 'Choisis une image JPEG, PNG ou WebP de 2 Mio maximum.');
}

async function preparePhoto(input) {
  if (!input || input.id) return input;
  const bytes = Buffer.from(input.base64, 'base64');
  if (!bytes.length || bytes.length > maxInputBytes || bytes.toString('base64') !== input.base64) {
    fail('invalid-argument', 'Image illisible ou trop volumineuse.');
  }
  try {
    const image = sharp(bytes, { limitInputPixels: 20000000, failOn: 'warning' });
    const info = await image.metadata();
    if (!['jpeg', 'png', 'webp'].includes(info.format) || (info.pages || 1) !== 1) {
      fail('invalid-argument', 'Choisis une image JPEG, PNG ou WebP fixe.');
    }
    for (const [size, quality] of [[1200, 80], [960, 73], [720, 68], [480, 60]]) {
      const result = await image.clone().rotate().resize({
        width: size, height: size, fit: 'inside', withoutEnlargement: true,
      }).flatten({ background: '#ffffff' }).jpeg({ quality }).toBuffer();
      if (result.length <= maxPhotoBytes) {
        return { id: createHash('sha256').update(result).digest('hex'), base64: result.toString('base64') };
      }
    }
  } catch (error) {
    if (error instanceof OtpError) throw error;
  }
  fail('invalid-argument', 'Cette image ne peut pas être traitée. Choisis une autre photo.');
}

function showcaseProjection(profile) {
  if (!profile) return null;
  const photo = (item) => item ? { id: item.id, base64: item.base64 } : null;
  return {
    revision: profile.revision,
    name: profile.name,
    trade: profile.trade,
    area: profile.area,
    bio: profile.bio,
    portrait: photo(profile.portrait),
    cover: photo(profile.cover),
    gallery: profile.gallery.map(photo),
  };
}

function createProfessionalShowcaseService({ store, auth }) {
  async function verify(uid) {
    const account = await auth.getUser(requireUid(uid));
    if (account.disabled || !account.emailVerified) {
      fail('permission-denied', 'Un compte actif avec une adresse vérifiée est nécessaire.');
    }
  }

  async function read(uid, proposalId) {
    await verify(uid);
    if (proposalId !== undefined && (typeof proposalId !== 'string' || !idPattern.test(proposalId))) {
      fail('invalid-argument', 'Proposition invalide.');
    }
    return store.transaction(async (tx) => {
      let professionalUid = uid;
      if (proposalId !== undefined) {
        const proposal = await tx.get(`proposals/${proposalId}`);
        if (!proposal || proposal.clientUid !== uid) {
          fail('permission-denied', 'Ce profil est réservé au client de la proposition.');
        }
        professionalUid = proposal.professionalUid;
      }
      const professional = await tx.get(`professionalProfiles/${professionalUid}`);
      if (professional?.status !== 'approved') {
        if (proposalId !== undefined) return null;
        fail('permission-denied', 'Ton dossier professionnel doit être approuvé.');
      }
      const profile = showcaseProjection(await tx.get(pathFor(professionalUid)));
      if (!profile || proposalId === undefined) return profile;
      const { directRequestActivity } = require('./direct-request-context');
      const catalog = await tx.get('referenceData/professionalOnboarding');
      return { ...profile, professionalId: professionalUid, requestActivity: directRequestActivity(professional, catalog) };
    });
  }

  async function save(uid, input) {
    await verify(uid);
    if (!input || !Number.isSafeInteger(input.revision) || input.revision < 0 ||
        !Array.isArray(input.gallery) || input.gallery.length > maxGallery) {
      fail('invalid-argument', 'Le profil peut contenir jusqu’à six réalisations.');
    }
    const text = {
      name: publicText(input.name, 65, true),
      trade: publicText(input.trade, 85, true),
      area: publicText(input.area, 100),
      bio: publicText(input.bio, 500),
    };
    const portrait = input.portrait == null ? null : photoInput(input.portrait);
    const cover = input.cover == null ? null : photoInput(input.cover);
    const gallery = input.gallery.map(photoInput);
    const mutation = createHash('sha256')
      .update(JSON.stringify({ revision: input.revision, text, portrait, cover, gallery }))
      .digest('hex');
    const path = pathFor(uid);
    async function current(tx) {
      const professional = await tx.get(`professionalProfiles/${uid}`);
      if (professional?.status !== 'approved') {
        fail('permission-denied', 'Ton dossier professionnel doit être approuvé.');
      }
      const previous = await tx.get(path);
      if (previous?.mutation !== mutation && (previous?.revision ?? 0) !== input.revision) {
        fail('aborted', 'Le profil a été modifié ailleurs. Rouvre-le avant d’enregistrer.');
      }
      return previous;
    }
    // Check approval and revision before doing CPU-intensive work, then recheck
    // in the commit transaction in case either changed during image processing.
    const previous = await store.transaction(current);
    if (previous?.mutation === mutation) return showcaseProjection(previous);
    const prepared = [];
    for (const item of [portrait, cover, ...gallery]) prepared.push(await preparePhoto(item));
    return store.transaction(async (tx) => {
      const previous = await current(tx);
      if (previous?.mutation === mutation) return showcaseProjection(previous);
      const existing = [previous?.portrait, previous?.cover, ...(previous?.gallery ?? [])];
      const photos = prepared.map((item) => {
        if (!item || item.base64) return item;
        const saved = existing.find((photo) => photo?.id === item.id);
        if (!saved) fail('invalid-argument', 'Cette photo n’appartient pas à ton profil.');
        return saved;
      });
      const next = {
        ...text,
        revision: input.revision + 1,
        mutation,
        portrait: photos[0],
        cover: photos[1],
        gallery: photos.slice(2),
      };
      tx.set(path, next);
      return showcaseProjection(next);
    });
  }

  return { read, save };
}

module.exports = { createProfessionalShowcaseService, showcaseProjection };
