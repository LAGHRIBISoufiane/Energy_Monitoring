import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models/energy_data.dart';
import 'models/alert_entry.dart';
import 'services/firestore_log_service.dart';
import 'screens/login_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/historical_screen.dart';
import 'screens/summary_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/alert_history_screen.dart';
import 'screens/comparison_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/maintenance_screen.dart';
import 'screens/user_logs_screen.dart';
import 'services/presence_service.dart';
import 'services/auto_report_service.dart';
import 'services/alert_notification_service.dart';
import 'services/user_log_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'l10n/app_strings.dart';

/// Global theme notifier — read/written by SettingsScreen
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

/// Global alert log — written by DashboardScreen, read by AlertHistoryScreen
final alertLogNotifier = ValueNotifier<List<AlertEntry>>([]);

/// Global selected-unit notifier — keeps RightInfoPanel in sync with Dashboard
final selectedUnitNotifier = ValueNotifier<String>('KOFERT_Unit_1');

/// Current user's role: 'admin', 'operator', or 'viewer'
final roleNotifier = ValueNotifier<String>('viewer');

/// Whether browser push notifications are enabled
final browserNotifNotifier = ValueNotifier<bool>(false);

/// Load saved theme on startup
Future<void> _loadTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('themeMode') ?? 'dark';
  themeNotifier.value = saved == 'light'
      ? ThemeMode.light
      : saved == 'system'
          ? ThemeMode.system
          : ThemeMode.dark;
  languageNotifier.value = prefs.getString('language') ?? 'fr';
  selectedUnitNotifier.value =
      prefs.getString('selectedUnit') ?? 'KOFERT_Unit_1';
  browserNotifNotifier.value = prefs.getBool('browserNotifEnabled') ?? false;
}

// ── Dark theme palette ────────────────────────────────────────────────────────
const Color kDarkBg      = Color(0xFF1E1E2E);
const Color kDarkSidebar = Color(0xFF16162A);
const Color kDarkCard    = Color(0xFF252535);
const Color kTeal        = Color(0xFF4ECDC4);
const Color kOrange      = Color(0xFFF5A623);
const Color kTextPri     = Color(0xFFFFFFFF);
const Color kTextSec     = Color(0x99FFFFFF);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _loadTheme();
  runApp(const KofertDashboard());
}

class KofertDashboard extends StatelessWidget {
  const KofertDashboard({super.key});

  static ThemeData get _darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kDarkBg,
        colorScheme: ColorScheme.dark(
          primary: kTeal,
          secondary: kOrange,
          surface: kDarkCard,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: kTextPri),
          bodySmall: TextStyle(color: kTextSec),
        ),
        sliderTheme: const SliderThemeData(activeTrackColor: kTeal),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? kTeal : Colors.grey),
          trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? kTeal.withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.3)),
        ),
        extensions: const [AppColors.dark],
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, child) => ValueListenableBuilder<String>(
        valueListenable: languageNotifier,
        builder: (context, lang, child) => MaterialApp(
          title: AppStrings.t('app_title'),
          theme: AppTheme.lightTheme,
          darkTheme: _darkTheme,
          themeMode: mode,
          locale: AppStrings.locale,
          supportedLocales: const [
            Locale('fr'),
            Locale('en'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          debugShowCheckedModeBanner: false,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.idTokenChanges(),
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  body: const Center(
                      child: CircularProgressIndicator(color: kTeal)),
                );
              }
              final user = snapshot.data;
              if (user == null) return const LoginScreen();
              if (!user.emailVerified) return const VerifyEmailScreen();
              // Sync Firebase Auth displayName → Firestore (fire-and-forget)
              final authName = user.displayName?.trim() ?? '';
              if (authName.isNotEmpty) {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .set({'displayName': authName}, SetOptions(merge: true));
              }
              return const MainScreen();
            },
          ),
        ),
      ),
    );
  }
}

