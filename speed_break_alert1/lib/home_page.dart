// ignore_for_file: deprecated_member_use, library_private_types_in_public_api, use_key_in_widget_constructors, use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  TextEditingController searchController = TextEditingController();
  Position? _currentPosition;
  late MapController _mapController;
  final String apiKey =
      "vk4KAuoAjiNPgl2DEtfW4wdkgobLhARj"; // Replace with actual API key
  LatLng? _searchedLocation;
  List<LatLng> _routeCoordinates = [];
  List<Marker> _speedBreakerMarkers = [];
  bool _showSpeedBreakers = false;

  // Add a stream subscription for real-time position updates
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _checkLocationPermissionAndFetch();
  }

  @override
  void dispose() {
    // Cancel the position stream subscription when the widget is disposed
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  void _checkLocationPermissionAndFetch() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError("Location services are disabled.");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError("Location permission denied.");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showError(
        "Location permission permanently denied. Enable it from settings.",
      );
      return;
    }

    _getCurrentLocation();
  }

  void _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _currentPosition = position;
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          15.0,
        );
      });

      // Start listening to position updates
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best, // Moved inside LocationSettings
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        setState(() {
          _currentPosition = position;
        });
        _checkForNearbySpeedBreakers(position);
      });
    } catch (e) {
      _showError("Failed to get location: $e");
    }
  }

  Future<void> _searchLocation() async {
    String query = searchController.text.trim();
    if (query.isEmpty) {
      _showError("Please enter a location.");
      return;
    }

    String url =
        "https://api.tomtom.com/search/2/search/$query.json?key=$apiKey&limit=1";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        if (data["results"].isNotEmpty) {
          double lat = data["results"][0]["position"]["lat"];
          double lon = data["results"][0]["position"]["lon"];

          setState(() {
            _searchedLocation = LatLng(lat, lon);
            _mapController.move(_searchedLocation!, 15.0);
            _fetchRoute();
          });
        } else {
          _showError("Location not found.");
        }
      } else {
        _showError("Error fetching location.");
      }
    } catch (e) {
      _showError("Network error: $e");
    }
  }

  Future<void> _fetchRoute() async {
    if (_currentPosition == null || _searchedLocation == null) return;

    double startLat = _currentPosition!.latitude;
    double startLon = _currentPosition!.longitude;
    double endLat = _searchedLocation!.latitude;
    double endLon = _searchedLocation!.longitude;

    String url =
        "https://api.tomtom.com/routing/1/calculateRoute/$startLat,$startLon:$endLat,$endLon/json?key=$apiKey";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        List<LatLng> routePoints = [];
        List<Marker> markers = [];

        if (data["routes"] != null && data["routes"].isNotEmpty) {
          var points = data["routes"][0]["legs"][0]["points"];
          for (var point in points) {
            routePoints.add(LatLng(point["latitude"], point["longitude"]));
          }
        }

        // Add start and end markers
        markers.add(
          Marker(
            point: LatLng(startLat, startLon),
            width: 40,
            height: 40,
            child: Icon(Icons.location_on, color: Colors.green, size: 30),
          ),
        );

        markers.add(
          Marker(
            point: LatLng(endLat, endLon),
            width: 40,
            height: 40,
            child: Icon(Icons.location_on, color: Colors.red, size: 30),
          ),
        );

        // Fetch speed breakers from Firestore
        QuerySnapshot snapshot =
            await FirebaseFirestore.instance.collection('speed_breakers').get();

        for (var doc in snapshot.docs) {
          double lat = doc['latitude'];
          double lon = doc['longitude'];
          LatLng speedBreakerLocation = LatLng(lat, lon);

          // Calculate distance from speed breaker to route
          double distance = _calculateDistanceFromPointToPolyline(
            speedBreakerLocation,
            routePoints,
          );

          // If speed breaker is within 50 meters of the route, add it to markers
          if (distance <= 10) {
            markers.add(
              Marker(
                point: speedBreakerLocation,
                width: 40,
                height: 40,
                child: Icon(Icons.warning, color: Colors.orange, size: 30),
              ),
            );
          }
        }

        setState(() {
          _routeCoordinates = routePoints;
          _speedBreakerMarkers = markers;
        });
      } else {
        _showError("Error fetching route.");
      }
    } catch (e) {
      _showError("Network error: $e");
    }
  }

  void _checkForNearbySpeedBreakers(Position userPosition) {
    if (_speedBreakerMarkers.isEmpty) return;

    for (var marker in _speedBreakerMarkers) {
      double distance = _calculateDistance(
        userPosition.latitude,
        userPosition.longitude,
        marker.point.latitude,
        marker.point.longitude,
      );

      if (distance <= 20) {
        Future.delayed(Duration(seconds: 1), () {
          _showAlert("Urgent Alert!", "Speed breaker ahead in 20 meters!");
        });
      } else if (distance <= 100) {
        Future.delayed(Duration(seconds: 4), () {
          _showAlert("Warning!", "Speed breaker ahead in 100 meters.");
        });
      }
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final Distance distance = Distance();
    return distance(LatLng(lat1, lon1), LatLng(lat2, lon2));
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (context) {
        Future.delayed(const Duration(seconds: 4), () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });

        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 50.0),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _calculateDistanceFromPointToPolyline(
    LatLng point,
    List<LatLng> polyline,
  ) {
    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      double distance = _calculateDistanceFromPointToLineSegment(
        point,
        polyline[i],
        polyline[i + 1],
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  double _calculateDistanceFromPointToLineSegment(
    LatLng point,
    LatLng start,
    LatLng end,
  ) {
    final Distance distance = Distance();
    final double lineLength = distance(start, end);
    if (lineLength == 0) return distance(point, start);

    final double t =
        ((point.latitude - start.latitude) * (end.latitude - start.latitude) +
            (point.longitude - start.longitude) *
                (end.longitude - start.longitude)) /
        (lineLength * lineLength);

    final double clampedT = t.clamp(0.0, 1.0);
    final LatLng closestPoint = LatLng(
      start.latitude + clampedT * (end.latitude - start.latitude),
      start.longitude + clampedT * (end.longitude - start.longitude),
    );

    return distance(point, closestPoint);
  }

  Future<void> _toggleSpeedBreakers() async {
    if (_showSpeedBreakers) {
      setState(() {
        _speedBreakerMarkers.clear();
        _showSpeedBreakers = false;
      });
      return;
    }

    try {
      QuerySnapshot snapshot =
          await FirebaseFirestore.instance.collection('speed_breakers').get();
      List<Marker> markers =
          snapshot.docs.map((doc) {
            double lat = doc['latitude'];
            double lon = doc['longitude'];

            return Marker(
              point: LatLng(lat, lon),
              width: 40,
              height: 40,
              child: Icon(Icons.warning, color: Colors.orange, size: 30),
            );
          }).toList();

      setState(() {
        _speedBreakerMarkers = markers;
        _showSpeedBreakers = true;
      });
    } catch (e) {
      _showError("Error fetching speed breakers: $e");
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Speed Breaker Alert")),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _currentPosition != null
                        ? LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        )
                        : LatLng(52.376372, 4.908066),
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      "https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png?key=$apiKey",
                ),
                if (_routeCoordinates.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routeCoordinates,
                        strokeWidth: 4.0,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                MarkerLayer(markers: _speedBreakerMarkers),
              ],
            ),
          ),

          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: "Search location...",
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: Icon(Icons.search),
                    onPressed: _searchLocation,
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 20,
            left: 10,
            right: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _toggleSpeedBreakers,
                  child: Text(
                    _showSpeedBreakers ? "Speed Breakers" : "Speed Breakers",
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/addSpeedBreaker');
                  },
                  child: Text("Add Speed Breaker"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
