import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/providers/org_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _selectedDepartment;
  String? _selectedJob;
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String? _selectedBranchId;
  bool _isLoading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cpfCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  String _formatCpf(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 3 || i == 6) buf.write('.');
      if (i == 9) buf.write('-');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  String _formatPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 0) buf.write('(');
      if (i == 2) buf.write(') ');
      if (i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  bool _isValidCpf(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(digits[i]) * (10 - i);
    }
    int remainder = (sum * 10) % 11;
    if (remainder == 10) remainder = 0;
    if (remainder != int.parse(digits[9])) return false;

    sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += int.parse(digits[i]) * (11 - i);
    }
    remainder = (sum * 10) % 11;
    if (remainder == 10) remainder = 0;
    return remainder == int.parse(digits[10]);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isValidCpf(_cpfCtrl.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('CPF inválido.'),
          backgroundColor: AppConstants.danger));
      return;
    }

    if (_passwordCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A senha deve ter pelo menos 6 caracteres.'),
          backgroundColor: AppConstants.danger));
      return;
    }

    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('As senhas não coincidem.'),
          backgroundColor: AppConstants.danger));
      return;
    }

    if (_selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione uma filial.'),
          backgroundColor: AppConstants.danger));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authResponse = await supabase.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        data: {
          'full_name': _nameCtrl.text.trim(),
          'cpf': _cpfCtrl.text.replaceAll(RegExp(r'\D'), ''),
          'phone': _phoneCtrl.text.replaceAll(RegExp(r'\D'), ''),
          'branch_id': _selectedBranchId,
          'department_id': _selectedDepartment,
          'job_position_id': _selectedJob,
        },
      );

      if (mounted && authResponse.user != null) {
        await supabase.auth.signOut();
        if (!mounted) return;
        _showSuccessDialog();
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppConstants.danger));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'), backgroundColor: AppConstants.danger));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(Icons.check_circle_rounded,
            color: theme.colorScheme.primary, size: 48),
        title: Text('Cadastro Enviado!',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text(
          'Seus dados foram registrados e serão analisados pela equipe de TI.\n\nVocê receberá acesso ao aplicativo assim que seu cadastro for aprovado.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/login');
            },
            child: Text('Voltar ao Login',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchesState = ref.watch(branchesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final screenSize = MediaQuery.of(context).size;
    final isSmallPhone = screenSize.height < 700;

    return Scaffold(
      appBar: AppBar(
        title: Text('Criar Conta',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [theme.scaffoldBackgroundColor, theme.colorScheme.surface]
                : [
                    theme.colorScheme.primary.withValues(alpha: 0.06),
                    theme.colorScheme.surface
                  ],
          ),
        ),
        child: SafeArea(
          child: branchesState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erro: $e')),
            data: (branches) => LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.maxWidth > 600;
                return SingleChildScrollView(
                  padding: EdgeInsets.all(isTablet ? 32 : 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: isTablet ? 520 : double.infinity),
                      child: _buildForm(
                          theme, isDark, primaryColor, branches, isSmallPhone),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme, bool isDark, Color primaryColor,
      List branches, bool isSmallPhone) {
    return Container(
      padding: EdgeInsets.all(isSmallPhone ? 20 : 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme, primaryColor),
            SizedBox(height: isSmallPhone ? 20 : 28),
            _buildSectionTitle('Dados Pessoais', theme, primaryColor),
            const SizedBox(height: 14),
            _buildTextField(
                controller: _nameCtrl,
                hint: 'Nome Completo',
                icon: Icons.person_outline,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Obrigatório' : null),
            const SizedBox(height: 12),
            _buildTextField(
                controller: _cpfCtrl,
                hint: 'CPF',
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11)
                ],
                onChanged: (v) {
                  final formatted = _formatCpf(v);
                  _cpfCtrl.value = TextEditingValue(
                    text: formatted,
                    selection:
                        TextSelection.collapsed(offset: formatted.length),
                  );
                },
                validator: (v) =>
                    v == null || v.isEmpty ? 'Obrigatório' : null),
            const SizedBox(height: 12),
            _buildTextField(
                controller: _phoneCtrl,
                hint: 'Telefone',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11)
                ],
                onChanged: (v) {
                  final formatted = _formatPhone(v);
                  _phoneCtrl.value = TextEditingValue(
                    text: formatted,
                    selection:
                        TextSelection.collapsed(offset: formatted.length),
                  );
                }),
            const SizedBox(height: 20),
            _buildSectionTitle('Credenciais', theme, primaryColor),
            const SizedBox(height: 14),
            _buildTextField(
                controller: _emailCtrl,
                hint: 'E-mail Corporativo',
                icon: Icons.business_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.isEmpty
                    ? 'Obrigatório'
                    : (!v.contains('@') ? 'E-mail inválido' : null)),
            const SizedBox(height: 12),
            _buildTextField(
                controller: _passwordCtrl,
                hint: 'Senha',
                icon: Icons.lock_outline_rounded,
                obscure: _obscure,
                suffix: IconButton(
                    icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure)),
                validator: (v) => v == null || v.isEmpty
                    ? 'Obrigatório'
                    : (v.length < 6 ? 'Mínimo 6 caracteres' : null)),
            const SizedBox(height: 12),
            _buildTextField(
                controller: _confirmPasswordCtrl,
                hint: 'Confirmar Senha',
                icon: Icons.lock_outline_rounded,
                obscure: _obscureConfirm,
                suffix: IconButton(
                    icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm)),
                validator: (v) => v == null || v.isEmpty
                    ? 'Obrigatório'
                    : (v != _passwordCtrl.text
                        ? 'Senhas não coincidem'
                        : null)),
            const SizedBox(height: 20),
            _buildSectionTitle('Informações Corporativas', theme, primaryColor),
            const SizedBox(height: 14),
            _buildDropdown(
                hint: 'Filial *',
                value: _selectedBranchId,
                items: branches
                    .map((b) => {'id': b['id'], 'name': b['name']})
                    .toList(),
                onChanged: (v) => setState(() => _selectedBranchId = v),
                validator: (v) => v == null ? 'Selecione uma filial' : null),
            const SizedBox(height: 12),
            _buildDropdown(
                hint: 'Departamento',
                value: _selectedDepartment,
                items: ref.watch(departmentsProvider).when(
                      data: (depts) => depts
                          .map((d) => {'id': d['id'], 'name': d['name']})
                          .toList(),
                      loading: () => [],
                      error: (_, __) => [],
                    ),
                onChanged: (v) => setState(() {
                      _selectedDepartment = v;
                      _selectedJob = null; // Reset cargo ao mudar departamento
                    })),
            const SizedBox(height: 12),
            _buildDropdown(
                hint: 'Cargo',
                value: _selectedJob,
                items:
                    ref.watch(jobPositionsProvider(_selectedDepartment)).when(
                          data: (jobs) => jobs
                              .map((j) => {'id': j['id'], 'name': j['name']})
                              .toList(),
                          loading: () => [],
                          error: (_, __) => [],
                        ),
                onChanged: (v) => setState(() => _selectedJob = v)),
            const SizedBox(height: 28),
            SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: _isLoading
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.onPrimary))
                      : Text('Cadastrar',
                          style: GoogleFonts.inter(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                )),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Já tem conta?',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: theme.colorScheme.onSurfaceVariant)),
              TextButton(
                  onPressed: () => context.go('/login'),
                  child: Text('Entrar',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: primaryColor))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color primaryColor) {
    return Column(children: [
      Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Image.asset('assets/images/logo.png',
              height: 40,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.person_add_rounded,
                  size: 40, color: primaryColor))),
      const SizedBox(height: 14),
      Text('Novo Colaborador',
          style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface)),
      const SizedBox(height: 4),
      Text('Preencha seus dados corporativos',
          style: GoogleFonts.inter(
              fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }

  Widget _buildSectionTitle(String title, ThemeData theme, Color primaryColor) {
    return Row(children: [
      Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
              color: primaryColor, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Text(title,
          style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface))
    ]);
  }

  Widget _buildTextField(
      {required TextEditingController controller,
      required String hint,
      required IconData icon,
      bool obscure = false,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      void Function(String)? onChanged,
      String? Function(String?)? validator,
      Widget? suffix}) {
    final theme = Theme.of(context);
    return TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        validator: validator,
        style:
            GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
                fontSize: 13,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            prefixIcon: Icon(icon, color: theme.colorScheme.primary, size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: theme.colorScheme.primary, width: 2)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14)));
  }

  Widget _buildDropdown(
      {required String hint,
      required String? value,
      required List<Map<String, dynamic>> items,
      required void Function(String?) onChanged,
      String? Function(String?)? validator}) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<String>(
        initialValue: value,
        onChanged: onChanged,
        validator: validator,
        style:
            GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
                fontSize: 13,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            prefixIcon: Icon(Icons.business_outlined,
                color: theme.colorScheme.primary, size: 20),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: theme.colorScheme.primary, width: 2)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
        items: items
            .map((item) => DropdownMenuItem(
                value: item['id'] as String,
                child: Text(item['name'] as String)))
            .toList());
  }
}
