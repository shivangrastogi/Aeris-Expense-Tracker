import 'dart:async';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/quote_service.dart';

/// Auto-advancing motivational quotes, each on its own **funky gradient
/// slide**. Hold to pause, swipe for next/previous, resumes on release.
class QuoteCarousel extends StatefulWidget {
  final List<Quote> quotes;
  const QuoteCarousel({super.key, required this.quotes});

  @override
  State<QuoteCarousel> createState() => _QuoteCarouselState();
}

class _QuoteCarouselState extends State<QuoteCarousel> {
  final _ctrl = PageController();
  Timer? _timer;
  int _page = 0;

  // A rotating set of distinct, vibrant slide themes.
  static const _themes = <List<Color>>[
    [Color(0xFF0EA5A4), Color(0xFF6366F1)], // teal → indigo
    [Color(0xFFF97316), Color(0xFFEC4899)], // orange → pink (sunset)
    [Color(0xFF8B5CF6), Color(0xFF4F46E5)], // violet → indigo
    [Color(0xFF10B981), Color(0xFF0EA5A4)], // emerald → teal
    [Color(0xFF3B82F6), Color(0xFF06B6D4)], // blue → cyan
    [Color(0xFF1F2937), Color(0xFF0F766E)], // slate → teal (dark)
  ];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    if (widget.quotes.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_ctrl.hasClients) return;
      final next = (_page + 1) % widget.quotes.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  void _pause() => _timer?.cancel();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 116,
            child: Listener(
              onPointerDown: (_) => _pause(),
              onPointerUp: (_) => _start(),
              onPointerCancel: (_) => _start(),
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: widget.quotes.length,
                itemBuilder: (_, i) =>
                    _slide(widget.quotes[i], _themes[i % _themes.length]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.quotes.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _page == i ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? AerisColors.seed
                        : Colors.grey.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slide(Quote q, List<Color> colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: colors.last.withOpacity(0.32),
              blurRadius: 16,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          // Decorative oversized glyph
          Positioned(
            right: -6,
            top: -28,
            child: Text('”',
                style: TextStyle(
                    fontSize: 96,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.16))),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(q.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic)),
              ),
              if (q.author.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('— ${q.author}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
