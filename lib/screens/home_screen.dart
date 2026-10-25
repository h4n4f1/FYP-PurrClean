import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../add_cat_page.dart';
import '../services/auth_service.dart';
import '../services/device_provisioning_service.dart';
import '../services/device_status_service.dart';
import '../services/sensor_service.dart';
import '../theme/app_styles.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/page_header.dart';
import '../widgets/stat_card.dart';
import 'cat_settings_screen.dart';

class HealthAlert {
  final String message;
  final String timeAgo;
  final bool isHighSeverity;

  const HealthAlert({
    required this.message,
    required this.timeAgo,
    this.isHighSeverity = false,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.refreshTick = 0});

  /// Changes whenever the user switches back to the Home tab.
  final int refreshTick;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _authService = FirebaseAuthService();
  final SensorService _sensorService = SensorService();

  String _activeDeviceId = '308C';
  bool _didAutoSeed = false;

  Stream<DatabaseEvent>? _deviceStream;
  String? _streamDeviceId;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _catStream;
  String? _streamCatUid;

  final Map<String, MemoryImage> _avatarCache = {};
  String? _selectedCatDocId;

  bool isAutoMode = true;
  bool isFanRunning = false;
  bool _isEmailVerified = false;

  @override
  void initState() {
    super.initState();
    _isEmailVerified = _authService.isEmailVerified;
    _ensureStreams();
    WidgetsBinding.instance.addObserver(this);
    _refreshEmailVerification();
    _resolveActiveDevice();
  }

