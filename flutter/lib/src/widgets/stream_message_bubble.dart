import 'package:flutter/material.dart';

import '../demo_widget_keys.dart';

class StreamMessageBubble extends StatelessWidget {
  const StreamMessageBubble({
    super.key,
    required this.text,
  });

  final String text;
  static const double _tailWidth = 10;
  static const double _tailHeight = 14;
  static const double _maxWidthFactor = 0.72;
  static final Color _bubbleColor = Colors.white.withAlpha(222);

  @override
  Widget build(BuildContext context) {
    final double maxWidth = MediaQuery.sizeOf(context).width * _maxWidthFactor;
    return ConstrainedBox(
      key: DemoWidgetKeys.streamMessageBubble,
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(begin: const Offset(0.24, 0), end: Offset.zero),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, Offset offset, Widget? child) {
          return FractionalTranslation(
            translation: offset,
            child: child,
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(26),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _StreamMessageBubblePainter(color: _bubbleColor),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, _tailWidth + 16, 9),
              child: Text(
                '流消息：$text',
                textAlign: TextAlign.left,
                softWrap: true,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.normal,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _StreamMessageBubblePainter extends CustomPainter {
  const _StreamMessageBubblePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bubbleRect = Rect.fromLTWH(0, 0, size.width - StreamMessageBubble._tailWidth, size.height);
    final Path path = Path()..addRRect(RRect.fromRectAndRadius(bubbleRect, const Radius.circular(25)));
    final double tailTop = size.height - StreamMessageBubble._tailHeight - 5;
    final double tailBaseX = bubbleRect.right - 2;
    path
      ..moveTo(tailBaseX, tailTop)
      ..quadraticBezierTo(
        size.width - 2,
        tailTop + StreamMessageBubble._tailHeight * 0.2,
        size.width,
        tailTop + StreamMessageBubble._tailHeight * 0.55,
      )
      ..quadraticBezierTo(
        tailBaseX + 2,
        tailTop + StreamMessageBubble._tailHeight * 0.92,
        tailBaseX - 6,
        tailTop + StreamMessageBubble._tailHeight,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _StreamMessageBubblePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
