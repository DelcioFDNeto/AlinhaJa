import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alinha_ja/features/channels/models/workspace_preset.dart';
import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';
import 'package:alinha_ja/features/workflow/models/workflow_supporting_models.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';

WorkflowStatusConfig _config(
  String status, {
  int order = 1,
  bool isFinal = false,
  bool isInitial = false,
  bool? isCancelled,
}) {
  return WorkflowStatusConfig(
    id: 'cfg_$status',
    channelId: 'ch1',
    status: status,
    statusOrder: order,
    isFinal: isFinal,
    isInitial: isInitial,
    isCancelled: isCancelled,
  );
}

WorkflowCard _card(String id, String status) {
  return WorkflowCard(
    id: id,
    channelId: 'ch1',
    cardType: WorkflowCardType.generic,
    title: 'Card $id',
    priority: WorkflowPriority.medium,
    status: status,
    createdAt: DateTime(2026, 8, 13),
    updatedAt: DateTime(2026, 8, 13),
  );
}

void main() {
  group('WorkflowStatusConfig — flags de etapa', () {
    test('is_cancelled explícito do banco tem precedência', () {
      final config = WorkflowStatusConfig.fromJson({
        'id': '1',
        'channel_id': 'ch1',
        'status': 'Recusado pelo gestor',
        'status_order': 4,
        'is_cancelled': true,
      });

      expect(config.isCancelled, isTrue);
    });

    test('banco antigo sem a coluna cai na heurística por nome', () {
      final legacy = WorkflowStatusConfig.fromJson({
        'id': '1',
        'channel_id': 'ch1',
        'status': 'Cancelado',
        'status_order': 5,
      });

      expect(legacy.isCancelled, isTrue,
          reason: 'canal criado antes da migration precisa continuar '
              'reconhecendo a etapa de cancelamento');
    });

    test('is_cancelled=false do banco vence o nome legado', () {
      final config = WorkflowStatusConfig.fromJson({
        'id': '1',
        'channel_id': 'ch1',
        'status': 'Cancelado',
        'status_order': 5,
        'is_cancelled': false,
      });

      expect(config.isCancelled, isFalse);
    });

    test('etapa com nome customizado não é cancelamento por acidente', () {
      expect(_config('Aguardando peça').isCancelled, isFalse);
    });
  });

  group('WorkflowState — semântica configurável de cancelamento', () {
    final state = WorkflowState(
      statusConfig: [
        _config('Aberto', order: 1, isInitial: true),
        _config('Em análise', order: 2),
        _config('Concluído', order: 3, isFinal: true),
        _config('Recusado', order: 4, isCancelled: true),
      ],
      cards: [
        _card('a', 'Aberto'),
        _card('b', 'Recusado'),
        _card('c', 'Concluído'),
      ],
    );

    test('isCancelledStatus segue a flag, não o nome', () {
      expect(state.isCancelledStatus('Recusado'), isTrue);
      expect(state.isCancelledStatus('recusado'), isTrue);
      expect(state.isCancelledStatus('Concluído'), isFalse);
    });

    test('cards cancelados saem do funil', () {
      final visible = state.getFilteredCards(null).map((c) => c.id).toList();

      expect(visible, containsAll(<String>['a', 'c']));
      expect(visible, isNot(contains('b')));
    });

    test('cardsByStatus não cria coluna para a etapa de cancelamento', () {
      expect(state.cardsByStatus.keys, isNot(contains('Recusado')));
      expect(state.cardsByStatus.keys, contains('Aberto'));
    });

    test('initialStatus respeita a flag is_initial, não a ordem da lista', () {
      final reordered = WorkflowState(
        statusConfig: [
          _config('Triagem', order: 2),
          _config('Entrada', order: 1, isInitial: true),
        ],
      );

      expect(reordered.initialStatus, equals('Entrada'));
    });

    test('sem is_initial, cai na primeira etapa não cancelada', () {
      final legacy = WorkflowState(
        statusConfig: [
          _config('Cancelado', order: 1),
          _config('Novo', order: 2),
        ],
      );

      expect(legacy.initialStatus, equals('Novo'));
    });
  });

  group('WorkflowStageDraft', () {
    test('toJson aplica a ordem recebida e preserva as flags', () {
      final stage = WorkflowStageDraft(
        id: '11111111-1111-1111-1111-111111111111',
        status: '  Em análise  ',
        color: '#F59E0B',
        icon: 'search',
        isFinal: false,
        isInitial: true,
      );

      final json = stage.toJson(3);

      expect(json['id'], equals('11111111-1111-1111-1111-111111111111'));
      expect(json['status'], equals('Em análise'),
          reason: 'espaços nas pontas não podem virar nome de etapa');
      expect(json['status_order'], equals(3));
      expect(json['is_initial'], isTrue);
      expect(json['is_cancelled'], isFalse);
    });

    test('detached() descarta o id — preset não pertence a canal algum', () {
      final stage = WorkflowStageDraft(
        id: '11111111-1111-1111-1111-111111111111',
        status: 'Novo',
      );

      expect(stage.detached().toJson(1).containsKey('id'), isFalse);
    });

    test('stagesToJson numera as etapas pela posição na lista', () {
      final stages = [
        WorkflowStageDraft(status: 'A'),
        WorkflowStageDraft(status: 'B'),
        WorkflowStageDraft(status: 'C'),
      ];

      final json = stagesToJson(stages);

      expect(json.map((e) => e['status_order']).toList(), equals([1, 2, 3]));
    });

    test('fromConfig ignora ids sintéticos de fallback', () {
      final fromFallback = WorkflowStageDraft.fromConfig(
        WorkflowStatusConfig(
          id: 'fallback_1',
          channelId: 'ch1',
          status: 'Solicitação aberta',
          statusOrder: 1,
        ),
      );

      expect(fromFallback.id, isNull,
          reason: 'o id de fallback não existe em workflow_status_config, '
              'então a etapa precisa ser tratada como nova');
    });
  });

  group('WorkspacePreset', () {
    final json = {
      'id': 'p1',
      'name': 'Aprovação de Compras',
      'description': 'Fluxo de compras',
      'category': 'financeiro',
      'icon': 'payments_outlined',
      'color': '#2E7D32',
      'card_type': 'conta_pagar',
      'workflow_enabled': true,
      'assignment_mode': 'operator_pool',
      'is_system': false,
      'is_shared': true,
      'created_by': 'user-1',
      'usage_count': 4,
      'status_config': [
        {
          'status': 'Novo',
          'status_order': 1,
          'color': '#3B82F6',
          'icon': 'add_circle',
          'is_initial': true,
        },
        {
          'status': 'Pago',
          'status_order': 2,
          'color': '#22C55E',
          'icon': 'task_alt',
          'is_final': true,
        },
      ],
    };

    test('fromJson desserializa as etapas embutidas', () {
      final preset = WorkspacePreset.fromJson(json);

      expect(preset.stages, hasLength(2));
      expect(preset.stages.first.isInitial, isTrue);
      expect(preset.stages.last.isFinal, isTrue);
      expect(preset.categoryLabel, equals('Financeiro'));
      expect(preset.usageCount, equals(4));
    });

    test('freshStages devolve cópias independentes do preset', () {
      final preset = WorkspacePreset.fromJson(json);
      final fresh = preset.freshStages();

      fresh.first.status = 'Renomeado';

      expect(preset.stages.first.status, equals('Novo'),
          reason: 'editar o rascunho não pode alterar o preset carregado');
    });

    test('preset de sistema nunca é editável, nem por admin global', () {
      final system = WorkspacePreset.fromJson({...json, 'is_system': true});

      expect(system.canEdit('user-1', isGlobalAdmin: true), isFalse);
    });

    test('dono edita o próprio preset; terceiro sem papel global, não', () {
      final preset = WorkspacePreset.fromJson(json);

      expect(preset.canEdit('user-1'), isTrue);
      expect(preset.canEdit('user-2'), isFalse);
      expect(preset.canEdit('user-2', isGlobalAdmin: true), isTrue);
    });
  });

  group('WorkspacePalette', () {
    test('toColor aceita hex com e sem cerquilha', () {
      expect(WorkspacePalette.toColor('#3B82F6'),
          equals(WorkspacePalette.toColor('3B82F6')));
    });

    test('hex inválido cai no fallback em vez de estourar', () {
      expect(WorkspacePalette.toColor('não-é-cor'),
          equals(const Color(0xFF6B7280)));
    });

    test('fromColor devolve hex reaproveitável pelo toColor', () {
      const original = Color(0xFF3B82F6);
      final hex = WorkspacePalette.fromColor(original);

      expect(hex, equals('#3B82F6'));
      expect(WorkspacePalette.toColor(hex), equals(original));
    });
  });
}
