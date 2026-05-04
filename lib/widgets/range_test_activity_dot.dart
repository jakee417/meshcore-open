import 'dart:async';

import 'package:flutter/material.dart';

class RangeTestActivityDot extends StatefulWidget {
  final bool active;

  const RangeTestActivityDot({super.key, required this.active});

  @override
  State<RangeTestActivityDot> createState() => _RangeTestActivityDotState();
}

class _RangeTestActivityDotState extends State<RangeTestActivityDot> {
  Timer? _timer;
  bool _blink = true;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant RangeTestActivityDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _startTimer();
    } else if (!widget.active && oldWidget.active) {
      _stopTimer();
      _blink = true;
    }
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() => _blink = !_blink);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.active && _blink;
    return Icon(
      Icons.circle,
      size: 12,
      color: on ? scheme.primary : scheme.outline,
    );
  }
}
