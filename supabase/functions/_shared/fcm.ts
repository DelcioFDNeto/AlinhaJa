// ============================================================
// Regras comuns de envio FCM (send-chat, send-call, send-workflow)
// ============================================================

/// Limite do texto de prévia. A notificação corta a exibição de qualquer
/// forma; mandar a mensagem inteira só aumenta o payload (teto de 4 KB).
export const PREVIEW_MAX = 300;

/// Prévia da mensagem no formato que o WhatsApp usa para mídia.
export function contentPreview(contentType: unknown, content: unknown): string {
  switch (contentType) {
    case 'image': return '📷 Foto';
    case 'video': return '🎥 Vídeo';
    case 'audio': return '🎙️ Áudio';
    case 'file': return '📎 Documento';
    case 'location': return '📍 Localização';
    case 'sticker': return '💟 Figurinha';
    case 'contact': return '👤 Contato';
    case 'poll': return '📊 Enquete';
    case 'meeting': return '📹 Videoconferência';
  }
  const text = typeof content === 'string' ? content.trim() : '';
  if (!text) return 'Enviou uma mensagem';
  return text.length > PREVIEW_MAX ? `${text.slice(0, PREVIEW_MAX - 1)}…` : text;
}

/// O token deve ser apagado? Só quando o FCM diz que ele não existe mais.
///
/// `INVALID_ARGUMENT` fica de fora de propósito: o FCM devolve o mesmo código
/// para payload malformado, e apagar o token nesse caso desliga as
/// notificações de um aparelho saudável.
export function isStaleTokenError(status: number, body: string): boolean {
  if (status === 404) return true;
  try {
    const parsed = JSON.parse(body);
    const details: unknown[] = parsed?.error?.details ?? [];
    return details.some((d) =>
      typeof d === 'object' && d !== null &&
      (d as Record<string, unknown>).errorCode === 'UNREGISTERED'
    );
  } catch {
    return false;
  }
}
