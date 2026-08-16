import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// A pin dropped on the map (origin/destination).
class MapPin {
  final double lat, lon;
  final String color; // hex, e.g. '#2E7D32'

  const MapPin(this.lat, this.lon, this.color);
}

/// The offline city map: MapLibre rendering a local PMTiles pack with a
/// local style — no network involved.
class TransitMap extends StatefulWidget {
  final String styleJson;
  final double centerLat, centerLon;
  final double zoom;
  final List<MapPin> pins;
  final void Function(double lat, double lon)? onTap;

  /// Device position: drawn as a blue dot; the camera moves to it whenever
  /// it changes (set after a my-location fix).
  final (double, double)? userPosition;

  const TransitMap({
    super.key,
    required this.styleJson,
    required this.centerLat,
    required this.centerLon,
    this.zoom = 11.5,
    this.pins = const [],
    this.onTap,
    this.userPosition,
  });

  @override
  State<TransitMap> createState() => TransitMapState();
}

class TransitMapState extends State<TransitMap> {
  MapLibreMapController? _controller;
  final List<Circle> _circles = [];

  Future<void> _syncPins() async {
    final c = _controller;
    if (c == null) return;
    for (final circle in _circles) {
      await c.removeCircle(circle);
    }
    _circles.clear();
    for (final p in widget.pins) {
      _circles.add(await c.addCircle(CircleOptions(
        geometry: LatLng(p.lat, p.lon),
        circleColor: p.color,
        circleRadius: 9,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      )));
    }
    final u = widget.userPosition;
    if (u != null) {
      _circles.add(await c.addCircle(CircleOptions(
        geometry: LatLng(u.$1, u.$2),
        circleColor: '#1565C0', // blue: you are here
        circleRadius: 8,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      )));
    }
  }

  @override
  void didUpdateWidget(TransitMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPins();
    final u = widget.userPosition;
    if (u != null && u != oldWidget.userPosition) {
      _controller?.animateCamera(CameraUpdate.newLatLng(LatLng(u.$1, u.$2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: widget.styleJson,
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.centerLat, widget.centerLon),
        zoom: widget.zoom,
      ),
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: _syncPins,
      onMapClick: (point, latLng) =>
          widget.onTap?.call(latLng.latitude, latLng.longitude),
      // The map sits inside a TabBarView — claim every gesture eagerly so
      // the pager's horizontal swipe never steals pans/pinches mid-drag.
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      // Offline pack: the compass/attribution defaults stay; no logo URL.
      compassEnabled: true,
      myLocationEnabled: false, // Play-Services-free location lands later
    );
  }
}
