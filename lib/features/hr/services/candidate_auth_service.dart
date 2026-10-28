import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alinha_ja/core/supabase_client.dart';

final candidateAuthProvider = StateNotifierProvider<CandidateAuthNotifier, CandidateAuthState>((ref) {
  return CandidateAuthNotifier();
});

class CandidateAuthState {
  final bool isLoading;
  final String? token;
  final Map<String, dynamic>? user;
  final List<dynamic>? candidaturas;
  final String? error;

  /// Fase 7: já existe currículo enviado que pode ser reaproveitado numa
  /// nova candidatura, dispensando o upload.
  final bool curriculoReaproveitavel;

  /// Extensão do currículo reaproveitável (`pdf`/`docx`), para exibição.
  final String? curriculoTipo;

  CandidateAuthState({
    this.isLoading = false,
    this.token,
    this.user,
    this.candidaturas,
    this.error,
    this.curriculoReaproveitavel = false,
    this.curriculoTipo,
  });

  bool get isLoggedIn => token != null && user != null;

  CandidateAuthState copyWith({
    bool? isLoading,
    String? token,
    Map<String, dynamic>? user,
    List<dynamic>? candidaturas,
    String? error,
    bool clearError = false,
    bool? curriculoReaproveitavel,
    String? curriculoTipo,
  }) {
    return CandidateAuthState(
      isLoading: isLoading ?? this.isLoading,
      token: token ?? this.token,
      user: user ?? this.user,
      candidaturas: candidaturas ?? this.candidaturas,
      error: clearError ? null : (error ?? this.error),
      curriculoReaproveitavel:
          curriculoReaproveitavel ?? this.curriculoReaproveitavel,
      curriculoTipo: curriculoTipo ?? this.curriculoTipo,
    );
  }
}

class CandidateAuthNotifier extends StateNotifier<CandidateAuthState> {
  static const _tokenKey = 'candidate_session_token';

  CandidateAuthNotifier() : super(CandidateAuthState()) {
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      state = state.copyWith(token: token);
      await fetchMe();
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await supabase.functions.invoke(
        'rh-candidatura',
        body: {'action': 'auth_login', 'email': email, 'password': password},
      );
      
      if (res.status == 200 && res.data != null && res.data['token'] != null) {
        final token = res.data['token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        state = state.copyWith(token: token);
        await fetchMe();
        return true;
      } else {
        state = state.copyWith(error: res.data?['error'] ?? 'Erro no login', isLoading: false);
        return false;
      }
    } catch (e) {
      state = state.copyWith(error: 'Falha na conexão', isLoading: false);
      return false;
    }
  }

  Future<bool> signup(String nome, String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await supabase.functions.invoke(
        'rh-candidatura',
        body: {'action': 'auth_signup', 'nome': nome, 'email': email, 'password': password},
      );
      
      state = state.copyWith(isLoading: false);
      if (res.status == 200 && res.data?['success'] == true) {
        return true;
      } else {
        state = state.copyWith(error: res.data?['error'] ?? 'Erro no cadastro', isLoading: false);
        return false;
      }
    } catch (e) {
      state = state.copyWith(error: 'Falha na conexão', isLoading: false);
      return false;
    }
  }

  Future<bool> verify(String token) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await supabase.functions.invoke(
        'rh-candidatura',
        body: {'action': 'auth_verify', 'token': token},
      );
      
      state = state.copyWith(isLoading: false);
      if (res.status == 200 && res.data?['success'] == true) {
        return true;
      } else {
        state = state.copyWith(error: res.data?['error'] ?? 'Código inválido', isLoading: false);
        return false;
      }
    } catch (e) {
      state = state.copyWith(error: 'Falha na conexão', isLoading: false);
      return false;
    }
  }

  Future<void> fetchMe() async {
    if (state.token == null) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await supabase.functions.invoke(
        'rh-candidatura',
        body: {'action': 'api_me'},
        headers: {'Authorization': 'Bearer ${state.token}'},
      );
      
      if (res.status == 200 && res.data != null) {
        state = state.copyWith(
          user: res.data['user'],
          candidaturas: res.data['candidaturas'],
          curriculoReaproveitavel:
              res.data['curriculo_reaproveitavel'] == true,
          curriculoTipo: res.data['curriculo_tipo'] as String?,
          isLoading: false,
        );
      } else {
        await logout();
      }
    } catch (e) {
      state = state.copyWith(error: 'Sessão expirada', isLoading: false);
      await logout();
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    state = CandidateAuthState();
  }
}
