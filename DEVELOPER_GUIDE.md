# Developer Setup & Maintenance Guide

## Project Architecture

```
Energy_Monitoring/
├── kofert_dashboard/          # Main Flutter web app (PRODUCTION)
│   ├── lib/
│   │   ├── main.dart          # App entry point
│   │   ├── screens/           # UI screens (dashboard, historical, settings)
│   │   ├── widgets/           # Reusable components
│   │   ├── models/            # Data models
│   │   ├── firebase_options.dart
│   │   └── dataconnect_generated/  # Auto-generated GraphQL SDKs
│   ├── pubspec.yaml           # Dependencies
│   └── web/                   # Web configuration
├── dataconnect/               # Firebase Data Connect backend
│   ├── dataconnect.yaml       # Service configuration
│   ├── schema/                # PostgreSQL schema definitions
│   ├── example/               # GraphQL queries & mutations
│   └── seed_data.gql          # Test data
├── flutter/                   # Flutter framework (development)
└── firebase.json              # Firebase project config
```

---

## Development Environment Setup

### 1. Install Required Tools

```bash
# Flutter SDK
# Download from: https://flutter.dev/docs/get-started/install
flutter doctor  # Verify installation

# Firebase CLI (already installed)
npx firebase --version

# Code Editor (VS Code recommended)
code .
```

### 2. Install Flutter Extensions

**VS Code Extensions:**
- Flutter (Dart Code)
- Dart (Dart Code)
- Firebase Explorer
- REST Client

```bash
# Or via command line:
code --install-extension Dart-Code.flutter
code --install-extension Dart-Code.dart-code
```

### 3. Clone and Setup Project

```bash
cd c:\Users\riosh\Documents\Energy_Monitoring
cd kofert_dashboard

# Get dependencies
flutter pub get

# Run on web
flutter run -d web

# Or run with specific configuration
flutter run -d web --release  # Production build
flutter run -d web --debug    # Debug mode with hot reload
```

---

## Project Dependencies

### Core Dependencies (pubspec.yaml):

```yaml
flutter: ^3.41.6
firebase_core: ^3.15.0
firebase_database: ^11.3.8
firebase_data_connect: ^0.1.5        # Data Connect SDK

syncfusion_flutter_gauges: ^33.1.47   # Power Factor gauge
syncfusion_flutter_charts: ^33.1.47   # Historical charts

shared_preferences: ^2.3.0            # Local settings storage
intl: ^0.19.0                         # Date formatting
```

### Update Dependencies:
```bash
flutter pub upgrade              # Update to latest compatible versions
flutter pub upgrade --major-versions  # Including major version changes
```

---

## Code Structure

### Main.dart
Entry point for the app. Initializes Firebase and sets up Material theme.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const KofertDashboard());
}
```

### Screens

#### DashboardScreen (dashboard_screen.dart)
- Real-time metrics via StreamBuilder
- Power factor gauge visualization
- Alert banner display
- Status card with unit information
- Real-time alert count badge

**Data Source:** Firebase Realtime Database (`KOFERT_Unit_1/current_metrics`)

**Key Methods:**
- `_updateAlertCount()` - Calculates active alerts based on thresholds
- `_loadAlertSettings()` - Loads user-configured thresholds
- `_buildPowerFactorGauge()` - Renders gauge widget
- `_getAlertMessage()` - Formats alert text

#### HistoricalScreen (historical_screen.dart) ✅
- Historical data visualization with charts
- Date range filtering
- Metric selection dropdown
- Statistics calculation (min, max, avg)
- CSV/JSON data export

**Data Source:** Firebase Realtime Database (`KOFERT_Unit_1/historical_data`)

**Key Methods:**
- `_applyDateFilter()` - Filters data by date range
- `_exportToCSV()` - Generates CSV format
- `_exportToJSON()` - Generates JSON format
- `_showExportDialog()` - Displays export preview

#### SettingsScreen (settings_screen.dart) ✅
- Alert threshold configuration
- Display preferences (theme, language)
- Unit selection
- Auto-refresh settings

**Data Storage:** SharedPreferences (local device storage)

**Key Methods:**
- `_loadSettings()` - Retrieves saved preferences
- `_saveSettings()` - Persists settings to device
- `_resetSettings()` - Returns to defaults

### Models

#### EnergyData (models/energy_data.dart)
Main data model for energy metrics.

```dart
class EnergyData {
  final String unitId;
  final DateTime timestamp;
  final double power;
  final double voltage;
  final double current;
  final double energy;
  final double powerFactor;
  final double frequency;
  final bool hasAlerts;

