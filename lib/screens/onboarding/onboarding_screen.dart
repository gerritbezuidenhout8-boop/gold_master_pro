import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/app_settings.dart';
import '../../widgets/brand.dart';
import '../../widgets/gold_button.dart';
import '../shell/root_shell.dart';

/// One-time onboarding intro (spec: Onboarding). A small carousel that
/// frames what the app does — analysis, not advice — then drops into the
/// shell. Shown only until [AppSettings.onboardingComplete] is set.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  const _OnboardingPage(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      Icons.speed_rounded,
      'The Gold Master Score',
      'A single 0–100 read on gold, blending trend, momentum, key levels '
          'and candle structure into one honest bias — bullish, bearish or '
          'neutral, with its reasoning shown.',
    ),
    _OnboardingPage(
      Icons.candlestick_chart_rounded,
      'Multi-timeframe analysis',
      'Live XAU/USD price, a full indicator suite (SMMA, RSI, StochRSI, '
          'MACD, ADX, Fibonacci) and a 5m→1h consensus so you see how the '
          'timeframes line up.',
    ),
    _OnboardingPage(
      Icons.notifications_active_rounded,
      'Alerts & journal',
      'Set price alerts that ping you in-app when gold crosses your level, '
          'and log your trades to track win-rate, P&L and R-multiples over '
          'time.',
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

  Future<void> _finish() async {
    await AppSettings.instance.setOnboardingComplete(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const GmpEmblem(size: 84),
            const SizedBox(height: 10),
            const GmpWordmark(),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _slide(_pages[i]),
              ),
            ),
            _dots(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GoldButton(
                label: _isLast ? 'Get Started' : 'Next',
                icon: _isLast ? Icons.arrow_forward_rounded : null,
                onPressed: _next,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 14, 28, 16),
              child: Text(
                'Gold Master Pro provides education and analysis, not '
                'financial advice. Trading carries risk.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slide(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Icon(page.icon, size: 44, color: AppTheme.gold),
          ),
          const SizedBox(height: 28),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _pages.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == _index ? AppTheme.gold : AppTheme.hairline,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
