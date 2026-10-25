import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/device_provisioning_service.dart';
import '../services/device_status_service.dart';
import '../services/sensor_service.dart';
import '../theme/app_styles.dart';
import '../widgets/page_header.dart';

enum AnalyticsPeriod { daily, weekly, monthly }

enum DwellUnit { minutes, seconds }

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
  final String deviceId;

  const AnalyticsScreen({super.key, this.deviceId = "308C"});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final SensorService _sensorService = SensorService();
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.daily;
  DwellUnit _dwellUnit = DwellUnit.minutes;

  late String _activeDeviceId = widget.deviceId;
  Stream<DatabaseEvent>? _visitStream;
  String? _streamDeviceId;
  bool _isSeeding = false;
  bool _didAutoSeed = false;

  // Mock Insights
  final List<BehavioralInsight> insights = const [
    BehavioralInsight(
      icon: Icons.trending_up,
      iconColor: Colors.orange,
      title: "Increased Morning & Evening Dwell Time",
      severity: "medium",
      description:
          "Longer dwell times detected at 08:40 (3.58 min / 215s) and 20:05 (4.08 min / 245s).",
    ),
    BehavioralInsight(
      icon: Icons.check_circle_outline,
      iconColor: Colors.green,
      title: "Normal Daytime Frequency",
      severity: "low",
      description:
          "8 total visits recorded across the 24-hour cycle (00:00–23:59) within a healthy range.",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ensureVisitStream();
    _resolveDeviceAndEnsureMockData();
  }

  void _ensureVisitStream() {
    if (_visitStream == null || _streamDeviceId != _activeDeviceId) {
      _streamDeviceId = _activeDeviceId;
      _visitStream = _sensorService.getVisitStream(_activeDeviceId);
    }
  }

  Future<void> _resolveDeviceAndEnsureMockData() async {
    final savedName = await DeviceProvisioningService.instance.savedDeviceName();
    if (savedName != null && savedName.trim().isNotEmpty && mounted) {
      final resolved = DeviceStatusService.idFromName(savedName);
      if (resolved != _activeDeviceId) {
        setState(() {
          _activeDeviceId = resolved;
          _ensureVisitStream();
        });
      }
    }
  }

  Future<void> _seedMockDatabase({bool showFeedback = true}) async {
    if (_isSeeding) return;
    setState(() => _isSeeding = true);
    final ok = await _sensorService.seedMockVisits(_activeDeviceId);
    if (_activeDeviceId != widget.deviceId) {
      await _sensorService.seedMockVisits(widget.deviceId);
    }
    if (!mounted) return;
    setState(() => _isSeeding = false);
    if (showFeedback) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Mock visit data synced to Firebase Realtime DB (devices/$_activeDeviceId/visits).'
                : 'Failed to sync mock data. Check internet connection.',
          ),
          backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
        ),
      );
    }
  }

  // Function to show PurrClean Alert & Notification Info Bottom Sheet
  // ignore: unused_element
  void _showInfoDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE0B2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.info_outline,
                          color: _kTrendOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "System Guide & Triggers",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.black45,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildInfoSection(
                    icon: Icons.notifications_active,
                    iconColor: Colors.blue,
                    title: "Push Notifications",
                    description:
                        "Triggered whenever your cat finishes a visit to the litter box or when maintenance is complete.",
                  ),
                  const Divider(),
                  _buildInfoSection(
                    icon: Icons.warning_amber_rounded,
                    iconColor: Colors.amber,
                    title: "Warning Alerts",
                    description:
                        "Triggered when gas levels exceed optimal thresholds or when a visit lasts unusually long (> 3 mins / 180s).",
                  ),
                  const Divider(),
                  _buildInfoSection(
                    icon: Icons.cleaning_services,
                    iconColor: Colors.green,
                    title: "Maintenance Alerts",
                    description:
                        "Triggered when the waste drawer weight reaches full capacity or when litter levels are low.",
                  ),
                  const SizedBox(height: 14),
                  _buildVisualStatusBarAid(
                    lowRange: "Safe Baseline",
                    moderateRange: "Elevated Watch",
                    alertRange: "Threshold Crossed",
                    triggerNote:
                        "App Warning Trigger: Dwell ≥ 3m, NH₃ ≥ 30ppm, Odor ≥ 80%, or Weight ≤ 3.9kg",
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Got it",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Helper widget for dialog sections
  Widget _buildInfoSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: Colors.black87, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: AnalyticsPeriod.values.map((period) {
          final isSelected = _selectedPeriod == period;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selectedPeriod = period),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  period.name[0].toUpperCase() + period.name.substring(1),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? AppColors.primary : Colors.white,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Unified Designer Color Palette for Graph 1, Graph 2 & Graph 3
  static const Color _kSafeAmber = Color(0xFFFFB74D); // Normal Dwell / Deposit
  static const Color _kDangerRed = Color(0xFFE53935); // Extended Dwell / Danger Odor (>=80%)
  static const Color _kSafeAmmonia = Color(0xFF7E57C2); // Safe Ammonia (<30 ppm) - Purple
  static const Color _kDangerAmmonia = Color(0xFFFF8A00); // Danger Ammonia (>=30 ppm) - Orange
  static const Color _kSafeOdor = Color(0xFF26A69A); // Safe Odor (<80%) - Teal
  static const Color _kTrendOrange = Color(0xFFE65100); // Trend Line & Accent
  static const Color _kTooltipBg = Color(0xFF263238); // Unified Tooltip & Axis Label Color

  int? _selectedHeatmapRow;
  int? _selectedHeatmapHour;

  /// Graph 1: Chronological Visit & Dwell Timeline (Combo Bar/Line Chart)
  /// X-axis: Hours of the day (00:00 to 23:59)
  /// Y-axis: Dwell time inside the box (Seconds/Minutes)
  Widget _buildComboDwellChartCard(List<VisitRecord> visits) {
    final bool inSeconds = _dwellUnit == DwellUnit.seconds;
    final double maxY = inSeconds ? 300.0 : 5.0;
    final double yInterval = inSeconds ? 60.0 : 1.0;
    final double warningThreshold = inSeconds ? 180.0 : 3.0;

    final int extendedCount = visits
        .where(
          (v) =>
              (inSeconds ? v.durationSeconds.toDouble() : v.durationMinutes) >=
              warningThreshold,
        )
        .length;

    final List<FlSpot> trendSpots = visits
        .map(
          (v) => FlSpot(
            v.hourX,
            inSeconds ? v.durationSeconds.toDouble() : v.durationMinutes,
          ),
        )
        .toList();

    // Build vertical bar series for each visit + 1 overlaid connecting line series
    final List<LineChartBarData> comboBarsAndLine = [
      // 1. Vertical Bars for each visit's dwell time
      for (final spot in trendSpots)
        LineChartBarData(
          spots: [FlSpot(spot.x, 0), spot],
          isCurved: false,
          barWidth: 9,
          isStrokeCapRound: true,
          color: spot.y >= warningThreshold
              ? _kDangerRed.withValues(alpha: 0.85)
              : _kSafeAmber.withValues(alpha: 0.85),
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),

      // 2. Chronological Trend Line connecting all visits across 00:00 - 23:59
      if (trendSpots.isNotEmpty)
        LineChartBarData(
          spots: trendSpots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: _kTrendOrange,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              final isHigh = spot.y >= warningThreshold;
              return FlDotCirclePainter(
                radius: 4.0,
                color: Colors.white,
                strokeWidth: 2.5,
                strokeColor: isHigh ? _kDangerRed : _kTrendOrange,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: _kTrendOrange.withValues(alpha: 0.08),
          ),
        ),
    ];

    final int trendLineIndex = comboBarsAndLine.length - 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + Unit Toggle (Min / Sec)
          _buildChartCardHeader(
            icon: Icons.schedule_rounded,
            title: "Chronological Visit & Dwell Timeline",
            subtitle: "Duration inside litter box across 24 hours",
            trailing: _buildUnitToggle(),
          ),
          const SizedBox(height: 12),

          // Unified Threshold Banner
          _buildThresholdBanner(
            text: extendedCount > 0
                ? 'Alert Zone: Dwell ≥ ${inSeconds ? "180s" : "3.0m"} ($extendedCount extended visit${extendedCount == 1 ? "" : "s"} today)'
                : 'Alert Zone: Extended Dwell ≥ ${inSeconds ? "180s" : "3.0m"}',
            hasAlert: extendedCount > 0,
          ),
          const SizedBox(height: 10),

          // Unified Legend Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: _kSafeAmber,
                label: inSeconds ? "Normal (<180s)" : "Normal (<3m)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: inSeconds ? "Extended (≥180s)" : "Extended (≥3m)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kTrendOrange,
                label: "Trend Line",
                isBar: false,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Combo Bar + Line Chart
          SizedBox(
            height: 225,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 24,
                minY: 0,
                maxY: maxY,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: yInterval,
                  verticalInterval: 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: warningThreshold,
                      color: _kDangerRed.withValues(alpha: 0.65),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(right: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerRed,
                        ),
                        labelResolver: (_) => inSeconds
                            ? 'Extended Alert'
                            : 'Extended Alert',
                      ),
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  // Left Y-Axis: Dwell Time (Seconds or Minutes via top-right toggle)
                  leftTitles: AxisTitles(
                    axisNameWidget: Center(
                      child: Text(
                        inSeconds
                            ? 'Dwell Time (Seconds)'
                            : 'Dwell Time (Minutes)',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kTrendOrange,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        final isAlertTick =
                            (value - warningThreshold).abs() < 0.01;
                        final label = inSeconds
                            ? '${value.toInt()}s'
                            : '${value.toInt()}m';
                        return SizedBox(
                          width: 32,
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isAlertTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isAlertTick ? _kDangerRed : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Light right spacer so Graph 1 widens to the right without clipping '23:59'
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      getTitlesWidget: (_, _) => const SizedBox.shrink(),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Time of Day (00:00 – 23:59)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 4,
                      getTitlesWidget: (value, meta) {
                        String? text;
                        switch (value.toInt()) {
                          case 0:
                            text = '00:00';
                            break;
                          case 4:
                            text = '04:00';
                            break;
                          case 8:
                            text = '08:00';
                            break;
                          case 12:
                            text = '12:00';
                            break;
                          case 16:
                            text = '16:00';
                            break;
                          case 20:
                            text = '20:00';
                            break;
                          case 24:
                            text = '23:59';
                            break;
                        }
                        if (text == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _kTooltipBg,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((barSpot) {
                        if (barSpot.barIndex != trendLineIndex) {
                          return null;
                        }
                        final spotIdx = barSpot.spotIndex;
                        if (spotIdx < 0 || spotIdx >= visits.length) {
                          return null;
                        }
                        final v = visits[spotIdx];
                        final isExtended =
                            (inSeconds
                                ? v.durationSeconds.toDouble()
                                : v.durationMinutes) >=
                            warningThreshold;
                        return LineTooltipItem(
                          '${v.timeLabel}\n'
                          'Dwell: ${v.durationSeconds}s (${v.durationMinutes.toStringAsFixed(1)}m)'
                          '${isExtended ? ' ⚠️' : ''}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: comboBarsAndLine,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Graph 2: Gas Fingerprint per Elimination Event (Grouped Bar Chart)
  /// X-axis: Elimination event time today (e.g., 01:30, 06:15, 08:40, ...)
  /// Y-axis: Dual scale — Left: Ammonia (NH3 ppm, 0..50), Right: Odor Index (%, 0..100)
  /// Distinct user-friendly colors:
  ///   - Ammonia (NH3): Safe = Purple (#7E57C2), Danger (>=30 ppm) = Orange (#FF8A00)
  ///   - Odor Index:    Safe = Teal (#26A69A),   Danger (>=80%)    = Coral Red (#E53935)
  Widget _buildGasFingerprintChartCard(List<VisitRecord> visits) {
    // Internal chart scale is 0..100 (matching Odor Index 0..100%).
    // Left Y-axis (Ammonia NH3 ppm, 0..50 ppm) maps 1 ppm -> 2 chart units.
    const double maxOdorScale = 100.0;
    const double maxAmmoniaPpm = 50.0;
    const double ammoniaToChartFactor = maxOdorScale / maxAmmoniaPpm; // 2.0

    const double dangerAmmoniaPpm = 30.0;
    const double dangerOdorPercent = 80.0;
    const double dangerAmmoniaScaled =
        dangerAmmoniaPpm * ammoniaToChartFactor; // 60.0 on chart

    final double barWidth = visits.length > 6 ? 6.5 : 8.5;

    final int dangerVisitCount = visits
        .where(
          (v) =>
              v.ammoniaPpm >= dangerAmmoniaPpm ||
              v.odorIndex >= dangerOdorPercent,
        )
        .length;

    final List<BarChartGroupData> barGroups = List.generate(visits.length, (i) {
      final v = visits[i];
      final scaledAmmonia =
          (v.ammoniaPpm * ammoniaToChartFactor).clamp(0.0, maxOdorScale);
      final scaledOdor = v.odorIndex.clamp(0.0, maxOdorScale);

      final bool isAmmoniaDangerous = v.ammoniaPpm >= dangerAmmoniaPpm;
      final bool isOdorDangerous = v.odorIndex >= dangerOdorPercent;

      return BarChartGroupData(
        x: i,
        barsSpace: 3,
        barRods: [
          // Rod 0 (Left bar): Ammonia (NH3 ppm) -> Purple (Safe) vs Orange (Danger >= 30 ppm)
          BarChartRodData(
            toY: scaledAmmonia,
            width: barWidth,
            color: isAmmoniaDangerous ? _kDangerAmmonia : _kSafeAmmonia,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxOdorScale,
              color: Colors.grey.shade100,
            ),
          ),
          // Rod 1 (Right bar): Odor Index (%) -> Teal (Safe) vs Coral Red (Danger >= 80%)
          BarChartRodData(
            toY: scaledOdor,
            width: barWidth,
            color: isOdorDangerous ? _kDangerRed : _kSafeOdor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxOdorScale,
              color: Colors.grey.shade100,
            ),
          ),
        ],
      );
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + Scale Badge
          _buildChartCardHeader(
            icon: Icons.air_rounded,
            title: "Gas Fingerprint per Elimination Event",
            subtitle: "Ammonia (NH₃) & Odor levels per visit today",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "ppm / %",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Unified Alert Threshold Callout Banner
          _buildThresholdBanner(
            text: dangerVisitCount > 0
                ? 'Alert Zone: NH₃ ≥ 30 ppm (Orange)  •  Odor ≥ 80% (Red) — $dangerVisitCount alert${dangerVisitCount == 1 ? "" : "s"}'
                : 'Alert Zone: NH₃ ≥ 30 ppm (Orange)  •  Odor ≥ 80% (Red)',
            hasAlert: dangerVisitCount > 0,
          ),
          const SizedBox(height: 10),

          // Unified 4-State Legend Row (Distinct Safe & Alert colors for each metric)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: _kSafeAmmonia,
                label: "NH₃ Safe (<30ppm)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerAmmonia,
                label: "NH₃ Alert (≥30ppm)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kSafeOdor,
                label: "Odor Safe (<80%)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: "Odor Alert (≥80%)",
                isBar: true,
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            height: 225,
            child: BarChart(
              BarChartData(
                maxY: maxOdorScale,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    // 30 ppm Ammonia alert line (Orange to match NH3 Alert bar)
                    HorizontalLine(
                      y: dangerAmmoniaScaled,
                      color: _kDangerAmmonia.withValues(alpha: 0.75),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerAmmonia,
                        ),
                        labelResolver: (_) => 'NH₃ Alert',
                      ),
                    ),
                    // 80% Odor Index danger line (Coral Red to match Odor Danger bar)
                    HorizontalLine(
                      y: dangerOdorPercent,
                      color: _kDangerRed.withValues(alpha: 0.70),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(right: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerRed,
                        ),
                        labelResolver: (_) => 'Odor Alert',
                      ),
                    ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  // Left Y-Axis: Ammonia (NH3 ppm) [0..50 ppm]
                  leftTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Ammonia (NH₃ ppm)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kSafeAmmonia,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 20,
                      getTitlesWidget: (value, meta) {
                        final ppm = (value / ammoniaToChartFactor).round();
                        final isDangerTick = ppm == 30;
                        return SizedBox(
                          width: 32,
                          child: Text(
                            '$ppm',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isDangerTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDangerTick
                                  ? _kDangerAmmonia
                                  : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Right Y-Axis: Odor Index (%) [0..100%]
                  rightTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Odor Index (%)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kSafeOdor,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 20,
                      getTitlesWidget: (value, meta) {
                        final pct = value.toInt();
                        final isDangerTick = pct == 80;
                        return SizedBox(
                          width: 32,
                          child: Text(
                            '$pct%',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isDangerTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDangerTick ? _kDangerRed : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // X-Axis: Time of each visit only (matches Graph 1 style)
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Time of Day (HH:mm)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= visits.length) {
                          return const SizedBox.shrink();
                        }
                        final v = visits[idx];
                        final isDanger = v.ammoniaPpm >= dangerAmmoniaPpm ||
                            v.odorIndex >= dangerOdorPercent;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            v.timeLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isDanger
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDanger
                                  ? _kDangerRed
                                  : Colors.grey.shade700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => _kTooltipBg,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex < 0 || groupIndex >= visits.length) {
                        return null;
                      }
                      final v = visits[groupIndex];
                      final bool isDanger = rodIndex == 0
                          ? v.ammoniaPpm >= dangerAmmoniaPpm
                          : v.odorIndex >= dangerOdorPercent;
                      final metricLine = rodIndex == 0
                          ? 'NH₃: ${v.ammoniaPpm.toStringAsFixed(1)} ppm${isDanger ? ' ⚠️ ALERT' : ''}'
                          : 'Odor: ${v.odorIndex.toStringAsFixed(0)}%${isDanger ? ' ⚠️ ALERT' : ''}';
                      return BarTooltipItem(
                        '${v.timeLabel}\n$metricLine',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Graph 3: Deposit Mass per Event (Bar Chart)
  /// X-axis: Each visit index today (displayed as HH:mm timestamp)
  /// Y-axis: Grams (g) from load cell delta (ΔWeight)
  Widget _buildDepositMassChartCard(List<VisitRecord> visits) {
    const double maxGrams = 100.0;
    const double alertGrams = 60.0;
    final double barWidth = visits.length > 6 ? 12.0 : 15.0;

    final int alertCount =
        visits.where((v) => v.depositGrams >= alertGrams).length;

    final List<BarChartGroupData> barGroups = List.generate(visits.length, (i) {
      final v = visits[i];
      final grams = v.depositGrams.clamp(0.0, maxGrams);
      final isAlert = v.depositGrams >= alertGrams;

      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: grams,
            width: barWidth,
            color: isAlert ? _kDangerRed : _kSafeAmber,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxGrams,
              color: Colors.grey.shade100,
            ),
          ),
        ],
      );
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + Unit Badge
          _buildChartCardHeader(
            icon: Icons.scale_rounded,
            title: "Deposit Mass per Event",
            subtitle: "Load cell delta (ΔWeight) per visit today",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "Grams (g)",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Unified Threshold Callout Banner
          _buildThresholdBanner(
            text: alertCount > 0
                ? 'Alert Zone: ΔWeight ≥ 60g ($alertCount heavy deposit${alertCount == 1 ? "" : "s"} today)'
                : 'Alert Zone: Heavy Deposit ΔWeight ≥ 60g',
            hasAlert: alertCount > 0,
          ),
          const SizedBox(height: 10),

          // Unified Legend Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: _kSafeAmber,
                label: "Normal (<60g)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: "Heavy Deposit (≥60g)",
                isBar: true,
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            height: 225,
            child: BarChart(
              BarChartData(
                maxY: maxGrams,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: alertGrams,
                      color: _kDangerRed.withValues(alpha: 0.70),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerRed,
                        ),
                        labelResolver: (_) => 'Heavy Alert (60g)',
                      ),
                    ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  // Left Y-Axis: Grams (g) from load cell delta (ΔWeight)
                  leftTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Deposit Mass (ΔWeight g)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kTrendOrange,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 20,
                      getTitlesWidget: (value, meta) {
                        final g = value.toInt();
                        final isDangerTick = g == 60;
                        return SizedBox(
                          width: 32,
                          child: Text(
                            '${g}g',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isDangerTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDangerTick ? _kDangerRed : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Light right spacer matching Graph 1 width
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      getTitlesWidget: (_, _) => const SizedBox.shrink(),
                    ),
                  ),
                  // X-Axis: Each visit index today (HH:mm)
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Time of Day (HH:mm)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= visits.length) {
                          return const SizedBox.shrink();
                        }
                        final v = visits[idx];
                        final isAlert = v.depositGrams >= alertGrams;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            v.timeLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isAlert
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isAlert
                                  ? _kDangerRed
                                  : Colors.grey.shade700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => _kTooltipBg,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex < 0 || groupIndex >= visits.length) {
                        return null;
                      }
                      final v = visits[groupIndex];
                      final isAlert = v.depositGrams >= alertGrams;
                      return BarTooltipItem(
                        '${v.timeLabel}\n'
                        'ΔWeight: ${v.depositGrams.toStringAsFixed(0)}g'
                        '${isAlert ? ' ⚠️' : ''}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCardHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE0B2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _kTrendOrange, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        trailing,
        const SizedBox(width: 6),
        Tooltip(
          message: "Graph Tip & Guide",
          child: InkWell(
            onTap: () => _showGraphTipDialog(
              icon: icon,
              title: title,
              subtitle: subtitle,
            ),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.55),
                  width: 1.2,
                ),
              ),
              child: const Text(
                "?",
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _kTrendOrange,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showGraphTipDialog({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final tipData = _getGraphTipDetails(title, subtitle);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bottom Sheet Drag Handle
                  Center(
                    child: Container(
                      width: 42,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Header Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE0B2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: _kTrendOrange, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tipData.badge,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: _kTrendOrange,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tipData.popupTitle,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.black45,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildInfoSection(
                            icon: Icons.analytics_outlined,
                            iconColor: _kSafeOdor,
                            title: "What it shows",
                            description: tipData.whatItShows,
                          ),
                          const Divider(height: 16),
                          _buildInfoSection(
                            icon: Icons.check_circle_outline_rounded,
                            iconColor: Colors.green.shade600,
                            title: "Normal Range",
                            description: tipData.normalRange,
                          ),
                          const Divider(height: 16),
                          _buildInfoSection(
                            icon: Icons.warning_amber_rounded,
                            iconColor: _kDangerAmmonia,
                            title: "Warning Signs",
                            description: tipData.warningSigns,
                          ),
                          const SizedBox(height: 14),
                          // Visual Aid: Mini Horizontal Status Bar with Indicator
                          _buildVisualStatusBarAid(
                            lowRange: tipData.lowLabel,
                            moderateRange: tipData.moderateLabel,
                            alertRange: tipData.alertLabel,
                            triggerNote: tipData.triggerNote,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Got it",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVisualStatusBarAid({
    required String lowRange,
    required String moderateRange,
    required String alertRange,
    required String triggerNote,
  }) {
    const Color greenColor = Color(0xFF43A047);
    const Color yellowColor = Color(0xFFFBC02D);
    const Color redColor = Color(0xFFE53935);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 15,
                color: _kTooltipBg,
              ),
              const SizedBox(width: 6),
              const Text(
                "Visual Aid: Status Threshold Scale",
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: _kTooltipBg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 3-Segment Horizontal Status Bar: [ Low (Green) | Moderate (Yellow) | Alert (Red) ]
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 7,
                      horizontal: 4,
                    ),
                    color: greenColor,
                    child: Column(
                      children: [
                        const Text(
                          "Low (Green)",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lowRange,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 7,
                      horizontal: 4,
                    ),
                    color: yellowColor,
                    child: Column(
                      children: [
                        const Text(
                          "Moderate (Yellow)",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          moderateRange,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 7,
                      horizontal: 4,
                    ),
                    color: redColor,
                    child: Column(
                      children: [
                        const Text(
                          "Alert (Red)",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alertRange,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Upward Indicator Arrow aligned under the Alert (Red) segment
          Row(
            children: [
              const Expanded(flex: 2, child: SizedBox()),
              Expanded(
                flex: 1,
                child: Center(
                  child: Icon(
                    Icons.arrow_drop_up_rounded,
                    color: redColor,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          // Warning Trigger Callout Box pointed to by the indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: redColor.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  size: 14,
                  color: redColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    triggerNote,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({
    String badge,
    String popupTitle,
    String whatItShows,
    String normalRange,
    String warningSigns,
    String lowLabel,
    String moderateLabel,
    String alertLabel,
    String triggerNote,
  }) _getGraphTipDetails(String title, String subtitle) {
    switch (title) {
      case "Chronological Visit & Dwell Timeline":
        return (
          badge: "1. Visit Timeline & Dwell Duration",
          popupTitle: "Daily Activity & Box Time",
          whatItShows:
              "Every time your cat steps into the litter box today, marked by the time of day and how long they stayed inside.",
          normalRange:
              "2 to 4 visits per day. A typical visit lasts between 30 and 90 seconds (digging, eliminating, and burying).",
          warningSigns:
              "• Visits lasting longer than 3 to 5 minutes (suggests constipation or straining to urinate).\n\n"
              "• Multiple visits clustered within 1–2 hours with short dwell times (often an early warning sign of a urinary blockage or cystitis).",
          lowLabel: "30s – 90s",
          moderateLabel: "90s – 3m",
          alertLabel: "≥ 3m (180s)",
          triggerNote:
              "App Warning Trigger: Dwell ≥ 3 min (180s) or clustered visits within 1–2 hrs",
        );
      case "Gas Fingerprint per Elimination Event":
        return (
          badge: "2. Waste Gas Profile (NH₃ & Odour)",
          popupTitle: "Gas & Odor Concentration",
          whatItShows:
              "The peak levels of ammonia gas (NH₃) and general odor detected right after your cat leaves the box.",
          normalRange:
              "• Urine visits: Ammonia between 10 and 25 ppm, with moderate odor (30%–50%).\n\n"
              "• Feces visits: Ammonia low (under 8 ppm), but odor higher (50%–75%).",
          warningSigns:
              "• Ammonia spiking above 35–50 ppm consistently (suggests concentrated urine from dehydration or potential bacterial urinary tract infections).\n\n"
              "• Odor index consistently above 80% on low ammonia (suggests diarrhea or digestive upset).",
          lowLabel: "<25ppm / <50%",
          moderateLabel: "25–29ppm / 75%",
          alertLabel: "≥30ppm / ≥80%",
          triggerNote:
              "App Warning Trigger: NH₃ ≥ 30 ppm (Orange) or Odor ≥ 80% (Red)",
        );
      case "Deposit Mass per Event":
        return (
          badge: "3. Deposit Mass per Event",
          popupTitle: "Waste Output Weight",
          whatItShows:
              "The exact weight added to the litter box after each visit, measured in grams.",
          normalRange:
              "• Urination clump: 20 to 60 grams per event.\n\n"
              "• Stool: 15 to 40 grams per event.",
          warningSigns:
              "• Visits recording near 0 grams while the dwell time is long (indicates unproductive straining, which is a veterinary emergency in male cats).",
          lowLabel: "15g – 45g",
          moderateLabel: "45g – 59g",
          alertLabel: "≥60g or ~0g",
          triggerNote:
              "App Warning Trigger: ΔWeight ≥ 60g (heavy) or ~0g with long dwell time",
        );
      case "Daily Total Eliminations & Output Volume":
        return (
          badge: "1. Daily Total Output Volume",
          popupTitle: "Weekly Excretion Volume",
          whatItShows:
              "Total combined weight of waste produced per day across the last 7 days, categorized by urine vs. stool.",
          normalRange:
              "Healthy cats produce roughly 100 to 200 grams of total waste per day depending on body size and diet (wet vs. dry food).",
          warningSigns:
              "• A sustained, steep climb in daily output weight (polyuria, often an early flag for diabetes or kidney disease).\n\n"
              "• A drop below 50 grams for consecutive days (dehydration, obstipation, or reduced intake).",
          lowLabel: "100g – 200g",
          moderateLabel: "200g – 239g",
          alertLabel: "≥240g or <50g",
          triggerNote:
              "App Warning Trigger: Daily output ≥ 240g/day or dropping < 50g/day",
        );
      case "Visit Frequency vs. Straining Ratio":
        return (
          badge: "2. Visit Frequency vs. Total Straining Time",
          popupTitle: "Visit Habits vs. Time Spent",
          whatItShows:
              "Compares the number of trips taken each day against the total time spent inside the box.",
          normalRange:
              "Bars should stay fairly level day-to-day (3–4 visits totaling around 3–6 minutes daily).",
          warningSigns:
              "• A sharp spike in visit count accompanied by elevated total box time (indicates acute discomfort, FLUTD, or litter box aversion).",
          lowLabel: "3 – 6 min/day",
          moderateLabel: "7 – 14 min/day",
          alertLabel: "≥ 15 min/day",
          triggerNote:
              "App Warning Trigger: Total straining/dwell time ≥ 15 min/day",
        );
      case "Litter Degradation & Fan Purge Duration":
        return (
          badge: "3. Litter Saturation Index",
          popupTitle: "Litter Cleanliness & Fan Runtime",
          whatItShows:
              "How many minutes the ventilation fan needs to run to pull box air back to fresh levels after a visit.",
          normalRange:
              "45 to 90 seconds on fresh litter.",
          warningSigns:
              "• Purge times steadily exceeding 3 to 4 minutes. This means the litter substrate is saturated with residual odor and moisture and requires a full cleanout and refill.",
          lowLabel: "45s – 90s",
          moderateLabel: "90s – 179s",
          alertLabel: "≥ 3m (180s)",
          triggerNote:
              "App Warning Trigger: Fan purge runtime ≥ 3 min (180s) — Swap litter",
        );
      case "Feline Body Weight Trajectory":
        return (
          badge: "1. Cat Body Weight Trend",
          popupTitle: "Body Weight Trajectory",
          whatItShows:
              "Your cat's body weight tracked daily on entry, with a smoothed 7-day average line.",
          normalRange:
              "Cat weight should remain stable, fluctuating by no more than ±1% to 2% week-over-week.",
          warningSigns:
              "• An unprompted loss of 5% or more of body weight over 30 days (e.g., losing 250g on a 5kg cat). In cats, progressive gradual weight loss is the number one early clinical indicator for hyperthyroidism, kidney disease, or metabolic illness.",
          lowLabel: "±1% – 2%",
          moderateLabel: "3% – 4% loss",
          alertLabel: "≥5% loss (≤3.9kg)",
          triggerNote:
              "App Warning Trigger: Weight ≤ 3.90 kg (or ≥ 5% body weight loss / 30d)",
        );
      case "24-Hour Circadian Elimination Heatmap":
        return (
          badge: "2. 24-Hour Circadian Elimination Heatmap",
          popupTitle: "Routine & Rhythm Heatmap",
          whatItShows:
              "A visual map showing what hours of the day or night your cat uses the box across the entire month. Darker tiles indicate frequent visits.",
          normalRange:
              "Clear, recurring habit clusters (e.g., early morning and shortly after evening feeding).",
          warningSigns:
              "• Erratic, fragmented visits through the middle of the night (nocturnal restlessness can indicate feline cognitive dysfunction syndrome, hypertension, or chronic discomfort).",
          lowLabel: "1–4 Routine",
          moderateLabel: "5–7 Peak",
          alertLabel: "01:00–04:00",
          triggerNote:
              "App Warning Trigger: Repeated nocturnal activity between 01:00–04:00",
        );
      case "Chronic Odor & Ammonia Baseline Trends":
        return (
          badge: "3. Long-Term Median Gas Concentration",
          popupTitle: "Chronic Gas Baselines",
          whatItShows:
              "The rolling monthly average of waste gas intensity.",
          normalRange:
              "Flat, predictable levels matching your cat's standard diet.",
          warningSigns:
              "• A continuous upward slope in median ammonia over weeks, even with fresh litter changes, pointing to chronic subclinical dehydration or changes in kidney filtration.",
          lowLabel: "<25ppm / <60%",
          moderateLabel: "25–29ppm / 79%",
          alertLabel: "≥30ppm / ≥80%",
          triggerNote:
              "App Warning Trigger: Daily median NH₃ ≥ 30 ppm or Odor ≥ 80%",
        );
      default:
        return (
          badge: "Analytics Guide",
          popupTitle: title,
          whatItShows: subtitle,
          normalRange:
              "Readings within the safe baseline zone below the dashed alert threshold line.",
          warningSigns:
              "Readings crossing the dashed Alert threshold line warrant closer hygiene or wellness monitoring.",
          lowLabel: "Normal",
          moderateLabel: "Elevated",
          alertLabel: "Alert Zone",
          triggerNote:
              "App Warning Trigger: Readings crossing the dashed Alert threshold line",
        );
    }
  }

  Widget _buildThresholdBanner({
    required String text,
    required bool hasAlert,
  }) {
    final Color bgColor = hasAlert
        ? const Color(0xFFFFF3E0)
        : const Color(0xFFF5F5F5);
    final Color borderColor = hasAlert
        ? Colors.orange.withValues(alpha: 0.45)
        : Colors.grey.shade300;
    final Color fgColor = hasAlert
        ? const Color(0xFFE65100)
        : Colors.grey.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            hasAlert ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: fgColor,
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fgColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildUnitChip("Min", DwellUnit.minutes),
          _buildUnitChip("Sec", DwellUnit.seconds),
        ],
      ),
    );
  }

  Widget _buildUnitChip(String label, DwellUnit unit) {
    final selected = _dwellUnit == unit;
    return GestureDetector(
      onTap: () => setState(() => _dwellUnit = unit),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required bool isBar,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isBar ? 10 : 14,
            height: isBar ? 10 : 3.5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// Page 2: Weekly Analytics ("Patterns & Box Hygiene")
  /// Graph 1: Daily Total Eliminations & Output Volume (Stacked Bar Chart)
  /// Graph 2: Visit Frequency vs. Straining Ratio (Grouped Bar + Line)
  /// Graph 3: Litter Degradation & Fan Purge Duration (Area / Step Line)
  Widget _buildWeeklySection() {
    return StreamBuilder<DatabaseEvent>(
      stream: _sensorService.getWeeklyStream(_activeDeviceId),
      builder: (context, weeklySnapshot) {
        final List<WeeklyDayRecord> weeklyDays =
            _sensorService.parseWeeklyRecords(weeklySnapshot.data?.snapshot);
        return Column(
          children: [
            _buildWeeklyOutputStackedChartCard(weeklyDays),
            _buildWeeklyFrequencyVsStrainingCard(weeklyDays),
            _buildWeeklyFanPurgeStepChartCard(weeklyDays),
          ],
        );
      },
    );
  }

  Widget _buildWeeklyOutputStackedChartCard(List<WeeklyDayRecord> weeklyDays) {
    const double maxDailyGrams = 300.0;
    const double highOutputAlertGrams = 240.0;
    const double barWidth = 18.0;

    final int alertDaysCount = weeklyDays
        .where((d) => d.totalGrams >= highOutputAlertGrams)
        .length;

    final List<BarChartGroupData> barGroups =
        List.generate(weeklyDays.length, (i) {
      final d = weeklyDays[i];
      final urineG = d.urineGrams.clamp(0.0, maxDailyGrams);
      final totalG = (d.urineGrams + d.fecesGrams).clamp(0.0, maxDailyGrams);

      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: totalG,
            width: barWidth,
            color: Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            rodStackItems: [
              // Bottom segment: Estimated Urine (g)
              BarChartRodStackItem(0, urineG, _kSafeAmber),
              // Top segment: Estimated Feces (g)
              BarChartRodStackItem(urineG, totalG, _kSafeAmmonia),
            ],
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxDailyGrams,
              color: Colors.grey.shade100,
            ),
          ),
        ],
      );
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + 7-Day Window Pill
          _buildChartCardHeader(
            icon: Icons.stacked_bar_chart_rounded,
            title: "Daily Total Eliminations & Output Volume",
            subtitle: "Patterns & Box Hygiene • Stacked Urine vs. Feces (g)",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "Mon – Sun",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Unified Threshold Banner
          _buildThresholdBanner(
            text: alertDaysCount > 0
                ? 'Hygiene Alert: Output ≥ 240g/day ($alertDaysCount high-volume day${alertDaysCount == 1 ? "" : "s"} this week)'
                : 'Hygiene Alert: High Daily Output ≥ 240g/day',
            hasAlert: alertDaysCount > 0,
          ),
          const SizedBox(height: 10),

          // Unified Legend Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: _kSafeAmber,
                label: "Est. Urine (g)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kSafeAmmonia,
                label: "Est. Feces (g)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: "High Output (≥240g)",
                isBar: false,
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            height: 225,
            child: BarChart(
              BarChartData(
                maxY: maxDailyGrams,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 60,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: highOutputAlertGrams,
                      color: _kDangerRed.withValues(alpha: 0.70),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerRed,
                        ),
                        labelResolver: (_) => 'High Output (240g)',
                      ),
                    ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  // Left Y-Axis: Total grams produced per day (0g..300g)
                  leftTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Total Output (g / day)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kTrendOrange,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 60,
                      getTitlesWidget: (value, meta) {
                        final g = value.toInt();
                        final isDangerTick = g == 240;
                        return SizedBox(
                          width: 32,
                          child: Text(
                            '${g}g',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isDangerTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDangerTick ? _kDangerRed : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Light right spacer matching Daily Graph 1 & Graph 3 width
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      getTitlesWidget: (_, _) => const SizedBox.shrink(),
                    ),
                  ),
                  // X-Axis: Days of the week (Mon – Sun)
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Days of the Week (Mon – Sun)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= weeklyDays.length) {
                          return const SizedBox.shrink();
                        }
                        final d = weeklyDays[idx];
                        final isAlert = d.totalGrams >= highOutputAlertGrams;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            d.dayLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isAlert
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isAlert
                                  ? _kDangerRed
                                  : Colors.grey.shade700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => _kTooltipBg,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex < 0 || groupIndex >= weeklyDays.length) {
                        return null;
                      }
                      final d = weeklyDays[groupIndex];
                      final isAlert = d.totalGrams >= highOutputAlertGrams;
                      return BarTooltipItem(
                        '${d.dayLabel} (${d.totalVisits} visits)\n'
                        'Total: ${d.totalGrams.toStringAsFixed(0)}g${isAlert ? ' ⚠️' : ''}\n'
                        'Urine: ${d.urineGrams.toStringAsFixed(0)}g  •  Feces: ${d.fecesGrams.toStringAsFixed(0)}g',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Weekly Graph 2: Visit Frequency vs. Straining Ratio (Grouped Bar + Line)
  /// X-axis: Days of the week (Mon – Sun)
  /// Y-axis: Left: Total visit count (0..10); Right: Total minutes spent straining/dwelling (0..25m)
  Widget _buildWeeklyFrequencyVsStrainingCard(List<WeeklyDayRecord> weeklyDays) {
    // Internal chart scale is 0..25 (matching Right Y-axis: 0..25 minutes).
    // Left Y-axis (0..10 visits) maps 1 visit -> 2.5 chart units.
    const double maxDwellMinutes = 25.0;
    const double maxVisitsScale = 10.0;
    const double visitsToChartFactor = maxDwellMinutes / maxVisitsScale; // 2.5
    const double strainingAlertMinutes = 15.0;
    const double barOffset = 0.14;

    final int alertDaysCount = weeklyDays
        .where((d) => d.totalDwellMinutes >= strainingAlertMinutes)
        .length;

    final List<FlSpot> trendSpots = List.generate(weeklyDays.length, (i) {
      final d = weeklyDays[i];
      return FlSpot(
        i.toDouble(),
        d.totalDwellMinutes.clamp(0.0, maxDwellMinutes),
      );
    });

    final List<LineChartBarData> groupedBarsAndLine = [
      // 1. Grouped Bars per Day (Left bar = Total Visits, Right bar = Dwell/Straining Minutes)
      for (int i = 0; i < weeklyDays.length; i++) ...[
        // Left bar: Total Visit Count (Purple)
        LineChartBarData(
          spots: [
            FlSpot(i - barOffset, 0),
            FlSpot(
              i - barOffset,
              (weeklyDays[i].totalVisits * visitsToChartFactor)
                  .clamp(0.0, maxDwellMinutes),
            ),
          ],
          isCurved: false,
          barWidth: 7.5,
          isStrokeCapRound: true,
          color: _kSafeAmmonia,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
        // Right bar: Total Minutes Spent Straining/Dwelling (Teal safe vs Red alert)
        LineChartBarData(
          spots: [
            FlSpot(i + barOffset, 0),
            FlSpot(
              i + barOffset,
              weeklyDays[i].totalDwellMinutes.clamp(0.0, maxDwellMinutes),
            ),
          ],
          isCurved: false,
          barWidth: 7.5,
          isStrokeCapRound: true,
          color: weeklyDays[i].totalDwellMinutes >= strainingAlertMinutes
              ? _kDangerRed
              : _kSafeOdor,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      ],

      // 2. Overlaid Curved Line connecting daily straining/dwell minutes across Mon - Sun
      if (trendSpots.isNotEmpty)
        LineChartBarData(
          spots: trendSpots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: _kTrendOrange,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              final isAlert = spot.y >= strainingAlertMinutes;
              return FlDotCirclePainter(
                radius: 4.0,
                color: Colors.white,
                strokeWidth: 2.5,
                strokeColor: isAlert ? _kDangerRed : _kTrendOrange,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: _kTrendOrange.withValues(alpha: 0.08),
          ),
        ),
    ];

    final int trendLineIndex = groupedBarsAndLine.length - 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + Dual Scale Pill
          _buildChartCardHeader(
            icon: Icons.multiline_chart_rounded,
            title: "Visit Frequency vs. Straining Ratio",
            subtitle: "Daily visit count vs. total straining/dwell minutes",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "Visits / Min",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Unified Threshold Banner
          _buildThresholdBanner(
            text: alertDaysCount > 0
                ? 'Straining Alert: Dwell ≥ 15m/day ($alertDaysCount elevated day${alertDaysCount == 1 ? "" : "s"} this week)'
                : 'Straining Alert: Total Dwell ≥ 15m/day',
            hasAlert: alertDaysCount > 0,
          ),
          const SizedBox(height: 10),

          // Unified Legend Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: _kSafeAmmonia,
                label: "Total Visits",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kSafeOdor,
                label: "Dwell Normal (<15m)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: "Straining Alert (≥15m)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kTrendOrange,
                label: "Straining Trend",
                isBar: false,
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            height: 225,
            child: LineChart(
              LineChartData(
                minX: -0.5,
                maxX: 6.5,
                minY: 0,
                maxY: maxDwellMinutes,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 5,
                  verticalInterval: 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: strainingAlertMinutes,
                      color: _kDangerRed.withValues(alpha: 0.70),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerRed,
                        ),
                        labelResolver: (_) => 'Straining Alert (15m)',
                      ),
                    ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  // Left Y-Axis: Total visit count (0..10 visits)
                  leftTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Total Visits (count)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kSafeAmmonia,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 5,
                      getTitlesWidget: (value, meta) {
                        final visitsCount =
                            (value / visitsToChartFactor).round();
                        return SizedBox(
                          width: 32,
                          child: Text(
                            '$visitsCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Right Y-Axis: Total minutes spent straining/dwelling (0..25m)
                  rightTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Straining / Dwell (min)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kSafeOdor,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 5,
                      getTitlesWidget: (value, meta) {
                        final mins = value.toInt();
                        final isDangerTick = mins == 15;
                        return SizedBox(
                          width: 32,
                          child: Text(
                            '${mins}m',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isDangerTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDangerTick ? _kDangerRed : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // X-Axis: Days of the week (Mon – Sun)
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Days of the Week (Mon – Sun)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        if ((value - value.roundToDouble()).abs() > 0.05) {
                          return const SizedBox.shrink();
                        }
                        final idx = value.round();
                        if (idx < 0 || idx >= weeklyDays.length) {
                          return const SizedBox.shrink();
                        }
                        final d = weeklyDays[idx];
                        final isAlert =
                            d.totalDwellMinutes >= strainingAlertMinutes;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            d.dayLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isAlert
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isAlert
                                  ? _kDangerRed
                                  : Colors.grey.shade700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _kTooltipBg,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((barSpot) {
                        if (barSpot.barIndex != trendLineIndex) {
                          return null;
                        }
                        final idx = barSpot.spotIndex;
                        if (idx < 0 || idx >= weeklyDays.length) {
                          return null;
                        }
                        final d = weeklyDays[idx];
                        final isAlert =
                            d.totalDwellMinutes >= strainingAlertMinutes;
                        return LineTooltipItem(
                          '${d.dayLabel} • ${d.totalVisits} visits (${d.strainingVisits} straining)\n'
                          'Dwell: ${d.totalDwellMinutes.toStringAsFixed(1)}m${isAlert ? ' ⚠️' : ''}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: groupedBarsAndLine,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Weekly Graph 3: Litter Degradation & Fan Purge Duration (Area / Step Line)
  /// X-axis: Days of the week / days since last full litter swap (Mon – Sun)
  /// Y-axis: Average Fan Purge Time per event (Seconds / Minutes)
  /// Visual: Upward staircase slope (Day 1 = 45s -> Day 7 = 230s / 3.8m)
  Widget _buildWeeklyFanPurgeStepChartCard(List<WeeklyDayRecord> weeklyDays) {
    final bool inSeconds = _dwellUnit == DwellUnit.seconds;
    final double maxY = inSeconds ? 300.0 : 5.0;
    final double yInterval = inSeconds ? 60.0 : 1.0;
    final double swapAlertThreshold = inSeconds ? 180.0 : 3.0;

    final int degradedDaysCount = weeklyDays
        .where((d) => d.fanPurgeSeconds >= 180)
        .length;

    final List<FlSpot> stepSpots = List.generate(weeklyDays.length, (i) {
      final d = weeklyDays[i];
      final yVal = inSeconds
          ? d.fanPurgeSeconds.toDouble()
          : d.fanPurgeMinutes;
      return FlSpot(i.toDouble(), yVal.clamp(0.0, maxY));
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + Unit Toggle (Min / Sec)
          _buildChartCardHeader(
            icon: Icons.wind_power_rounded,
            title: "Litter Degradation & Fan Purge Duration",
            subtitle: "Staircase purge time from Day 1 (45s) to Day 7",
            trailing: _buildUnitToggle(),
          ),
          const SizedBox(height: 12),

          // Unified Threshold Banner
          _buildThresholdBanner(
            text: degradedDaysCount > 0
                ? 'Litter Swap Alert: Purge ≥ ${inSeconds ? "180s" : "3.0m"} ($degradedDaysCount day${degradedDaysCount == 1 ? "" : "s"} degraded — swap litter)'
                : 'Litter Swap Alert: Fan Purge ≥ ${inSeconds ? "180s" : "3.0m"}',
            hasAlert: degradedDaysCount > 0,
          ),
          const SizedBox(height: 10),

          // Unified Legend Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: _kSafeOdor,
                label: inSeconds ? "Fresh (<180s)" : "Fresh (<3m)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: inSeconds
                    ? "Clumping Breakdown (≥180s)"
                    : "Clumping Breakdown (≥3m)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kTrendOrange,
                label: "Step Slope Area",
                isBar: false,
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            height: 225,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maxY,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: yInterval,
                  verticalInterval: 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: swapAlertThreshold,
                      color: _kDangerRed.withValues(alpha: 0.70),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerRed,
                        ),
                        labelResolver: (_) => inSeconds
                            ? 'Litter Swap Alert (180s)'
                            : 'Litter Swap Alert (3m)',
                      ),
                    ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  // Left Y-Axis: Average Fan Purge Time per event (Seconds / Minutes)
                  leftTitles: AxisTitles(
                    axisNameWidget: Center(
                      child: Text(
                        inSeconds
                            ? 'Avg Fan Purge (Sec)'
                            : 'Avg Fan Purge (Min)',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kTrendOrange,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        final isAlertTick =
                            (value - swapAlertThreshold).abs() < 0.01;
                        final label = inSeconds
                            ? '${value.toInt()}s'
                            : '${value.toInt()}m';
                        return SizedBox(
                          width: 32,
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isAlertTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isAlertTick ? _kDangerRed : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Light right spacer matching Daily Graph 1 & Graph 3 width
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      getTitlesWidget: (_, _) => const SizedBox.shrink(),
                    ),
                  ),
                  // X-Axis: Days of the week / days since last litter swap
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Days Since Litter Swap (Mon – Sun)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx < 0 || idx >= weeklyDays.length) {
                          return const SizedBox.shrink();
                        }
                        final d = weeklyDays[idx];
                        final isDegraded = d.fanPurgeSeconds >= 180;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            d.dayLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isDegraded
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDegraded
                                  ? _kDangerRed
                                  : Colors.grey.shade700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _kTooltipBg,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((barSpot) {
                        final idx = barSpot.spotIndex;
                        if (idx < 0 || idx >= weeklyDays.length) {
                          return null;
                        }
                        final d = weeklyDays[idx];
                        final isDegraded = d.fanPurgeSeconds >= 180;
                        return LineTooltipItem(
                          'Day ${idx + 1} (${d.dayLabel})\n'
                          'Purge: ${d.fanPurgeSeconds}s (${d.fanPurgeMinutes.toStringAsFixed(1)}m)'
                          '${isDegraded ? ' ⚠️ Swap' : ''}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: stepSpots,
                    isStepLineChart: true,
                    lineChartStepData: const LineChartStepData(
                      stepDirection: LineChartStepData.stepDirectionForward,
                    ),
                    color: _kTrendOrange,
                    barWidth: 2.8,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        final isDegraded = spot.y >= swapAlertThreshold;
                        return FlDotCirclePainter(
                          radius: 4.2,
                          color: Colors.white,
                          strokeWidth: 2.5,
                          strokeColor: isDegraded ? _kDangerRed : _kSafeOdor,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _kTrendOrange.withValues(alpha: 0.28),
                          _kSafeAmber.withValues(alpha: 0.05),
                        ],
                      ),
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

  /// Page 3: Monthly Analytics ("Long-Term Veterinary Health Record")
  /// Graph 1: Feline Body Weight Trajectory (Smoothed Line Chart)
  /// Graph 2: 24-Hour Circadian Elimination Heatmap (Grid Matrix)
  /// Graph 3: Chronic Odor & Ammonia Baseline Trends (Dual-Trend Line)
  Widget _buildMonthlySection() {
    return StreamBuilder<DatabaseEvent>(
      stream: _sensorService.getMonthlyStream(_activeDeviceId),
      builder: (context, monthlySnapshot) {
        final List<MonthlyDayRecord> monthlyDays =
            _sensorService.parseMonthlyRecords(monthlySnapshot.data?.snapshot);
        return Column(
          children: [
            _buildMonthlyWeightTrajectoryCard(monthlyDays),
            _buildMonthlyCircadianHeatmapCard(monthlyDays),
            _buildMonthlyGasBaselineTrendCard(monthlyDays),
          ],
        );
      },
    );
  }

  Widget _buildMonthlyWeightTrajectoryCard(List<MonthlyDayRecord> monthlyDays) {
    const double minWeightKg = 3.5;
    const double maxWeightKg = 4.5;
    const double weightIntervalKg = 0.2;
    const double vetAlertWeightKg = 3.9;

    final int lowWeightDays = monthlyDays
        .where((d) => d.weightKg <= vetAlertWeightKg)
        .length;

    final List<FlSpot> dailyWeightSpots = monthlyDays
        .map(
          (d) => FlSpot(
            d.dayOfMonth.toDouble(),
            d.weightKg.clamp(minWeightKg, maxWeightKg),
          ),
        )
        .toList();

    final List<FlSpot> movingAvgSpots = monthlyDays
        .map(
          (d) => FlSpot(
            d.dayOfMonth.toDouble(),
            d.movingAvg7dKg.clamp(minWeightKg, maxWeightKg),
          ),
        )
        .toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + Unit Badge
          _buildChartCardHeader(
            icon: Icons.monitor_weight_rounded,
            title: "Feline Body Weight Trajectory",
            subtitle: "Long-Term Vet Record • Daily Points & 7-Day Moving Avg",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "kg (30d)",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Unified Threshold Banner
          _buildThresholdBanner(
            text: lowWeightDays > 0
                ? 'Vet Alert: Weight ≤ 3.90 kg ($lowWeightDays day${lowWeightDays == 1 ? "" : "s"} below baseline — chronic weight loss)'
                : 'Vet Alert: Clinical Weight Loss Threshold ≤ 3.90 kg',
            hasAlert: lowWeightDays > 0,
          ),
          const SizedBox(height: 10),

          // Unified Legend Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: _kSafeOdor,
                label: "Daily Weight (>3.9kg)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: "Low Weight (≤3.9kg)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kTrendOrange,
                label: "7-Day Moving Avg",
                isBar: false,
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            height: 225,
            child: LineChart(
              LineChartData(
                minX: 1,
                maxX: 30,
                minY: minWeightKg,
                maxY: maxWeightKg,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: weightIntervalKg,
                  verticalInterval: 5,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: vetAlertWeightKg,
                      color: _kDangerRed.withValues(alpha: 0.70),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerRed,
                        ),
                        labelResolver: (_) => 'Vet Alert (3.9 kg)',
                      ),
                    ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  // Left Y-Axis: Cat Weight in kg (3.5 .. 4.5 kg)
                  leftTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Cat Weight (kg)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kTrendOrange,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: weightIntervalKg,
                      getTitlesWidget: (value, meta) {
                        final isDangerTick =
                            (value - vetAlertWeightKg).abs() < 0.02;
                        return SizedBox(
                          width: 32,
                          child: Text(
                            value.toStringAsFixed(1),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isDangerTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDangerTick ? _kDangerRed : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Light right spacer matching Daily Graph 1 & Graph 3 width
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      getTitlesWidget: (_, _) => const SizedBox.shrink(),
                    ),
                  ),
                  // X-Axis: Days of the month (1–30)
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Days of the Month (Day 1 – Day 30)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final day = value.round();
                        if (day != 1 &&
                            day != 5 &&
                            day != 10 &&
                            day != 15 &&
                            day != 20 &&
                            day != 25 &&
                            day != 30) {
                          return const SizedBox.shrink();
                        }
                        final isAlertDay = day >= 25;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'D$day',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isAlertDay
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isAlertDay
                                  ? _kDangerRed
                                  : Colors.grey.shade700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _kTooltipBg,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((barSpot) {
                        // Show unified tooltip once on the 7-day moving average line
                        if (barSpot.barIndex != 1) {
                          return null;
                        }
                        final idx = barSpot.spotIndex;
                        if (idx < 0 || idx >= monthlyDays.length) {
                          return null;
                        }
                        final d = monthlyDays[idx];
                        final isLow = d.weightKg <= vetAlertWeightKg;
                        return LineTooltipItem(
                          'Day ${d.dayOfMonth}\n'
                          'Daily: ${d.weightKg.toStringAsFixed(2)} kg${isLow ? ' ⚠️' : ''}\n'
                          '7d Avg: ${d.movingAvg7dKg.toStringAsFixed(2)} kg',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  // Series 0: Individual Daily Weight Points (Load-cell entry readings)
                  LineChartBarData(
                    spots: dailyWeightSpots,
                    isCurved: false,
                    barWidth: 0,
                    color: Colors.transparent,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        final isLow = spot.y <= vetAlertWeightKg;
                        return FlDotCirclePainter(
                          radius: 3.3,
                          color: isLow
                              ? _kDangerRed.withValues(alpha: 0.85)
                              : _kSafeOdor.withValues(alpha: 0.85),
                          strokeWidth: 1.2,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                  // Series 1: Smoothed 7-Day Moving Average Curve
                  LineChartBarData(
                    spots: movingAvgSpots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: _kTrendOrange,
                    barWidth: 2.8,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _kTrendOrange.withValues(alpha: 0.22),
                          _kSafeAmber.withValues(alpha: 0.03),
                        ],
                      ),
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

  /// Monthly Graph 2: 24-Hour Circadian Elimination Heatmap (Grid Matrix)
  /// X-axis: Hours of the day (0–23)
  /// Y-axis: Days of the month grouped into 6 five-day blocks (D1–5 .. D26–30)
  /// Visual: Color-intensity cells representing when box visits occur
  Widget _buildMonthlyCircadianHeatmapCard(List<MonthlyDayRecord> monthlyDays) {
    const List<String> rowLabels = [
      'D1–5',
      'D6–10',
      'D11–15',
      'D16–20',
      'D21–25',
      'D26–30',
    ];

    // Aggregate 30 days into 6 rows x 24 hours (0..23)
    final List<List<int>> matrix = List.generate(
      6,
      (_) => List<int>.filled(24, 0),
    );

    int nocturnalAlertCells = 0;

    for (final dayRecord in monthlyDays) {
      final int rowIdx = ((dayRecord.dayOfMonth - 1) ~/ 5).clamp(0, 5);
      final List<int> hours = dayRecord.hourlyVisits.length == 24
          ? dayRecord.hourlyVisits
          : SensorService.buildCircadianRowForDay(dayRecord.dayOfMonth);
      for (int h = 0; h < 24; h++) {
        matrix[rowIdx][h] += hours[h];
      }
    }

    for (int r = 0; r < 6; r++) {
      for (int h = 0; h < 24; h++) {
        final isNocturnal = h >= 1 && h <= 4;
        if (isNocturnal && matrix[r][h] >= 4) {
          nocturnalAlertCells++;
        }
      }
    }

    Color cellColorFor(int rowIdx, int hour, int count) {
      if (count <= 0) return const Color(0xFFF1F3F5);
      final bool isNocturnalHour = hour >= 1 && hour <= 4;
      if ((isNocturnalHour && count >= 4) || count >= 8) {
        return _kDangerRed;
      }
      if (count >= 5) {
        return _kTrendOrange;
      }
      if (count >= 3) {
        return _kSafeAmber;
      }
      return _kSafeOdor.withValues(alpha: 0.65);
    }

    final int activeRow = _selectedHeatmapRow ?? 5;
    final int activeHour = _selectedHeatmapHour ?? 2;
    final int activeCount = matrix[activeRow][activeHour];
    final bool activeIsNocturnalAlert =
        (activeHour >= 1 && activeHour <= 4 && activeCount >= 4) ||
            activeCount >= 8;
    final String activeHourStr =
        '${activeHour.toString().padLeft(2, '0')}:00–${activeHour.toString().padLeft(2, '0')}:59';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + 24h Matrix Badge
          _buildChartCardHeader(
            icon: Icons.grid_view_rounded,
            title: "24-Hour Circadian Elimination Heatmap",
            subtitle: "Hourly visit intensity across the month (00:00 – 23:00)",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "0h – 23h",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Unified Threshold Banner
          _buildThresholdBanner(
            text: nocturnalAlertCells > 0
                ? 'Circadian Alert: Late-month nocturnal activity (01:00–04:00) detected on D21–30'
                : 'Circadian Rhythm: Normal crepuscular pattern (dawn & dusk peaks)',
            hasAlert: nocturnalAlertCells > 0,
          ),
          const SizedBox(height: 10),

          // Unified Legend Row (Intensity Scale)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: const Color(0xFFE2E6EA),
                label: "0 Visits",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kSafeOdor.withValues(alpha: 0.70),
                label: "Low (1–2)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kSafeAmber,
                label: "Routine (3–4)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kTrendOrange,
                label: "Peak (5–7)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: "Nocturia Alert",
                isBar: true,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Interactive Selected Cell Tooltip Pill (matches _kTooltipBg style)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _kTooltipBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Selected: ${rowLabels[activeRow]}  •  $activeHourStr',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$activeCount visit${activeCount == 1 ? "" : "s"}${activeIsNocturnalAlert ? " ⚠️ Nocturia" : ""}',
                  style: TextStyle(
                    color: activeIsNocturnalAlert
                        ? const Color(0xFFFF8A80)
                        : _kSafeAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 24-Hour x 30-Day Grid Matrix aligned with Left (18+32=50px) & Right (16px) chart margins
          SizedBox(
            height: 215,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Axis Name (18px, matching fl_chart axisNameSize: 18)
                      const SizedBox(
                        width: 18,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Center(
                            child: Text(
                              'Days of Month (D1–30)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: _kTrendOrange,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Left Y-Axis Labels (32px, matching fl_chart reservedSize: 32)
                      SizedBox(
                        width: 32,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: List.generate(6, (r) {
                            final isAlertRow = r >= 4;
                            return Text(
                              rowLabels[r],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isAlertRow
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isAlertRow ? _kDangerRed : _kTooltipBg,
                              ),
                            );
                          }),
                        ),
                      ),
                      // 6 x 24 Heatmap Grid Cells
                      Expanded(
                        child: Column(
                          children: List.generate(6, (r) {
                            return Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 1.8),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: List.generate(24, (h) {
                                    final count = matrix[r][h];
                                    final isSelected =
                                        r == activeRow && h == activeHour;
                                    return Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _selectedHeatmapRow = r;
                                          _selectedHeatmapHour = h;
                                        }),
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 1.0,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cellColorFor(r, h, count),
                                            borderRadius:
                                                BorderRadius.circular(3.5),
                                            border: isSelected
                                                ? Border.all(
                                                    color: _kTooltipBg,
                                                    width: 1.6,
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      // Right Spacer (16px, matching fl_chart rightTitles reservedSize: 16)
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
                // Bottom X-Axis Tick Numbers (22px, matching fl_chart bottomTitles reservedSize: 22)
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      const SizedBox(width: 50), // 18 + 32 left offset
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              '00:00',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF616161),
                              ),
                            ),
                            Text(
                              '04:00',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: _kDangerRed,
                              ),
                            ),
                            Text(
                              '08:00',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF616161),
                              ),
                            ),
                            Text(
                              '12:00',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF616161),
                              ),
                            ),
                            Text(
                              '16:00',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF616161),
                              ),
                            ),
                            Text(
                              '20:00',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF616161),
                              ),
                            ),
                            Text(
                              '23:00',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF616161),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
                // Bottom X-Axis Title (20px, matching fl_chart axisNameSize: 20)
                const SizedBox(
                  height: 20,
                  child: Padding(
                    padding: EdgeInsets.only(top: 4, left: 34),
                    child: Text(
                      'Hours of the Day (00:00 – 23:00)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Monthly Graph 3: Chronic Odor & Ammonia Baseline Trends (Dual-Trend Line)
  /// X-axis: Weeks / Days of the month (D1 – D30)
  /// Y-axis: Dual scale — Left: Median Peak NH3 (ppm, 0..50), Right: Median Odor (%, 0..100)
  Widget _buildMonthlyGasBaselineTrendCard(List<MonthlyDayRecord> monthlyDays) {
    // Internal chart scale is 0..100 (matching Right Y-axis: Median Odor 0..100%).
    // Left Y-axis (Median Peak NH3 ppm, 0..50 ppm) maps 1 ppm -> 2 chart units.
    const double maxOdorScale = 100.0;
    const double maxAmmoniaPpm = 50.0;
    const double ammoniaToChartFactor = maxOdorScale / maxAmmoniaPpm; // 2.0

    const double dangerAmmoniaPpm = 30.0;
    const double dangerOdorPercent = 80.0;
    const double dangerAmmoniaScaled =
        dangerAmmoniaPpm * ammoniaToChartFactor; // 60.0 on chart

    final int alertDaysCount = monthlyDays
        .where(
          (d) =>
              d.medianAmmoniaPpm >= dangerAmmoniaPpm ||
              d.medianOdorIndex >= dangerOdorPercent,
        )
        .length;

    final List<FlSpot> ammoniaSpots = monthlyDays
        .map(
          (d) => FlSpot(
            d.dayOfMonth.toDouble(),
            (d.medianAmmoniaPpm * ammoniaToChartFactor)
                .clamp(0.0, maxOdorScale),
          ),
        )
        .toList();

    final List<FlSpot> odorSpots = monthlyDays
        .map(
          (d) => FlSpot(
            d.dayOfMonth.toDouble(),
            d.medianOdorIndex.clamp(0.0, maxOdorScale),
          ),
        )
        .toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified Card Header + Dual Scale Badge
          _buildChartCardHeader(
            icon: Icons.science_rounded,
            title: "Chronic Odor & Ammonia Baseline Trends",
            subtitle: "Daily median peak NH₃ (ppm) & Odor (%) over 30 days",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "ppm / %",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Unified Threshold Banner
          _buildThresholdBanner(
            text: alertDaysCount > 0
                ? 'Chronic Gas Alert: NH₃ ≥ 30 ppm (Orange)  •  Odor ≥ 80% (Red) — $alertDaysCount day${alertDaysCount == 1 ? "" : "s"}'
                : 'Chronic Gas Baseline: NH₃ < 30 ppm  •  Odor < 80%',
            hasAlert: alertDaysCount > 0,
          ),
          const SizedBox(height: 10),

          // Unified Legend Row (matches Daily Graph 2 color mapping)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildLegendItem(
                color: _kSafeAmmonia,
                label: "Median NH₃ (ppm)",
                isBar: false,
              ),
              _buildLegendItem(
                color: _kDangerAmmonia,
                label: "NH₃ Alert (≥30ppm)",
                isBar: true,
              ),
              _buildLegendItem(
                color: _kSafeOdor,
                label: "Median Odor (%)",
                isBar: false,
              ),
              _buildLegendItem(
                color: _kDangerRed,
                label: "Odor Alert (≥80%)",
                isBar: true,
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            height: 225,
            child: LineChart(
              LineChartData(
                minX: 1,
                maxX: 30,
                minY: 0,
                maxY: maxOdorScale,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 20,
                  verticalInterval: 5,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    // 30 ppm Ammonia danger line (Orange)
                    HorizontalLine(
                      y: dangerAmmoniaScaled,
                      color: _kDangerAmmonia.withValues(alpha: 0.75),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerAmmonia,
                        ),
                        labelResolver: (_) => 'NH₃ Alert',
                      ),
                    ),
                    // 80% Odor Index danger line (Coral Red)
                    HorizontalLine(
                      y: dangerOdorPercent,
                      color: _kDangerRed.withValues(alpha: 0.70),
                      strokeWidth: 1.3,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _kDangerRed,
                        ),
                        labelResolver: (_) => 'Odor Alert',
                      ),
                    ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  // Left Y-Axis: Median Peak NH3 (ppm) [0..50 ppm]
                  leftTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Median Peak NH₃ (ppm)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kSafeAmmonia,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 20,
                      getTitlesWidget: (value, meta) {
                        final ppm = (value / ammoniaToChartFactor).round();
                        final isDangerTick = ppm == 30;
                        return SizedBox(
                          width: 32,
                          child: Text(
                            '$ppm',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isDangerTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDangerTick
                                  ? _kDangerAmmonia
                                  : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Right Y-Axis: Median Odor (%) [0..100%]
                  rightTitles: AxisTitles(
                    axisNameWidget: const Center(
                      child: Text(
                        'Median Odor (%)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _kSafeOdor,
                        ),
                      ),
                    ),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 20,
                      getTitlesWidget: (value, meta) {
                        final pct = value.toInt();
                        final isDangerTick = pct == 80;
                        return SizedBox(
                          width: 32,
                          child: Text(
                            '$pct%',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isDangerTick
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isDangerTick ? _kDangerRed : _kTooltipBg,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // X-Axis: Weeks / Days of the month (D1 – D30)
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Weeks / Days of the Month (D1 – D30)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final day = value.round();
                        if (day != 1 &&
                            day != 5 &&
                            day != 10 &&
                            day != 15 &&
                            day != 20 &&
                            day != 25 &&
                            day != 30) {
                          return const SizedBox.shrink();
                        }
                        final isAlertDay = day >= 25;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'D$day',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isAlertDay
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isAlertDay
                                  ? _kDangerRed
                                  : Colors.grey.shade700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _kTooltipBg,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((barSpot) {
                        if (barSpot.barIndex != 0) {
                          return null;
                        }
                        final idx = barSpot.spotIndex;
                        if (idx < 0 || idx >= monthlyDays.length) {
                          return null;
                        }
                        final d = monthlyDays[idx];
                        final nh3Alert = d.medianAmmoniaPpm >= dangerAmmoniaPpm;
                        final odorAlert = d.medianOdorIndex >= dangerOdorPercent;
                        return LineTooltipItem(
                          'Day ${d.dayOfMonth}\n'
                          'NH₃: ${d.medianAmmoniaPpm.toStringAsFixed(1)} ppm${nh3Alert ? " ⚠️" : ""}\n'
                          'Odor: ${d.medianOdorIndex.toStringAsFixed(0)}%${odorAlert ? " ⚠️" : ""}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  // Trend Line 0: Median Peak NH3 (ppm) — Purple safe, Orange danger dots
                  LineChartBarData(
                    spots: ammoniaSpots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: _kSafeAmmonia,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) =>
                          spot.x.round() % 5 == 0 ||
                          spot.x.round() == 1 ||
                          spot.y >= dangerAmmoniaScaled,
                      getDotPainter: (spot, percent, barData, index) {
                        final isDanger = spot.y >= dangerAmmoniaScaled;
                        return FlDotCirclePainter(
                          radius: isDanger ? 3.8 : 3.0,
                          color: Colors.white,
                          strokeWidth: 2.2,
                          strokeColor:
                              isDanger ? _kDangerAmmonia : _kSafeAmmonia,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _kSafeAmmonia.withValues(alpha: 0.07),
                    ),
                  ),
                  // Trend Line 1: Median Odor Index (%) — Teal safe, Coral Red danger dots
                  LineChartBarData(
                    spots: odorSpots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: _kSafeOdor,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) =>
                          spot.x.round() % 5 == 0 ||
                          spot.x.round() == 1 ||
                          spot.y >= dangerOdorPercent,
                      getDotPainter: (spot, percent, barData, index) {
                        final isDanger = spot.y >= dangerOdorPercent;
                        return FlDotCirclePainter(
                          radius: isDanger ? 3.8 : 3.0,
                          color: Colors.white,
                          strokeWidth: 2.2,
                          strokeColor: isDanger ? _kDangerRed : _kSafeOdor,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _kSafeOdor.withValues(alpha: 0.07),
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
    _ensureVisitStream();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          PageHeader(
            title: 'Analytics',
            subtitle: 'Behavioral insights for your cat',
            icon: Icons.insights_rounded,
            actions: [
              HeaderActionButton(
                tooltip: 'Seed Mock Data to Firebase RTDB',
                icon: Icons.cloud_upload_outlined,
                onPressed: _isSeeding ? null : () => _seedMockDatabase(),
                child: _isSeeding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : null,
              ),
            ],
            bottom: _buildPeriodToggle(),
          ),
          Expanded(
      child: SingleChildScrollView(
        child: StreamBuilder<DatabaseEvent>(
          stream: _visitStream,
          builder: (context, snapshot) {
            List<VisitRecord> visits = [];

            if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
              visits = _sensorService.parseVisitRecords(snapshot.data!.snapshot);
            } else if (snapshot.connectionState == ConnectionState.active &&
                !_didAutoSeed) {
              _didAutoSeed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _seedMockDatabase(showFeedback: false);
              });
            }

            // Compute live summary metrics from visits if available
            final int totalVisits = visits.length;
            final double avgMin = totalVisits > 0
                ? visits.fold<double>(0, (sum, v) => sum + v.durationMinutes) /
                    totalVisits
                : 1.9;
            final int avgSec = totalVisits > 0
                ? (visits.fold<int>(0, (sum, v) => sum + v.durationSeconds) /
                        totalVisits)
                    .round()
                : 114;

            return Column(
              children: [
                const SizedBox(height: 10),

                // Show Daily, Weekly, or Monthly graphs based on selected period
                if (_selectedPeriod == AnalyticsPeriod.daily)
                  (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData)
                      ? Container(
                          height: 220,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            _buildComboDwellChartCard(visits),
                            _buildGasFingerprintChartCard(visits),
                            _buildDepositMassChartCard(visits),
                          ],
                        )
                else if (_selectedPeriod == AnalyticsPeriod.weekly)
                  _buildWeeklySection()
                else
                  _buildMonthlySection(),

                // Behavioral Insights Section
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: AppDecorations.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.iconBgOrange,
                            child: Icon(
                              Icons.insights_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "Behavioral Insights",
                            style: AppTextStyles.cardTitle,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ...insights.map(
                        (insight) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: insight.iconColor
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  insight.icon,
                                  color: insight.iconColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      insight.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textDark,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      insight.description,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Summary Metric Cards
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: AppDecorations.cardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.pets_rounded,
                                    size: 16,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    "Today's Visits",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "$totalVisits visits",
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
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
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: AppDecorations.cardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 16,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    "Avg Dwell Time",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Text(
                                  _dwellUnit == DwellUnit.seconds
                                      ? "$avgSec sec"
                                      : "${avgMin.toStringAsFixed(1)} min",
                                  key: ValueKey(_dwellUnit),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],
            );
          },
        ),
      ),
          ),
        ],
      ),
    );
  }
}
