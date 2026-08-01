import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/gmp_card.dart';

/// About Gold Master Pro — what the app does, how it reaches its numbers,
/// and who built it. Reached from the Home drawer.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _intro =
      'Gold Master Pro is a focused analysis workspace for spot gold '
      '(XAUUSD). It brings live pricing, classical technical analysis and a '
      'transparent scoring engine into one place, so you can judge the gold '
      'market on evidence instead of instinct.';

  static const String _philosophy =
      'Every number in Gold Master Pro is computed, never guessed. The Gold '
      'Master Score is a deterministic weighted rubric — the same market data '
      'always produces the same score, and the app shows you which components '
      'drove it. There is no black box, and no hidden model deciding for you.';

  static const List<(IconData, String, String)> _features = [
    (
      Icons.speed_outlined,
      'Gold Master Score',
      'Five weighted components — trend, momentum, key-level position, '
          'Fibonacci context and candlestick structure — resolved into a '
          'single 0–100 reading with a bias, a confidence figure and a '
          'plain-English breakdown of what moved it.',
    ),
    (
      Icons.candlestick_chart_outlined,
      'Full technical suite',
      'SMMA 21/50/200, RSI with pivot-based divergence detection, Stochastic '
          'RSI, MACD, ADX with directional movement, ATR, automatic Fibonacci '
          'retracements, daily and weekly key levels, and fourteen '
          'candlestick patterns detected geometrically.',
    ),
    (
      Icons.route_outlined,
      'Structured trade plans',
      'When conviction is genuinely high — a score at or above 80, or at or '
          'below 20 — the app derives a concrete plan: entry zone, an '
          'ATR-clamped stop behind the recent swing, and two targets drawn '
          'from real key levels. In between, it stays flat and says so.',
    ),
    (
      Icons.fact_check_outlined,
      'An honest track record',
      'One signal runs at a time. It closes only at its target or its stop, '
          'booked at the level — and a bar that touches both counts as the '
          'stop. Results are never flattered, so the record you see is the '
          'record you got.',
    ),
    (
      Icons.notifications_active_outlined,
      'Alerts that reach you',
      'Price-crossing alerts and high-conviction signal alerts arrive as real '
          'device notifications while the app is running, so a setup is not '
          'missed because you were looking at another screen.',
    ),
    (
      Icons.event_note_outlined,
      'Context and record-keeping',
      'A this-week economic calendar covering the releases that actually move '
          'gold, a live multi-asset watchlist, and a trading journal for '
          'recording your own decisions and reviewing them later.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          _header(),
          GmpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SectionLabel('Overview'),
                SizedBox(height: 10),
                Text(_intro, style: _body),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: SectionLabel('What it does'),
          ),
          for (final (icon, title, detail) in _features)
            _feature(icon, title, detail),
          GmpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SectionLabel('How it thinks'),
                SizedBox(height: 10),
                Text(_philosophy, style: _body),
              ],
            ),
          ),
          _credit(),
          _disclaimer(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        children: [
          const GmpEmblem(size: 88),
          const SizedBox(height: 14),
          ShaderMask(
            shaderCallback: (r) => AppTheme.goldGradient.createShader(r),
            child: const Text(
              AppConstants.appName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'EVIDENCE-BASED GOLD ANALYSIS',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          const GmpPill(
            text: 'Version ${AppConstants.appVersion}',
            color: AppTheme.gold,
          ),
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String title, String detail) {
    return GmpCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.gold, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(detail, style: _body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _credit() {
    return GmpCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTheme.surfaceAlt, AppTheme.surface],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Credits'),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.hairline),
                  color: AppTheme.background,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.architecture,
                    color: AppTheme.gold, size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gold Master Pro was designed and made by '
                      '${AppConstants.author}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Concept, product design and development.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _disclaimer() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Text(
        'Gold Master Pro provides market education and technical analysis '
        'only. Nothing in this app is financial advice, an offer, or a '
        'recommendation to buy or sell any instrument. Trading carries risk, '
        'including the loss of your capital. Always do your own research and '
        'consider your circumstances before acting.',
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  static const TextStyle _body = TextStyle(
    fontSize: 13,
    height: 1.5,
    color: AppTheme.textSecondary,
  );
}
