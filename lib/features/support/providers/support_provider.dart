import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/support/models/support_ticket_model.dart';
import 'package:alinha_ja/features/support/models/ticket_message_model.dart';

// ─── Helpers de tradução ────────────────────────────────────────────────────

const categoryLabels = <String, String>{
  'software': 'Sistema / Software',
  'hardware': 'Equipamentos / Hardware',
  'network': 'Internet / Rede',
  'external_access': 'Acessos / Credenciais',
  'general': 'Dúvida Geral',
  'other': 'Outro',
};

const priorityLabels = <String, String>{
  'low': 'Baixa',
  'medium': 'Normal',
  'high': 'Alta',
  'urgent': 'Urgente',
};

const statusLabels = <String, String>{
  'new': 'Novo',
  'in_progress': 'Em Andamento',
  'pending_vendor': 'Pendente Fornecedor',
  'resolved': 'Resolvido',
  'cancelled': 'Cancelado',
};

String translateCategory(String raw) => categoryLabels[raw] ?? raw;
String translatePriority(String raw) => priorityLabels[raw] ?? raw;
String translateStatus(String raw) => statusLabels[raw] ?? raw;

/// Formato relativo simples ("há 5 min", "há 2 dias")
String timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'agora mesmo';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays < 7) {
    return 'há ${diff.inDays} dia${diff.inDays > 1 ? 's' : ''}';
  }
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ─── Helper: enriquecer lista de tickets com dados de users ─────────────────

Future<List<SupportTicketModel>> _enrichTickets(
    List<Map<String, dynamic>> data) async {
  final userIds = <String>{};
  for (var row in data) {
    userIds.add(row['creator_id'] as String);
    if (row['assigned_to'] != null) userIds.add(row['assigned_to'] as String);
  }
  if (userIds.isEmpty) return [];

  final usersData = await supabase
      .from('users')
      .select('id, full_name, avatar_url')
      .inFilter('id', userIds.toList());

  final userMap = {for (var u in usersData as List) u['id']: u};

  return data.map((d) {
    final map = Map<String, dynamic>.from(d);
    map['creator'] = userMap[map['creator_id']];
    if (map['assigned_to'] != null) {
      map['assignee'] = userMap[map['assigned_to']];
    }
    return SupportTicketModel.fromJson(map);
  }).toList();
}

// ─── Providers ──────────────────────────────────────────────────────────────

/// Provider para buscar os tickets do próprio usuário (com dados do criador/responsável)
final myTicketsProvider = StreamProvider<List<SupportTicketModel>>((ref) {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return const Stream.empty();

  return supabase
      .from('support_tickets')
      .stream(primaryKey: ['id'])
      .eq('creator_id', userId)
      .order('created_at', ascending: false)
      .asyncMap((data) => _enrichTickets(data));
});

/// Provider para buscar TODOS os tickets (apenas acessível via RLS por TI)
final adminTicketsProvider = StreamProvider<List<SupportTicketModel>>((ref) {
  return supabase
      .from('support_tickets')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .asyncMap((data) => _enrichTickets(data));
});

/// Provider para buscar UM ticket específico (funciona para criador E TI via RLS)
final ticketDetailProvider =
    FutureProvider.family<SupportTicketModel?, String>((ref, ticketId) async {
  final data = await supabase
      .from('support_tickets')
      .select()
      .eq('id', ticketId)
      .maybeSingle();

  if (data == null) return null;
  final enriched = await _enrichTickets([data]);
  return enriched.isNotEmpty ? enriched.first : null;
});

/// Provider para buscar e escutar mensagens de um ticket específico
final ticketMessagesProvider =
    StreamProvider.family<List<TicketMessageModel>, String>((ref, ticketId) {
  return supabase
      .from('support_ticket_messages')
      .stream(primaryKey: ['id'])
      .eq('ticket_id', ticketId)
      .order('created_at', ascending: true)
      .asyncMap((data) async {
        final userIds = <String>{};
        for (var row in data) {
          userIds.add(row['sender_id'] as String);
        }
        if (userIds.isEmpty) return <TicketMessageModel>[];

        final usersData = await supabase
            .from('users')
            .select('id, full_name, avatar_url')
            .inFilter('id', userIds.toList());

        final userMap = {for (var u in usersData as List) u['id']: u};

        return data.map((d) {
          final map = Map<String, dynamic>.from(d);
          map['sender'] = userMap[map['sender_id']];
          return TicketMessageModel.fromJson(map);
        }).toList();
      });
});

// ─── Serviços / Ações ───────────────────────────────────────────────────────

class SupportService {
  static Future<void> createTicket({
    required String title,
    required String description,
    required String category,
    required String priority,
    String? deviceInfo,
    List<String> attachments = const [],
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Usuário não autenticado');

    await supabase.from('support_tickets').insert({
      'creator_id': userId,
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
      'device_info': deviceInfo,
      'attachments': attachments,
      'status': 'new',
    });
  }

  static Future<void> sendMessage(
    String ticketId,
    String content, {
    List<String> attachments = const [],
    bool isInternal = false,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Usuário não autenticado');

    await supabase.from('support_ticket_messages').insert({
      'ticket_id': ticketId,
      'sender_id': userId,
      'content': content,
      'attachments': attachments,
      'is_internal': isInternal,
    });
  }

  static Future<void> updateTicketStatus(String ticketId, String status) async {
    final updates = <String, dynamic>{'status': status};
    if (status == 'resolved') {
      updates['resolved_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await supabase.from('support_tickets').update(updates).eq('id', ticketId);
  }

  static Future<void> assignTicket(String ticketId, String assigneeId) async {
    await supabase.from('support_tickets').update({
      'assigned_to': assigneeId,
      'status': 'in_progress',
    }).eq('id', ticketId);
  }
}
