// Formatação das notificações web/PWA (estilo WhatsApp).
// Separado do service worker para ser testável fora do navegador.
(function (root) {
  const APP_ICON = '/icons/Icon-192.png';
  const BADGE = '/icons/Icon-maskable-192.png';

  function isCall(data) {
    return data.type === 'call' || data.type === 'voice' || data.type === 'video' || !!data.call_id;
  }

  function contextId(data) {
    const id = data.chat_id && data.chat_id !== 'null' ? data.chat_id : data.channel_id;
    return id && id !== 'null' ? id : '';
  }

  // Uma notificação por conversa: mensagens novas substituem a anterior.
  function tagFor(data) {
    if (isCall(data)) return 'call_' + (data.call_id || contextId(data) || 'default');
    return contextId(data) || 'default';
  }

  // Rota interna enviada pelo servidor (avisos de conta). Só caminho do app.
  function safeRoute(route) {
    return typeof route === 'string' && route.charAt(0) === '/' && route.charAt(1) !== '/'
      ? route
      : null;
  }

  function pathFor(chatId, chatType, route) {
    var internal = safeRoute(route);
    if (internal) return '/#' + internal;
    if (!chatId) return '/';
    // Card de workflow pertence a um canal: abre o canal.
    return chatType === 'channel' || chatType === 'workflow'
      ? '/#/channel/' + chatId
      : '/#/chat/' + chatId;
  }

  function httpsOrNull(url) {
    return typeof url === 'string' && url.indexOf('https://') === 0 ? url : null;
  }

  // Monta título e opções. `previousCount` é quantas mensagens a notificação
  // da mesma conversa já acumulava (0 se não havia notificação aberta).
  function build(data, previousCount) {
    const id = contextId(data);
    const chatType = data.chat_type || 'direct';

    if (isCall(data)) {
      return {
        title: data.title || (data.is_video === 'true' ? '📹 Chamada de vídeo' : '📞 Chamada de voz'),
        options: {
          body: data.body || ((data.caller_name || 'Alguém') + ' está ligando…'),
          icon: httpsOrNull(data.caller_avatar) || APP_ICON,
          badge: BADGE,
          tag: tagFor(data),
          renotify: true,
          requireInteraction: true,
          vibrate: [300, 150, 300, 150, 300],
          data: { chatId: id, chatType: chatType, name: data.caller_name || 'Chamada', count: 1 },
        },
      };
    }

    if (data.type === 'account') {
      return {
        title: data.title || 'Aviso',
        options: {
          body: data.body || '',
          icon: APP_ICON,
          badge: BADGE,
          tag: 'account_' + Date.now(),
          vibrate: [200, 100, 200],
          data: { chatId: '', chatType: 'account', route: safeRoute(data.route), name: data.title || '', count: 1 },
        },
      };
    }

    const count = (previousCount || 0) + 1;
    const baseTitle = data.title || 'Nova mensagem';
    return {
      title: count > 1 ? baseTitle + ' (' + count + ' mensagens)' : baseTitle,
      options: {
        body: data.body || '',
        icon: httpsOrNull(data.sender_avatar) || APP_ICON,
        badge: BADGE,
        tag: tagFor(data),
        renotify: true,
        vibrate: [200, 100, 200],
        timestamp: Date.now(),
        data: { chatId: id, chatType: chatType, name: data.chat_name || baseTitle, count: count },
      },
    };
  }

  root.AlinhaJaNotificationFormat = { build: build, tagFor: tagFor, pathFor: pathFor, contextId: contextId };
  if (typeof module !== 'undefined') module.exports = root.AlinhaJaNotificationFormat;
})(typeof self !== 'undefined' ? self : globalThis);
