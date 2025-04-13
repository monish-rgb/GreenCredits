// location_service.dart
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Location service
  final Location _location = Location();

  // Tracking state
  bool _isTracking = false;
  LatLng _currentPosition = LatLng(0, 0);
  List<LatLng> _routePoints = [];
  double _totalDistance = 0.0;
  StreamSubscription<LocationData>? locationSubscription;

  // Getters
  bool get isTracking => _isTracking;
  LatLng get currentPosition => _currentPosition;
  List<LatLng> get routePoints => _routePoints;
  double get totalDistance => _totalDistance;

  // Location update callback
  Function(LatLng)? onLocationUpdate;

  // Initialize location service
  Future<bool> initialize() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          return false;
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted != PermissionStatus.granted &&
          permissionGranted != PermissionStatus.grantedLimited) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          return false;
        }
      }

      // Get initial location
      LocationData locationData = await _location.getLocation();
      _currentPosition = LatLng(
        locationData.latitude!,
        locationData.longitude!,
      );

      return true;
    } catch (e) {
      print("Failed to initialize location service: $e");
      return false;
    }
  }

  // Start tracking
  void startTracking(Function(LatLng) updateCallback, {Function(double)? distanceCallback}) {
    if (_isTracking) return;

    _isTracking = true;
    _routePoints = [_currentPosition];
    _totalDistance = 0.0;
    onLocationUpdate = updateCallback;

    _location.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 5000, // Update every 5 seconds
      distanceFilter: 10, // Update if moved 10 meters
    );

    locationSubscription = _location.onLocationChanged.listen((LocationData locationData) {
      if (!_isTracking) return;

      LatLng newPosition = LatLng(locationData.latitude!, locationData.longitude!);
      _currentPosition = newPosition;

      // Calculate distance from last point
      if (_routePoints.isNotEmpty) {
        double segmentDistance = _calculateDistance(
            _routePoints.last.latitude,
            _routePoints.last.longitude,
            newPosition.latitude,
            newPosition.longitude
        );

        // Only add point if it's a significant distance (to avoid small GPS fluctuations)
        if (segmentDistance > 0.01) { // More than 10 meters
          _routePoints.add(newPosition);
          _totalDistance += segmentDistance;


          if (distanceCallback != null) {
            distanceCallback(_totalDistance);
          }
        }
      }

      // Notify listeners
      if (onLocationUpdate != null) {
        onLocationUpdate!(newPosition);
      }
    });
  }

  // Stop tracking
  void stopTracking() {
    _isTracking = false;
    locationSubscription?.cancel();
    locationSubscription = null;
    onLocationUpdate = null;
  }

  // Resume tracking if it was active
  void resumeTracking(Function(LatLng) updateCallback, {Function(double)? distanceCallback}) {
    if (_isTracking && locationSubscription == null) {
      // Restart subscription
      startTracking(updateCallback, distanceCallback: distanceCallback);
    }
  }

  // Reset tracking state (for testing/debugging)
  void reset() {
    stopTracking();
    _routePoints = [];
    _totalDistance = 0.0;
  }

  // Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final c = (lat2 - lat1) * p;
    final a = 0.5 - (c / 2) + (0.5 - (lon2 - lon1) * p / 2) *
        ((1 - c) * 0.5 - c * 0.5);
    return 12742 * (1 - 2 * a); // 2 * R; R = 6371 km
  }

  // Cleanup when app is terminated
  void dispose() {
    locationSubscription?.cancel();
    locationSubscription = null;
  }
}