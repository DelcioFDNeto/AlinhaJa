import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/features/workflow/models/workflow_enums.dart';
import 'package:alinha_ja/features/workflow/providers/workflow_provider.dart';
import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'dart:typed_data';

class CreateCardSheet extends ConsumerStatefulWidget {
  final String channelId;
  final String channelName;
  final WorkflowCardType? initialType;
  final VoidCallback onCreated;

  const CreateCardSheet({
    super.key,
    required this.channelId,
    required this.channelName,
    this.initialType,
    required this.onCreated,
  });

  @override
  ConsumerState<CreateCardSheet> createState() => _CreateCardSheetState();
}

class _CreateCardSheetState extends ConsumerState<CreateCardSheet> {
  final _formKey = GlobalKey<FormState>();
  WorkflowCardType _selectedType = WorkflowCardType.generic;

  // Campos comuns
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedPriority = 'medium';

  String _selectedStatus = 'novo';

  // Conta Pagar
  final _supplierController = TextEditingController();
  final _expenseDescriptionController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime? _dueDate;
  final _costCenterController = TextEditingController();

  // Liberação de Pedido (legado: fat_moto)
  final _clientNameController = TextEditingController();
  final _orderNumberController = TextEditingController();
  final _fichaNumberController = TextEditingController();
  final _consultantController = TextEditingController();

  // Documentação/Cadastro (legado: emplacamento)
  final _clientCpfCnpjController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _chassisNumberController = TextEditingController();
  final _plateController = TextEditingController();
  final _branchController = TextEditingController();

  // Faturamento OS
  final _osNumberController = TextEditingController();
  final _budgetNumberController = TextEditingController();
  final _billingTypeController = TextEditingController();
  final _itemsDetailsController = TextEditingController();

  // B2: Proper controller for observations field (was orphan before)
  final _observationsController = TextEditingController();

  // Anexos
  final List<PlatformFile> _selectedFiles = [];
  bool _isZipping = false;

  @override
  void initState() {
    super.initState();
    // B1: Read status config synchronously in initState (ConsumerStatefulWidget supports ref.read)
    final workflowState = ref.read(workflowProvider(widget.channelId));
    _selectedStatus = _getInitialStatus(workflowState);

    if (widget.initialType != null) {
      _selectedType = widget.initialType!;
    } else {
      _selectedType = _detectCardTypeFromChannel(widget.channelName);
    }
  }

  WorkflowCardType _detectCardTypeFromChannel(String channelName) {
    final name = channelName.toLowerCase();
    if (name.contains('contas a pagar') || name.contains('conta pagar')) {
      return WorkflowCardType.contaPagar;
    } else if (name.contains('liberação de pedido') ||
        name.contains('liberação pedido') ||
        name.contains('fat moto') ||
        name.contains('faturamento moto')) {
      return WorkflowCardType.fatMoto;
    } else if (name.contains('documentação') ||
        name.contains('cadastro') ||
        name.contains('emplacamento')) {
      return WorkflowCardType.emplacamento;
    } else if (name.contains('faturamento os/produtos') ||
        name.contains('faturamento os/peças') ||
        name.contains('faturamento os') ||
        (name.contains('faturamento') && name.contains('produtos')) ||
        (name.contains('faturamento') && name.contains('peças'))) {
      return WorkflowCardType.faturamentoOs;
    } else if (name.contains('avisos gerais') || name.contains('aviso')) {
      return WorkflowCardType.aviso;
    }
    return WorkflowCardType.generic;
  }

