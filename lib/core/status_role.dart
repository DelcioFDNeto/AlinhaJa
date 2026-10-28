/// Papel semântico de um status de domínio (funcionário, candidato,
/// documento…). A UI nunca escolhe a cor crua: mapeia o status para um
/// [StatusRole] e resolve a cor via `AlinhaStatusTokens`, permitindo
/// paletas por tenant (white-label) sem tocar nas telas.
///
/// Enum puro (sem Flutter) de propósito, para que os models do RH
/// continuem livres de dependência de `material.dart`.
library;

enum StatusRole {
  success, // verde   — estado saudável/positivo (ativo, contratado, válido)
  info, // azul    — informativo/inicial (novo, férias)
  warning, // laranja — requer atenção (afastado, em análise, pendente)
  danger, // vermelho — crítico/negativo (vencido, rejeitado)
  neutral, // cinza   — inerte/terminal (desligado, descartado)
  highlight, // roxo    — etapa em destaque (entrevista)
  progress, // teal    — avanço no funil (aprovado)
  pending, // âmbar   — prestes a expirar (próximo do vencimento)
}
