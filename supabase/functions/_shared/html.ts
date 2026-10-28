// ============================================================
// Escape de dados em e-mails (auditoria 2026-09-16)
//
// Os templates HTML interpolavam o nome digitado no portal público de
// candidatos sem escape. Qualquer pessoa podia informar o e-mail de outra e
// um "nome" com `<a href=...>`, e o SMTP da empresa entregava o link de
// phishing com a identidade da empresa. Todo valor que não é HTML escrito
// por nós passa por aqui antes de entrar num template.
// ============================================================

const HTML_ENTITIES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

/// Escapa texto para uso em conteúdo HTML e em atributos entre aspas.
export function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (c) => HTML_ENTITIES[c]);
}

/// Remove quebras de linha de valores usados em cabeçalhos (assunto,
/// remetente). CR/LF num cabeçalho permitiria injetar cabeçalhos extras.
export function stripHeaderBreaks(value: unknown): string {
  return String(value ?? '').replace(/[\r\n]+/g, ' ').trim();
}
