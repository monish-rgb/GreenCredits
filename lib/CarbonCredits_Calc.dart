import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CarbonCredits {
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

  // Fetch all trips and calculate total credits
  Future<Map<String, dynamic>> getUserCarbonCredits() async {
    if (_userEmail == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Get all user trips
      QuerySnapshot tripsSnapshot = await _firestore
          .collection('users_data')
          .doc(_userEmail)
          .collection('trips')
          .where('status', isEqualTo: 'completed')
          .get();

      double totalCredits = 0.0;
      double totalCO2Saved = 0.0;

      // Process each trip
      for (var doc in tripsSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        String transportMode = data['transportMode'] ?? 'TransportMode.car';
        double distance = (data['distance'] ?? 0.0).toDouble();

        double tripCredits = calculateTripCredits(transportMode, distance);
        totalCredits += tripCredits;

        // Calculate CO2 saved compared to car
        double carEmissions = distance * _carEmissionFactor;
        double actualEmissions = data['carbonFootprint'] ?? 0.0;
        totalCO2Saved += (carEmissions - actualEmissions);
      }

      // Update the user's total credits in Firestore
      await _updateUserCreditBalance(totalCredits);

      // Return summary data
      return {
        'totalCredits': totalCredits,
        'totalCO2Saved': totalCO2Saved,
        'tripCount': tripsSnapshot.docs.length,
      };
    } catch (e) {
      print('Error calculating carbon credits: $e');
      rethrow;
    }
  }

  // Update the user's credit balance in Firestore
  Future<void> _updateUserCreditBalance(double totalCredits) async {
    if (_userEmail == null) return;

    try {
      await _firestore.collection('users_data').doc(_userEmail).set({
        'carbonCredits': totalCredits,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating user credit balance: $e');
    }
  }

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

   Future<double?> getLastCO2() async {
    try {
      // Query the collection, order by a timestamp field in descending order, and limit to 1
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('users_data')
          .doc(_userEmail)
          .collection('trips')
          .orderBy('createdAt', descending: true)  // Replace 'timestamp' with your field
          .limit(1)
          .get();

      // Check if any documents were returned
      if (querySnapshot.docs.isNotEmpty) {
        Map<String, dynamic> data = querySnapshot.docs.first.data() as Map<String, dynamic>;
        print('Last Carbon Footprint: ${data['carbonFootprint']}');
        return data['carbonFootprint'];
      } else {
        print('No documents found in the collection');
        return null;
      }
    } catch (e) {
      print('Error getting last Carbon Footprint: $e');
      return null;
    }
  }
}

class CarbonCreditsScreen extends StatefulWidget {
  const CarbonCreditsScreen({super.key});

  @override
  _CarbonCreditsScreenState createState() => _CarbonCreditsScreenState();
}

class _CarbonCreditsScreenState extends State<CarbonCreditsScreen> {
  final CarbonCredits _creditsService = CarbonCredits();
  bool _isLoading = true;
  Map<String, dynamic> _creditsData = {};

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
      // Get all-time credits
      Map<String, dynamic> allTimeData = await _creditsService.getUserCarbonCredits();

      setState(() {
        _creditsData = {
          'allTime': allTimeData,
        };
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading carbon footprint: $e');
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load your last activity'))
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Carbon Credits', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        actions: [
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
            _buildCreditsSummaryCard(),
            SizedBox(height: 16),
            _buildCreditExplanation(),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditsSummaryCard() {
    final allTimeData = _creditsData['allTime'] ?? {};
    final totalCredits = allTimeData['totalCredits'] ?? 0.0;
    final totalCO2Saved = allTimeData['totalCO2Saved'] ?? 0.0;
    final tripCount = allTimeData['tripCount'] ?? 0;

    return Card(
      elevation: 4,
      color: Colors.black87,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Carbon Credits',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 16),
            Center(
              child: Text(
                '${totalCredits.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('CO₂ Saved', '${totalCO2Saved.toStringAsFixed(2)} kg', Icons.eco),
                _buildStat('Total Trips', '$tripCount', Icons.route),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditExplanation() {
    return Card(
      elevation: 4,
      color: Colors.black87,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How Credits Work',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '• Walking/Cycling: 0.5 credits per kg CO₂ saved\n'
                  '• Train: 0.3 credits per kg CO₂ saved\n'
                  '• Bus: 0.2 credits per kg CO₂ saved\n'
                  '• Car: No credits (baseline for comparison)',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Credits are calculated based on CO₂ savings compared to driving a car for the same distance.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
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