// ── Main shell ────────────────────────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Firestore real-time listeners
  StreamSubscription? _assignedTasksSub;
  StreamSubscription? _resolvedAlertsSub;
  final Set<String> _seenAlertIds = {};
  bool _alertsInitialLoadDone = false;
  bool _maintenanceInitialLoadDone = false;

  // Background RTDB → Firestore write pipeline (app-level, always alive)
  final List<StreamSubscription> _bgSensorSubs = [];

  static const _screens = [
    DashboardScreen(),      // 0
    HistoricalScreen(),     // 1
    SummaryScreen(),        // 2
    AlertHistoryScreen(),   // 3
    ComparisonScreen(),     // 4
    SettingsScreen(),       // 5
    ChatScreen(),           // 6
    ProfileScreen(),        // 7
    MaintenanceScreen(),    // 8
    UserLogsScreen(),       // 9
  ];

  @override
  void initState() {
    super.initState();
    PresenceService.instance.initialize();
    AutoReportService.instance.initialize();
    _loadUserRole();
    // Start real-time listeners and show missed alerts after first frame.
    _startBackgroundSensorSync();
    _logLogin();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startMaintenanceListener();
      _startResolvedAlertsListener();
      AlertNotificationService.instance.checkMissedOnLogin(
        context,
        onViewAlerts: () {
          if (mounted) setState(() => _selectedIndex = 3);
        },
      );
    });
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await ref.get();
      final data = doc.data();

      // Always ensure soufianelaghri1@gmail.com has the admin role.
      // Set roleNotifier FIRST so the UI is correct even if the Firestore
      // write is blocked by rules (bootstrapping chicken-and-egg).
      if (user.email?.toLowerCase() == 'soufianelaghri1@gmail.com') {
        roleNotifier.value = 'admin';
        try {
          await ref.set({'role': 'admin', 'email': user.email},
              SetOptions(merge: true));
        } catch (_) {} // OK if blocked — client role already set
        return;
      }

      final existingRole = data?['role'] as String?;
      roleNotifier.value = existingRole ?? 'viewer';
      // Always persist email so broadcast notifications can reach this user.
      // Also writes 'viewer' role if not yet set — required for security rules.
      try {
        await ref.set(
          {
            if (existingRole == null) 'role': 'viewer',
            if ((user.email ?? '').isNotEmpty) 'email': user.email,
          },
          SetOptions(merge: true),
        );
      } catch (_) {} // OK if blocked — client role already set
    } catch (_) {}
  }

  void _logLogin() {
    // Defer so roleNotifier is already set
    Future.microtask(() =>
      UserLogService.instance.log(action: 'login', detail: 'Tableau de bord ouvert'));
  }

  // Subscribes to RTDB current_metrics for all 3 units at the app level.
  // This ensures Firestore writes happen regardless of which tab is active.
  void _startBackgroundSensorSync() {
    for (final sub in _bgSensorSubs) {
      sub.cancel();
    }
    _bgSensorSubs.clear();
    const units = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];
    for (final unitId in units) {
      final sub = FirebaseDatabase.instance
          .ref('$unitId/current_metrics')
          .onValue
          .listen((event) {
        if (event.snapshot.value == null) return;
        try {
          final data = EnergyData.fromJson(
            event.snapshot.value as Map<dynamic, dynamic>,
            unitId,
          );
          FirestoreLogService.instance.logReading(data);
        } catch (_) {}
      });
      _bgSensorSubs.add(sub);
    }
  }

  @override
  void dispose() {
    for (final sub in _bgSensorSubs) {
      sub.cancel();
    }
    _assignedTasksSub?.cancel();
    _resolvedAlertsSub?.cancel();
    PresenceService.instance.dispose();
    AutoReportService.instance.dispose();
    super.dispose();
  }

  // ── Real-time: maintenance tasks assigned to current user ─────────────────
  void _startMaintenanceListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _assignedTasksSub = FirebaseFirestore.instance
        .collection('maintenance_logs')
        .where('assignedToUid', isEqualTo: uid)
        .where('resolved', isEqualTo: false)
        .snapshots()
        .listen(_onAssignedTasksSnapshot);
  }

  void _onAssignedTasksSnapshot(QuerySnapshot snap) {
    final isInitialLoad = !_maintenanceInitialLoadDone;
    _maintenanceInitialLoadDone = true;
    final existing = alertLogNotifier.value.map((e) => e.title).toSet();
    final newEntries = <AlertEntry>[];
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final d = change.doc.data() as Map<String, dynamic>;
      final docId = change.doc.id;
      final title = '${AppStrings.t('maintenance_assigned')}|$docId';
      if (existing.contains(title)) continue;
      final type = d['type'] as String? ?? 'inspection';
      final desc = d['description'] as String? ?? '';
      final color = type == 'repair'
          ? const Color(0xFFE74C3C)
          : type == 'calibration' ? kOrange : kTeal;
      newEntries.add(AlertEntry(
        title: title,
        detail: desc.isNotEmpty ? desc : AppStrings.t(type),
        color: color,
        time: (d['timestamp'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
        unitId: d['unitId'] as String? ?? '',
      ));
    }
    if (newEntries.isNotEmpty) {
      alertLogNotifier.value = [...alertLogNotifier.value, ...newEntries];
      // Show a snackbar only for NEW assignments (not the initial load at startup)
      if (!isInitialLoad && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.build_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(AppStrings.t('maintenance_assigned')),
          ]),
          backgroundColor: kTeal,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: AppStrings.t('view'),
            textColor: Colors.white,
            onPressed: () {
              if (mounted) setState(() => _selectedIndex = 8);
            },
          ),
        ));
      }
    }
  }

  // ── Real-time: maintenance resolved alerts broadcast to all users ─────────
  void _startResolvedAlertsListener() {
    _resolvedAlertsSub = FirebaseFirestore.instance
        .collection('alerts')
        .where('type', isEqualTo: 'maintenance_resolved')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen(_onResolvedAlertsSnapshot);
  }

  void _onResolvedAlertsSnapshot(QuerySnapshot snap) {
    if (!_alertsInitialLoadDone) {
      // Mark all current docs as seen so we don't re-show historical resolutions.
      for (final doc in snap.docs) {
        _seenAlertIds.add(doc.id);
      }
      _alertsInitialLoadDone = true;
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      if (_seenAlertIds.contains(change.doc.id)) continue;
      _seenAlertIds.add(change.doc.id);
      final d = change.doc.data() as Map<String, dynamic>;
      // Skip if this user was the one who resolved it (they already see it locally)
      final resolvedByUid = d['resolvedByUid'] as String? ?? '';
      if (resolvedByUid == uid) continue;
      final title = d['title'] as String? ?? '';
      final detail = d['detail'] as String? ?? '';
      final unitId = d['unitId'] as String? ?? '';
      if (title.isEmpty) continue;
      alertLogNotifier.value = [
        ...alertLogNotifier.value,
        AlertEntry(
          title: title,
          detail: detail,
          color: const Color(0xFF2ECC71),
          time: DateTime.now(),
          unitId: unitId,
        ),
      ];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
          ]),
          backgroundColor: const Color(0xFF2ECC71),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: AppStrings.t('view'),
            textColor: Colors.white,
            onPressed: () {
              if (mounted) setState(() => _selectedIndex = 8);
            },
          ),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      const mobileNavScreens = [0, 1, 3, 6, 7];
      final bottomNavIdx = mobileNavScreens.contains(_selectedIndex)
          ? mobileNavScreens.indexOf(_selectedIndex)
          : 0;
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.card,
          elevation: 0,
          titleSpacing: 0,
          iconTheme: IconThemeData(color: c.textPri),
          title: Row(children: [
            const SizedBox(width: 4),
            Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(7)),
              ),
              padding: const EdgeInsets.all(4),
              child: Image.asset('assets/images/ocp_logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 8),
            Text('KOFERT Energy',
                style: TextStyle(color: c.textPri, fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          actions: const [
            Padding(padding: EdgeInsets.only(right: 8), child: QuickSettingsBar()),
          ],
        ),
        drawer: Drawer(
          width: 240,
          backgroundColor: c.card,
          child: _DarkSidebar(
            selectedIndex: _selectedIndex,
            onSelect: (i) {
              setState(() => _selectedIndex = i);
              Navigator.of(context).pop();
            },
          ),
        ),
        body: _screens[_selectedIndex],
        bottomNavigationBar: ValueListenableBuilder<List<AlertEntry>>(
          valueListenable: alertLogNotifier,
          builder: (context, log, _) => BottomNavigationBar(
            currentIndex: bottomNavIdx,
            backgroundColor: c.card,
            selectedItemColor: kTeal,
            unselectedItemColor: c.textSec,
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            onTap: (i) => setState(() => _selectedIndex = mobileNavScreens[i]),
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.dashboard_outlined, size: 22),
                activeIcon: const Icon(Icons.dashboard, size: 22),
                label: AppStrings.t('dashboard'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.history_outlined, size: 22),
                activeIcon: const Icon(Icons.history, size: 22),
                label: AppStrings.t('historical'),
              ),
              BottomNavigationBarItem(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_outlined, size: 22),
                    if (log.isNotEmpty)
                      Positioned(
                        right: -3, top: -3,
                        child: Container(
                          width: 9, height: 9,
                          decoration: const BoxDecoration(
                              color: Color(0xFFE74C3C), shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                activeIcon: const Icon(Icons.notifications, size: 22),
                label: AppStrings.t('alerts'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 22),
                activeIcon: const Icon(Icons.chat_bubble_rounded, size: 22),
                label: AppStrings.t('chat'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.person_outline_rounded, size: 22),
                activeIcon: const Icon(Icons.person_rounded, size: 22),
                label: AppStrings.t('profile'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: Row(
        children: [
          // ── Left sidebar ─────────────────────────────────────
          _DarkSidebar(
            selectedIndex: _selectedIndex,
            onSelect: (i) => setState(() => _selectedIndex = i),
          ),
          // ── Main content ─────────────────────────────────────
          Expanded(child: _screens[_selectedIndex]),
          // ── Right info panel (dashboard only) ────────────────
          if (_selectedIndex == 0) const _RightInfoPanel(),
        ],
      ),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────
class _DarkSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _DarkSidebar({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, lang, child) => Container(
      width: 240,
      color: AppColors.of(context).sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset('assets/images/ocp_logo.png',
                      fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OCP Group',
                        style: TextStyle(
                            color: AppColors.of(context).textPri,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text('Energy Monitor',
                        style: TextStyle(color: AppColors.of(context).textSec, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
          const SizedBox(height: 16),
          // Nav items
          _SidebarItem(
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard,
            label: AppStrings.t('dashboard'),
            isActive: selectedIndex == 0,
            onTap: () => onSelect(0),
          ),
          _SidebarItem(
            icon: Icons.history_outlined,
            activeIcon: Icons.history,
            label: AppStrings.t('historical'),
            isActive: selectedIndex == 1,
            onTap: () => onSelect(1),
          ),
          _SidebarItem(
            icon: Icons.summarize_outlined,
            activeIcon: Icons.summarize,
            label: AppStrings.t('summary'),
            isActive: selectedIndex == 2,
            onTap: () => onSelect(2),
          ),
          ValueListenableBuilder<List<AlertEntry>>(
            valueListenable: alertLogNotifier,
            builder: (context, log, _) => _SidebarItem(
              icon: Icons.notifications_outlined,
              activeIcon: Icons.notifications,
              label: AppStrings.t('alerts'),
              isActive: selectedIndex == 3,
              onTap: () => onSelect(3),
              badgeCount: log.length,
            ),
          ),
          _SidebarItem(
            icon: Icons.compare_arrows_outlined,
            activeIcon: Icons.compare_arrows,
            label: AppStrings.t('comparison'),
            isActive: selectedIndex == 4,
            onTap: () => onSelect(4),
          ),
          ValueListenableBuilder<String>(
            valueListenable: roleNotifier,
            builder: (context, role, _) =>
                (role == 'viewer' || role == 'observer')
                ? const SizedBox.shrink()
                : _SidebarItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: AppStrings.t('settings'),
                    isActive: selectedIndex == 5,
                    onTap: () => onSelect(5),
                  ),
          ),
          _SidebarItem(
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_rounded,
            label: AppStrings.t('chat'),
            isActive: selectedIndex == 6,
            onTap: () => onSelect(6),
          ),
          _SidebarItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: AppStrings.t('profile'),
            isActive: selectedIndex == 7,
            onTap: () => onSelect(7),
          ),
          ValueListenableBuilder<String>(
            valueListenable: roleNotifier,
            builder: (context, role, _) =>
                (role == 'viewer' || role == 'observer')
                ? const SizedBox.shrink()
                : _SidebarItem(
                    icon: Icons.build_circle_outlined,
                    activeIcon: Icons.build_circle,
                    label: AppStrings.t('maintenance'),
                    isActive: selectedIndex == 8,
                    onTap: () => onSelect(8),
                  ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: roleNotifier,
            builder: (context, role, _) =>
                (role == 'admin' || role == 'moderator')
                ? _SidebarItem(
                    icon: Icons.manage_history_outlined,
                    activeIcon: Icons.manage_history_rounded,
                    label: AppStrings.t('user_logs'),
                    isActive: selectedIndex == 9,
                    onTap: () => onSelect(9),
                  )
                : const SizedBox.shrink(),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: const QuickSettingsBar(),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
          _SidebarItem(
            icon: Icons.logout,
            activeIcon: Icons.logout,
            label: AppStrings.t('logout'),
            isActive: false,
            isDestructive: true,
            onTap: () async {
              await UserLogService.instance.log(action: 'logout', detail: 'Déconnexion');
              await FirebaseAuth.instance.signOut();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    ), // ValueListenableBuilder
    );
  }
}

// ── Quick Settings Bar (theme + language) ─────────────────────────────────────
/// Compact theme toggle + language chips. Usable anywhere.
class QuickSettingsBar extends StatelessWidget {
  const QuickSettingsBar({super.key});

  Future<void> _setLang(String lang) async {
    languageNotifier.value = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
  }

  Future<void> _toggleTheme() async {
    final next = themeNotifier.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeNotifier.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', next == ThemeMode.light ? 'light' : 'dark');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) => ValueListenableBuilder<String>(
        valueListenable: languageNotifier,
        builder: (context, lang, _) {
          final isDark = themeMode == ThemeMode.dark ||
              (themeMode == ThemeMode.system &&
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LangChip(label: 'FR', selected: lang == 'fr', onTap: () => _setLang('fr')),
              const SizedBox(width: 4),
              _LangChip(label: 'EN', selected: lang == 'en', onTap: () => _setLang('en')),
              const SizedBox(width: 4),
              _LangChip(label: 'AR', selected: lang == 'ar', onTap: () => _setLang('ar')),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleTheme,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: kTeal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: kTeal,
                    size: 17,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? kTeal : kTeal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black87 : kTeal,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final bool isDestructive;
  final VoidCallback onTap;
  final int badgeCount;

  const _SidebarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isDestructive = false,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = isDestructive
        ? const Color(0xFFE74C3C)
        : isActive
            ? kTeal
            : c.textSec;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isActive
                ? kTeal.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(isActive ? activeIcon : icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE74C3C),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Right info panel ──────────────────────────────────────────────────────────
class _RightInfoPanel extends StatelessWidget {
  const _RightInfoPanel();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: selectedUnitNotifier,
      builder: (context, unit, child) => Container(
      width: 300,
      color: AppColors.of(context).sidebar,
      child: StreamBuilder(
        stream: FirebaseDatabase.instance
            .ref('$unit/current_metrics')
            .onValue,
        builder: (context, snapshot) {
          EnergyData? data;
          if (snapshot.hasData &&
              snapshot.data!.snapshot.value != null) {
            try {
              data = EnergyData.fromJson(
                  snapshot.data!.snapshot.value as Map<dynamic, dynamic>,
                  unit);
            } catch (_) {}
          }
          return ListView(
            padding: const EdgeInsets.all(0),
            children: [
              // ── Unit card (like profile card) ───────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                child: Column(
                  children: [
                    // Logo circle
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: kTeal.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2)
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Image.asset('assets/images/ocp_logo.png',
                          fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 14),
                    Text('KOFERT JFC3',
                        style: TextStyle(
                            color: AppColors.of(context).textPri,
                            fontWeight: FontWeight.bold,
                            fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(
                      data != null ? 'En ligne  •  Actif' : 'Connexion...',
                      style: TextStyle(
                          color: data != null
                              ? kTeal
                              : AppColors.of(context).textSec,
                          fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    // Stats row (Tension / Courant / FP)
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.of(context).card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _InfoStat(
                              label: 'Tension',
                              value: data != null
                                  ? data.voltage.toStringAsFixed(0)
                                  : '--',
                              unit: 'V'),
                          Container(
                              width: 1,
                              height: 32,
                              color: Colors.white.withValues(alpha: 0.08)),
                          _InfoStat(
                              label: 'Courant',
                              value: data != null
                                  ? data.current.toStringAsFixed(1)
                                  : '--',
                              unit: 'A'),
                          Container(
                              width: 1,
                              height: 32,
                              color: Colors.white.withValues(alpha: 0.08)),
                          _InfoStat(
                              label: 'FP',
                              value: data != null
                                  ? data.powerFactor.toStringAsFixed(2)
                                  : '--',
                              unit: ''),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                  color: Colors.white.withValues(alpha: 0.07), height: 1),
              // ── Alerts / Status (like Scheduled) ───────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Alertes & Statut',
                        style: TextStyle(
                            color: AppColors.of(context).textPri,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ],
                ),
              ),
              _buildAlertItem(
                context,
                title: data != null && !data.hasAlerts
                    ? 'Système Opérationnel'
                    : 'Vérification requise',
                subtitle: data != null
                    ? _getTimestamp(data.timestamp)
                    : 'En attente…',
                icon: data != null && !data.hasAlerts
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: data != null && !data.hasAlerts
                    ? kTeal
                    : const Color(0xFFF5A623),
              ),
              if (data != null && data.hasLowPowerFactor)
                _buildAlertItem(
                  context,
                  title: 'Facteur de puissance bas',
                  subtitle: 'FP = ${data.powerFactor.toStringAsFixed(3)}',
                  icon: Icons.electric_bolt,
                  color: const Color(0xFFE74C3C),
                ),
              if (data != null && (data.hasHighVoltage || data.hasLowVoltage))
                _buildAlertItem(
                  context,
                  title: data.hasHighVoltage ? 'Surtension' : 'Sous-tension',
                  subtitle: '${data.voltage.toStringAsFixed(1)} V détecté',
                  icon: Icons.flash_on,
                  color: const Color(0xFFE74C3C),
                ),
              if (data != null && data.hasHighCurrent)
                _buildAlertItem(
                  context,
                  title: 'Surcharge courant',
                  subtitle: '${data.current.toStringAsFixed(2)} A',
                  icon: Icons.electrical_services,
                  color: const Color(0xFFE74C3C),
                ),
              _buildAlertItem(
                context,
                title: 'Fréquence nominale',
                subtitle: data != null
                    ? '${data.frequency.toStringAsFixed(2)} Hz'
                    : '--',
                icon: Icons.waves,
                color: const Color(0xFF4FC3F7),
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    ), // Container
    ); // ValueListenableBuilder
  }

  Widget _buildAlertItem(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.of(context).card,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: AppColors.of(context).textPri,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style:
                          TextStyle(color: AppColors.of(context).textSec, fontSize: 11)),
                ],
              ),
            ),
            Icon(icon, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  String _getTimestamp(DateTime t) {
    return 'Aujourd\'hui, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _InfoStat(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        Text(
          '$value$unit',
          style: TextStyle(
              color: c.textPri,
              fontWeight: FontWeight.bold,
              fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(color: c.textSec, fontSize: 11)),
      ],
    );
  }
}
