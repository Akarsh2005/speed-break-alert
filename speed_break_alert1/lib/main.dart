// ignore_for_file: prefer_const_constructors, use_key_in_widget_constructors

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'login.dart'; // Import LoginPage
import 'home_page.dart'; // Import HomePage
import 'add_speed_break.dart'; // Import AddSpeedBreakerPage

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Initialize Firebase
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speed Breaker Alert',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginPage(), // Start with LoginPage
      routes: {
        '/home': (context) => HomePage(),
        '/addSpeedBreaker': (context) => AddSpeedBreakerPage(),
      },
    );
  }
}