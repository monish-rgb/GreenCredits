import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

// User model class
class UserModel {

  final String email;
  final String name;
  final String home;
  final String work;

  UserModel({

    required this.email,
    required this.name,
    required this.home,
    required this.work,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {

      'email': email,
      'name': name,
      'home': home,
      'work': work,
    };
  }

  // Create from JSON (for retrieval)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(

      email: json['email'] ?? '',
      name: json['name'] ?? '',
      home: json['home'] ?? '',
      work: json['work'] ?? '',
    );
  }

  // Create a copy with updated fields
  UserModel copyWith({

    String? email,
    String? name,
    String? home,
    String? work,
  }) {
    return UserModel(

      email: email ?? this.email,
      name: name ?? this.name,
      home: home ?? this.home,
      work: work ?? this.work,
    );
  }
}

// User state service class
class UserStateService {
  // Singleton pattern
  static final UserStateService _instance = UserStateService._internal();
  factory UserStateService() => _instance;
  UserStateService._internal();

  // Current user in memory
  UserModel? _currentUser;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get current user
  UserModel? get currentUser => _currentUser;

  // Check if user is logged in
  bool get isLoggedIn => _currentUser != null;

  // Store user in SharedPreferences, Firestore, and memory
  Future<void> storeUser(firebase_auth.User firebaseUser) async {

    // First, check if user exists in Firestore
    UserModel? userData = await _fetchUserFromFirestore(firebaseUser.email ?? '');

    // If user doesn't exist in Firestore yet, create a new entry
    if (userData == null) {
      userData = UserModel(

        email: firebaseUser.email ?? '',
        name: '',
        home: '',
        work: '',
      );

      // Save new user to Firestore
      await _saveUserToFirestore(userData);
    }

    // Store in memory
    _currentUser = userData;

    // Store in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(userData.toJson()));
    await prefs.setBool('isLoggedIn', true);
  }

  // Fetch user data from Firestore
  Future<UserModel?> _fetchUserFromFirestore(String email) async {
    if (email.isEmpty) return null;

    try {
      final docRef = _db.collection('users_data').doc(email);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        return UserModel(
          email: email,
          name: data['name'] ?? '',
          home: data['home'] ?? '',
          work: data['work'] ?? '',
        );
      }
      return null;
    } catch (e) {
      print('Error fetching user from Firestore: $e');
      return null;
    }
  }

  // Save user data to Firestore
  Future<void> _saveUserToFirestore(UserModel user) async {
    if (user.email.isEmpty) return;

    try {
      print('Attempting to save to Firestore: ${user.email}'); // Debug log
      print('Attempting to save to home location Firestore: ${user.home}');
      await _db.collection('users_data').doc(user.email).set({

        'name': user.name,
        'home': user.home,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving user to Firestore: $e');
    }
  }

  // Update user data in memory, SharedPreferences and Firestore
  Future<void> updateUserData({
    String? name,
    String? home,
  }) async {
    if (_currentUser == null) return;

    // Create updated user model
    final updatedUser = _currentUser!.copyWith(
      name: name,
      home: home,
    );

    // Update in memory
    _currentUser = updatedUser;

    // Update in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(updatedUser.toJson()));

    // Update in Firestore
    await _saveUserToFirestore(updatedUser);
  }

  // Load user from SharedPreferences and refresh from Firestore
  Future<UserModel?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');

    if (userData != null) {
      try {
        final userMap = jsonDecode(userData) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(userMap);

        // Refresh data from Firestore to ensure we have the latest
        if (_currentUser!.email.isNotEmpty) {
          final firestoreUser = await _fetchUserFromFirestore(_currentUser!.email);
          if (firestoreUser != null) {
            _currentUser = firestoreUser;
            // Update SharedPreferences with latest data
            await prefs.setString('user_data', jsonEncode(_currentUser!.toJson()));
          }
        }

        return _currentUser;
      } catch (e) {
        print('Error parsing user data: $e');
        return null;
      }
    }
    return null;
  }

  // Clear user data (logout)
  Future<void> clearUser() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    await prefs.setBool('isLoggedIn', false);
  }
}