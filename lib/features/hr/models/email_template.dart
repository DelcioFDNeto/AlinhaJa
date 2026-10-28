class EmailTemplate {
  final String? id;
  final String? organizationId;
  final String nome;
  final String assunto;
  final String bodyHtml;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  EmailTemplate({
    this.id,
    this.organizationId,
    required this.nome,
    required this.assunto,
    required this.bodyHtml,
    this.createdAt,
    this.updatedAt,
  });

  factory EmailTemplate.fromMap(Map<String, dynamic> map) {
    return EmailTemplate(
      id: map['id'] as String?,
      organizationId: map['organization_id'] as String?,
      nome: map['nome'] as String? ?? '',
      assunto: map['assunto'] as String? ?? '',
      bodyHtml: map['body_html'] as String? ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      'nome': nome,
      'assunto': assunto,
      'body_html': bodyHtml,
    };
  }
}
