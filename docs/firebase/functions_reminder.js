// functions/index.js — Node 20, планировщик напоминаний.
// Деплой: firebase deploy --only functions:sendReminders
const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendReminders = functions.pubsub
  .schedule('every 1 minutes')
  .timeZone('Europe/Moscow')
  .onRun(async () => {
    const now = Date.now();
    const windowEnd = now + 60 * 1000;
    const db = admin.firestore();

    // Личные и семейные коллекции.
    const familySnap = await db.collectionGroup('notes')
      .where('reminderAtMs', '>=', now)
      .where('reminderAtMs', '<', windowEnd)
      .where('done', '==', false)
      .get();

    const tokens = new Set();
    const batch = db.batch();
    familySnap.docs.forEach((doc) => {
      const data = doc.data();
      (data.deviceTokens || []).forEach((t) => tokens.add(t));
      batch.update(doc.ref, { notified: true });
    });

    if (tokens.size === 0) return null;
    const message = {
      notification: { title: 'Напоминание Smart Notes', body: 'Откройте приложение' },
      tokens: [...tokens],
    };
    await admin.messaging().sendEachForMulticast(message);
    await batch.commit();
    return null;
  });
