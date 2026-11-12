// Private requests never have a document in the public requests collection.
async function requestRecord(tx, id) {
  return await tx.get(`requests/${id}`) || await tx.get(`directRequests/${id}`);
}
module.exports = { requestRecord };
