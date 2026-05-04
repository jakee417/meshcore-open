import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:background_location/background_location.dart' as bg;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/channel.dart';
import '../models/contact.dart';

enum BeaconScope { channel, contact }

class BeaconBackgroundConfig {
  final int distanceFilterMeters;
  final int minimumIntervalSeconds;

  const BeaconBackgroundConfig({
    required this.distanceFilterMeters,
    required this.minimumIntervalSeconds,
  });

  const BeaconBackgroundConfig.defaults()
    : distanceFilterMeters = 50,
      minimumIntervalSeconds = 0;

  BeaconBackgroundConfig copyWith({
    int? distanceFilterMeters,
    int? minimumIntervalSeconds,
  }) {
    return BeaconBackgroundConfig(
      distanceFilterMeters: distanceFilterMeters ?? this.distanceFilterMeters,
      minimumIntervalSeconds:
          minimumIntervalSeconds ?? this.minimumIntervalSeconds,
    );
  }
}

class BeaconActionResult {
  final bool ok;
  final String? error;

  const BeaconActionResult._({required this.ok, this.error});

  const BeaconActionResult.success() : this._(ok: true);

  const BeaconActionResult.failure(String message)
    : this._(ok: false, error: message);
}

class BeaconRangeTestStatus {
  final bool isRunning;
  final BeaconBackgroundConfig config;
  final int enrolledChannels;
  final int enrolledContacts;
  final Set<int> enrolledChannelIds;
  final Set<String> enrolledContactIds;

  const BeaconRangeTestStatus({
    required this.isRunning,
    required this.config,
    required this.enrolledChannels,
    required this.enrolledContacts,
    required this.enrolledChannelIds,
    required this.enrolledContactIds,
  });

  const BeaconRangeTestStatus.idle()
    : isRunning = false,
      config = const BeaconBackgroundConfig.defaults(),
      enrolledChannels = 0,
      enrolledContacts = 0,
      enrolledChannelIds = const <int>{},
      enrolledContactIds = const <String>{};

  BeaconRangeTestStatus copyWith({
    bool? isRunning,
    BeaconBackgroundConfig? config,
    int? enrolledChannels,
    int? enrolledContacts,
    Set<int>? enrolledChannelIds,
    Set<String>? enrolledContactIds,
  }) {
    return BeaconRangeTestStatus(
      isRunning: isRunning ?? this.isRunning,
      config: config ?? this.config,
      enrolledChannels: enrolledChannels ?? this.enrolledChannels,
      enrolledContacts: enrolledContacts ?? this.enrolledContacts,
      enrolledChannelIds: enrolledChannelIds ?? this.enrolledChannelIds,
      enrolledContactIds: enrolledContactIds ?? this.enrolledContactIds,
    );
  }

  bool isChannelEnrolled(int channelId) =>
      enrolledChannelIds.contains(channelId);

  bool isContactEnrolled(String contactPublicKeyHex) {
    return enrolledContactIds.contains(contactPublicKeyHex);
  }
}

class BeaconRangePoint {
  final double lat;
  final double lon;
  final int sequence;
  final DateTime timestamp;
  final double? altitude;
  final double? bearing;
  final double? accuracy;
  final double? speed;
  final double? locationTime;
  final bool? isMock;

  const BeaconRangePoint({
    required this.lat,
    required this.lon,
    required this.sequence,
    required this.timestamp,
    this.altitude,
    this.bearing,
    this.accuracy,
    this.speed,
    this.locationTime,
    this.isMock,
  });
}

class BeaconTargetRangeTestStatus {
  final BeaconScope scope;
  final String targetId;
  final bool isRunning;
  final int sessionId;
  final int nextSequence;
  final int totalUpdates;
  final List<BeaconRangePoint> points;

  const BeaconTargetRangeTestStatus({
    required this.scope,
    required this.targetId,
    required this.isRunning,
    required this.sessionId,
    required this.nextSequence,
    required this.totalUpdates,
    required this.points,
  });

