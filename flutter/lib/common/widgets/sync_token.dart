// Build local o CI sin secreto: token vacio => la sincronizacion queda
// desactivada. En los builds de release, GitHub Actions sobrescribe este
// archivo con el secreto SYNC_TOKEN. Nunca commitear un token aca.
const String kSyncToken = '';
