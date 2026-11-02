// Pure planner. No SDK, network or writes; ambiguous legacy records are left untouched.
function planNegotiationMigration(records) {
  const docs = new Map(records.map(d => [d.path,d.data]));
  const groups = [], anomalies = [], seen = new Set();
  let legacy = 0, reopen = 0, closed = 0;
  for (const {path,data:chat} of records.filter(d => /^conversations\/[^/]+$/.test(d.path))) {
    if (chat.schemaVersion === 81) continue;
    legacy++;
    const id = path.split('/')[1], pid = chat.proposalId || chat.selectedProposalId;
    const ppath = `proposals/${pid}`, p = docs.get(ppath);
    const ownPath = `userRequests/${chat.clientUid}/items/${chat.requestId}`, own = docs.get(ownPath);
    const pubPath = `requests/${chat.requestId}`, pub = docs.get(pubPath);
    if (!p || !own || !pub || p.status !== 'selected' || p.conversationId !== id || p.requestId !== chat.requestId || p.clientUid !== chat.clientUid || p.professionalUid !== chat.professionalUid || own.selectedProposalId !== pid || own.conversationId !== id || own.createdAt !== pub.createdAt || own.status !== pub.status || !['in_discussion','closed','deleted'].includes(own.status) || !['active','read_only'].includes(chat.status) || (own.status === 'in_discussion' && chat.status !== 'active') || chat.archivedReason || seen.has(ownPath)) {
      anomalies.push({path,reason:'Legacy ownership, selection or publication does not match'});continue;
    }
    seen.add(ownPath);
    const status = own.status === 'in_discussion' ? 'published' : own.status;
    if (own.status === 'in_discussion') reopen++;
    if (own.status === 'closed') closed++;
    const afterOwn = {...own,status,schemaVersion:81};
    delete afterOwn.selectedProposalId;delete afterOwn.selectedProfessionalUid;delete afterOwn.conversationId;
    const afterChat = {...chat,proposalId:pid,proposalStatus:'discussing',schemaVersion:81,
      status:status === 'deleted' ? 'read_only' : 'active',
      requestSnapshot:{...chat.requestSnapshot,status}};
    if (status === 'deleted') afterChat.archivedReason = 'request_deleted';
    const changes = [
      {path:ownPath,before:own,after:afterOwn},
      {path:ppath,before:p,after:{...p,status:'discussing',schemaVersion:81}},
      {path,before:chat,after:afterChat},
    ];
    if (status !== pub.status) changes.push({path:pubPath,before:pub,after:{...pub,status}});
    groups.push({requestId:chat.requestId,changes});
  }
  for (const {path,data} of records.filter(d=>/^requests\/[^/]+$/.test(d.path))) {
    if (data.status === 'in_discussion' && !groups.some(g=>g.requestId === path.split('/')[1])) anomalies.push({path,reason:'Hidden request has no fully verified legacy selection'});
  }
  return {groups,anomalies,counts:{legacyConversations:legacy,eligible:groups.length,reopen,closedPreserved:closed}};
}
module.exports = {planNegotiationMigration};