  factory BeaconTargetRangeTestStatus.idle({
    required BeaconScope scope,
    required String targetId,
  }) {
    return BeaconTargetRangeTestStatus(
      scope: scope,
      targetId: targetId,
      isRunning: false,
      sessionId: 0,
      nextSequence: 1,
      totalUpdates: 0,
      points: const <BeaconRangePoint>[],
    );
  }

  BeaconTargetRangeTestStatus copyWith({
    bool? isRunning,
    int? sessionId,
    int? nextSequence,
    int? totalUpdates,
    List<BeaconRangePoint>? points,
  }) {
    return BeaconTargetRangeTestStatus(
      scope: scope,
      targetId: targetId,
      isRunning: isRunning ?? this.isRunning,
      sessionId: sessionId ?? this.sessionId,
      nextSequence: nextSequence ?? this.nextSequence,
      totalUpdates: totalUpdates ?? this.totalUpdates,
      points: points ?? this.points,
    );
  }
}

class BeaconService {
  BeaconService._();

  static final BeaconService instance = BeaconService._();

  static const _prefsDistanceFilterKey = 'beacon_bg_distance_filter_m';
  static const _prefsMinimumIntervalKey = 'beacon_bg_min_interval_s';
  static const _prefsEnrolledChannelsKey = 'beacon_bg_enrolled_channels';
  static const _prefsEnrolledContactsKey = 'beacon_bg_enrolled_contacts';

  final ValueNotifier<BeaconRangeTestStatus> status = ValueNotifier(
    const BeaconRangeTestStatus.idle(),
  );
  final ValueNotifier<int> backgroundPollActivityTick = ValueNotifier<int>(0);
  final Map<int, ValueNotifier<BeaconTargetRangeTestStatus>>
  _channelSessionNotifiers =
      <int, ValueNotifier<BeaconTargetRangeTestStatus>>{};
  final Map<String, ValueNotifier<BeaconTargetRangeTestStatus>>
  _contactSessionNotifiers =
      <String, ValueNotifier<BeaconTargetRangeTestStatus>>{};

  MeshCoreConnector? _connector;
  BeaconBackgroundConfig _config = const BeaconBackgroundConfig.defaults();
  final Set<int> _enrolledChannelIds = <int>{};
  final Set<String> _enrolledContactIds = <String>{};
  final Set<String> _backgroundSendInFlightTargets = <String>{};
  Stopwatch? _backgroundPollPulseStopwatch;
  bool _loadedFromPrefs = false;
  bool _listenersRegistered = false;

  BeaconBackgroundConfig get config => _config;

  bool get backgroundPollActivityPulse {
    final sw = _backgroundPollPulseStopwatch;
    if (sw == null || !sw.isRunning) return false;
    return sw.elapsedMilliseconds < 6000;
  }

  ValueListenable<BeaconTargetRangeTestStatus> channelRangeTestStatusListenable(
    int channelId,
  ) {
    return _channelSessionNotifier(channelId);
  }

  ValueListenable<BeaconTargetRangeTestStatus> contactRangeTestStatusListenable(
    String contactPublicKeyHex,
  ) {
    return _contactSessionNotifier(contactPublicKeyHex);
  }

  ValueNotifier<BeaconTargetRangeTestStatus> _channelSessionNotifier(
    int channelId,
  ) {
    return _channelSessionNotifiers.putIfAbsent(
      channelId,
      () => ValueNotifier(
        BeaconTargetRangeTestStatus.idle(
          scope: BeaconScope.channel,
          targetId: channelId.toString(),
        ),
      ),
    );
  }

  ValueNotifier<BeaconTargetRangeTestStatus> _contactSessionNotifier(
    String contactPublicKeyHex,
  ) {
    return _contactSessionNotifiers.putIfAbsent(
      contactPublicKeyHex,
      () => ValueNotifier(
        BeaconTargetRangeTestStatus.idle(
          scope: BeaconScope.contact,
          targetId: contactPublicKeyHex,
        ),
      ),
    );
  }

