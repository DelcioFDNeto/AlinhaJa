enum WorkflowCardType {
  // Os values internos ('fat_moto', 'emplacamento') são mantidos por
  // compatibilidade com cards já gravados no banco; apenas os rótulos
  // exibidos foram generalizados para qualquer ramo empresarial.
  contaPagar('conta_pagar', 'Liberação Contas a Pagar'),
  fatMoto('fat_moto', 'Liberação de Pedido'),
  emplacamento('emplacamento', 'Documentação/Cadastro'),
  faturamentoOs('faturamento_os', 'Faturamento OS/Produtos'),
  aviso('aviso', 'Avisos Gerais'),
  generic('generic', 'Genérico');

  final String value;
  final String label;

  const WorkflowCardType(this.value, this.label);

  static WorkflowCardType fromString(String value) {
    return WorkflowCardType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => WorkflowCardType.generic,
    );
  }
}

enum WorkflowPriority {
  low('low', 'Baixa', 0xFF6B7280),
  medium('medium', 'Média', 0xFFF59E0B),
  high('high', 'Alta', 0xFFF97316),
  urgent('urgent', 'Urgente', 0xFFEF4444);

  final String value;
  final String label;
  final int color;

  const WorkflowPriority(this.value, this.label, this.color);

  static WorkflowPriority fromString(String value) {
    return WorkflowPriority.values.firstWhere(
      (e) => e.value == value,
      orElse: () => WorkflowPriority.medium,
    );
  }
}
