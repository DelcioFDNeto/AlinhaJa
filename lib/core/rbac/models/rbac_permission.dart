library;

class RbacPermission {
  final String id;
  final String module;
  final String action;
  final String? description;

  const RbacPermission({
    required this.id,
    required this.module,
    required this.action,
    this.description,
  });

  factory RbacPermission.fromJson(Map<String, dynamic> json) {
    return RbacPermission(
      id: json['id'] as String,
      module: json['module'] as String,
      action: json['action'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'module': module,
      'action': action,
      'description': description,
    };
  }
}