  factory EnergyData.fromJson(Map<dynamic, dynamic> json, String unitId) {
    // Parse Firebase data into EnergyData object
  }
}
```

**Key Methods:**
- `fromJson()` - Parses Firebase JSON
- `hasAlerts()` - Checks if thresholds exceeded
- Properties for each metric

### Widgets

#### MetricCard (widgets/metric_card.dart)
Reusable card for displaying a single metric.

```dart
MetricCard(
  label: 'Puissance',
  value: data.power,
  unit: 'W',
  icon: Icons.power,
  color: Colors.blue,
)
```

#### AlertBanner (widgets/alert_banner.dart)
Alert notification UI component.

```dart
AlertBanner(
  message: 'Anomalies détectées',
  type: AlertType.warning,
)
```

---

## Firebase Integration

### Configuration

**firebase_options.dart** - Auto-generated, contains:
```dart
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return web; // or android, ios, windows, etc.
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '...',
    appId: '...',
    messagingSenderId: '...',
    projectId: 'energymonitoring-fdc',
    // ...
  );
}
```

### Database Structure

```
energymonitoring-fdc (Firebase Realtime Database)
├── KOFERT_Unit_1/
│   ├── current_metrics/
│   │   ├── power: 2400.5
│   │   ├── voltage: 230.2
│   │   ├── current: 10.43
│   │   ├── energy: 125.8
│   │   ├── powerFactor: 0.92
│   │   ├── frequency: 50.0
│   │   └── timestamp: 1712976645000
│   └── historical_data/
│       ├── metric_1/
│       ├── metric_2/
│       └── ...
├── KOFERT_Unit_2/
└── KOFERT_Unit_3/
```

### Reading Data

**Real-Time Stream:**
```dart
_dbRef.onValue.listen((event) {
  if (event.snapshot.exists) {
    final data = event.snapshot.value as Map;
    final energyData = EnergyData.fromJson(data, 'KOFERT_Unit_1');
    setState(() => _currentData = energyData);
  }
});
```

**One-Time Read:**
```dart
final snapshot = await _dbRef.get();
if (snapshot.exists) {
  // Process data
}
```

---

## Data Connect Integration (Future)

### Current Status: Blocked
The backend is configured but deployment requires Firebase CLI support for `firebase data-connect deploy`.

### Schema Definition (schema/schema.gql)

```graphql
type EnergyUnit {
  id: String!
  name: String!
  location: String
  installDate: Date
  createdAt: DateTime!
  updatedAt: DateTime!
}

type EnergyMetric {
  id: String!
  unitId: String! @foreignKey(table: "EnergyUnit")
  timestamp: DateTime!
  power: Float!
  voltage: Float!
  current: Float!
  energy: Float!
  powerFactor: Float!
  frequency: Float!
}

type EnergyAlert {
  id: String!
  unitId: String! @foreignKey(table: "EnergyUnit")
  type: String!
  severity: String!
  message: String!
  createdAt: DateTime!
  resolvedAt: DateTime
}
```

### When Deployed - SDK Usage

```dart
// Generated by Data Connect
import 'dataconnect_generated/generated.dart';

// Initialize
final client = DataConnectClient();

// Execute queries
final response = await client.listEnergyUnits();

// Execute mutations
await client.registerEnergyUnit(
  name: 'New Unit',
  location: 'Building A',
);
```

---

## Building & Deployment

### Local Testing

```bash
# Debug mode (with hot reload)
flutter run -d web

# Release build (optimized)
flutter run -d web --release

# Run with specific browser
flutter run -d web -d chrome    # Chrome
flutter run -d web -d edge      # Edge
```

### Performance Analysis

```bash
# Generate performance report
flutter run -d web --profile

# Run with timeline events
flutter run -d web --trace-startup
```

### Web Build

```bash
# Generate production build
flutter build web --release