  String _getInitialStatus(WorkflowState? workflowState) {
    if (workflowState != null && workflowState.initialStatus != null) {
      return workflowState.initialStatus!;
    }
    final name = widget.channelName.toLowerCase();
    if (name.contains('contas a pagar')) return 'Novo';
    if (name.contains('fat moto') || name.contains('liberação de pedido')) {
      return 'Solicitação criada';
    }
    if (name.contains('emplacamento') ||
        name.contains('documentação') ||
        name.contains('cadastro')) {
      return 'Solicitação aberta';
    }
    if (name.contains('faturamento')) return 'Aberto';
    if (name.contains('avisos')) return 'Ativo';
    return 'novo';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _supplierController.dispose();
    _expenseDescriptionController.dispose();
    _amountController.dispose();
    _costCenterController.dispose();
    _clientNameController.dispose();
    _orderNumberController.dispose();
    _fichaNumberController.dispose();
    _consultantController.dispose();
    _clientCpfCnpjController.dispose();
    _vehicleModelController.dispose();
    _chassisNumberController.dispose();
    _plateController.dispose();
    _branchController.dispose();
    _osNumberController.dispose();
    _budgetNumberController.dispose();
    _billingTypeController.dispose();
    _itemsDetailsController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHeader(theme),
          const Divider(height: 1),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildTypeSelector(theme),
                  const SizedBox(height: 16),
                  _buildFormCard(theme, 'Informações Básicas',
                      Icons.info_outline, _buildCommonFields(theme)),
                  const SizedBox(height: 16),
                  if (_selectedType != WorkflowCardType.generic) ...[
                    _buildFormCard(theme, 'Detalhes Específicos',
                        Icons.article_outlined, _buildSpecificFields(theme)),
                    const SizedBox(height: 16),
                  ],
                  _buildFormCard(theme, 'Anexos', Icons.attach_file,
                      _buildAttachmentsField(theme)),
                ],
              ),
            ),
          ),
          _buildFooter(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.add_circle_outline,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nova Solicitação',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.channelName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de Card',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: WorkflowCardType.values.map((type) {
            final isSelected = _selectedType == type;
            return GestureDetector(
              onTap: () {
                if (_selectedType != type) {
                  _clearSpecificFields();
                  setState(() => _selectedType = type);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getIconForType(type),
                      size: 16,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      type.label,
                      style: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFormCard(
      ThemeData theme, String title, IconData icon, Widget content) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }

  Widget _buildCommonFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _titleController,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Título', Icons.title),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          maxLines: 3,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Descrição', Icons.description),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _observationsController,
          maxLines: 2,
          decoration: _inputDecoration('Observações', Icons.notes),
        ),
        const SizedBox(height: 16),
        Text(
          'Prioridade',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _PriorityChip(
              label: 'Baixa',
              value: 'low',
              color: const Color(0xFF6B7280),
              selected: _selectedPriority == 'low',
              onTap: () => setState(() => _selectedPriority = 'low'),
            ),
            _PriorityChip(
              label: 'Média',
              value: 'medium',
              color: const Color(0xFFF59E0B),
              selected: _selectedPriority == 'medium',
              onTap: () => setState(() => _selectedPriority = 'medium'),
            ),
            _PriorityChip(
              label: 'Alta',
              value: 'high',
              color: const Color(0xFFF97316),
              selected: _selectedPriority == 'high',
              onTap: () => setState(() => _selectedPriority = 'high'),
            ),
            _PriorityChip(
              label: 'Urgente',
              value: 'urgent',
              color: const Color(0xFFEF4444),
              selected: _selectedPriority == 'urgent',
              onTap: () => setState(() => _selectedPriority = 'urgent'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpecificFields(ThemeData theme) {
    switch (_selectedType) {
      case WorkflowCardType.contaPagar:
        return _buildContaPagarFields(theme);
      case WorkflowCardType.fatMoto:
        return _buildFatMotoFields(theme);
      case WorkflowCardType.emplacamento:
        return _buildEmplacamentoFields(theme);
      case WorkflowCardType.faturamentoOs:
        return _buildFaturamentoOsFields(theme);
      case WorkflowCardType.aviso:
        return _buildAvisoFields(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildContaPagarFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _supplierController,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Fornecedor', Icons.business),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _expenseDescriptionController,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration:
              _inputDecoration('Descrição da Despesa', Icons.description),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Valor', Icons.attach_money),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _selectDueDate(context),
                child: InputDecorator(
                  decoration:
                      _inputDecoration('Vencimento', Icons.calendar_today),
                  child: Text(
                    _dueDate != null
                        ? '${_dueDate!.day.toString().padLeft(2, '0')}/${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.year}'
                        : 'Selecione',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _costCenterController,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Centro Custo', Icons.account_balance),
        ),
      ],
    );
  }

  Widget _buildFatMotoFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _clientNameController,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Nome do Cliente', Icons.person),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _orderNumberController,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                decoration: _inputDecoration('Número do Pedido', Icons.receipt),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _fichaNumberController,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                decoration:
                    _inputDecoration('Referência Interna', Icons.description),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _consultantController,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration:
              _inputDecoration('Responsável/Vendedor', Icons.support_agent),
        ),
      ],
    );
  }

  Widget _buildEmplacamentoFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _clientNameController,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Nome do Cliente', Icons.person),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _clientCpfCnpjController,
          decoration: _inputDecoration('CPF/CNPJ', Icons.badge_outlined),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _vehicleModelController,
                decoration: _inputDecoration(
                    'Item/Objeto', Icons.inventory_2_outlined),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _plateController,
                textCapitalization: TextCapitalization.characters,
                decoration: _inputDecoration(
                    'Código/Identificação', Icons.confirmation_number_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _chassisNumberController,
          decoration:
              _inputDecoration('Nº do Documento/Série', Icons.qr_code_outlined),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _consultantController,
                decoration: _inputDecoration('Responsável', Icons.storefront),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _branchController,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                decoration: _inputDecoration('Filial', Icons.business),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFaturamentoOsFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _osNumberController,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                decoration:
                    _inputDecoration('Número da OS', Icons.receipt_long),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _budgetNumberController,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                decoration: _inputDecoration(
                    'Número do Orçamento', Icons.request_quote),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _billingTypeController,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Tipo de Faturamento', Icons.category),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _itemsDetailsController,
          maxLines: 3,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
          decoration: _inputDecoration('Detalhes dos Itens', Icons.list_alt),
        ),
      ],
    );
  }

  Widget _buildAvisoFields(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Avisos são comunicados que aparecem no canal para todos os membros. Use a aba Conversa para enviar.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom > 0
              ? MediaQuery.of(context).viewInsets.bottom + 20
              : 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isZipping ? null : _createCard,
          icon: _isZipping
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.add, color: Colors.white),
          label: Text(
              _isZipping ? 'Processando Anexos...' : 'Enviar Solicitação',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: theme.colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  IconData _getIconForType(WorkflowCardType type) {
    switch (type) {
      case WorkflowCardType.contaPagar:
        return Icons.payments_outlined;
      case WorkflowCardType.fatMoto:
        return Icons.fact_check_outlined;
      case WorkflowCardType.emplacamento:
        return Icons.description_outlined;
      case WorkflowCardType.faturamentoOs:
        return Icons.receipt_outlined;
      case WorkflowCardType.aviso:
        return Icons.campaign_outlined;
      default:
        return Icons.assignment_outlined;
    }
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _dueDate = date);
    }
  }

  Future<String?> _compressAndUploadAttachments() async {
    if (_selectedFiles.isEmpty) return null;

    setState(() => _isZipping = true);

    try {
      final archive = Archive();

      for (var f in _selectedFiles) {
        final bytes = f.bytes;
        if (bytes != null && bytes.isNotEmpty) {
          archive.addFile(ArchiveFile(f.name, bytes.length, bytes));
        }
      }

      final zipEncoder = ZipEncoder();
      final zipData = Uint8List.fromList(zipEncoder.encode(archive));

      final zipFileName = 'anexos_${DateTime.now().millisecondsSinceEpoch}.zip';
      final storagePath = 'workflow_attachments/$zipFileName';

      await supabase.storage
          .from('chat-media')
          .uploadBinary(storagePath, zipData);

      final publicUrl =
          supabase.storage.from('chat-media').getPublicUrl(storagePath);
      return publicUrl;
    } catch (e) {
      debugPrint("Erro no upload do ZIP: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Falha ao processar anexos: $e')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _isZipping = false);
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true, // Necessário para Web — carrega bytes em memória
    );
    if (result != null) {
      setState(() {
        _selectedFiles.addAll(result.files);
      });
    }
  }

  Widget _buildAttachmentsField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedType == WorkflowCardType.emplacamento)
          Container(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              '• Documentos do cliente (RG/CNH ou contrato social)\n• Nota fiscal\n• Comprovantes\n• Procuração (se aplicável)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        InkWell(
          onTap: _pickFiles,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.upload_file, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedFiles.isEmpty
                        ? 'Adicionar Anexos (PDFs/Imagens serão Zipados)'
                        : '${_selectedFiles.length} arquivo(s) selecionado(s)',
                    style: TextStyle(
                      color: _selectedFiles.isEmpty
                          ? theme.colorScheme.outline
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_selectedFiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _selectedFiles.map((f) {
              return Chip(
                label: Text(f.name, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() {
                    _selectedFiles.remove(f);
                  });
                },
              );
            }).toList(),
          )
        ],
      ],
    );
  }

  Future<void> _createCard() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedType == WorkflowCardType.contaPagar && _dueDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('A data de vencimento é obrigatória.'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (_selectedType == WorkflowCardType.emplacamento &&
        _selectedFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Para Documentação/Cadastro, anexar os documentos é obrigatório.'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    String? zipUrl;
    if (_selectedFiles.isNotEmpty) {
      zipUrl = await _compressAndUploadAttachments();
      if (zipUrl == null) {
        // Aborta a criação se o upload falhou (já informou via SnackBar no método upload)
        return;
      }
    }

    final notifier = ref.read(workflowProvider(widget.channelId).notifier);
    final workflowState = ref.read(workflowProvider(widget.channelId));
    final now = DateTime.now();

    final currentUserId = supabase.auth.currentUser?.id;
    final assignedOperatorId = workflowState.assignmentMode == 'single_operator'
        ? workflowState.defaultOperatorId
        : null;

    final card = WorkflowCard(
      id: '',
      channelId: widget.channelId,
      cardType: _selectedType,
      title: _titleController.text,
      description: _descriptionController.text.isNotEmpty
          ? _descriptionController.text
          : null,
      priority: WorkflowPriority.fromString(_selectedPriority),
      status: _selectedStatus,
      requestedBy: currentUserId,
      assignedTo: assignedOperatorId,
      createdAt: now,
      updatedAt: now,
      attachments: zipUrl != null
          ? [
              {'name': 'Anexos ZIP', 'url': zipUrl, 'type': 'application/zip'}
            ]
          : [],
      // Conta Pagar
      supplier:
          _supplierController.text.isNotEmpty ? _supplierController.text : null,
      expenseDescription: _expenseDescriptionController.text.isNotEmpty
          ? _expenseDescriptionController.text
          : null,
      amount: double.tryParse(
          _amountController.text.replaceAll('.', '').replaceAll(',', '.')),
      dueDate: _dueDate,
      costCenter: _costCenterController.text.isNotEmpty
          ? _costCenterController.text
          : null,
      // Liberação de Pedido
      clientName: _clientNameController.text.isNotEmpty
          ? _clientNameController.text
          : null,
      orderNumber: _orderNumberController.text.isNotEmpty
          ? _orderNumberController.text
          : null,
      fichaNumber: _fichaNumberController.text.isNotEmpty
          ? _fichaNumberController.text
          : null,
      consultant: _consultantController.text.isNotEmpty
          ? _consultantController.text
          : null,
      // Documentação/Cadastro
      clientCpfCnpj: _clientCpfCnpjController.text.isNotEmpty
          ? _clientCpfCnpjController.text
          : null,
      vehicleModel: _vehicleModelController.text.isNotEmpty
          ? _vehicleModelController.text
          : null,
      chassisNumber: _chassisNumberController.text.isNotEmpty
          ? _chassisNumberController.text
          : null,
      plate: _plateController.text.isNotEmpty ? _plateController.text : null,
      branch: _branchController.text.isNotEmpty ? _branchController.text : null,
      metadata: {
        'assignment_mode': workflowState.assignmentMode,
        'operator_ids': workflowState.operatorIds,
      },
      // Faturamento OS
      osNumber:
          _osNumberController.text.isNotEmpty ? _osNumberController.text : null,
      budgetNumber: _budgetNumberController.text.isNotEmpty
          ? _budgetNumberController.text
          : null,
      billingType: _billingTypeController.text.isNotEmpty
          ? _billingTypeController.text
          : null,
      itemsDetails: _itemsDetailsController.text.isNotEmpty
          ? _itemsDetailsController.text
          : null,
      // B2: Map observations field from proper controller
      observations: _observationsController.text.isNotEmpty
          ? _observationsController.text
          : null,
    );

    try {
      await notifier.createCard(card);
      widget.onCreated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Solicitação criada com sucesso!'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar card: $e')),
        );
      }
    }
  }

  /// Limpa os controllers específicos para evitar dados residuais ao trocar tipo.
  void _clearSpecificFields() {
    _supplierController.clear();
    _expenseDescriptionController.clear();
    _amountController.clear();
    _costCenterController.clear();
    _clientNameController.clear();
    _orderNumberController.clear();
    _fichaNumberController.clear();
    _consultantController.clear();
    _clientCpfCnpjController.clear();
    _vehicleModelController.clear();
    _chassisNumberController.clear();
    _plateController.clear();
    _branchController.clear();
    _osNumberController.clear();
    _budgetNumberController.clear();
    _billingTypeController.clear();
    _itemsDetailsController.clear();
    _observationsController.clear();
    _dueDate = null;
  }
}

class _PriorityChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PriorityChip({
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : null,
                fontWeight: selected ? FontWeight.bold : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
