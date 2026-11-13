const {key, catalog, cleanPreview} = require('./notification-policy');

const noticeTypes = Object.freeze({
  warn:'safety.warned', hide:'safety.content_hidden', suspend:'safety.suspended',
  restore_content:'safety.content_restored', restore_account:'safety.account_restored',
});

// Select only the recipient's own content. Never serialize the evidence object,
// reporter, moderator, conversation counterpart or private justification.
function noticeContent(report, own) {
  if(!report)return null;
  const e=report.evidence || {}, type=report.targetType;
  let title,excerpt='',createdAt=null;
  if(type==='request'){
    title=`Demande « ${cleanPreview(e.title || own?.title || report.label || 'Sans titre',120)} »`;
    excerpt=cleanPreview(e.description || own?.description,1600);
    createdAt=e.createdAt || own?.createdAt || null;
  }else if(type==='professional'){
    title=`Profil professionnel « ${cleanPreview(e.name || report.label || 'Mon profil',120)} »`;
    excerpt=cleanPreview(e.bio,1600);
  }else if(type==='message'){
    const m=e.message;
    title='Message';
    if(m?.senderUid===report.reportedUid){
      createdAt=m.createdAt || null;
      excerpt=cleanPreview(m.type==='text' || !m.type ? m.text : ({image:'Photo',pdf:'Document PDF',contact:'Contact partagé'})[m.type],1600);
    }
  }else{
    title=e.requestTitle ? `Conversation liée à « ${cleanPreview(e.requestTitle,120)} »` : 'Conversation';
  }
  return {type,id:report.targetId,title,excerpt,createdAt:Number.isSafeInteger(createdAt)?createdAt:null};
}

function decisionNotification(action, decisionKey, uid, now, {report,own,publicMessage}={}) {
  const type = noticeTypes[action];
  if (!type) return null;
  const eventId = `safetyDecisions/${decisionKey}`, id = key(eventId, uid);
  const [category,title,bodySafe] = catalog[type];
  const content=noticeContent(report,own);
  const message=publicMessage || bodySafe;
  const context=content ? `\n\nContenu concerné : ${content.title}\nRéférence : ${content.id}${content.createdAt ? `\nDate du contenu : ${new Date(content.createdAt).toISOString()}` : ''}${content.excerpt ? `\nExtrait du contenu examiné :\n${content.excerpt}` : ''}` : '';
  return {
    id,
    notice: {notificationId:id, recipientUid:uid, action, type, publicMessage:message,content,
      text:`${title}. ${message}${context}\n\nPour une explication ou une contestation, contacte l’assistance Foundi : kouamedenzel09@gmail.com.`, createdAt:now,acknowledgedAt:null},
    notification: {eventId,type,category,title,bodySafe:content ? `${content.title}. ${cleanPreview(message,240)}` : message,recipientUid:uid,actorUid:null,
      resourceType:'safetyNotice',resourceId:decisionKey,requestId:null,proposalId:null,conversationId:null,
      occurredAt:now,createdAt:new Date(now),readAt:null,schemaVersion:9,isGeneral:true},
    // Lock-screen pushes stay generic; full context is confined to the inbox.
    outbox: {notificationId:id,uid,actorUid:null,category,title,bodySafe,conversationId:null,
      state:'pending',dueAt:now,createdAt:now},
  };
}

function matchesSafetyNotice(uid, id, notification, notice) {
  return !!notice && notification?.resourceType === 'safetyNotice' &&
    notification.schemaVersion === 9 && notification.recipientUid === uid && notification.actorUid === null &&
    notification.type === noticeTypes[notice.action] && notice.type === notification.type &&
    notice.recipientUid === uid && notice.notificationId === id &&
    notification.eventId === `safetyDecisions/${notification.resourceId}` &&
    id === key(notification.eventId, uid);
}

module.exports = {decisionNotification, matchesSafetyNotice};
