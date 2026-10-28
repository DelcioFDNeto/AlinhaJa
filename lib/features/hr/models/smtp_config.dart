class SmtpConfig {
  final String? organizationId;
  final String host;
  final int port;
  final String username;

  /// Apenas de saída (gravação via RPC). A senha NUNCA volta do banco
  /// para o cliente — a leitura expõe só [hasPassword].
  final String? password;

  /// true quando já existe senha cifrada gravada no banco.
  final bool hasPassword;
  final String fromEmail;
  final String fromName;

  SmtpConfig({
    this.organizationId,
    required this.host,
    this.port = 465,
    required this.username,
    this.password,
    this.hasPassword = false,
    required this.fromEmail,
    required this.fromName,
  });

  factory SmtpConfig.fromMap(Map<String, dynamic> map) {
    return SmtpConfig(
      organizationId: map['organization_id'] as String?,
      host: map['host'] as String? ?? '',
      port: map['port'] as int? ?? 465,
      username: map['username'] as String? ?? '',
      hasPassword: map['has_password'] as bool? ?? false,
      fromEmail: map['from_email'] as String? ?? '',
      fromName: map['from_name'] as String? ?? '',
    );
  }
}
