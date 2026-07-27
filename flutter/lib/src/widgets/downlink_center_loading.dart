import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

enum DownlinkCenterIndicatorMode { loading, running, error }

class DownlinkCenterLoading extends StatefulWidget {
  const DownlinkCenterLoading({
    super.key,
    this.label = '加载中',
    this.mode = DownlinkCenterIndicatorMode.loading,
  });

  final String label;
  final DownlinkCenterIndicatorMode mode;

  @override
  State<DownlinkCenterLoading> createState() => _DownlinkCenterLoadingState();
}

class _DownlinkCenterLoadingState extends State<DownlinkCenterLoading> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant DownlinkCenterLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _syncAnimationState();
    }
  }

  void _syncAnimationState() {
    if (widget.mode == DownlinkCenterIndicatorMode.loading) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
      return;
    }

    _controller
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildLoadingIndicator() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (int index) {
            final double progress = (_controller.value + index * 0.18) % 1.0;
            final double wave = math.sin(progress * math.pi);
            final double scale = 0.78 + (wave * 0.38);
            final double offsetY = -6.5 * wave;
            final double alpha = 0.52 + (wave * 0.48);

            return Transform.translate(
              offset: Offset(0, offsetY),
              child: Container(
                width: 8,
                height: 8,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    ExampleTheme.primary.withAlpha(214),
                    Colors.white,
                    alpha,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.white.withAlpha((alpha * 84).round()),
                      blurRadius: 10,
                      spreadRadius: 1.2,
                    ),
                  ],
                ),
                transform: Matrix4.diagonal3Values(scale, scale, 1),
                transformAlignment: Alignment.center,
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildErrorIndicator() {
    return const Icon(
      Icons.error_outline_rounded,
      size: 36,
      color: ExampleTheme.failure,
    );
  }

  Widget _buildRunningIndicator() {
    return const Icon(
      Icons.radio_button_checked_rounded,
      size: 32,
      color: ExampleTheme.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(117),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withAlpha(28)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(56),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              switch (widget.mode) {
                DownlinkCenterIndicatorMode.loading => _buildLoadingIndicator(),
                DownlinkCenterIndicatorMode.running => _buildRunningIndicator(),
                DownlinkCenterIndicatorMode.error => _buildErrorIndicator(),
              },
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
