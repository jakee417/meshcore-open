import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../helpers/snack_bar_builder.dart';

class RangeTestScreen<T> extends StatefulWidget {
  final String title;
  final ValueListenable<T> statusListenable;
  final bool Function(T status) isRunning;
  final int Function(T status) totalBeacons;
  final int Function(T status) sentBeacons;
  final int Function(T status) frequencyMinutes;
  final int? Function(T status) testId;
  final Future<String?> Function(int totalBeacons, int frequencyMinutes)
  onStart;
  final VoidCallback onStop;

  const RangeTestScreen({
    super.key,
    required this.title,
    required this.statusListenable,
    required this.isRunning,
    required this.totalBeacons,
    required this.sentBeacons,
    required this.frequencyMinutes,
    required this.testId,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<RangeTestScreen<T>> createState() => _RangeTestScreenState<T>();
}

class _RangeTestScreenState<T> extends State<RangeTestScreen<T>> {
  late final TextEditingController _totalController;
  late final TextEditingController _frequencyController;

  @override
  void initState() {
    super.initState();
    _totalController = TextEditingController(text: '30');
    _frequencyController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _totalController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  Future<void> _startPressed() async {
    final total = int.tryParse(_totalController.text.trim());
    final frequencyMinutes = int.tryParse(_frequencyController.text.trim());
    if (total == null || total <= 0) {
      showDismissibleSnackBar(
        context,
        content: const Text('Enter a valid total beacon count.'),
      );
      return;
    }
    if (frequencyMinutes == null || frequencyMinutes <= 0) {
      showDismissibleSnackBar(
        context,
        content: const Text('Enter a valid frequency in minutes.'),
      );
      return;
    }

    final error = await widget.onStart(total, frequencyMinutes);
    if (!mounted) return;
    if (error != null) {
      showDismissibleSnackBar(context, content: Text(error));
      return;
    }

    showDismissibleSnackBar(
      context,
      content: const Text(
        'Range test started and will keep running while the app process remains active.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ValueListenableBuilder<T>(
        valueListenable: widget.statusListenable,
        builder: (context, status, _) {
          final running = widget.isRunning(status);
          final total = widget.totalBeacons(status);
          final sent = widget.sentBeacons(status);
          final frequencyMinutes = widget.frequencyMinutes(status);
          final testId = widget.testId(status);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _totalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total beacons (X)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _frequencyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Frequency minutes (Y)',
                  helperText: 'Sent every Y minute(s)',
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('X total beacons: $total'),
                      const SizedBox(height: 4),
                      Text('Y frequency: every $frequencyMinutes minute(s)'),
                      const SizedBox(height: 4),
                      Text('Progress: $sent/$total'),
                      if (testId != null) ...[
                        const SizedBox(height: 4),
                        Text('Test ID: $testId'),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        running ? 'Running' : 'Idle',
                        style: TextStyle(
                          color: running ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (running)
                FilledButton.tonalIcon(
                  onPressed: () {
                    widget.onStop();
                    showDismissibleSnackBar(
                      context,
                      content: const Text('Range test stopped.'),
                    );
                  },
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Test'),
                )
              else
                FilledButton.icon(
                  onPressed: _startPressed,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Test'),
                ),
            ],
          );
        },
      ),
    );
  }
}