  void _ensureStreams() {
    if (_deviceStream == null || _streamDeviceId != _activeDeviceId) {
      _streamDeviceId = _activeDeviceId;
      _deviceStream = _sensorService.getDeviceStream(_activeDeviceId);
    }
    final uid = _authService.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      if (_catStream == null || _streamCatUid != uid) {
        _streamCatUid = uid;
        _catStream = FirebaseFirestore.instance
            .collection('cats')
            .where('user_id', isEqualTo: uid)
            .snapshots();
      }
    } else {
      _streamCatUid = null;
      _catStream = null;
    }
  }

  Future<void> _resolveActiveDevice() async {
    final savedName =
        await DeviceProvisioningService.instance.savedDeviceName();
    if (savedName != null && savedName.trim().isNotEmpty && mounted) {
      final resolvedId = DeviceStatusService.idFromName(savedName);
      if (resolvedId != _activeDeviceId) {
        setState(() {
          _activeDeviceId = resolvedId;
          _ensureStreams();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _refreshEmailVerification();
      _resolveActiveDevice();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshEmailVerification();
    }
  }

  Future<void> _refreshEmailVerification() async {
    try {
      await _authService.reloadUser();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final verified = _authService.isEmailVerified;
    final currentUid = _authService.currentUser?.uid;
    if (verified != _isEmailVerified || currentUid != _streamCatUid) {
      setState(() {
        _isEmailVerified = verified;
        _ensureStreams();
      });
    }
  }

  String get fanStatusText => isFanRunning ? 'Running' : 'Stopped';

  List<HealthAlert> _deriveHealthAlerts(List<VisitRecord> visits) {
    final List<HealthAlert> list = [];
    for (final v in visits.reversed) {
      final bool longDwell = v.durationMinutes >= 3.0;
      final bool highGas = v.ammoniaPpm >= 30.0 || v.odorIndex >= 80.0;
      final bool heavyDeposit = v.depositGrams >= 60.0;

      if (longDwell && highGas) {
        list.add(
          HealthAlert(
            message:
                'Extended dwell (${v.durationMinutes.toStringAsFixed(1)}m / ${v.durationSeconds}s) & gas alert (NH₃ ${v.ammoniaPpm.toStringAsFixed(0)} ppm • Odor ${v.odorIndex.toStringAsFixed(0)}%)',
            timeAgo: 'Today at ${v.timeLabel}',
            isHighSeverity: true,
          ),
        );
      } else if (longDwell) {
        list.add(
          HealthAlert(
            message:
                'Extended dwell time detected (${v.durationMinutes.toStringAsFixed(1)}m / ${v.durationSeconds}s)',
            timeAgo: 'Today at ${v.timeLabel}',
            isHighSeverity: true,
          ),
        );
      } else if (highGas) {
        list.add(
          HealthAlert(
            message:
                'Elevated gas alert (NH₃ ${v.ammoniaPpm.toStringAsFixed(0)} ppm • Odor ${v.odorIndex.toStringAsFixed(0)}%)',
            timeAgo: 'Today at ${v.timeLabel}',
            isHighSeverity: true,
          ),
        );
      } else if (heavyDeposit || v.odorIndex >= 60.0) {
        list.add(
          HealthAlert(
            message:
                'Moderate odor spike (${v.odorIndex.toStringAsFixed(0)}% • NH₃ ${v.ammoniaPpm.toStringAsFixed(0)} ppm) — fan auto-purged',
            timeAgo: 'Today at ${v.timeLabel}',
            isHighSeverity: false,
          ),
        );
      }
    }
    return list.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    _ensureStreams();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
        child: StreamBuilder<DatabaseEvent>(
          stream: _deviceStream,
          builder: (context, deviceSnap) {
            List<VisitRecord> visits = [];
            double? rtdbLatestWeightKg;

            final rootSnapshot = deviceSnap.data?.snapshot;
            if (rootSnapshot != null && rootSnapshot.value is Map) {
              final visitsSnap = rootSnapshot.child('visits');
              if (visitsSnap.exists) {
                visits = _sensorService.parseVisitRecords(visitsSnap);
                final rawVisits = visitsSnap.value;
                if (rawVisits is Map) {
                  for (final entry in rawVisits.values) {
                    if (entry is Map && entry['weight_g'] is num) {
                      rtdbLatestWeightKg =
                          (entry['weight_g'] as num).toDouble() / 1000.0;
                    }
                  }
                }
              }

              final fanSnap = rootSnapshot.child('fan');
              if (fanSnap.exists && fanSnap.value is Map) {
                final fanMap = Map<dynamic, dynamic>.from(fanSnap.value as Map);
                if (fanMap['auto_mode'] is bool) {
                  isAutoMode = fanMap['auto_mode'] as bool;
                }
                if (fanMap['is_running'] is bool) {
                  isFanRunning = fanMap['is_running'] as bool;
                }
              }
            } else if (deviceSnap.connectionState == ConnectionState.active &&
                !_didAutoSeed) {
              _didAutoSeed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _sensorService.seedMockVisits(_activeDeviceId);
              });
            }

            // Compute live dashboard metrics from RTDB visits
            final String liveLastVisit = visits.isNotEmpty
                ? '${visits.last.timeLabel} (${visits.last.durationSeconds}s)'
                : 'No visits yet';
            final String liveTodaysVisits = '${visits.length}';

            final double totalDepositGrams = visits.fold<double>(
              0.0,
              (acc, v) => acc + v.depositGrams,
            );
            // 500g waste drawer capacity reference
            final int wastePct =
                ((totalDepositGrams / 500.0) * 100).round().clamp(0, 100);
            final String liveWasteLevel = '$wastePct%';

            final int liveAmmoniaPpm =
                visits.isNotEmpty ? visits.last.ammoniaPpm.round() : 0;
            final int peakAmmoniaPpm = visits.isNotEmpty
                ? visits
                    .map((v) => v.ammoniaPpm)
                    .reduce((a, b) => a > b ? a : b)
                    .round()
                : 0;
            final int liveOdorPct =
                visits.isNotEmpty ? visits.last.odorIndex.round() : 0;
            // Derive equivalent CO2 / VOC ppm from RTDB odor index (baseline 400 ppm + odor scaling)
            final int liveCo2Ppm =
                visits.isNotEmpty ? 400 + (liveOdorPct * 8) : 400;

            final String liveAirQualityStatus =
                (liveAmmoniaPpm >= 30 || liveOdorPct >= 80)
                    ? 'Alert'
                    : (liveAmmoniaPpm >= 18 || liveOdorPct >= 40)
                        ? 'Moderate'
                        : 'Good';

            final List<HealthAlert> liveAlerts = _deriveHealthAlerts(visits);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_isEmailVerified) _buildEmailVerificationNotice(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCatInfoCard(
                          rtdbLatestWeightKg: rtdbLatestWeightKg,
                          totalVisitsToday: visits.length,
                        ),
                        const SizedBox(height: 18),
                        _buildHealthAlertsCard(liveAlerts),
                        const SizedBox(height: 18),
                        _buildStatsGrid(
                          lastVisitValue: liveLastVisit,
                          todaysVisitsValue: liveTodaysVisits,
                          wasteLevelValue: liveWasteLevel,
                          airQualityStatusValue: liveAirQualityStatus,
                        ),
                        const SizedBox(height: 18),
                        _buildAirQualityMonitoringCard(
                          airQualityStatusValue: liveAirQualityStatus,
                          currentAmmoniaPpm: liveAmmoniaPpm,
                          peakAmmoniaPpm: peakAmmoniaPpm,
                          currentCo2Ppm: liveCo2Ppm,
                          currentOdorPct: liveOdorPct,
                        ),
                        const SizedBox(height: 18),
                        _buildOdorControlCard(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailVerificationNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.mark_email_unread_outlined,
            color: Colors.red,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Please verify your email. Check your inbox or spam folder for the verification email.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red.shade800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Compact Shortened Header ---------------------------------------------

  Widget _buildHeader() {
    final name = _authService.currentUser?.displayName?.trim() ?? '';
    return PageHeader(
      title: 'PurrClean',
      subtitle: name.isNotEmpty
          ? 'Hi ${name.split(' ').first}, here\'s today\'s overview'
          : 'Your personal litter box assistant',
      leading: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
    );
  }

  // -- Bigger Orange Cat Info Card (High-Contrast Readability) --------------

  Widget _buildCatInfoCard({
    required double? rtdbLatestWeightKg,
    required int totalVisitsToday,
  }) {
    final uid = _authService.currentUser?.uid;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppDecorations.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pets_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cat Profile',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (uid != null && uid.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => AddCatPage.open(context, userId: uid),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Add Cat',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (uid == null || uid.isEmpty)
            const Text(
              'Please sign in to view your cat profile.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _catStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return const Text(
                    'Could not load cat info right now.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }

                // Strictly verify that user_id matches the current logged-in uid
                final matchingDocs = (snapshot.data?.docs ?? []).where((doc) {
                  final data = doc.data();
                  final docUserId = data['user_id']?.toString().trim();
                  return docUserId != null && docUserId == uid;
                }).toList();

                if (matchingDocs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.38),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.pets_rounded,
                                color: AppColors.primary,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'No cat profile linked to your account yet. Add your cat\'s details to personalise PurrClean.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: () => AddCatPage.open(
                              context,
                              userId: uid,
                              existingCatCount: 0,
                            ),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text(
                              'Set Up Cat Profile',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: AppDecorations.buttonRadius,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Resolve active cat for the Home card
                QueryDocumentSnapshot<Map<String, dynamic>> activeDoc =
                    matchingDocs.first;
                if (_selectedCatDocId != null) {
                  final found = matchingDocs
                      .where((d) => d.id == _selectedCatDocId)
                      .toList();
                  if (found.isNotEmpty) {
                    activeDoc = found.first;
                  } else {
                    _selectedCatDocId = activeDoc.id;
                  }
                } else {
                  _selectedCatDocId = activeDoc.id;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (matchingDocs.length > 1) ...[
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: matchingDocs.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final doc = matchingDocs[i];
                            final isSelected = doc.id == activeDoc.id;
                            final rawName =
                                (doc.data()['cat_name'] as String?)?.trim() ??
                                    '';
                            final name =
                                rawName.isEmpty ? 'Cat ${i + 1}' : rawName;
                            return GestureDetector(
                              onTap: () => setState(
                                () => _selectedCatDocId = doc.id,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.4),
                                    width: 1.2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.pets_rounded,
                                      size: 14,
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected
                                            ? AppColors.primary
                                            : Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _buildCatProfileItem(
                      activeDoc.data(),
                      docId: activeDoc.id,
                      rtdbLatestWeightKg: rtdbLatestWeightKg,
                      totalVisitsToday: totalVisitsToday,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCatProfileItem(
    Map<String, dynamic> data, {
    required String docId,
    required double? rtdbLatestWeightKg,
    required int totalVisitsToday,
  }) {
    final rawName = (data['cat_name'] as String?)?.trim() ?? '';
    final catName = rawName.isEmpty ? 'My Cat' : rawName;
    final rawBreed = (data['breed'] as String?)?.trim() ?? '';
    final breed = rawBreed.isEmpty ? 'Domestic Cat' : rawBreed;
    final profileWeight =
        data['weight'] is num ? (data['weight'] as num).toDouble() : 0.0;
    final effectiveWeight =
        profileWeight > 0 ? profileWeight : (rtdbLatestWeightKg ?? 0.0);
    final ageNum = data['age'] is num ? (data['age'] as num).toInt() : 0;
    final base64Image = (data['image_base64'] as String?) ?? '';

    ImageProvider? avatarImage;
    if (base64Image.isNotEmpty) {
      avatarImage = _avatarCache[base64Image];
      if (avatarImage == null) {
        try {
          final memoryImg = MemoryImage(base64Decode(base64Image));
          _avatarCache[base64Image] = memoryImg;
          avatarImage = memoryImg;
        } catch (_) {}
      }
    }

    final weightLabel = effectiveWeight > 0
        ? '${effectiveWeight.toStringAsFixed(effectiveWeight.truncateToDouble() == effectiveWeight ? 1 : 2)} kg'
        : '— kg';
    final ageLabel =
        ageNum > 0 ? '$ageNum ${ageNum == 1 ? 'Year' : 'Years'}' : '— Years';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CatSettingsScreen(initialCatDocId: docId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.38),
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2.5,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? const Icon(
                            Icons.pets_rounded,
                            color: AppColors.primary,
                            size: 38,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        catName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 4.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          breed,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.90),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 17,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildBigCatStatTile(
                    icon: Icons.monitor_weight_outlined,
                    title: 'Weight',
                    value: weightLabel,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildBigCatStatTile(
                    icon: Icons.cake_outlined,
                    title: 'Age',
                    value: ageLabel,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildBigCatStatTile(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Today',
                    value: '$totalVisitsToday Visits',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBigCatStatTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4B5563),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // -- Health alerts (Connected to RTDB) ------------------------------------

  Widget _buildHealthAlertsCard(List<HealthAlert> liveAlerts) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(
            icon: Icons.error_outline,
            iconBg: AppColors.iconBgOrange,
            iconColor: AppColors.primary,
            title: 'Health Alerts',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: liveAlerts.isEmpty
                    ? const Color(0xFFE8F5E9)
                    : AppColors.iconBgOrange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                liveAlerts.isEmpty ? 'All Clear' : '${liveAlerts.length} Active',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: liveAlerts.isEmpty
                      ? AppColors.successGreen
                      : AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (liveAlerts.isEmpty)
            Text(
              'No alerts right now — everything looks good!',
              style: TextStyle(color: Colors.grey.shade600),
            )
          else
            Column(
              children: [
                for (int i = 0; i < liveAlerts.length; i++) ...[
                  _buildAlertRow(liveAlerts[i]),
                  if (i != liveAlerts.length - 1)
                    Divider(
                      height: 24,
                      thickness: 0.8,
                      color: Colors.grey.shade200,
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAlertRow(HealthAlert alert) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          alert.isHighSeverity
              ? Icons.warning_amber_rounded
              : Icons.notifications_none_rounded,
          color: AppColors.alertBell,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                alert.message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 3),
              Text(alert.timeAgo, style: AppTextStyles.timestamp),
            ],
          ),
        ),
      ],
    );
  }

  // -- Stats grid (Connected to RTDB) ---------------------------------------

  Widget _buildStatsGrid({
    required String lastVisitValue,
    required String todaysVisitsValue,
    required String wasteLevelValue,
    required String airQualityStatusValue,
  }) {
    final bool isAlert = airQualityStatusValue == 'Alert';
    final bool isGood = airQualityStatusValue == 'Good';

    final Color pillBg = isAlert
        ? const Color(0xFFFFEBEE)
        : isGood
            ? const Color(0xFFE8F5E9)
            : AppColors.moderatePillBg;
    final Color pillText = isAlert
        ? const Color(0xFFD32F2F)
        : isGood
            ? const Color(0xFF2E7D32)
            : AppColors.moderatePillText;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.access_time_rounded,
                iconBg: AppColors.iconBgOrange,
                iconColor: AppColors.primary,
                label: 'Last Visit',
                value: lastVisitValue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                icon: Icons.people_alt_outlined,
                iconBg: AppColors.iconBgYellow,
                iconColor: AppColors.moderatePillText,
                label: "Today's Visits",
                value: todaysVisitsValue,
                trailing: const Icon(
                  Icons.trending_up_rounded,
                  color: AppColors.successGreen,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.inventory_2_outlined,
                iconBg: AppColors.iconBgYellow,
                iconColor: AppColors.moderatePillText,
                label: 'Waste Level',
                value: wasteLevelValue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                icon: Icons.air_rounded,
                iconBg: AppColors.iconBgYellow,
                iconColor: AppColors.moderatePillText,
                label: 'Air Quality',
                valueWidget: StatusPill(
                  label: airQualityStatusValue,
                  background: pillBg,
                  textColor: pillText,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -- Air quality monitoring (Connected to RTDB) ---------------------------

  Widget _buildAirQualityMonitoringCard({
    required String airQualityStatusValue,
    required int currentAmmoniaPpm,
    required int peakAmmoniaPpm,
    required int currentCo2Ppm,
    required int currentOdorPct,
  }) {
    const int ammoniaMaxPpm = 50;
    const int co2MaxPpm = 1200;
    const int autoActivationThresholdPpm = 30;

    final bool isAlert = airQualityStatusValue == 'Alert';
    final bool isGood = airQualityStatusValue == 'Good';
    final Color statusBg = isAlert
        ? const Color(0xFFFFEBEE)
        : isGood
            ? const Color(0xFFE8F5E9)
            : AppColors.moderatePillBg;
    final Color statusText = isAlert
        ? const Color(0xFFD32F2F)
        : isGood
            ? const Color(0xFF2E7D32)
            : AppColors.moderatePillText;
    final IconData statusIcon = isAlert
        ? Icons.warning_amber_rounded
        : isGood
            ? Icons.check_circle_outline_rounded
            : Icons.thumb_up_alt_outlined;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            icon: Icons.bar_chart_rounded,
            iconBg: AppColors.iconBgBlue,
            iconColor: AppColors.infoBlue,
            title: 'Air Quality Monitoring',
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overall Status (Odor $currentOdorPct% • Peak NH₃ $peakAmmoniaPpm PPM)',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      label: airQualityStatusValue,
                      background: statusBg,
                      textColor: statusText,
                    ),
                  ],
                ),
              ),
              RoundIcon(
                icon: statusIcon,
                background: statusBg,
                iconColor: statusText,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _buildMetricBar(
            label: 'Ammonia (NH₃)',
            valuePpm: currentAmmoniaPpm,
            maxPpm: ammoniaMaxPpm,
            color: AppColors.infoBlue,
          ),
          const SizedBox(height: 18),
          _buildMetricBar(
            label: 'Carbon Dioxide (CO₂)',
            valuePpm: currentCo2Ppm,
            maxPpm: co2MaxPpm,
            color: AppColors.successGreen,
          ),
          const SizedBox(height: 18),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Auto-activation threshold',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const Text(
                '$autoActivationThresholdPpm PPM',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBar({
    required String label,
    required int valuePpm,
    required int maxPpm,
    required Color color,
  }) {
    final progress = maxPpm > 0 ? (valuePpm / maxPpm).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$valuePpm PPM',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.barTrack,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // -- Automated odor control (Connected to RTDB) ---------------------------

  Widget _buildOdorControlCard() {
    const String fanName = 'DC Brushless Fan';
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            icon: Icons.air_rounded,
            iconBg: AppColors.iconBgOrange,
            iconColor: AppColors.primary,
            title: 'Automated Odor Control',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const RoundIcon(
                icon: Icons.air_rounded,
                background: AppColors.iconBgOrange,
                iconColor: AppColors.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(fanName, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 2),
                    Text(
                      fanStatusText,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: isAutoMode ? 'Auto Mode' : 'Manual',
                background: isAutoMode
                    ? AppColors.iconBgBlue
                    : AppColors.manualPillBg,
                textColor: isAutoMode
                    ? AppColors.infoBlue
                    : AppColors.manualPillText,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildModeToggle(),
          if (!isAutoMode) ...[
            const SizedBox(height: 12),
            _buildFanControlButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.toggleTrack,
        borderRadius: AppDecorations.toggleRadius,
      ),
      child: Row(
        children: [
          Expanded(child: _modeButton('Auto', isAutoMode)),
          Expanded(child: _modeButton('Manual', !isAutoMode)),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool selected) {
    final gradient = label == 'Auto'
        ? AppColors.fanGradient
        : AppColors.manualGradient;
    return GestureDetector(
      onTap: () {
        final nextAuto = label == 'Auto';
        setState(() => isAutoMode = nextAuto);
        _sensorService.updateFanControl(
          _activeDeviceId,
          isAutoMode: nextAuto,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: selected ? gradient : null,
          borderRadius: AppDecorations.toggleButtonRadius,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: selected
              ? AppTextStyles.toggleLabelActive
              : AppTextStyles.toggleLabelInactive,
        ),
      ),
    );
  }

  Widget _buildFanControlButton() {
    return GestureDetector(
      onTap: () {
        final nextRunning = !isFanRunning;
        setState(() => isFanRunning = nextRunning);
        _sensorService.updateFanControl(
          _activeDeviceId,
          isRunning: nextRunning,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: isFanRunning
              ? AppColors.stopGradient
              : AppColors.startGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (isFanRunning
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF22C55E))
                  .withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          isFanRunning ? 'Stop Fan' : 'Start Fan',
          style: AppTextStyles.buttonLabel,
        ),
      ),
    );
  }
}
