import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alinha_ja/core/constants.dart';

/// Slide de conteúdo da introdução.
class _IntroSlide {
  final IconData? icon;
  final bool showLogo;
  final String title;
  final String subtitle;
  final Color accent;

  const _IntroSlide({
    this.icon,
    this.showLogo = false,
    required this.title,
    required this.subtitle,
    required this.accent,
  });
}

/// Carrossel de boas-vindas exibido no primeiro login.
///
/// Retorna (via `Navigator.pop`):
/// • `true`  → usuário optou por **fazer o tour** guiado;
/// • `false` → usuário **pulou** / apenas começou a usar.
///
/// Quando [enableTour] é `false` (ex.: desktop, onde os alvos do tour não
/// existem), a última tela mostra apenas "Começar" e sempre retorna `false`.
class WelcomeIntroScreen extends StatefulWidget {
  final bool enableTour;

  const WelcomeIntroScreen({super.key, this.enableTour = true});

  @override
  State<WelcomeIntroScreen> createState() => _WelcomeIntroScreenState();
}

class _WelcomeIntroScreenState extends State<WelcomeIntroScreen> {
  final _controller = PageController();
  int _page = 0;

  // Ícones em variantes BASE (codepoint 0xe___) — as variantes _rounded/
  // _outlined podem cair na faixa 0xf___ e sumir no build Web. Ver memória
  // "armadilha-icones-web-codepoint".
  static const _slides = <_IntroSlide>[
    _IntroSlide(
      showLogo: true,
      title: 'Bem-vindo ao ${AppConstants.appName}',
      subtitle:
          'A plataforma de comunicação e gestão operacional da sua empresa, '
          'reunida em um só lugar.',
      accent: Color(0xFF1A73E8),
    ),
    _IntroSlide(
      icon: Icons.campaign,
      title: 'Comunicação alinhada',
      subtitle:
          'Canais para avisos da empresa, conversas diretas e em grupo, e '
          'chamadas de voz e vídeo — tudo integrado.',
      accent: Color(0xFF1A73E8),
    ),
    _IntroSlide(
      icon: Icons.badge,
      title: 'Departamentos no seu ritmo',
      subtitle:
          'RH, Helpdesk e Painel Administrativo aparecem conforme as suas '
          'permissões, sem poluir a tela de quem não usa.',
      accent: Color(0xFFE65100),
    ),
    _IntroSlide(
      icon: Icons.lock,
      title: 'Seguro por padrão',
      subtitle:
          'Autenticação em duas etapas e mensagens protegidas mantêm as '
          'informações da empresa no lugar certo.',
      accent: Color(0xFF2E7D32),
    ),
  ];

  bool get _isLast => _page == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish(startTour: widget.enableTour);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish({required bool startTour}) => Navigator.of(context).pop(startTour);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Barra superior: "Pular"
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: TextButton(
                  onPressed: () => _finish(startTour: false),
                  child: Text(
                    'Pular',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // Slides
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
              ),
            ),

            // Indicadores de página
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final selected = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            // Ação principal
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isLast
                        ? (widget.enableTour ? 'Fazer o tour' : 'Começar')
                        : 'Continuar',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _IntroSlide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emblema (logo ou ícone)
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  slide.accent.withValues(alpha: 0.18),
                  slide.accent.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Center(
              child: slide.showLogo
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 96,
                        height: 96,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.chat_bubble,
                          size: 72,
                          color: slide.accent,
                        ),
                      ),
                    )
                  : Icon(slide.icon, size: 76, color: slide.accent),
            ),
          ),
          const SizedBox(height: 48),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
