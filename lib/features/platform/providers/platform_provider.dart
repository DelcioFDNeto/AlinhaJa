import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/models/org_settings.dart';

/// Uma empresa (tenant) na visão do dono da aplicação.
/// Espelha o retorno de `platform_list_organizations()`.
@immutable
class PlatformOrganization {
  final String id;
  final String name;
  final String slug;
  final String? legalName;
  final String? cnpj;
  final bool isActive;
  final int userCount;
  final Map<String, dynamic> settings;

  const PlatformOrganization({
    required this.id,
    required this.name,
    required this.slug,
    this.legalName,
    this.cnpj,
    this.isActive = true,
    this.userCount = 0,
    this.settings = const {},
  });

  factory PlatformOrganization.fromJson(Map<String, dynamic> json) =>
      PlatformOrganization(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '—',
        slug: (json['slug'] as String?) ?? '',
        legalName: json['legal_name'] as String?,
        cnpj: json['cnpj'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        userCount: (json['user_count'] as num?)?.toInt() ?? 0,
        settings: json['settings'] is Map
            ? Map<String, dynamic>.from(json['settings'] as Map)
            : const {},
      );

  /// IDs dos módulos licenciáveis contratados por esta empresa, lidos de
  /// `settings.modules`. Vazio quando ainda não configurado.
  Set<String> get enabledModuleIds => OrgSettings(settings).modulos;
}

/// Repositório das operações de plataforma (todas guardadas por
/// `fn_is_platform_owner()` no banco).
class PlatformRepository {
  const PlatformRepository();

  Future<List<PlatformOrganization>> listOrganizations() async {
    final res = await supabase.rpc('platform_list_organizations');
    final list = (res as List?) ?? const [];
    return list
        .map((e) => PlatformOrganization.fromJson(
            Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  /// Cria a empresa e retorna o `organization_id` gerado.
  ///
  /// [legal] carrega o perfil legal (endereço, Encarregado, vigência…) no mesmo
  /// ato: não dá para gravá-lo depois com `admin_set_org_legal_profile`, que
  /// opera sobre `fn_current_org()` — o dono da plataforma não está atuando na
  /// empresa recém-criada, e a gravação cairia na empresa errada.
  Future<String> createOrganization({
    required String name,
    required String slug,
    String? legalName,
    String? cnpj,
    Map<String, dynamic>? legal,
  }) async {
    final res = await supabase.rpc('platform_create_organization', params: {
      'p_name': name,
      'p_slug': slug,
      'p_legal_name': legalName,
      'p_cnpj': cnpj,
      'p_legal': legal ?? const <String, dynamic>{},
    });
    return res as String;
  }

  /// Cria o primeiro admin da empresa (único caminho cross-tenant).
  Future<void> createOrgAdmin({
    required String orgId,
    required String email,
    required String password,
    required String fullName,
  }) async {
    await supabase.rpc('platform_create_org_admin', params: {
      'p_org_id': orgId,
      'p_email': email,
      'p_password': password,
      'p_full_name': fullName,
    });
  }

  Future<void> setOrgActive(String orgId, bool active) async {
    await supabase.rpc('platform_set_org_active', params: {
      'p_org_id': orgId,
      'p_active': active,
    });
  }

  /// Grava os módulos licenciáveis contratados por uma empresa em
  /// `organizations.settings.modules` (guardado por `fn_is_platform_owner()`).
  Future<void> setOrgModules(String orgId, List<String> moduleIds) async {
    await supabase.rpc('platform_set_org_modules', params: {
      'p_org_id': orgId,
      'p_modules': moduleIds,
    });
  }

  /// Alterna a empresa em atuação do dono da plataforma. `orgId == null` volta
  /// para a org natal. Guardada por `fn_is_platform_owner()` no banco.
  Future<void> setActingOrg(String? orgId) async {
    await supabase.rpc('platform_set_acting_org', params: {'p_org_id': orgId});
  }
}

final platformRepositoryProvider =
    Provider<PlatformRepository>((ref) => const PlatformRepository());

/// Lista de empresas para o Console de Plataforma.
final platformOrganizationsProvider =
    FutureProvider<List<PlatformOrganization>>((ref) async {
  return ref.read(platformRepositoryProvider).listOrganizations();
});