  Future<BeaconActionResult> sendSingleChannelBeacon({
    required MeshCoreConnector connector,
    required Channel channel,
  }) async {
    return _sendChannelBeacon(
      connector: connector,
      channel: channel,
      id: 1,
      seq: null,
    );
  }

  Future<BeaconActionResult> sendSingleContactBeacon({
    required MeshCoreConnector connector,
    required Contact contact,
  }) async {
    return _sendContactBeacon(
      connector: connector,
      contact: contact,
      id: 1,
      seq: null,
    );
  }

  Future<BeaconActionResult> startChannelRangeTest({
    required MeshCoreConnector connector,
    required Channel channel,
    required int totalBeacons,
    required int frequencyMinutes,
  }) async {
    return startChannelSessionRangeTest(connector: connector, channel: channel);
  }

  Future<BeaconActionResult> startContactRangeTest({
    required MeshCoreConnector connector,
    required Contact contact,
    required int totalBeacons,
    required int frequencyMinutes,
  }) async {
    return startContactSessionRangeTest(connector: connector, contact: contact);
  }

  Future<BeaconActionResult> startChannelSessionRangeTest({
    required MeshCoreConnector connector,
    required Channel channel,
  }) async {
    await _ensureLoaded();
    _connector = connector;

    _enrolledChannelIds.add(channel.index);
    final notifier = _channelSessionNotifier(channel.index);
    notifier.value = BeaconTargetRangeTestStatus(
      scope: BeaconScope.channel,
      targetId: channel.index.toString(),
      isRunning: true,
      sessionId: math.Random.secure().nextInt(0x7fffffff),
      nextSequence: 1,
      totalUpdates: 0,
      points: const <BeaconRangePoint>[],
    );

    final applyResult = await _applyBackgroundConfig(startOrStop: true);
    if (!applyResult.ok) return applyResult;

    await _persistState();
    _publishStatus();
    return const BeaconActionResult.success();
  }

  Future<BeaconActionResult> startContactSessionRangeTest({
    required MeshCoreConnector connector,
    required Contact contact,
  }) async {
    await _ensureLoaded();
    _connector = connector;

    _enrolledContactIds.add(contact.publicKeyHex);
    final notifier = _contactSessionNotifier(contact.publicKeyHex);
    notifier.value = BeaconTargetRangeTestStatus(
      scope: BeaconScope.contact,
      targetId: contact.publicKeyHex,
      isRunning: true,
      sessionId: math.Random.secure().nextInt(0x7fffffff),
      nextSequence: 1,
      totalUpdates: 0,
      points: const <BeaconRangePoint>[],
    );

    final applyResult = await _applyBackgroundConfig(startOrStop: true);
    if (!applyResult.ok) return applyResult;

    await _persistState();
    _publishStatus();
    return const BeaconActionResult.success();
  }

  Future<void> stopChannelSessionRangeTest(int channelId) async {
    await _ensureLoaded();
    _enrolledChannelIds.remove(channelId);
    final notifier = _channelSessionNotifier(channelId);
    notifier.value = notifier.value.copyWith(isRunning: false);
    await _applyBackgroundConfig(startOrStop: true);
    await _persistState();
    _publishStatus();
  }

  Future<void> stopContactSessionRangeTest(String contactPublicKeyHex) async {
    await _ensureLoaded();
    _enrolledContactIds.remove(contactPublicKeyHex);
    final notifier = _contactSessionNotifier(contactPublicKeyHex);
    notifier.value = notifier.value.copyWith(isRunning: false);
    await _applyBackgroundConfig(startOrStop: true);
    await _persistState();
    _publishStatus();
  }

