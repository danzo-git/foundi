const { createHash, randomUUID } = require('node:crypto');
const sharp = require('sharp');
const { OtpError, requireUid } = require('./auth-validation');
const { checkMagic } = require('./attachment-validation');

const hour = 3600000;
const day = 24 * hour;
const lease = 3 * 60000;
const maxBytes = 5 * 1024 * 1024;
const maxStoredBytes = 1024 * 1024;
const requestPattern = /^[a-zA-Z0-9_-]{20,80}$/;
const photoPattern = /^[a-f0-9]{32}$/;
const formats = { 'image/jpeg': 'jpeg', 'image/png': 'png', 'image/webp': 'webp' };
const manifestPath = (id) => `requestPhotoDrafts/${id}`;
const photoPath = (id, photoId) => `requestPhotoFiles/${id}_${photoId}`;
const ownPath = (uid, id) => `userRequests/${uid}/items/${id}`;
const storagePath = (p) => `requestPhotos/${p.uid}/${p.requestId}/${p.photoId}/${p.objectId}.webp`;
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

function fail(code, message) {
  throw new OtpError(code, message);
}

function checkRequest(id) {
  if (typeof id !== 'string' || !requestPattern.test(id)) {
    fail('invalid-argument', 'Demande invalide.');
  }
}

function photoIds(value) {
  if (!Array.isArray(value) || value.length > 3 || new Set(value).size !== value.length ||
      value.some((id) => typeof id !== 'string' || !photoPattern.test(id))) {
    fail('invalid-argument', 'Choisis jusqu’à trois photos distinctes.');
  }
  return value;
}

async function normalize(bytes, type) {
  try {
    const image = sharp(bytes, { limitInputPixels: 20000000, failOn: 'warning' });
    const info = await image.metadata();
    if (formats[type] !== info.format ||
        !info.width || !info.height || info.width * info.height > 20000000 ||
        (info.pages || 1) !== 1) {
      fail('invalid-argument', 'Choisis une photo JPEG, PNG ou WebP fixe et lisible.');
    }
    const resized = image.rotate().resize({
      width: 1440, height: 1440, fit: 'inside', withoutEnlargement: true,
    });
    const result = await resized.webp({ quality: 78 }).toBuffer();
    if (result.length <= maxStoredBytes) return result;
  } catch (error) {
    if (error instanceof OtpError) throw error;
  }
  fail('invalid-argument', 'Cette photo est illisible ou trop complexe. Choisis une autre image.');
}

