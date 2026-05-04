import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/beacon_service.dart';
import '../services/map_tile_cache_service.dart';

class RangeTestPointsMap extends StatelessWidget {
  final List<BeaconRangePoint> points;

  const RangeTestPointsMap({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No points yet',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final latLngPoints = points
        .map((p) => LatLng(p.lat, p.lon))
        .toList(growable: false);
    final center = latLngPoints.last;

    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: kMapTileUrlTemplate,
              userAgentPackageName: MapTileCacheService.userAgentPackageName,
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: latLngPoints,
                  strokeWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (var i = 0; i < latLngPoints.length; i++)
                  Marker(
                    point: latLngPoints[i],
                    width: 28,
                    height: 28,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: i == latLngPoints.length - 1
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          points[i].sequence.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
