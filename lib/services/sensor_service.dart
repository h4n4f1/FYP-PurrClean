import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';

class SensorService {
  // Pass the databaseURL explicitly inside instanceFor
  late final DatabaseReference _dbRef;

  SensorService() {
    final FirebaseApp app = Firebase.app();
    final FirebaseDatabase db = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: 'https://purrclean-124-default-rtdb.asia-southeast1.firebasedatabase.app',
    );
    _dbRef = db.ref();
  }

  // Listens to live sensor data under: devices/purrclean_01/visits
  Stream<DatabaseEvent> getVisitStream(String deviceId) {
    return _dbRef.child('devices/$deviceId/visits').onValue;
  }

  // Converts Firebase JSON payload to fl_chart FlSpot(x, y) coordinates
  List<FlSpot> parseSensorDataToSpots(DataSnapshot snapshot) {
    List<FlSpot> spots = [];

    if (snapshot.value != null) {
      final Map<dynamic, dynamic> rawMap =
          Map<dynamic, dynamic>.from(snapshot.value as Map);

      rawMap.forEach((key, value) {
        if (value is Map && value.containsKey('timestamp')) {
          DateTime time = DateTime.fromMillisecondsSinceEpoch(value['timestamp']);

          // X-axis: Hour of day (e.g., 8:30 AM = 8.5)
          double hourX = time.hour + (time.minute / 60.0);

          // Y-axis: Duration or weight measurement
          double valueY = (value['duration'] ?? value['weight'] ?? 0).toDouble();

          spots.add(FlSpot(hourX, valueY));
        }
      });
    }

    // Sort chronologically left-to-right
    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }
}