  Future<BeaconActionResult> sendManualChannelRangeBeacon({
    required MeshCoreConnector connector,
    required Channel channel,
  }) async {
    final session = _channelSessionNotifier(channel.index).value;
    if (!session.isRunning) {
      return const BeaconActionResult.failure(
        'Start the channel range test before sending manual range beacons.',
      );
    }
    final coords = await _resolveCurrentCoords();
    if (!coords.ok) {
      return BeaconActionResult.failure(coords.error!);
    }

    final result = await _sendChannelBeaconWithPosition(
      connector: connector,
      channel: channel,
      id: session.sessionId,
      seq: session.nextSequence,
      lat: coords.lat!,
      lon: coords.lon!,
    );
    if (!result.ok) return result;

    await _applySuccessfulUpdate(
      notifier: _channelSessionNotifier(channel.index),
      sequence: session.nextSequence,
      lat: coords.lat!,
      lon: coords.lon!,
    );
    return const BeaconActionResult.success();
  }

  Future<BeaconActionResult> sendManualContactRangeBeacon({
    required MeshCoreConnector connector,
    required Contact contact,
  }) async {
    final session = _contactSessionNotifier(contact.publicKeyHex).value;
    if (!session.isRunning) {
      return const BeaconActionResult.failure(
        'Start the contact range test before sending manual range beacons.',
      );
    }
    final coords = await _resolveCurrentCoords();
    if (!coords.ok) {
      return BeaconActionResult.failure(coords.error!);
    }

    final result = await _sendContactBeaconWithPosition(
      connector: connector,
      contact: contact,
      id: session.sessionId,
      seq: session.nextSequence,
      lat: coords.lat!,
      lon: coords.lon!,
    );
    if (!result.ok) return result;

    await _applySuccessfulUpdate(
      notifier: _contactSessionNotifier(contact.publicKeyHex),
      sequence: session.nextSequence,
      lat: coords.lat!,
      lon: coords.lon!,
    );
    return const BeaconActionResult.success();
  }

  Future<BeaconActionResult> configureBackgroundService({
    required int distanceFilterMeters,
    required int minimumIntervalSeconds,
  }) async {
    await _ensureLoaded();
    if (distanceFilterMeters <= 0) {
      return const BeaconActionResult.failure(
        'Distance filter must be greater than 0 meters.',
      );
    }
    if (minimumIntervalSeconds < 0) {
      return const BeaconActionResult.failure(
        'Minimum interval cannot be negative.',
      );
    }

    _config = _config.copyWith(
      distanceFilterMeters: distanceFilterMeters,
      minimumIntervalSeconds: minimumIntervalSeconds,
    );

    final applyResult = await _applyBackgroundConfig(startOrStop: true);
    if (!applyResult.ok) {
      return applyResult;
    }

    await _persistState();
    _publishStatus();
    return const BeaconActionResult.success();
  }

  Future<BeaconActionResult> enrollChannel({
    required MeshCoreConnector connector,
    required Channel channel,
  }) async {
    return startChannelSessionRangeTest(connector: connector, channel: channel);
  }

  Future<BeaconActionResult> enrollContact({
    required MeshCoreConnector connector,
    required Contact contact,
  }) async {
    return startContactSessionRangeTest(connector: connector, contact: contact);
  }

  Future<void> unenrollChannel(int channelId) async {
    await stopChannelSessionRangeTest(channelId);
  }

  Future<void> unenrollContact(String contactPublicKeyHex) async {
    await stopContactSessionRangeTest(contactPublicKeyHex);
  }

  Future<BeaconActionResult> restoreBackgroundState({
    required MeshCoreConnector connector,
  }) async {
    _connector = connector;
    await _ensureLoaded();
    return _applyBackgroundConfig(startOrStop: true);
  }

  Future<void> _ensureLoaded() async {
    if (_loadedFromPrefs) return;

    final prefs = await SharedPreferences.getInstance();
    _config = BeaconBackgroundConfig(
      distanceFilterMeters: prefs.getInt(_prefsDistanceFilterKey) ?? 50,
      minimumIntervalSeconds: prefs.getInt(_prefsMinimumIntervalKey) ?? 0,
    );
    _enrolledChannelIds
      ..clear()
      ..addAll(
        (prefs.getStringList(_prefsEnrolledChannelsKey) ?? const <String>[])
            .map(int.tryParse)
            .whereType<int>(),
      );
    _enrolledContactIds
      ..clear()
      ..addAll(
        prefs.getStringList(_prefsEnrolledContactsKey) ?? const <String>[],
      );

    for (final channelId in _enrolledChannelIds) {
      final notifier = _channelSessionNotifier(channelId);
      notifier.value = notifier.value.copyWith(isRunning: true);
    }
    for (final contactId in _enrolledContactIds) {
      final notifier = _contactSessionNotifier(contactId);
      notifier.value = notifier.value.copyWith(isRunning: true);
    }

    _loadedFromPrefs = true;
    _publishStatus();
  }

