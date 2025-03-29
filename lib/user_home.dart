
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_location_search/flutter_location_search.dart';
import 'main.dart';
import 'user_state_service.dart';
import 'tracker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  UserModel? _userData;
  bool _isLoading = true;
  String _locationText = 'Tap here to search a place';

  final TextEditingController nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    // Get user data from our service
    final userService = UserStateService();
    final userData = userService.currentUser ?? await userService.loadUser();

    setState(() {
      _userData = userData;
      _isLoading = false;
    });
  }
  Future<void> _signOut() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      // Sign out from Google if used
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();

      // Clear user state using our service
      await UserStateService().clearUser();

      // Navigate to login page
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => LoginPage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }
  Future<void> _verifylocation(String location) async {
    // setState(() {
    //   _isLoading = true;
    // });

    try {
      // Clear user state using our service
      final userService = UserStateService();

      // Make sure we have a logged-in user
      if (!userService.isLoggedIn) {
        await userService.loadUser();
        if (!userService.isLoggedIn) {
          throw Exception('No user is logged in');
        }
      }

      // Update the home location field if it's empty
      if(_userData!.home == '') {
        await userService.updateUserData(home: location);

        // Update local state
        final updatedUser = userService.currentUser;
        setState(() {
          _userData = updatedUser;
          _isLoading = false;
        });
      }
      // else if(_userData!.home.isNotEmpty) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(content: Text('Home location already set')),
      //   );
      // }

// Verify the location in the database
      if(_userData!.home.isNotEmpty && _userData!.home == location) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Home Location verified successfully')),
        );
      }
      else if(_userData!.home != location) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sorry, this location does not match your home location')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error verifying location: $e')),
      );
    }
  }
  Future<void> _updateName(String newName) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Clear user state using our service
      final userService = UserStateService();

      // Make sure we have a logged-in user
      if (!userService.isLoggedIn) {
        await userService.loadUser();
        if (!userService.isLoggedIn) {
          throw Exception('No user is logged in');
        }
      }

      // Update only the name field
      await userService.updateUserData(name: newName);

      // Update local state
      final updatedUser = userService.currentUser;
      setState(() {
        _userData = updatedUser;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Name updated successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: $e')),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }


    final email = _userData?.email ?? '';
    final name = _userData?.name ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Home',
          style: TextStyle(
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black,

        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu,color: Colors.white,),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            );
          },
        ),
        iconTheme: IconThemeData(
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _signOut,
            color: Colors.white,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          // Important: Remove any padding from the ListView.
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(name),
              accountEmail: Text(email),
              decoration: BoxDecoration(color: Colors.black),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.grey,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: TextStyle(fontSize: 32, color: Colors.black),
                ),
              ),
            ),
            ListTile(
              title: const Text('Signout'),
              leading: Icon(Icons.logout),
              onTap: () {
                _signOut();
              },
            ),
            ListTile(
              title: const Text('Tracker'),
              leading: Icon(Icons.map_outlined),
              onTap: () {
                // Close the drawer first
                Navigator.pop(context);

                // Navigate to the map screen
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TrackerMap()),
                );
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Enter your preferred name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _updateName(nameController.text),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('update name',style: TextStyle(
                  color: Colors.black,
                )),
              ),
              SizedBox(height: 16),
              TextButton(
                child: Text(_locationText),
                onPressed: () async {
                  try {
                    LocationData? locationData = await LocationSearch.show(
                        context: context,
                        lightAddress: false,
                        mode: Mode.fullscreen,
                        userAgent: UserAgent(appName: 'Employee Home Location',
                            email: email)
                    );
                    if (locationData != null) {
                      setState(() {
                        _locationText = locationData.address;
                      });
                    }
                  }
                  catch (e) {
                    print('Error during location search: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to get location'))
                    );
                  }
                }
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _verifylocation(_locationText),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('verify your home location',style: TextStyle(
                  color: Colors.black,
                )),
              ),
              SizedBox(height: 16),
              // User stats/info section
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Activity',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,

                        ),
                      ),
                      SizedBox(height: 12),
                      ListTile(
                        leading: Icon(Icons.calendar_today,
                            ),
                        title: Text(
                          'Last Login',
                          style: TextStyle(
                            //color: darkModeEnabled ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: Text(
                          'Today',
                          style: TextStyle(
                            //color: darkModeEnabled ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.bar_chart,
                            ),
                        title: Text(
                          'Carbon Footprint',
                          style: TextStyle(

                          ),
                        ),
                        subtitle: Text(
                          'Tap to calculate',
                          style: TextStyle(

                          ),
                        ),
                        onTap: () {
                          // Navigate to carbon footprint calculator
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}