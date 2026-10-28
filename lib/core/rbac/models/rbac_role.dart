library;

class RbacRole {
  final String id;
  final String organizationId;
  final String name;
  final String? description;
  final bool isSystem;

  const RbacRole({
    required this.id,
    required this.organizationId,
    required this.name,
    this.description,
    this.isSystem = false,
  });

  factory RbacRole.fromJson(Map<String, dynamic> json) {
    return RbacRole(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isSystem: json['is_system'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'name': name,
      'description': description,
      'is_system': isSystem,
    };
  }
}
