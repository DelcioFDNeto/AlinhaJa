import 'package:flutter/material.dart';


import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/globals.dart';
import '../services/mfa_service.dart';
import '../services/two_factor_service.dart';
import 'package:alinha_ja/core/constants.dart';




class SplashScreen extends ConsumerStatefulWidget {

  const SplashScreen({super.key});



  @override

  ConsumerState<SplashScreen> createState() => _SplashScreenState();

}



class _SplashScreenState extends ConsumerState<SplashScreen>

    with SingleTickerProviderStateMixin {

  late final AnimationController _controller;

  late final Animation<double> _fadeIn;

  late final Animation<double> _scale;



  @override

  void initState() {

    super.initState();



    _controller = AnimationController(

      vsync: this,

      duration: const Duration(milliseconds: 1800),

    );



    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(

      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),

    );



    _controller.forward();



    // Navega automaticamente após a animação

    Future.delayed(const Duration(milliseconds: 2500), _navigate);

  }



  Future<void> _navigate() async {

    if (!mounted) return;

    final session = supabase.auth.currentSession;

    if (session != null) {

      // Verificar se o usuário está ativo (aprovado pelo TI)

      try {

        final userId = supabase.auth.currentUser?.id;

        if (userId != null) {

          final row = await supabase

              .from('users')

              .select('is_active')

              .eq('id', userId)

              .maybeSingle();



          if (row == null || row['is_active'] == false) {

            // usuário pendente de aprovação — deslogar

            Globals.is2faVerified = false;

            await supabase.auth.signOut();

            if (mounted) context.go('/login');

            return;

          }

        }

      } catch (_) {

        // Se falhar a consulta, prosseguir para login por segurança

        Globals.is2faVerified = false;

        await supabase.auth.signOut();

        if (mounted) context.go('/login');

        return;

      }

      // Sessão restaurada: decide pelo nível de garantia (AAL) da sessão.

      final status = MfaService().evaluate();

      if (!mounted) return;

      switch (status) {

        case MfaGateStatus.verified:

          Globals.is2faVerified = true;

          context.go('/chats');

        case MfaGateStatus.notEnrolled:

          // Sem app autenticador: cai no 2FA por e-mail (apenas se o
          // usuário ativou o 2FA por e-mail).
          final gateOk = await TwoFactorService().emailGateSatisfied();
          if (!mounted) return;
          if (gateOk) {
            Globals.is2faVerified = true;
            context.go('/chats');
          } else {
            Globals.is2faVerified = false;
            context.go('/verify-email-2fa');
          }

        case MfaGateStatus.challengeRequired:

          Globals.is2faVerified = false;

          context.go('/verify-2fa');

      }

    } else {

      context.go('/login');

    }

  }



  @override

  void dispose() {

    _controller.dispose();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);



    return Scaffold(

      backgroundColor: theme.colorScheme.surface,

      body: Center(

        child: FadeTransition(

          opacity: _fadeIn,

          child: ScaleTransition(

            scale: _scale,

            child: Column(

              mainAxisSize: MainAxisSize.min,

              children: [

                // Logo do AlinhaJá


                ClipRRect(

                  borderRadius: BorderRadius.circular(24),

                  child: Image.asset(

                    'assets/images/logo.png',

                    width: 120,

                    height: 120,

                  ),

                ),

                const SizedBox(height: 32),



                // Nome do App

                Text(

                  AppConstants.appName,


                  style: theme.textTheme.displaySmall?.copyWith(

                    fontWeight: FontWeight.w900,

                    letterSpacing: 2,

                    color: theme.colorScheme.primary,

                  ),

                ),

                const SizedBox(height: 8),



                // Tagline

                Text(

                  'Comunicação corporativa inteligente',

                  style: theme.textTheme.bodyMedium?.copyWith(

                    color: theme.colorScheme.onSurfaceVariant,

                    letterSpacing: 0.5,

                  ),

                ),



                const SizedBox(height: 48),



                // Indicador de carregamento sutil

                SizedBox(

                  width: 24,

                  height: 24,

                  child: CircularProgressIndicator(

                    strokeWidth: 2,

                    color: theme.colorScheme.primary.withValues(alpha: 0.5),

                  ),

                ),

              ],

            ),

          ),

        ),

      ),

    );

  }

}



