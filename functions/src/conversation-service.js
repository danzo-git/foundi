const { OtpError, requireUid } = require('./auth-validation');
const fail = (code, message) => { throw new OtpError(code, message); };
const idOK = id => typeof id === 'string' && /^[a-zA-Z0-9_-]{20,80}$/.test(id);
const proposalIdOK = id => typeof id === 'string' && /^[a-f0-9]{64}$/.test(id);
const publicFields = ['title','description','categoryId','categoryLabel','specialtyId','specialtyLabel','zoneId','zoneLabel','budget','status','createdAt','updatedAt'];
const proposalOf = chat => chat.proposalId || chat.selectedProposalId;
function linked(chat, p, id) {
  return chat && chat.requestId === p.requestId && proposalOf(chat) === id && chat.clientUid === p.clientUid && chat.professionalUid === p.professionalUid;
}
async function readConversation(tx, uid, id) {
  const chat = await tx.get(`conversations/${id}`);
  if (!chat || ![chat.clientUid,chat.professionalUid].includes(uid)) fail('permission-denied', 'Cette discussion est privée.');
  const own = await tx.get(`userRequests/${chat.clientUid}/items/${chat.requestId}`);
  const p = await tx.get(`proposals/${proposalOf(chat)}`);
  const writable = chat.status === 'active' && own && ['published','closed','in_discussion'].includes(own.status) &&
    p && linked(chat,p,proposalOf(chat)) && p.conversationId === id && ['discussing','retained','selected'].includes(p.status);
  return {chat,own,p,writable:!!writable};
}
function createConversationService({ store, auth, clock = () => Date.now(), onSendTiming = () => {} }) {
  async function account(uid) {
    requireUid(uid);
    const a = await auth.getUser(uid);
    if (a.disabled || !a.emailVerified) fail('permission-denied', 'Un compte actif et vérifié est nécessaire.');
    return a;
  }
  // Compatibility name: V8 selectProposal now opens a discussion only.
  async function select(uid, data) {
    const a = await account(uid);
    if (!data || Object.keys(data).some(k => !['requestId','proposalId'].includes(k)) || !idOK(data.requestId) || !proposalIdOK(data.proposalId)) fail('invalid-argument', 'Discussion invalide.');
    const { requestId, proposalId } = data;
    return store.transaction(async tx => {
      const p = await tx.get(`proposals/${proposalId}`);
      const own = await tx.get(`userRequests/${uid}/items/${requestId}`);
      if (!own || !p || p.clientUid !== uid || p.requestId !== requestId || p.professionalUid === uid) fail('permission-denied', 'Seul l’auteur peut ouvrir la discussion pour une proposition reçue.');
      const conversationId = p.conversationId || proposalId;
      const chat = await tx.get(`conversations/${conversationId}`);
      if (chat) {
        if (!linked(chat, p, proposalId)) fail('failed-precondition', 'La discussion liée est indisponible.');
        return { conversationId, alreadySelected: true };
      }
      const pub = await tx.get(`requests/${requestId}`);
      const user = await tx.get(`users/${uid}`);
      const pro = await tx.get(`professionalProfiles/${p.professionalUid}`);
      if (own.status !== 'published' || pub?.status !== 'published' || own.createdAt !== pub.createdAt || !['sent','retained'].includes(p.status) || p.conversationId) fail('failed-precondition', 'Une nouvelle discussion nécessite une demande ouverte et une proposition disponible.');
      if (pro?.status !== 'approved') fail('permission-denied', 'Ce professionnel n’est plus approuvé.');
      const now = clock(), status = p.status === 'retained' ? 'retained' : 'discussing';
      const snapshot = Object.fromEntries(publicFields.filter(k => pub[k] !== undefined).map(k => [k,pub[k]]));
      tx.set(`proposals/${proposalId}`, { ...p, status, conversationId, discussionOpenedAt: now });
      tx.set(`conversations/${conversationId}`, {
        requestId, proposalId, selectedProposalId: proposalId, clientUid: uid, professionalUid: p.professionalUid,
        participantUids: [uid,p.professionalUid], clientName: typeof user?.fullName === 'string' && user.fullName.trim() ? user.fullName.trim() : a.displayName || 'Client',
        professionalName: pro.businessName || p.professionalName, requestTitle: pub.title, requestSnapshot: snapshot,
        status: 'active', proposalStatus: status, schemaVersion: 81, createdAt: now, updatedAt: now, lastMessageAt: now, lastMessagePreview: '',
      });
      return { conversationId, alreadySelected: false };
    });
  }
  async function decide(uid, data) {
    await account(uid);
    if (!data || Object.keys(data).some(k => !['requestId','proposalId','action','decisionId','expectedRetainedProposalId','reason'].includes(k)) || !idOK(data.requestId) || !proposalIdOK(data.proposalId) || !idOK(data.decisionId) || !['retain','reject'].includes(data.action) || (data.expectedRetainedProposalId != null && !proposalIdOK(data.expectedRetainedProposalId)) || (data.reason !== undefined && (typeof data.reason !== 'string' || data.reason.trim().length > 300))) fail('invalid-argument', 'Décision invalide.');
    const { requestId, proposalId, action, decisionId } = data;
    const expected = data.expectedRetainedProposalId ?? null, reason = (data.reason || '').trim();
    return store.transaction(async tx => {
      const ownPath = `userRequests/${uid}/items/${requestId}`, auditPath = `${ownPath}/decisions/${decisionId}`;
      const own = await tx.get(ownPath), p = await tx.get(`proposals/${proposalId}`), audit = await tx.get(auditPath);
      if (!own || !p || p.clientUid !== uid || p.requestId !== requestId || p.professionalUid === uid) fail('permission-denied', 'Seul l’auteur peut décider pour cette proposition.');
      if (audit) {
        if (audit.proposalId !== proposalId || audit.action !== action || audit.expectedRetainedProposalId !== expected || audit.reason !== reason) fail('already-exists', 'Cet identifiant correspond à une autre décision.');
        return { proposalId, status: audit.status, alreadyDecided: true };
      }
      if (!['published','closed'].includes(own.status) || !['sent','discussing','retained','selected'].includes(p.status)) fail('failed-precondition', 'Cette proposition ne peut plus être modifiée.');
      const currentId = own.retainedProposalId || null;
      if (action === 'retain' && currentId !== expected) fail('failed-precondition', 'La proposition retenue a changé. Actualise puis confirme le remplacement.');
      const previous = currentId && currentId !== proposalId ? await tx.get(`proposals/${currentId}`) : null;
      const chat = p.conversationId ? await tx.get(`conversations/${p.conversationId}`) : null;
      const previousChat = action === 'retain' && previous?.conversationId ? await tx.get(`conversations/${previous.conversationId}`) : null;
      const pro = action === 'retain' ? await tx.get(`professionalProfiles/${p.professionalUid}`) : null;
      if (action === 'retain' && pro?.status !== 'approved') fail('permission-denied', 'Ce professionnel n’est plus approuvé.');
      if (chat && !linked(chat,p,proposalId)) fail('failed-precondition','Discussion incohérente.');
      if (action === 'retain' && previous && (previous.clientUid !== uid || previous.requestId !== requestId || previous.status !== 'retained' || (previousChat && !linked(previousChat,previous,currentId)))) fail('failed-precondition','La retenue précédente est incohérente.');
      if (action === 'retain' && currentId && currentId !== proposalId && !previous) fail('failed-precondition','La retenue précédente est indisponible.');
      const now = Math.max(clock(), (own.updatedAt ?? own.createdAt) + 1), status = action === 'retain' ? 'retained' : 'rejected';
      if (action === 'retain' && previous) {
        const priorStatus = previous.conversationId ? 'discussing' : 'sent';
        tx.set(`proposals/${currentId}`, { ...previous, status: priorStatus, updatedAt: now });
        if (previousChat) tx.set(`conversations/${previous.conversationId}`, { ...previousChat, proposalStatus: priorStatus, updatedAt: now });
      }
      tx.set(`proposals/${proposalId}`, { ...p, status, updatedAt: now, ...(action === 'reject' ? { rejectionReason: reason } : {}) });
      if (action === 'retain' || currentId === proposalId) tx.set(ownPath, { ...own, retainedProposalId: action === 'retain' ? proposalId : null, retainedProfessionalName: action === 'retain' ? p.professionalName : null, updatedAt: now });
      if (chat) tx.set(`conversations/${p.conversationId}`, { ...chat, proposalStatus: status, updatedAt: now, ...(action === 'reject' ? { status: 'read_only', archivedReason: 'proposal_rejected' } : {}) });
      tx.set(auditPath, { actorUid: uid, requestId, proposalId, action, status, previousRetainedProposalId: currentId, expectedRetainedProposalId: expected, reason, createdAt: now });
      return { proposalId, status, alreadyDecided: false };
    });
  }
  async function send(uid, data) {
    const started = process.hrtime.bigint();
    const report = (stage, extra = {}) => {
      // Never log payloads, participant IDs or tokens, even on validation errors.
      try { onSendTiming({event:'message_send_server_timing',messageId:idOK(data?.messageId)?data.messageId:undefined,stage,elapsedMs:Number(process.hrtime.bigint()-started)/1e6,...extra}); } catch (_) { /* Metrics cannot affect delivery. */ }
    };
    report('S0_handler');
    try {
      const result = await sendValidated(uid, data, report);
      report('S4_committed');
      return result;
    } catch (error) {
      report('S_failed', {code:typeof error.code==='string'?error.code:'unknown'});
      throw error;
    }
  }
  async function sendValidated(uid, data, report) {
    await account(uid);
    report('S1_account_validated');
    const type = data?.type ?? 'text';
    const fields = type === 'contact' ? ['conversationId','messageId','type','phoneNumber','consent'] : ['conversationId','messageId','type','text'];
    if (!data || Object.keys(data).some(k => !fields.includes(k)) || !idOK(data.conversationId) || !idOK(data.messageId) ||
        !['text','contact'].includes(type) || (type === 'text' && (typeof data.text !== 'string' || !data.text.trim() || data.text.trim().length > 2000)) ||
        (type === 'contact' && (data.consent !== true || typeof data.phoneNumber !== 'string' || !/^\+[1-9][0-9]{7,14}$/.test(data.phoneNumber)))) fail('invalid-argument', type === 'contact' ? 'Confirme le numéro international à partager.' : 'Écris un message de 1 à 2000 caractères.');
    const { conversationId, messageId } = data;
    const payload = type === 'text' ? {text:data.text.trim()} : {phoneNumber:data.phoneNumber};
    report('S2_payload_validated');
    let attempt = 0;
    return store.transaction(async tx => {
      attempt++;
      const {chat,writable} = await readConversation(tx,uid,conversationId);
      const existing = await tx.get(`conversations/${conversationId}/messages/${messageId}`);
      report('S3_transaction_reads', {attempt});
      if (existing) {
        if (existing.senderUid !== uid || (existing.type || 'text') !== type || Object.entries(payload).some(([k,v])=>existing[k]!==v)) fail('already-exists', 'Cet identifiant correspond à un autre message.');
        return { messageId, createdAt: existing.createdAt };
      }
      if (!writable) fail('failed-precondition', 'Cette discussion est désormais en lecture seule.');
      const now = Math.max(clock(), (chat.lastMessageAt || chat.createdAt) + 1);
      tx.set(`conversations/${conversationId}/messages/${messageId}`, { senderUid: uid, type, ...payload, createdAt: now });
      tx.set(`conversations/${conversationId}`, { ...chat, lastMessageAt: now, lastMessagePreview: type === 'text' ? payload.text.slice(0,120) : 'Contact partagé', updatedAt: now });
      return { messageId, createdAt: now };
    });
  }
  return { select, decide, send };
}
module.exports = { createConversationService, readConversation, idOK };
