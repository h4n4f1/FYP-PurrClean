import 'package:flutter/material.dart';
import 'auth_wrapper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('Handling a background message: ${message.messageId}');
}

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

// Safely requests permissions and gets token after the UI mounts
void _setupPushNotifications() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request notification permissions
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('User granted notification permission');
    
    // Get the FCM Token
    String? token = await messaging.getToken();
    print("FCM Token: $token");

    // Handle messages while the app is active and open on the screen
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      
      final notification = message.notification;
      
      if (notification != null) {
        print('Notification Title: ${notification.title}');
        print('Notification Body: ${notification.body}');
      }
    });
  } else {
    print('User declined notification permission');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State createState() => _MyAppState();
}

class _MyAppState extends State {
  @override
  void initState() {
    super.initState();
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