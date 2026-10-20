import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

enum AnalyticsPeriod { daily, weekly, monthly }

class BehavioralInsight {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String severity; // 'high' | 'medium' | 'low'
  final String description;

  const BehavioralInsight({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.severity,
    required this.description,
  });
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.daily;

  // Mock Summary Stats
  final String avgHourlyVisits = "1.8 visits";
  final String avgDuration = "3.5 min";

  // Mock Insights
  final List<BehavioralInsight> insights = const [
    BehavioralInsight(
      icon: Icons.trending_up,
      iconColor: Colors.orange,
      title: "Increased Morning Usage",
      severity: "medium",
      description: "Cat visits peaked significantly between 6 AM and 9 AM today.",
    ),
    BehavioralInsight(
      icon: Icons.check_circle_outline,
      iconColor: Colors.green,
      title: "Normal Duration Pattern",
      severity: "low",
      description: "Average visit duration remains stable and within a healthy range.",
    ),
  ];

  // Mock Spot Data for Charts
  final List<FlSpot> visitFrequencyData = const [
    FlSpot(0, 0),
    FlSpot(4, 1),
    FlSpot(8, 2.5),
    FlSpot(12, 1.2),
    FlSpot(16, 2.8),
    FlSpot(20, 1.0),
    FlSpot(24, 0.2),
  ];

  final List<FlSpot> visitDurationData = const [
    FlSpot(0, 0),
    FlSpot(4, 2.0),
    FlSpot(8, 5.5),
    FlSpot(12, 3.2),
    FlSpot(16, 6.0),
    FlSpot(20, 4.1),
    FlSpot(24, 1.5),
  ];

  final List<FlSpot> wasteAccumulationData = const [
    FlSpot(0, 0),
    FlSpot(4, 25),
    FlSpot(8, 80),
    FlSpot(12, 115),
    FlSpot(16, 160),
    FlSpot(20, 205),
    FlSpot(24, 215),
  ];

  Widget _buildPeriodToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: AnalyticsPeriod.values.map((period) {
          final isSelected = _selectedPeriod == period;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriod = period),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.orange : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  period.name[0].toUpperCase() + period.name.substring(1),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLineChart(String title, List<FlSpot> spots, double maxY) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                maxY: maxY,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 4,
                      getTitlesWidget: (value, meta) {
                        switch (value.toInt()) {
                          case 0: return const Text('12AM', style: TextStyle(fontSize: 10, color: Colors.grey));
                          case 4: return const Text('4AM', style: TextStyle(fontSize: 10, color: Colors.grey));
                          case 8: return const Text('8AM', style: TextStyle(fontSize: 10, color: Colors.grey));
                          case 12: return const Text('12PM', style: TextStyle(fontSize: 10, color: Colors.grey));
                          case 16: return const Text('4PM', style: TextStyle(fontSize: 10, color: Colors.grey));
                          case 20: return const Text('8PM', style: TextStyle(fontSize: 10, color: Colors.grey));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.orange.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E5),
      appBar: AppBar(
        title: const Text("Behavioral Analytics"),
        backgroundColor: Colors.orange,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildPeriodToggle(),
            
            // Charts
            _buildLineChart("Visit Frequency", visitFrequencyData, 3.0),
            _buildLineChart("Visit Duration (min)", visitDurationData, 8.0),
            _buildLineChart("Waste Accumulation (grams)", wasteAccumulationData, 250.0),

            // Behavioral Insights Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      CircleAvatar(
                        backgroundColor: Color(0xFFFFE0B2),
                        child: Icon(Icons.show_chart, color: Colors.orange),
                      ),
                      SizedBox(width: 12),
                      Text("Behavioral Insights", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...insights.map((insight) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(insight.icon, color: insight.iconColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(insight.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(insight.description, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),

            // Summary Metric Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Avg Hourly Visits", style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text(avgHourlyVisits, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Avg Duration", style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text(avgDuration, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}