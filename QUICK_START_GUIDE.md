# KOFERT Energy Monitoring Dashboard - Quick Start Guide

## Running the Application

### Prerequisites
- Windows 10/11 or macOS/Linux
- Flutter SDK 3.40+
- Microsoft Edge/Chrome/Firefox browser
- Firebase account with configured project

### Installation

1. **Navigate to dashboard directory:**
   ```bash
   cd kofert_dashboard
   ```

2. **Get dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the web app:**
   ```bash
   flutter run -d web
   ```

   The app will automatically open in your default browser at `http://localhost:port`

---

## Dashboard Features Guide

### 1. Dashboard Screen (Home)
![Dashboard Interface]

**What You See:**
- Power Factor gauge (0-1 scale) with real-time value
- Quick metric cards:
  - Power (W) - Watts
  - Voltage (V) - Volts
  - Current (A) - Amperes
  - Energy (kWh) - Kilowatt-hours
  - Frequency (Hz) - Frequency
- Alert banner (red, appears if anomalies detected)

**Alert Badge:**
- Red badge in AppBar top-right showing count of active alerts
- Updates in real-time as thresholds are breached/resolved

**Current Metrics Source:**
- Firebase Realtime Database: `KOFERT_Unit_1/current_metrics`

---

### 2. Historical Data Screen

#### Features:
✅ **Date Range Filter**
- Click calendar icons to select start/end dates
- Default: Last 7 days
- Click refresh icon to reset to today

✅ **Metric Selection**
- Dropdown menu to choose metric to analyze
- Options:
  - Puissance (Power) - Watts
  - Tension (Voltage) - Volts
  - Courant (Current) - Amperes
  - Énergie (Energy) - kWh
  - Facteur de Puissance (Power Factor)
  - Fréquence (Frequency) - Hz

✅ **Data Visualization**
- Line chart showing metric evolution
- Chart updates based on selected metric and date range
- Tooltip on hover for exact values

✅ **Statistics**
- Minimum value
- Maximum value
- Average value
- All relative to selected date range

✅ **Data table**
- Lists latest measurements
- Shows timestamp and selected metric value
- Sorted by recency (newest first)

#### Export Data:

**CSV Export:**
1. Click the download menu (three dots) in app bar
2. Select "Exporter CSV"
3. Preview appears with filename and entry count
4. Click "Copier" to copy to clipboard
5. Paste into spreadsheet or text editor

CSV Format:
```
Timestamp,Power (W),Voltage (V),Current (A),Energy (kWh),Power Factor,Frequency (Hz)
2026-04-12 14:30:45,2400.5,230.2,10.43,125.8,0.92,50.0
```

**JSON Export:**
1. Click the download menu
2. Select "Exporter JSON"
3. Structured format with metadata
4. Click "Copier" to copy

JSON Format:
```json
{
  "unit": "KOFERT_Unit_1",
  "date_range": {
    "start": "2026-04-05",
    "end": "2026-04-12"
  },
  "total_records": 156,
  "data": [
    {
      "timestamp": "2026-04-12 14:30:45",
      "power_w": 2400.5,
      "voltage_v": 230.2,
      ...
    }
  ]
}
```

---

### 3. Settings Screen (Paramètres)

#### Alert Configuration:
**Enable/Disable Alerts:**
- Toggle "Activer les alertes" to turn alerts on/off
- When disabled, alert badge disappears from dashboard

**Voltage Thresholds:**
- Seuil tension haute (High): Default 250V, range 220-280V
- Seuil tension basse (Low): Default 200V, range 180-220V
- Alert triggered if voltage exceeds high or drops below low

**Current Threshold:**
- Seuil courant: Default 50A, range 10-100A
- Alert triggered if current exceeds threshold

**Power Factor Threshold:**
- Seuil facteur de puissance: Default 0.7, range 0.5-0.95
- Alert triggered if power factor drops below threshold

#### Display Settings:
**Auto-Refresh:**
- Toggle "Actualisation automatique"
- Select refresh interval: 1s, 5s, 10s, 30s, 1 min

**Theme:**
- Système (follow OS setting)
- Clair (Light mode)
- Sombre (Dark mode)

**Language:**
- Français (French) - Default
- English
- العربية (Arabic)

#### Unit Selection:
**Monitor Multiple Units:**
- Dropdown: "Sélectionnez l'unité KOFERT à surveiller"
- Available options:
  - KOFERT_Unit_1 (Default)
  - KOFERT_Unit_2
  - KOFERT_Unit_3