  Future<void> _setupBackgroundListeners() async {
    if (_listenersRegistered) {
      return;
    }

    bg.BackgroundLocation.getLocationUpdates((location) {
      unawaited(_sendBackgroundBeaconsForLocation(location));
    });
    _listenersRegistered = true;
  }

  Future<BeaconActionResult> _applyBackgroundConfig({
    required bool startOrStop,
  }) async {
    try {
      await _setupBackgroundListeners();
      if (startOrStop) {
        if (_hasActiveSubscriptions) {
          await bg.BackgroundLocation.setAndroidNotification(
            title: 'MeshCore',
            message: 'Background range test active',
          );
          await bg.BackgroundLocation.startLocationService(
            distanceFilter: _config.distanceFilterMeters.toDouble(),
          );
        } else {
          await bg.BackgroundLocation.stopLocationService();
        }
      }

      await _publishRunningState();
      return const BeaconActionResult.success();
    } catch (_) {
      return const BeaconActionResult.failure(
        'Unable to configure background location service.',
      );
    }
  }

  Future<void> _publishRunningState() async {
    bool running = false;
    try {
      running = await bg.BackgroundLocation.isServiceRunning();
    } catch (_) {
      running = false;
    }

    status.value = status.value.copyWith(isRunning: running, config: _config);
  }

  void _publishStatus() {
    final previous = status.value;
    status.value = BeaconRangeTestStatus(
      isRunning: previous.isRunning,
      config: _config,
      enrolledChannels: _enrolledChannelIds.length,
      enrolledContacts: _enrolledContactIds.length,
      enrolledChannelIds: Set<int>.unmodifiable(_enrolledChannelIds),
      enrolledContactIds: Set<String>.unmodifiable(_enrolledContactIds),
    );
  }

  Future<void> _sendBackgroundBeaconsForLocation(bg.Location location) async {
    final connector = _connector;
    if (connector == null || !connector.isConnected) return;
    if (!_hasActiveSubscriptions) return;
    if (location.latitude == null || location.longitude == null) return;
    _markBackgroundPollActivity();

    final lat = double.parse(location.latitude!.toStringAsFixed(6));
    final lon = double.parse(location.longitude!.toStringAsFixed(6));
    final altitude = location.altitude;
    final bearing = location.bearing;
    final accuracy = location.accuracy;
    final speed = location.speed;
    final locationTime = (location.time ?? DateTime.now().millisecondsSinceEpoch)
        .toDouble();
    final isMock = location.isMock;
    for (final channelId in _enrolledChannelIds.toList()) {
      final channel = connector.channels
          .where((c) => c.index == channelId)
          .firstOrNull;
      if (channel == null) continue;
      final targetKey = 'channel:$channelId';
      if (_backgroundSendInFlightTargets.contains(targetKey)) continue;
      final notifier = _channelSessionNotifier(channelId);
      final session = notifier.value;
      if (!session.isRunning) continue;
      if (!_hasMetMinimumInterval(notifier, locationTime)) continue;

      _backgroundSendInFlightTargets.add(targetKey);
      try {
        final sendResult = await _sendChannelBeaconWithPosition(
          connector: connector,
          channel: channel,
          id: session.sessionId,
          seq: session.nextSequence,
          lat: lat,
          lon: lon,
        );
        if (sendResult.ok) {
          await _applySuccessfulUpdate(
            notifier: notifier,
            sequence: session.nextSequence,
            lat: lat,
            lon: lon,
            altitude: altitude,
            bearing: bearing,
            accuracy: accuracy,
            speed: speed,
            locationTime: locationTime,
            isMock: isMock,
          );
        }
      } finally {
        _backgroundSendInFlightTargets.remove(targetKey);
      }
    }

    for (final contactKey in _enrolledContactIds.toList()) {
      final contact = connector.contacts
          .where((c) => c.publicKeyHex == contactKey)
          .firstOrNull;
      if (contact == null) continue;
      final targetKey = 'contact:$contactKey';
      if (_backgroundSendInFlightTargets.contains(targetKey)) continue;
      final notifier = _contactSessionNotifier(contactKey);
      final session = notifier.value;
      if (!session.isRunning) continue;
      if (!_hasMetMinimumInterval(notifier, locationTime)) continue;

      _backgroundSendInFlightTargets.add(targetKey);
      try {
        final sendResult = await _sendContactBeaconWithPosition(
          connector: connector,
          contact: contact,
          id: session.sessionId,
          seq: session.nextSequence,
          lat: lat,
          lon: lon,
        );
        if (sendResult.ok) {
          await _applySuccessfulUpdate(
            notifier: notifier,
            sequence: session.nextSequence,
            lat: lat,
            lon: lon,
            altitude: altitude,
            bearing: bearing,
            accuracy: accuracy,
            speed: speed,
            locationTime: locationTime,
            isMock: isMock,
          );
        }
      } finally {
        _backgroundSendInFlightTargets.remove(targetKey);
      }
    }
  }