# Output directory: ./build/web/
# Deploy to:
# - Firebase Hosting
# - Cloud Run
# - App Engine
# - Custom server
```

---

## Testing

### Unit Tests

Create tests in `test/` directory:

```dart
// test/models/energy_data_test.dart
void main() {
  test('EnergyData parses JSON correctly', () {
    final json = {
      'power': 2400.5,
      'voltage': 230.2,
      // ...
    };
    final data = EnergyData.fromJson(json, 'KOFERT_Unit_1');
    expect(data.power, 2400.5);
  });
}
```

Run tests:
```bash
flutter test              # Run all tests
flutter test test/file_test.dart  # Specific file
```

### Widget Tests

```dart
testWidgets('DashboardScreen displays metrics', (WidgetTester tester) async {
  await tester.pumpWidget(const KofertDashboard());
  expect(find.text('Puissance'), findsOneWidget);
});
```

---

## Debugging

### Enable Debug Mode

```bash
# Run with verbose logging
flutter run -d web -v

# Enable Dart DevTools
flutter pub global activate devtools
devtools
```

### Browser DevTools

Press `F12` in the browser to open developer console:
- **Console:** JavaScript errors and logs
- **Network:** API calls and bandwidth
- **Sources:** Code debugging
- **Application:** Local storage, preferences

### Common Issues

**Issue:** Hot reload not working
**Solution:** 
```bash
flutter run -d web --no-fast-start
```

**Issue:** Widget not updating
**Solution:** Wrap in `setState()`:
```dart
setState(() {
  _variable = newValue;
});
```

**Issue:** Firebase connection refused
**Solution:** Check:
- Internet connectivity
- Firebase project credentials
- Database rules allow read/write
- Realtime Database is enabled in Firebase Console

---

## Code Quality

### Analysis

```bash
# Check for issues
flutter analyze

# Format code
dart format lib/
flutter format lib/
```

### Linting Rules

Configure in `analysis_options.yaml`:
```yaml
linter:
  rules:
    - prefer_const_constructors
    - prefer_const_declarations
    - avoid_empty_else
    - avoid_print
```

---

## Version Control

### Recommended Workflow

```bash
# Create feature branch
git checkout -b feature/new-feature

# Make changes
git add .
git commit -m "Add new feature"

# Push and create PR
git push origin feature/new-feature

# Merge after review
git checkout main
git merge feature/new-feature
```

### Ignore Files (.gitignore)

```
build/
.dart_tool/
.flutter-plugins
.packages
*.lock
.DS_Store
.env
```

---

## Maintenance Tasks

### Regular Updates

```bash
# Check for outdated packages
flutter pub outdated

# Update packages (safe)
flutter pub upgrade

# Update Flutter SDK
flutter upgrade
```

### Performance Monitoring

Monitor these metrics:
- App load time (< 3 seconds)
- Frame rate (60 FPS on web)
- Memory usage (< 100MB)
- API response time (< 1 second)

### Backup & Recovery

```bash
# Backup Firebase data
firebase database:get / > backup.json

# Restore Firebase data
firebase database:set / < backup.json
```

---

## Troubleshooting Common Issues

### Flutter Web Issues

| Issue | Solution |
|-------|----------|
| CORS error | Check Firebase CORS policy in Firebase Console |
| Web canvas black | Clear browser cache, restart Flutter |
| Build fails | `flutter clean`, then `flutter pub get` |
| Hot reload slow | Reduce project size, close other browsers |

### Firebase Issues

| Issue | Solution |
|-------|----------|
| Permission denied | Check Realtime Database rules |
| Data not syncing | Verify internet connection, check timestamps |
| Quota exceeded | Check Firebase usage in console |

---

## Contributing Guidelines

1. **Fork & Create Branch:** `feature/description`
2. **Follow Dart Style Guide:** Run `dart format`
3. **Write Tests:** 80%+ code coverage
4. **Document Changes:** Update README if needed
5. **Submit PR:** Include description and testing notes

---

## Resources

- **Flutter Docs:** https://flutter.dev/docs
- **Firebase:** https://firebase.google.com/docs
- **Dart Language:** https://dart.dev/guides
- **Syncfusion:** https://www.syncfusion.com/flutter-widgets
- **Material Design:** https://material.io/design

---

**Last Updated:** April 12, 2026  
**Maintainer:** Development Team  
**Version:** 1.0.0