**Note:** Unit switching is configured but requires backend integration

#### Save Settings:
- Click "💾 Icône" button in AppBar (top-right)
- Confirmation message appears
- All settings persist to device storage

---

## Understanding the Alerts

### Alert Types:

| Condition | Threshold | Action |
|-----------|-----------|--------|
| Voltage Too High | > 250V | Red alert |
| Voltage Too Low | < 200V | Red alert |
| Current Exceeded | > 50A | Red alert |
| Power Factor Low | < 0.7 | Red alert |

### Alert Badge:
```
Badge Shows:  🚨 3
├─ 1 x Voltage alert
├─ 1 x Current alert
└─ 1 x Power factor alert
```

---

## Using the Data Export

### When to Export:
- Regular reports for management
- Data analysis in Excel
- Compliance documentation
- Performance audits
- Trend investigation

### How to Share:
1. Export to CSV or JSON
2. Click "Copier"
3. Paste into email or document
4. Share or upload to cloud storage

### Common Use Cases:

**Weekly Report:**
1. Go to Historical screen
2. Set date range: Last 7 days
3. Select "Power" metric
4. Export as CSV
5. Copy into Excel
6. Create a summary chart

**Anomaly Investigation:**
1. Set date range around incident
2. Select relevant metric (usually Voltage or Current)
3. Analyze statistics (min, max, avg)
4. Export for technical analysis

**Compliance Audit:**
1. Set date range for audit period
2. Export alljson metrics
3. Share JSON file with auditors
4. Includes timestamp for regulatory proof

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Alt + D` | Go to Dashboard |
| `Alt + H` | Go to Historical |
| `Alt + S` | Go to Settings |
| `Ctrl + R` | Refresh current screen |

---

## Troubleshooting

### Issue: App not loading
**Solution:** 
- Clear browser cache (Ctrl+Shift+Delete)
- Restart Flutter: `flutter run -d web -v`

### Issue: Real-time data not updating
**Solution:**
- Check Firebase connection
- Verify database rules allow read access
- Check internet connectivity

### Issue: Export button not working
**Solution:**
- Ensure date range contains data
- Try selecting a wider date range
- Refresh the page (F5)

### Issue: Settings not saving
**Solution:**
- Check browser's local storage settings
- Clear browser data and retry
- Try a different browser

### Issue: Alert badge shows but no alert banner
**Solution:**
- Check "Alertes" is enabled in Settings
- Adjust thresholds if data is within acceptable range
- View Settings to modify thresholds

---

## Performance Tips

1. **Best Experience:**
   - Use Microsoft Edge or Chrome
   - Set refresh interval to 5-10 seconds
   - Close unused tabs

2. **Mobile Use:**
   - Landscape orientation recommended
   - Touch-friendly date picker
   - Responsive design adapts to screen size

3. **Large Data Sets:**
   - Export limits to last 500 records
   - For longer periods, export multiple times
   - Use narrower date ranges for analysis

---

## Understanding the Interface

### Colors & Icons:
- **Blue:** Primary color, metrics, normal state
- **Green:** Voltage metric
- **Orange:** Current metric
- **Purple:** Energy metric
- **Red:** Alert/warning state
- **🔄 Refresh:** Reload/reset
- **📊 Download:** Export data
- **⚙️ Settings:** Configuration

### Data Units:
```
W  = Watts (Power)
V  = Volts (Voltage)
A  = Amperes (Current)
kWh = Kilowatt-hours (Energy)
Hz = Hertz (Frequency)
```

---

## Next Features (Coming Soon)

- 📍 Multi-unit dashboard view
- 📈 Advanced analytics and predictions
- 📧 Email alerts
- 🔔 Push notifications
- 📱 Mobile app
- 🌐 Cloud synchronization
- 👥 User management and roles

---

## Support & Documentation

**For Issues:**
- Check DEPLOYMENT_STATUS.md for system status
- Review error messages in browser console (F12)
- Check Firebase configuration in firebase_options.dart

**Project Directories:**
- Dashboard code: `./lib/screens/` and `./lib/widgets/`
- Models: `./lib/models/energy_data.dart`
- Configuration: `./firebase_options.dart`
- Dependencies: `./pubspec.yaml`

---

**Last Updated:** April 12, 2026  
**Version:** 1.0.0  
**Language:** Français/English