function createRequestPhotoService({ store, auth, files, clock = Date.now, newId = randomUUID }) {
  async function account(uid) {
    const user = await auth.getUser(requireUid(uid));
    if (user.disabled || user.emailVerified !== true) {
      fail('permission-denied', 'Un compte actif avec une adresse vérifiée est nécessaire.');
    }
  }

  async function limits(tx, uid, now) {
    const path = `requestPhotoLimits/${uid}`;
    const current = await tx.get(path);
    const date = Math.floor(now / day);
    const value = current?.date === date ? current : { date, uploads: 0, bytes: 0, reads: 0 };
    return { path, value };
  }

  async function upload(uid, requestId, photoId, bytes, type) {
    await account(uid);
    checkRequest(requestId);
    photoIds([photoId]);
    if (typeof type !== 'string' || !Object.hasOwn(formats, type) ||
        !Buffer.isBuffer(bytes) || !bytes.length || bytes.length > maxBytes) {
      fail('invalid-argument', 'Choisis une photo JPEG, PNG ou WebP de 5 Mio maximum.');
    }
    checkMagic(bytes, type);
    const digest = sha256(bytes);
    const path = photoPath(requestId, photoId);
    const attempt = newId();
    const reserved = await store.transaction(async (tx) => {
      const now = clock();
      const own = await tx.get(ownPath(uid, requestId));
      const published = await tx.get(`requests/${requestId}`) || await tx.get(`directRequests/${requestId}`);
      if (own) {
        if (own.status !== 'published' || published?.status !== 'published' || own.createdAt !== published.createdAt) {
          fail('failed-precondition', 'Cette demande n’est plus modifiable.');
        }
        if (own.photoIds?.includes(photoId)) return { published: true };
      }
      if (published && !own) fail('permission-denied', 'Cette demande ne t’appartient pas.');
      const manifest = await tx.get(manifestPath(requestId));
      const previous = await tx.get(path);
      const { path: limitPath, value } = await limits(tx, uid, now);
      if (manifest && manifest.uid !== uid) fail('permission-denied', 'Cette demande ne t’appartient pas.');
      if (previous && (previous.uid !== uid || previous.digest !== digest ||
          !['pending', 'uploading', 'ready'].includes(previous.state))) {
        fail('failed-precondition', 'Retire cette photo et sélectionne-la à nouveau.');
      }
      const ids = (manifest?.ids ?? []).filter((id) => !own?.photoIds?.includes(id));
      if (!ids.includes(photoId) && ids.length >= 3) {
        fail('resource-exhausted', 'Retire une photo avant d’en ajouter une autre.');
      }
      if (previous?.state === 'uploading' && previous.leaseUntil > now) {
        fail('failed-precondition', 'L’envoi de cette photo est encore en cours. Réessaie dans un instant.');
      }
      if (value.uploads >= 40 || value.bytes + bytes.length > 100 * 1024 * 1024) {
        fail('resource-exhausted', 'La limite d’envoi de photos est atteinte pour aujourd’hui.');
      }
      tx.set(limitPath, { ...value, uploads: value.uploads + 1, bytes: value.bytes + bytes.length });
      if (previous?.state === 'ready' && previous.deleteAt > now) return { ready: true };
      const record = {
        uid, requestId, photoId, digest, objectId: previous?.objectId ?? attempt, attempt,
        state: 'uploading', leaseUntil: now + lease, deleteAt: now + day,
      };
      tx.set(path, record);
      tx.set(manifestPath(requestId), { uid, ids: ids.includes(photoId) ? ids : [...ids, photoId] });
      return { record };
    });
    if (!reserved.record) return reserved;
    const record = reserved.record;
    try {
      const image = await normalize(bytes, type);
      const generation = await files.save(storagePath(record), image, sha256(image));
      await store.transaction(async (tx) => {
        const current = await tx.get(path);
        if (current?.attempt !== attempt || current.state !== 'uploading') {
          fail('failed-precondition', 'Cet envoi a été remplacé ou retiré.');
        }
        tx.set(path, { ...current, state: 'ready', generation });
      });
      return { ready: true };
    } catch (error) {
      await store.transaction(async (tx) => {
        const current = await tx.get(path);
        if (current?.attempt === attempt && current.state === 'uploading') {
          tx.set(path, { ...current, state: 'pending' });
        }
      }).catch(() => {});
      throw error;
    }
  }

  async function discard(uid, requestId, ids) {
    await account(uid);
    checkRequest(requestId);
    photoIds(ids);
    return store.transaction(async (tx) => {
      const manifest = await tx.get(manifestPath(requestId));
      if (!manifest) return { discarded: true };
      if (manifest.uid !== uid) fail('permission-denied', 'Cette demande ne t’appartient pas.');
      const paths = ids.filter((id) => manifest.ids.includes(id)).map((id) => photoPath(requestId, id));
      const records = await Promise.all(paths.map((path) => tx.get(path)));
      const removed = [];
      for (let i = 0; i < records.length; i++) {
        const p = records[i];
        if (!p || !['ready', 'pending', 'uploading'].includes(p.state)) continue;
        tx.set(paths[i], { ...p, state: 'discarded', deleteAt: Math.max(clock(), p.leaseUntil) });
        removed.push(p.photoId);
      }
      if (removed.length) tx.set(manifestPath(requestId), {
        ...manifest, ids: manifest.ids.filter((id) => !removed.includes(id)),
      });
      return { discarded: true };
    });
  }

  async function link(tx, uid, requestId, ids, now) {
    photoIds(ids);
    if (!ids.length) return;
    const manifest = await tx.get(manifestPath(requestId));
    if (manifest?.uid !== uid || ids.some((id) => !manifest.ids.includes(id))) {
      fail('failed-precondition', 'Une photo est indisponible. Renvoie-la avant de publier.');
    }
    const paths = ids.map((id) => photoPath(requestId, id));
    const records = await Promise.all(paths.map((path) => tx.get(path)));
    if (records.some((p) => p?.uid !== uid || p.state !== 'ready' ||
        !p.generation || p.deleteAt <= now)) {
      fail('failed-precondition', 'Une photo est indisponible. Renvoie-la avant de publier.');
    }
    for (let i = 0; i < paths.length; i++) {
      tx.set(paths[i], { ...records[i], state: 'linked', deleteAt: null });
    }
  }

  async function scheduleDelete(tx, uid, requestId, ids) {
    const paths = ids.map((id) => photoPath(requestId, id));
    const records = await Promise.all(paths.map((path) => tx.get(path)));
    for (let i = 0; i < paths.length; i++) {
      const p = records[i];
      if (p?.uid === uid && p.state === 'linked') {
        tx.set(paths[i], { ...p, state: 'discarded', deleteAt: clock() });
      }
    }
  }

  async function replace(tx, uid, requestId, previousIds, ids, now) {
    photoIds(ids);
    const manifest = await tx.get(manifestPath(requestId));
    const allIds = [...new Set([...previousIds, ...ids])];
    const paths = allIds.map((id) => photoPath(requestId, id));
    const records = await Promise.all(paths.map((path) => tx.get(path)));
    for (const id of ids) {
      const record = records[allIds.indexOf(id)];
      const retained = previousIds.includes(id);
      if (record?.uid !== uid || !record.generation ||
          (retained ? record.state !== 'linked' :
            record.state !== 'ready' || record.deleteAt <= now ||
            manifest?.uid !== uid || !manifest.ids.includes(id))) {
        fail('failed-precondition', 'Une photo est indisponible. Renvoie-la avant d’enregistrer.');
      }
    }
    for (let i = 0; i < allIds.length; i++) {
      const record = records[i];
      if (ids.includes(allIds[i])) {
        if (record.state !== 'linked') tx.set(paths[i], { ...record, state: 'linked', deleteAt: null });
      } else if (record?.uid === uid && record.state === 'linked') {
        tx.set(paths[i], { ...record, state: 'discarded', deleteAt: now });
      }
    }
    if (manifest?.uid === uid) {
      tx.set(manifestPath(requestId), { ...manifest, ids: manifest.ids.filter((id) => !allIds.includes(id)) });
    }
  }

  async function publishedPhoto(tx, requestId, photoId, publicOnly = false) {
    const request = await tx.get(`requests/${requestId}`) || (!publicOnly && await tx.get(`directRequests/${requestId}`));
    if (request?.status !== 'published' || !request.photoIds?.includes(photoId) ||
        (publicOnly && request.photosPublic !== true)) {
      fail('not-found', 'Cette photo est indisponible.');
    }
    const photo = await tx.get(photoPath(requestId, photoId));
    if (photo?.state !== 'linked' || !photo.generation) fail('not-found', 'Cette photo est indisponible.');
    return { ...photo, directRequest: request.visibility === 'direct' ? request : null };
  }

  async function readPublic(requestId, photoId) {
    checkRequest(requestId);
    photoIds([photoId]);
    const authorize = (tx) => publishedPhoto(tx, requestId, photoId, true);
    const photo = await store.transaction(authorize);
    const bytes = await files.read(storagePath(photo), photo.generation);
    await store.transaction(authorize);
    return bytes;
  }

  async function read(uid, requestId, photoId) {
    await account(uid);
    checkRequest(requestId);
    photoIds([photoId]);
    const authorize = async (tx) => {
      const photo = await publishedPhoto(tx, requestId, photoId);
      if (photo.directRequest && uid !== photo.directRequest.clientUid &&
          (uid !== photo.directRequest.directProfessionalId || (await tx.get(`professionalProfiles/${uid}`))?.status !== 'approved')) {
        fail('permission-denied', 'Cette photo est privée.');
      }
      if (photo.uid !== uid && (await tx.get(`professionalProfiles/${uid}`))?.status !== 'approved') {
        fail('permission-denied', 'Ces photos sont réservées à l’auteur et aux professionnels approuvés.');
      }
      return photo;
    };
    const photo = await store.transaction(async (tx) => {
      const p = await authorize(tx);
      const { path, value } = await limits(tx, uid, clock());
      if (value.reads >= 300) fail('resource-exhausted', 'La limite de consultation des photos est atteinte pour aujourd’hui.');
      tx.set(path, { ...value, reads: value.reads + 1 });
      return p;
    });
    const bytes = await files.read(storagePath(photo), photo.generation);
    await store.transaction(authorize);
    return bytes;
  }

  async function cleanup() {
    const candidates = await store.expiredRequestPhotos(clock(), 150);
    let removed = 0;
    let failed = 0;
    for (const path of candidates) {
      const photo = await store.transaction(async (tx) => {
        const p = await tx.get(path);
        if (!p || p.state === 'linked' || p.deleteAt == null || p.deleteAt > clock()) return null;
        tx.set(path, { ...p, state: 'deleting' });
        return p;
      });
      if (!photo) continue;
      try {
        await files.remove(storagePath(photo));
        await store.transaction(async (tx) => {
          const current = await tx.get(path);
          if (current?.objectId !== photo.objectId || current.state !== 'deleting') return;
          const manifest = await tx.get(manifestPath(photo.requestId));
          if (manifest?.uid === photo.uid) {
            const ids = manifest.ids.filter((id) => id !== photo.photoId);
            if (ids.length) tx.set(manifestPath(photo.requestId), { ...manifest, ids });
            else tx.delete(manifestPath(photo.requestId));
          }
          tx.delete(path);
        });
        removed++;
      } catch {
        failed++;
        await store.transaction(async (tx) => {
          const current = await tx.get(path);
          if (current?.objectId === photo.objectId && current.state === 'deleting') {
            tx.set(path, { ...current, deleteAt: clock() + hour });
          }
        });
      }
    }
    return { removed, failed };
  }

  return { upload, discard, link, replace, scheduleDelete, read, readPublic, cleanup };
}

module.exports = { createRequestPhotoService, photoIds };
