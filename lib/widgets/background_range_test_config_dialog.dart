import 'package:flutter/material.dart';

import '../helpers/snack_bar_builder.dart';
import '../services/beacon_service.dart';

class BackgroundRangeTestConfigDialog extends StatefulWidget {
  final BeaconRangeTestStatus initialStatus;

  const BackgroundRangeTestConfigDialog({
    super.key,
    required this.initialStatus,
  });

  @override
  State<BackgroundRangeTestConfigDialog> createState() =>
      _BackgroundRangeTestConfigDialogState();
}

class _BackgroundRangeTestConfigDialogState
    extends State<BackgroundRangeTestConfigDialog> {
  late final TextEditingController _distanceController;
  late final TextEditingController _minimumIntervalController;

  @override
  void initState() {
    super.initState();
    _distanceController = TextEditingController(
      text: widget.initialStatus.config.distanceFilterMeters.toString(),
    );
    _minimumIntervalController = TextEditingController(
      text: widget.initialStatus.config.minimumIntervalSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _distanceController.dispose();
    _minimumIntervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialStatus = widget.initialStatus;

    return AlertDialog(
      title: const Text('Range Test'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _distanceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Distance threshold (meters)',
                helperText:
                    'Minimum distance change to trigger beaconing.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _minimumIntervalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minimum time (seconds)',
                helperText:
                    'Minimum time between successful background beacons.',
              ),
            ),
            const SizedBox(height: 8),
            Text('Enrolled chats: ${initialStatus.enrolledContacts}'),
            const SizedBox(height: 4),
            Text('Enrolled channels: ${initialStatus.enrolledChannels}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final distance = int.tryParse(_distanceController.text.trim()) ?? 0;
            final minimumInterval =
                int.tryParse(_minimumIntervalController.text.trim()) ?? 0;
            final result = await BeaconService.instance
                .configureBackgroundService(
                  distanceFilterMeters: distance,
                  minimumIntervalSeconds: minimumInterval,
                );
            if (!context.mounted) return;
            if (!result.ok) {
              showDismissibleSnackBar(
                context,
                content: Text(result.error ?? 'Unable to save settings.'),
              );
              return;
            }
            Navigator.pop(context);
            showDismissibleSnackBar(
              context,
              content: const Text('Background range test settings saved.'),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