  Future<BeaconActionResult> _sendChannelBeaconWithPosition({
    required MeshCoreConnector connector,
    required Channel channel,
    required int id,
    required int seq,
    required double lat,
    required double lon,
  }) async {
    return _sendBeaconWithPosition(
      connector: connector,
      id: id,
      seq: seq,
      lat: lat,
      lon: lon,
      prepareOutbound: (messageText) =>
          connector.prepareChannelOutboundText(channel.index, messageText),
      maxBytes: maxChannelMessageBytes(connector.selfName),
      send: (messageText) => connector.sendChannelMessage(channel, messageText),
      payloadTooLongErrorPrefix: 'channel',
    );
  }

  Future<BeaconActionResult> _sendContactBeaconWithPosition({
    required MeshCoreConnector connector,
    required Contact contact,
    required int id,
    required int seq,
    required double lat,
    required double lon,
  }) async {
    return _sendBeaconWithPosition(
      connector: connector,
      id: id,
      seq: seq,
      lat: lat,
      lon: lon,
      prepareOutbound: (messageText) =>
          connector.prepareContactOutboundText(contact, messageText),
      maxBytes: maxContactMessageBytes(),
      send: (messageText) => connector.sendMessage(contact, messageText),
      payloadTooLongErrorPrefix: 'contact',
    );
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsDistanceFilterKey, _config.distanceFilterMeters);
    await prefs.setInt(
      _prefsMinimumIntervalKey,
      _config.minimumIntervalSeconds,
    );
    await prefs.setStringList(
      _prefsEnrolledChannelsKey,
      _enrolledChannelIds.map((v) => v.toString()).toList(),
    );
    await prefs.setStringList(
      _prefsEnrolledContactsKey,
      _enrolledContactIds.toList(),
    );
  }

  Future<BeaconActionResult> _sendBeaconWithPosition({
    required MeshCoreConnector connector,
    required int id,
    required int seq,
    required double lat,
    required double lon,
    required String Function(String messageText) prepareOutbound,
    required int maxBytes,
    required Future<void> Function(String messageText) send,
    required String payloadTooLongErrorPrefix,
  }) async {
    if (!connector.isConnected) {
      return const BeaconActionResult.failure(
        'Connect to a node before sending a beacon.',
      );
    }

    final messageText =
        'pos ${jsonEncode({'id': id, 'seq': seq, 'lat': lat, 'lon': lon})}';

    final outboundText = prepareOutbound(messageText);
    if (utf8.encode(outboundText).length > maxBytes) {
      return BeaconActionResult.failure(
        'Beacon payload exceeds $payloadTooLongErrorPrefix max bytes ($maxBytes).',
      );
    }

    try {
      await send(messageText);
      return const BeaconActionResult.success();
    } catch (_) {
      return const BeaconActionResult.failure('Unable to send beacon payload.');
    }
  }

  Future<BeaconActionResult> _applySuccessfulUpdate({
    required ValueNotifier<BeaconTargetRangeTestStatus> notifier,
    required int sequence,
    required double lat,
    required double lon,
    double? altitude,
    double? bearing,
    double? accuracy,
    double? speed,
    double? locationTime,
    bool? isMock,
  }) async {
    final current = notifier.value;
    final nextPoints = List<BeaconRangePoint>.from(current.points)
      ..add(
        BeaconRangePoint(
          lat: lat,
          lon: lon,
          sequence: sequence,
          timestamp: DateTime.now(),
          altitude: altitude,
          bearing: bearing,
          accuracy: accuracy,
          speed: speed,
          locationTime: locationTime,
          isMock: isMock,
        ),
      );
    notifier.value = current.copyWith(
      nextSequence: sequence + 1,
      totalUpdates: current.totalUpdates + 1,
      points: List<BeaconRangePoint>.unmodifiable(nextPoints),
    );
    await _persistState();
    return const BeaconActionResult.success();
  }

  Future<_CurrentCoordsResult> _resolveCurrentCoords() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const _CurrentCoordsResult.failure(
          'Location services are disabled on this phone.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const _CurrentCoordsResult.failure(
          'Location permission is required to send a beacon.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      return _CurrentCoordsResult.success(
        lat: double.parse(position.latitude.toStringAsFixed(6)),
        lon: double.parse(position.longitude.toStringAsFixed(6)),
      );
    } catch (_) {
      return const _CurrentCoordsResult.failure(
        'Unable to fetch current location.',
      );
    }
  }

  Future<void> _restoreActiveRangeTest({
    required MeshCoreConnector connector,
    required BeaconScope expectedScope,
    required String expectedTargetId,
    required Channel? channel,
    required Contact? contact,
  }) async {
    _connector = connector;
    await _ensureLoaded();
    await _applyBackgroundConfig(startOrStop: true);
  }

  bool get _hasActiveSubscriptions =>
      _enrolledChannelIds.isNotEmpty || _enrolledContactIds.isNotEmpty;

  bool _hasMetMinimumInterval(
    ValueNotifier<BeaconTargetRangeTestStatus> notifier,
    double candidateLocationTimeMs,
  ) {
    final minIntervalMs = _config.minimumIntervalSeconds * 1000;
    if (minIntervalMs <= 0) return true;

    final points = notifier.value.points;
    if (points.isEmpty) return true;

    final lastPoint = points.last;
    final lastPointTimeMs =
        lastPoint.locationTime ??
        lastPoint.timestamp.millisecondsSinceEpoch.toDouble();
    return (candidateLocationTimeMs - lastPointTimeMs) >= minIntervalMs;
  }

  Future<void> restoreActiveChannelRangeTest({
    required MeshCoreConnector connector,
    required Channel channel,
  }) async {
    await _restoreActiveRangeTest(
      connector: connector,
      expectedScope: BeaconScope.channel,
      expectedTargetId: channel.index.toString(),
      channel: channel,
      contact: null,
    );
  }

  Future<void> restoreActiveContactRangeTest({
    required MeshCoreConnector connector,
    required Contact contact,
  }) async {
    await _restoreActiveRangeTest(
      connector: connector,
      expectedScope: BeaconScope.contact,
      expectedTargetId: contact.publicKeyHex,
      channel: null,
      contact: contact,
    );
  }

  Future<BeaconActionResult> _sendChannelBeacon({
    required MeshCoreConnector connector,
    required Channel channel,
    required int id,
    required int? seq,
  }) async {
    return _sendBeacon(
      connector: connector,
      id: id,
      seq: seq,
      prepareOutbound: (messageText) =>
          connector.prepareChannelOutboundText(channel.index, messageText),
      maxBytes: maxChannelMessageBytes(connector.selfName),
      send: (messageText) => connector.sendChannelMessage(channel, messageText),
      payloadTooLongErrorPrefix: 'channel',
    );
  }

  Future<BeaconActionResult> _sendContactBeacon({
    required MeshCoreConnector connector,
    required Contact contact,
    required int id,
    required int? seq,
  }) async {
    return _sendBeacon(
      connector: connector,
      id: id,
      seq: seq,
      prepareOutbound: (messageText) =>
          connector.prepareContactOutboundText(contact, messageText),
      maxBytes: maxContactMessageBytes(),
      send: (messageText) => connector.sendMessage(contact, messageText),
      payloadTooLongErrorPrefix: 'contact',
    );
  }

  Future<BeaconActionResult> _sendBeacon({
    required MeshCoreConnector connector,
    required int id,
    required int? seq,
    required String Function(String messageText) prepareOutbound,
    required int maxBytes,
    required Future<void> Function(String messageText) send,
    required String payloadTooLongErrorPrefix,
  }) async {
    if (!connector.isConnected) {
      return const BeaconActionResult.failure(
        'Connect to a node before sending a beacon.',
      );
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const BeaconActionResult.failure(
          'Location services are disabled on this phone.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const BeaconActionResult.failure(
          'Location permission is required to send a beacon.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      final payload = <String, dynamic>{
        'id': id,
        'lat': double.parse(position.latitude.toStringAsFixed(6)),
        'lon': double.parse(position.longitude.toStringAsFixed(6)),
      };
      if (seq != null) {
        payload['seq'] = seq;
      }
      final messageText = 'pos ${jsonEncode(payload)}';

      final outboundText = prepareOutbound(messageText);
      if (utf8.encode(outboundText).length > maxBytes) {
        return BeaconActionResult.failure(
          'Beacon payload exceeds $payloadTooLongErrorPrefix max bytes ($maxBytes).',
        );
      }

      await send(messageText);
      return const BeaconActionResult.success();
    } catch (_) {
      return const BeaconActionResult.failure(
        'Unable to fetch current location.',
      );
    }
  }

  void stopRangeTest({bool clearPersisted = true}) {
    unawaited(disableBackgroundService(clearPersisted: clearPersisted));
  }

  Future<void> disableBackgroundService({bool clearPersisted = false}) async {
    try {
      await bg.BackgroundLocation.stopLocationService();
    } catch (_) {
      // Keep local state consistent even if stop fails.
    }

    if (clearPersisted) {
      _enrolledChannelIds.clear();
      _enrolledContactIds.clear();

      for (final notifier in _channelSessionNotifiers.values) {
        notifier.value = notifier.value.copyWith(isRunning: false);
      }
      for (final notifier in _contactSessionNotifiers.values) {
        notifier.value = notifier.value.copyWith(isRunning: false);
      }
    }
    await _persistState();
    await _publishRunningState();
    _publishStatus();
  }

  Future<void> dispose() async {
    await bg.BackgroundLocation.stopLocationService();
    _backgroundPollPulseStopwatch?.stop();
    _backgroundPollPulseStopwatch = null;
    _listenersRegistered = false;
  }

  void _markBackgroundPollActivity() {
    final sw = _backgroundPollPulseStopwatch ??= Stopwatch();
    sw
      ..reset()
      ..start();
    backgroundPollActivityTick.value++;
  }
}

class _CurrentCoordsResult {
  final bool ok;
  final String? error;
  final double? lat;
  final double? lon;

  const _CurrentCoordsResult._({
    required this.ok,
    this.error,
    this.lat,
    this.lon,
  });

  const _CurrentCoordsResult.success({required double lat, required double lon})
    : this._(ok: true, lat: lat, lon: lon);

  const _CurrentCoordsResult.failure(String error)
    : this._(ok: false, error: error);
}
