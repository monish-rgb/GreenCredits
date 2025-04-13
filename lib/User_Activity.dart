import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class GreenActivity {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Base rates for carbon credits (credits per kg CO2 saved)
  final Map<String, double> _baseCreditsRate = {
    'TransportMode.walking': 0.5,    // 0.5 credits per kg CO2 saved
    'TransportMode.cycling': 0.5,    // 0.5 credits per kg CO2 saved
    'TransportMode.bus': 0.2,       // 0.2 credits per kg CO2 saved
    'TransportMode.train': 0.3,     // 0.3 credits per kg CO2 saved
  };

  // Average car emissions (kg CO2 per km) - baseline for comparing savings
  final double _carEmissionFactor = 0.192;

  // Calculate carbon credits for a single trip
  double calculateTripCredits(String transportMode, double distance) {
    // Default to 0 credits for car trips (no savings)
    if (transportMode == 'TransportMode.car') {
      return 0.0;
    }

    // Calculate how much CO2 would have been emitted if using a car
    double carEmissions = distance * _carEmissionFactor;

    // Calculate actual emissions based on transport mode
    double actualEmissions = 0.0;
    switch (transportMode) {
      case 'TransportMode.walking':
      case 'TransportMode.cycling':
        actualEmissions = 0.0; // Zero emissions
        break;
      case 'TransportMode.bus':
        actualEmissions = distance * 0.105; // Bus emissions
        break;
      case 'TransportMode.train':
        actualEmissions = distance * 0.041; // Train emissions
        break;
      default:
        return 0.0; // Unknown mode
    }

    // Calculate CO2 savings
    double co2Saved = carEmissions - actualEmissions;

    // Calculate credits based on savings and rate
    double creditsEarned = co2Saved * (_baseCreditsRate[transportMode] ?? 0.0);

    return creditsEarned;
  }

  // Get the current user's email
  String? get _userEmail => _auth.currentUser?.email;

  // Get real-time carbon credits balance
  Stream<double> getCarbonCreditsStream() {
    if (_userEmail == null) {
      return Stream.value(0.0);
    }

    return _firestore
        .collection('users_data')
        .doc(_userEmail)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        return (data['carbonCredits'] ?? 0.0).toDouble();
      } else {
        return 0.0;
      }
    });
  }

  // Method to calculate credits for a specific date range
  Future<Map<String, dynamic>> getCreditsForDateRange(DateTime startDate, DateTime endDate) async {
    if (_userEmail == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Convert dates to Timestamps for Firestore query
      Timestamp startTimestamp = Timestamp.fromDate(startDate);
      Timestamp endTimestamp = Timestamp.fromDate(endDate);

      // Query trips within the date range
      QuerySnapshot tripsSnapshot = await _firestore
          .collection('users_data')
          .doc(_userEmail)
          .collection('trips')
          .where('startTime', isGreaterThanOrEqualTo: startTimestamp)
          .where('startTime', isLessThanOrEqualTo: endTimestamp)
          .where('status', isEqualTo: 'completed')
          .get();

      double periodCredits = 0.0;
      double periodCO2Saved = 0.0;
      Map<String, int> transportModeCount = {
        'walking': 0,
        'cycling': 0,
        'bus': 0,
        'train': 0,
        'car': 0,
      };

      // Process each trip in the date range
      for (var doc in tripsSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        String transportMode = data['transportMode'] ?? 'TransportMode.car';
        double distance = (data['distance'] ?? 0.0).toDouble();

        // Update mode count
        String modeKey = transportMode.split('.').last.toLowerCase();
        transportModeCount[modeKey] = (transportModeCount[modeKey] ?? 0) + 1;

        // Calculate credits
        double tripCredits = calculateTripCredits(transportMode, distance);
        periodCredits += tripCredits;

        // Calculate CO2 saved
        double carEmissions = distance * _carEmissionFactor;
        double actualEmissions = data['carbonFootprint'] ?? 0.0;
        periodCO2Saved += (carEmissions - actualEmissions);
      }

      // Return detailed summary for the period
      return {
        'periodCredits': periodCredits,
        'periodCO2Saved': periodCO2Saved,
        'tripCount': tripsSnapshot.docs.length,
        'transportModeCount': transportModeCount,
        'startDate': startDate,
        'endDate': endDate,
      };
    } catch (e) {
      print('Error calculating period carbon credits: $e');
      rethrow;
    }
  }
}

class ActivityScreen extends StatefulWidget {
  @override
  _ActivityScreenState createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final GreenActivity _creditsService = GreenActivity();
  bool _isLoading = true;
  Map<String, dynamic> _creditsData = {};

  // Date range for filtering
  DateTime _startDate = DateTime.now().subtract(Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCarbonCredits();
  }

  Future<void> _loadCarbonCredits() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get period-specific credits
      Map<String, dynamic> periodData = await _creditsService.getCreditsForDateRange(
          _startDate,
          _endDate
      );

      setState(() {
        _creditsData = {
          'period': periodData,
        };
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading carbon credits: $e');
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load carbon credits'))
      );
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Colors.green.shade300,
              onPrimary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.black

            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black),
            ),
            dialogTheme: DialogTheme(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 12,
              backgroundColor: Colors.grey[900],
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });

      _loadCarbonCredits();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Trips History', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.date_range, color: Colors.white),
            onPressed: () => _selectDateRange(context),
            tooltip: 'Select Date Range',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadCarbonCredits,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPeriodSummaryCard(),
            SizedBox(height: 16),
            _buildTransportModeBreakdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSummaryCard() {
    final periodData = _creditsData['period'] ?? {};
    final periodCredits = periodData['periodCredits'] ?? 0.0;
    final periodCO2Saved = periodData['periodCO2Saved'] ?? 0.0;
    final periodTripCount = periodData['tripCount'] ?? 0;

    final dateFormat = DateFormat('MMM d, yyyy');
    final dateRangeText = '${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}';

    return Card(
      elevation: 4,
      color: Colors.black87,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Period Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  dateRangeText,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('Credits', '${periodCredits.toStringAsFixed(2)}', Icons.star, Colors.amber),
                _buildStat('CO₂ Saved', '${periodCO2Saved.toStringAsFixed(2)} kg', Icons.eco),
                _buildStat('Trips', '$periodTripCount', Icons.route),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportModeBreakdown() {
    final periodData = _creditsData['period'] ?? {};
    final transportModeCount = periodData['transportModeCount'] ?? {};

    return Card(
      elevation: 4,
      color: Colors.black87,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transport Mode Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            _buildTransportModeItem('Walking', Icons.directions_walk, transportModeCount['walking'] ?? 0),
            _buildTransportModeItem('Cycling', Icons.directions_bike, transportModeCount['cycling'] ?? 0),
            _buildTransportModeItem('Bus', Icons.directions_bus, transportModeCount['bus'] ?? 0),
            _buildTransportModeItem('Train', Icons.train, transportModeCount['train'] ?? 0),
            _buildTransportModeItem('Car', Icons.directions_car, transportModeCount['car'] ?? 0),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportModeItem(String mode, IconData icon, int count) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          SizedBox(width: 12),
          Text(
            mode,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          Spacer(),
          Text(
            '$count trips',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon, [Color? iconColor]) {
    return Column(
      children: [
        Icon(
          icon,
          color: iconColor ?? Colors.white,
          size: 28,
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}

