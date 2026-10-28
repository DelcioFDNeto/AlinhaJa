// Firebase Messaging Service Worker — AlinhaJá
// Este SW intercepta push messages mesmo com a aba fechada/minimizada.
importScripts("https://www.gstatic.com/firebasejs/10.8.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.8.0/firebase-messaging-compat.js");
importScripts("notification-format.js");

firebase.initializeApp({
  apiKey: "AIzaSyC7bvI3M84iM6prl4nVnZ2kENnwxWII7bg",
  appId: "1:6609270866:web:5667fb8a6229676a90878b",
  messagingSenderId: "6609270866",
  projectId: "alinhaja",
});

const messaging = firebase.messaging();

// ─── Helper: Verifica se o usuário está logado via IndexedDB ───
// Se a flag 'logged_in' existir e for false, a notificação é suprimida.
// Na ausência da flag (padrão), considera logado: o token FCM já é apagado
// do servidor no logout.
function isUserLoggedIn() {
  return new Promise((resolve) => {
    try {
      const request = indexedDB.open('alinhaja_auth', 1);
      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains('state')) {
          db.createObjectStore('state');
        }
      };
      request.onsuccess = (event) => {
        try {
          const db = event.target.result;
          const tx = db.transaction('state', 'readonly');
          const store = tx.objectStore('state');
          const getReq = store.get('logged_in');
          getReq.onsuccess = () => {
            resolve(getReq.result !== false);
          };
          getReq.onerror = () => resolve(true);
        } catch (e) {
          resolve(true);
        }
      };
      request.onerror = () => resolve(true);
    } catch (e) {
      resolve(true);
    }
  });
}

// ─── Background Push Handler ───
// O SDK só chama este handler quando NENHUMA aba do app está visível; com
// aba visível a mensagem vai para a página (FirebaseMessaging.onMessage).
messaging.onBackgroundMessage(async (payload) => {
  // Mensagem com bloco `notification` (ex.: workflow) já foi exibida pelo
  // próprio SDK antes de chegar aqui. Exibir de novo duplicava.
  if (payload.notification) return;

  const loggedIn = await isUserLoggedIn();
  if (!loggedIn) return;

  const data = payload.data || {};
  const existing = await self.registration.getNotifications({
    tag: AlinhaJaNotificationFormat.tagFor(data),
  });
  const previousCount = existing.length > 0 && existing[0].data
    ? existing[0].data.count || 1
    : 0;

  const view = AlinhaJaNotificationFormat.build(data, previousCount);
  return self.registration.showNotification(view.title, view.options);
});

// ─── Notification Click Handler ───
// Foca a aba já aberta do app (navegando até a conversa) ou abre uma nova.
self.addEventListener('notificationclick', (event) => {
  const data = event.notification.data || {};
  // Notificações exibidas pelo SDK (com FCM_MSG) são tratadas por ele.
  if (data.FCM_MSG) return;
  event.notification.close();

  const chatId = data.chatId || '';
  const chatType = data.chatType || 'direct';
  const targetPath = AlinhaJaNotificationFormat.pathFor(chatId, chatType, data.route);

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.postMessage({
            type: 'NOTIFICATION_CLICK',
            chatId: chatId,
            chatType: chatType,
            route: data.route || null,
            name: data.name || 'Chat',
          });
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetPath);
      }
    })
  );
});
