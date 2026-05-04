import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../helpers/snack_bar_builder.dart';
import '../services/beacon_service.dart';
import '../widgets/range_test_points_map.dart';

class RangeTestSessionScreen extends StatelessWidget {
  final String title;
  final ValueListenable<BeaconTargetRangeTestStatus> statusListenable;
  final Future<BeaconActionResult> Function() onStart;
  final Future<void> Function() onStop;
  final Future<BeaconActionResult> Function() onManual;

  const RangeTestSessionScreen({
    super.key,
    required this.title,
    required this.statusListenable,
    required this.onStart,
    required this.onStop,
    required this.onManual,
  });

  Future<void> _handleStart(BuildContext context) async {
    final result = await onStart();
    if (!context.mounted) return;
    if (!result.ok) {
      showDismissibleSnackBar(
        context,
        content: Text(result.error ?? 'Unable to start range test.'),
      );
      return;
    }
    showDismissibleSnackBar(
      context,
      content: const Text('Range test started.'),
    );
  }

  Future<void> _handleManual(BuildContext context) async {
    final result = await onManual();
    if (!context.mounted) return;
    if (!result.ok) {
      showDismissibleSnackBar(
        context,
        content: Text(result.error ?? 'Unable to send manual range beacon.'),
      );
      return;
    }
    showDismissibleSnackBar(
      context,
      content: const Text('Manual range beacon sent.'),
    );
  }

  Future<void> _handleStop(BuildContext context) async {
    await onStop();
    if (!context.mounted) return;
    showDismissibleSnackBar(
      context,
      content: const Text('Range test stopped.'),
    );
  }

  static String _fmt(double? v, {int decimals = 1, String suffix = ''}) {
    if (v == null) return '—';
    return '${v.toStringAsFixed(decimals)}$suffix';
  }

  static String _fmtTime(double? ms) {
    if (ms == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} '
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static String _fmtBearing(double? v) {
    if (v == null) return '—';
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((v + 22.5) / 45).floor() % 8;
    return '${v.toStringAsFixed(0)}° ${dirs[idx]}';
  }

  Widget _buildStats(BuildContext context, List<BeaconRangePoint> points) {
    if (points.isEmpty) return const SizedBox.shrink();

    double? avgOf(double? Function(BeaconRangePoint p) sel) {
      final vals = points.map(sel).whereType<double>().toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    }

    double? minOf(double? Function(BeaconRangePoint p) sel) {
      final vals = points.map(sel).whereType<double>().toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a < b ? a : b);
    }

    double? maxOf(double? Function(BeaconRangePoint p) sel) {
      final vals = points.map(sel).whereType<double>().toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a > b ? a : b);
    }

    final avgAlt = avgOf((p) => p.altitude);
    final avgSpeed = avgOf((p) => p.speed);
    final avgAccuracy = avgOf((p) => p.accuracy);
    final earliestTime = minOf((p) => p.locationTime);
    final latestTime = maxOf((p) => p.locationTime);
    final latestBearing = points
        .lastWhere((p) => p.bearing != null, orElse: () => points.last)
        .bearing;

    final rows = <({String label, String value})>[
      if (avgAlt != null)
        (label: 'Avg altitude', value: _fmt(avgAlt, decimals: 1, suffix: ' m')),
      if (avgSpeed != null)
        (
          label: 'Avg speed',
          value: _fmt(avgSpeed, decimals: 2, suffix: ' m/s'),
        ),
      if (avgAccuracy != null)
        (
          label: 'Avg accuracy',
          value: _fmt(avgAccuracy, decimals: 1, suffix: ' m'),
        ),
      if (latestBearing != null)
        (label: 'Latest bearing', value: _fmtBearing(latestBearing)),
      if (earliestTime != null)
        (label: 'First fix', value: _fmtTime(earliestTime)),
      if (latestTime != null) (label: 'Last fix', value: _fmtTime(latestTime)),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Location Stats', style: tt.titleSmall),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.label, style: tt.bodyMedium),
                    Text(
                      row.value,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: ValueListenableBuilder<BeaconTargetRangeTestStatus>(
        valueListenable: statusListenable,
        builder: (context, status, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                status.isRunning ? 'Running' : 'Stopped',
                style: tt.titleMedium?.copyWith(
                  color: status.isRunning ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text('Total beacons: ${status.totalUpdates}'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: status.isRunning
                    ? FilledButton.tonalIcon(
                        onPressed: () => _handleStop(context),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop'),
                      )
                    : FilledButton.icon(
                        onPressed: () => _handleStart(context),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: status.isRunning
                      ? () => _handleManual(context)
                      : null,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Manual Beacon'),
                ),
              ),
              const SizedBox(height: 16),
              RangeTestPointsMap(points: status.points),
              if (status.points.isNotEmpty) const SizedBox(height: 12),
              _buildStats(context, status.points),
            ],
          );
        },
      ),
    );
  }
}
