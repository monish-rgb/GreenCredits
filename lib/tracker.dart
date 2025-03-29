import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import 'dart:async';
import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/services.dart' show rootBundle;

enum TransportMode {
  walking,
  cycling,
  car,
  bus,
  train
}

class Trip {
  final String id;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final TransportMode transportMode;
  final double distance;
  final double carbonFootprint;
  final List<GeoPoint> routePoints;

  Trip({
    required this.id,
    required this.userId,
    required this.startTime,
    this.endTime,
    required this.transportMode,
    required this.distance,
    required this.carbonFootprint,
    required this.routePoints,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'startTime': startTime,
      'endTime': endTime,
      'transportMode': transportMode.toString(),
      'distance': distance,
      'carbonFootprint': carbonFootprint,
      'routePoints': routePoints,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class TrackerMap extends StatefulWidget {
  @override
  _TrackerState createState() => _TrackerState();
}

class _TrackerState extends State<TrackerMap> with WidgetsBindingObserver {

  GoogleMapController? _mapController;
  Location _locationService = Location();
  LatLng _currentPosition = LatLng(0, 0);
  bool _isLoading = true;
  bool _isTracking = false;
  late String _mapStyleString;


  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? get _currentUser => _auth.currentUser;

  String? _currentTripId;
  DateTime? _tripStartTime;

  // Journey tracking
  List<LatLng> _routePoints = [];
  StreamSubscription<LocationData>? _locationSubscription;
  double _totalDistance = 0.0; // in kilometers
  double _carbonFootprint = 0.0; // in kg CO2

  // Selected transport mode
  TransportMode _selectedMode = TransportMode.car;

  // Carbon emission factors (kg CO2 per km)
  final Map<TransportMode, double> _emissionFactors = {
    TransportMode.walking: 0.0,
    TransportMode.cycling: 0.0,
    TransportMode.car: 0.192, // Average car
    TransportMode.bus: 0.105, // Average bus
    TransportMode.train: 0.041, // Average train
  };

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    rootBundle.loadString('assets/mapstyle.json').then((string) {
      _mapStyleString = string;
    });
    super.initState();
    _getUserLocation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes to manage location updates appropriately
    if (state == AppLifecycleState.resumed) {
      // App is in the foreground
      if (_isTracking) {
        print("Resuming tracking");
        // Refresh UI state from service
        setState(() {
          _routePoints = List.from(_routePoints);
          _totalDistance = _totalDistance;
          _carbonFootprint = _carbonFootprint;
          _updatePolyline();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTracking();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _getUserLocation() async {

    print("user ID: $_currentUser");
    try {
      bool serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
        print("Service Enabled: $serviceEnabled");
        if (!serviceEnabled) {
          return;
        }
      }

      PermissionStatus permissionGranted = await _locationService.hasPermission();
      if (permissionGranted!= PermissionStatus.granted
          && permissionGranted != PermissionStatus.grantedLimited) {
        permissionGranted = await _locationService.requestPermission();
        print("Permission Granted: $permissionGranted");
        if (permissionGranted != PermissionStatus.granted) {
          return;
        }
      }

      LocationData locationData = await _locationService.getLocation();
      print("Location Data: $locationData");

      setState(() {
        _currentPosition = LatLng(
          locationData.latitude!,
          locationData.longitude!,
        );
        _isLoading = false;
      print("Current Position: $_currentPosition");
        // Add marker for current position
        _markers.add(
          Marker(
            markerId: MarkerId("currentLocation"),
            position: _currentPosition,
            infoWindow: InfoWindow(title: "Your Location"),
          ),
        );
      });

      // Move camera to user's location
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _currentPosition,
              zoom: 15,
            ),
          ),
        );
      }
    } catch (e) {
      print("Failed to get your location: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startTracking() async {
    if (_isTracking) return;

    // Access current user inside a method
    String? userEmail = _auth.currentUser?.email;

    // Create a new trip document in Firestore
    _tripStartTime = DateTime.now();
    DocumentReference tripRef = await _firestore.collection('users_data').doc(userEmail).collection('trips').add({
      'userId': _currentUser!.uid,
      'startTime': _tripStartTime,
      'transportMode': _selectedMode.toString(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });

    _currentTripId = tripRef.id;
    print("Started trip with ID: $_currentTripId");

    setState(() {
      _isTracking = true;
      _routePoints = [_currentPosition]; // Start with current position
      _totalDistance = 0.0;
      _carbonFootprint = 0.0;

      // Clear previous route
      _polylines.clear();
      _markers.clear();

      // Add start marker
      _markers.add(
        Marker(
          markerId: MarkerId("startLocation"),
          position: _currentPosition,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: "Start Point"),
        ),
      );
    });

    // Save initial location to Firestore
    //await _saveLocationToFirestore(_currentPosition);

    // Start listening to location updates
    _locationService.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 5000, // Update every 5 seconds
      distanceFilter: 10, // Update if moved 10 meters
    );

    _locationSubscription = _locationService.onLocationChanged.listen((LocationData locationData) {
      if (!_isTracking) return;

      LatLng newPosition = LatLng(locationData.latitude!, locationData.longitude!);

      setState(() {
        // Update current position
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
            _carbonFootprint = _totalDistance * _emissionFactors[_selectedMode]!;

            // Update polyline
            _updatePolyline();

            // Update current location marker
            _markers.removeWhere((marker) => marker.markerId.value == "currentLocation");
            _markers.add(
              Marker(
                markerId: MarkerId("currentLocation"),
                position: newPosition,
                infoWindow: InfoWindow(title: "Current Location"),
              ),
            );

            // Save initial location to Firestore
            //_saveLocationToFirestore(newPosition);
          }
        }
      });

      // Move camera to follow user
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(newPosition),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tracking started')),
    );
  }
/*
  Future<void> _saveLocationToFirestore(LatLng position) async {
    if (_currentTripId == null || _currentUser == null) return;
  String? userEmail = _auth.currentUser?.email;
    try {
      await _firestore
          .collection('users_data').doc(userEmail).collection('trips')
          .doc(_currentTripId)
          .collection('locations')
          .add({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error saving location: $e");
    }
  }

 */

  void _stopTracking() async {
    if (!_isTracking) return;

    _locationSubscription?.cancel();

    setState(() {
      _isTracking = false;

      // Add end marker if we have tracked a route
      if (_routePoints.length > 1) {
        _markers.add(
          Marker(
            markerId: MarkerId("endLocation"),
            position: _routePoints.last,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: "End Point"),
          ),
        );
      }
    });

    // Update trip document in Firestore
    if (_currentTripId != null) {
      try {
        // Convert route points to GeoPoints for Firestore
        List<GeoPoint> geoPoints = _routePoints
            .map((point) => GeoPoint(point.latitude, point.longitude))
            .toList();
        String? userEmail = _auth.currentUser?.email;
        await _firestore.collection('users_data').doc(userEmail).collection('trips').doc(_currentTripId).update({
          'endTime': DateTime.now(),
          'distance': _totalDistance,
          'carbonFootprint': _carbonFootprint,
          'transportMode': _selectedMode.toString(),
          'status': 'completed',
          'summary': {
            'startPoint': GeoPoint(_routePoints.first.latitude, _routePoints.first.longitude),
            'endPoint': GeoPoint(_routePoints.last.latitude, _routePoints.last.longitude),
            'numberOfPoints': _routePoints.length,
          }
        });

        print("Trip $_currentTripId completed and saved to Firestore");
      } catch (e) {
        print("Error updating trip: $e");
      }
    }

    // Show journey summary
    _showJourneySummary();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tracking stopped')),
    );
  }

