import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MobilePageShell extends StatelessWidget {
  const MobilePageShell({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: AppTheme.canvas,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox.expand(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlobalVillageHeader extends StatelessWidget {
  const GlobalVillageHeader({
    this.showBackButton = false,
    this.onBack,
    super.key,
  });

  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 66,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (showBackButton)
                Positioned(
                  left: 8,
                  child: IconButton(
                    tooltip: 'Back',
                    onPressed: onBack ?? () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  ),
                ),
              const Text(
                'Global Village',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFD5D5D5)),
      ],
    );
  }
}

class AuthPageTitle extends StatelessWidget {
  const AuthPageTitle({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
