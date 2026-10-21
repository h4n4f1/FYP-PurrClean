import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_wrapper.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('Handling a background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start Firebase and warm up local storage at the same time.
  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    SharedPreferences.getInstance(),
  ]);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

// Safely requests permissions and gets token after the UI mounts
Future<void> _setupPushNotifications() async {
  final messaging = FirebaseMessaging.instance;

  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    debugPrint('User granted notification permission');

    final token = await messaging.getToken();
    debugPrint('FCM Token: $token');

    // Handle messages while the app is active and open on the screen
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');

      final notification = message.notification;
      if (notification != null) {
        debugPrint('Notification Title: ${notification.title}');
        debugPrint('Notification Body: ${notification.body}');
      }
    });
  } else {
    debugPrint('User declined notification permission');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Runs after the first frame so it never delays opening the app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupPushNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PurrClean',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFFFF8A00),
        scaffoldBackgroundColor: const Color(0xFFFFF3D6),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF8A00)),
      ),
      home: const AuthWrapper(),
    );
  }
}