  void _showJourneySummary() {
    showModalBottomSheet(
      backgroundColor: Colors.black,
      context: context,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Journey Summary',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,color: Colors.white),
            ),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.directions,color: Colors.white),
              title: Text('Distance Traveled',style: TextStyle(color: Colors.white)),
              trailing: Text('${_totalDistance.toStringAsFixed(2)} km',style: TextStyle(color: Colors.white)),
            ),
            ListTile(
              leading: Icon(Icons.eco,color: Colors.white),
              title: Text('Carbon Footprint',style: TextStyle(color: Colors.white)),
              trailing: Text('${_carbonFootprint.toStringAsFixed(2)} kg CO₂',style: TextStyle(color: Colors.white)),
            ),
            ListTile(
              leading: Icon(_getTransportIcon(),color: Colors.white),
              title: Text('Transport Mode',style: TextStyle(color: Colors.white)),
              trailing: Text(_selectedMode.toString().split('.').last,style: TextStyle(color: Colors.white)),
            ),
            if (_tripStartTime != null)
              ListTile(
                leading: Icon(Icons.access_time,color: Colors.white),
                title: Text('Trip Duration',style: TextStyle(color: Colors.white)),
                trailing: Text(_formatDuration(DateTime.now().difference(_tripStartTime!)),style: TextStyle(color: Colors.white)),
              ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: Text('Close',style: TextStyle(color: Colors.black)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _viewTripHistory();
              },
              child: Text('View Trip History',style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
  IconData _getTransportIcon() {
    switch (_selectedMode) {
      case TransportMode.walking:
        return Icons.directions_walk;
      case TransportMode.cycling:
        return Icons.directions_bike;
      case TransportMode.car:
        return Icons.directions_car;
      case TransportMode.bus:
        return Icons.directions_bus;
      case TransportMode.train:
        return Icons.train;
      }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void _viewTripHistory() {
    // Navigate to a trip history screen
    // This would be implemented separately
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Trip history feature coming soon')),
    );
  }

  void _updatePolyline() {
    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: PolylineId('userRoute'),
        points: _routePoints,
        color: Colors.blue,
        width: 5,
      ),
    );
  }

  // Haversine formula to calculate distance between two coordinates
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295; // Math.PI / 180
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  void _selectTransportMode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.all(16),
        titlePadding: EdgeInsets.all(16),
        backgroundColor: Colors.black,
        title: Text('Select Transport Mode',style: TextStyle(color: Colors.white)),
        content: Container(
          width: double.minPositive,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: TransportMode.values.map((mode) {
              return ListTile(
                leading: Icon(_getTransportModeIcon(mode),color: Colors.white),
                title: Text(mode.toString().split('.').last,style: TextStyle(color: Colors.white)),
                onTap: () {
                  setState(() {
                    _selectedMode = mode;
                    // Recalculate carbon footprint with new mode
                    _carbonFootprint = _totalDistance * _emissionFactors[_selectedMode]!;
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  IconData _getTransportModeIcon(TransportMode mode) {
    switch (mode) {
      case TransportMode.walking:
        return Icons.directions_walk;
      case TransportMode.cycling:
        return Icons.directions_bike;
      case TransportMode.car:
        return Icons.directions_car;
      case TransportMode.bus:
        return Icons.directions_bus;
      case TransportMode.train:
        return Icons.train;
      }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Carbon Tracker Map",style: TextStyle(color: Colors.white,fontSize: 13),),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.commute, color: Colors.white),
            onPressed: _selectTransportMode,
            tooltip: 'Select Transport Mode',
          ),
        ],
      ),

      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Stack(children: [GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _currentPosition,
          zoom: 15,
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        markers: _markers,
        polylines: _polylines,
        onMapCreated: (GoogleMapController controller) {
          _mapController = controller;
        },
        style: _mapStyleString,
      ),
        if (_isTracking)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tracking Journey...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(_getTransportIcon(), size: 20),
                            SizedBox(width: 4),
                            Text(
                              _selectedMode.toString().split('.').last,
                            ),
                          ],
                        ),
                        Text('${_totalDistance.toStringAsFixed(2)} km'),
                        Text('${_carbonFootprint.toStringAsFixed(2)} kg CO₂'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    ],
      ),

     floatingActionButton: FloatingActionButton.extended(
        onPressed: _isTracking ? _stopTracking : _startTracking,
        icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow,color: Colors.black),
        label: Text(_isTracking ? 'Stop Tracking' : 'Start Tracking',style: TextStyle(color: Colors.black),),
        backgroundColor: _isTracking ? Colors.red[300] : Colors.green,
      ),

    );
  }
}