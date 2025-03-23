// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, deprecated_member_use, avoid_print, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class AddSpeedBreakerPage extends StatefulWidget {
  @override
  _AddSpeedBreakerPageState createState() => _AddSpeedBreakerPageState();
}

class _AddSpeedBreakerPageState extends State<AddSpeedBreakerPage> {
  TextEditingController descriptionController = TextEditingController();
  LatLng? _selectedPosition;
  bool _isLoading = false;
  late MapController _mapController;
  final String apiKey =
      "vk4KAuoAjiNPgl2DEtfW4wdkgobLhARj"; // Replace with your actual API key

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initializeFirebase();
  }

  // Ensure Firebase is initialized before using Firestore
  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp();
      _getCurrentLocation();
    } catch (e) {
      _showError("Firebase initialization failed: $e");
    }
  }

  // Get the current user location
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        _selectedPosition = LatLng(position.latitude, position.longitude);
        _mapController.move(_selectedPosition!, 15.0);
      });
    } catch (e) {
      _showError("Failed to get location: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Add speed breaker to Firestore
  Future<void> _addSpeedBreaker() async {
    if (_selectedPosition == null) {
      _showError("Please select a location.");
      return;
    }
    if (descriptionController.text.trim().isEmpty) {
      _showError("Please enter a description.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('speed_breakers').add({
        'latitude': _selectedPosition!.latitude,
        'longitude': _selectedPosition!.longitude,
        'description': descriptionController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      _showSuccess("Speed breaker added successfully!");

      // Delay to show success message before navigating
      await Future.delayed(const Duration(seconds: 1));

      // Navigate to home page
      Navigator.pop(context);
    } catch (e) {
      _showError("Error adding speed breaker: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Show error message
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // Show success message
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Speed Breaker")),
      body: Column(
        children: [
          // Map Display for Selecting Location
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selectedPosition ?? LatLng(52.376372, 4.908066),
                initialZoom: 15.0,
                onTap: (tapPosition, point) {
                  setState(() => _selectedPosition = point);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      "https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png?key=$apiKey",
                ),
                if (_selectedPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedPosition!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Input Fields
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedPosition != null) ...[
                  Text(
                    "Selected Location: \nLatitude: ${_selectedPosition!.latitude}, Longitude: ${_selectedPosition!.longitude}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 10),

                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _getCurrentLocation,
                      child: const Text("Use Current Location"),
                    ),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _addSpeedBreaker,
                      child:
                          _isLoading
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text("Add Speed Breaker"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
