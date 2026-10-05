import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/theme.dart';

/// Shown by [WidgetConfigureActivity] (a separate native Activity) right
/// after the OS finishes placing the AERIS widget on the home screen.
/// Confirms placement and tells Android the configuration is complete via
/// `HomeWidget.finishHomeWidgetConfigure()`.
class WidgetConfigureScreen extends StatefulWidget {
  const WidgetConfigureScreen({super.key});

  @override
  State<WidgetConfigureScreen> createState() => _WidgetConfigureScreenState();
}

class _WidgetConfigureScreenState extends State<WidgetConfigureScreen> {
  @override
  void initState() {
    super.initState();
    // Marks this launch as a widget-configure flow; sets a CANCELED result
    // so the OS removes the placeholder if the user backs out without
    // tapping "Done".
    HomeWidget.initiallyLaunchedFromHomeWidgetConfigure();
  }

  Future<void> _done() async {
    await HomeWidget.finishHomeWidgetConfigure();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AerisColors.heroGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.widgets_rounded,
                        size: 48, color: Colors.white),
                  ).animate().scale(
                      begin: const Offset(0.6, 0.6),
                      duration: 350.ms,
                      curve: Curves.easeOutBack),
                  const SizedBox(height: 24),
                  const Text(
                    'Widget added!',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4),
                  ).animate(delay: 100.ms).fadeIn(duration: 300.ms),
                  const SizedBox(height: 10),
                  Text(
                    'Your AERIS widget is now on your home screen. Long-press it anytime to move or resize.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.85)),
                  ).animate(delay: 150.ms).fadeIn(duration: 300.ms),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _done,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AerisColors.accent(context),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontFamily: kFontFamily, 
                            fontSize: 15, fontWeight: FontWeight.w800),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Done'),
                    ),
                  ).animate(delay: 200.ms).fadeIn(duration: 300.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
