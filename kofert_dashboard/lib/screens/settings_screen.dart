import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import '../main.dart' show kTeal, themeNotifier, selectedUnitNotifier, browserNotifNotifier, roleNotifier;
import '../l10n/app_strings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppColors get _c => AppColors.of(context);
  bool _alertsEnabled = true;
  bool _browserNotifEnabled = false;
  double _tariffRate = 1.15;
  double _voltageThresholdHigh = 250.0;
  double _voltageThresholdLow = 200.0;
  double _currentThreshold = 50.0;
  double _powerFactorThreshold = 0.8;
  bool _autoRefresh = true;
  int _refreshInterval = 5; // seconds
  String _themeMode = 'system';
  String _language = 'fr';
  String _selectedUnit = 'KOFERT_Unit_1';
  final List<String> _availableUnits = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _alertsEnabled = prefs.getBool('alertsEnabled') ?? true;
      _browserNotifEnabled = prefs.getBool('browserNotifEnabled') ?? false;
      _tariffRate = prefs.getDouble('tariffRate') ?? 1.15;
      _voltageThresholdHigh = prefs.getDouble('voltageThresholdHigh') ?? 250.0;
      _voltageThresholdLow = prefs.getDouble('voltageThresholdLow') ?? 200.0;
      _currentThreshold = prefs.getDouble('currentThreshold') ?? 50.0;
      _powerFactorThreshold = prefs.getDouble('powerFactorThreshold') ?? 0.8;
      _autoRefresh = prefs.getBool('autoRefresh') ?? true;
      _refreshInterval = prefs.getInt('refreshInterval') ?? 5;
      _themeMode = prefs.getString('themeMode') ?? 'system';
      _language = prefs.getString('language') ?? 'fr';
      _selectedUnit = prefs.getString('selectedUnit') ?? 'KOFERT_Unit_1';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alertsEnabled', _alertsEnabled);
    await prefs.setBool('browserNotifEnabled', _browserNotifEnabled);
    browserNotifNotifier.value = _browserNotifEnabled;
    await prefs.setDouble('tariffRate', _tariffRate);
    await prefs.setDouble('voltageThresholdHigh', _voltageThresholdHigh);
    await prefs.setDouble('voltageThresholdLow', _voltageThresholdLow);
    await prefs.setDouble('currentThreshold', _currentThreshold);
    await prefs.setDouble('powerFactorThreshold', _powerFactorThreshold);
    await prefs.setBool('autoRefresh', _autoRefresh);
    await prefs.setInt('refreshInterval', _refreshInterval);
    await prefs.setString('themeMode', _themeMode);
    await prefs.setString('language', _language);
    await prefs.setString('selectedUnit', _selectedUnit);
    // Apply live notifiers
    themeNotifier.value = _themeMode == 'light'
        ? ThemeMode.light
        : _themeMode == 'system'
            ? ThemeMode.system
            : ThemeMode.dark;
    languageNotifier.value = _language;
    selectedUnitNotifier.value = _selectedUnit;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paramètres sauvegardés')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _c.bg,
      body: Column(
        children: [
          Container(
            color: _c.card,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                const Text('Paramètres', style: TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.bold, fontSize: 18)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.save_outlined, color: kTeal),
                  onPressed: _saveSettings,
                  tooltip: 'Sauvegarder',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Alerts Section — admin & moderator only
          if (roleNotifier.value == 'admin' || roleNotifier.value == 'moderator')
          _buildSection(
            'Alertes',
            Icons.warning,
            AppTheme.warningYellow,
            [
              SwitchListTile(
                title: const Text('Activer les alertes'),
                subtitle: const Text('Recevoir des notifications en cas d\'anomalie'),
                value: _alertsEnabled,
                onChanged: (value) {
                  setState(() {
                    _alertsEnabled = value;
                  });
                },
              ),
              SwitchListTile(
                title: Text(AppStrings.t('browser_notif')),
                subtitle: Text(AppStrings.t('sensor_offline')),
                secondary: const Icon(Icons.notifications_active_outlined),
                value: _browserNotifEnabled,
                onChanged: (value) {
                  setState(() => _browserNotifEnabled = value);
                  if (value && html.Notification.supported) {
                    html.Notification.requestPermission();
                  }
                },
              ),
              const SizedBox(height: 16),
              _buildThresholdSlider(
                'Seuil tension haute',
                _voltageThresholdHigh,
                220.0,
                280.0,
                'V',
                (value) {
                  setState(() {
                    _voltageThresholdHigh = value;
                  });
                },
              ),
              _buildThresholdSlider(
                'Seuil tension basse',
                _voltageThresholdLow,
                180.0,
                220.0,
                'V',
                (value) {
                  setState(() {
                    _voltageThresholdLow = value;
                  });
                },
              ),
              _buildThresholdSlider(
                'Seuil courant',
                _currentThreshold,
                10.0,
                100.0,
                'A',
                (value) {
                  setState(() {
                    _currentThreshold = value;
                  });
                },
              ),
              _buildThresholdSlider(
                'Seuil facteur de puissance',
                _powerFactorThreshold,
                0.5,
                0.95,
                '',
                (value) {
                  setState(() {
                    _powerFactorThreshold = value;
                  });
                },
              ),
            ],
          ),
          if (roleNotifier.value == 'admin' || roleNotifier.value == 'moderator')
          const SizedBox(height: 24),
          
          // Monitoring Units Section — admin, moderator & operator
          _buildSection(
            'Unités de Surveillance',
            Icons.location_on,
            AppTheme.secondaryOrange,
            [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButton<String>(
                    value: _selectedUnit,
                    isExpanded: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.expand_more, color: AppTheme.primaryNavy),
                    items: _availableUnits.map((unit) {
                      return DropdownMenuItem<String>(
                        value: unit,
                        child: Text(unit),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedUnit = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sélectionnez l\'unité KOFERT à surveiller',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.darkGray.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Tariff / Display / Info — admin & moderator only
          if (roleNotifier.value == 'admin' || roleNotifier.value == 'moderator') ...[          
          _buildSection(
            'Tarif Électrique',
            Icons.payments_outlined,
            kTeal,
            [
              _buildThresholdSlider(
                'Tarif (MAD/mWh)',
                _tariffRate,
                0.5,
                5.0,
                'MAD',
                (value) => setState(() => _tariffRate = value),
              ),
              const Text(
                'Utilisé pour calculer le coût estimé de la consommation.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Display Section
          _buildSection(
            'Affichage',
            Icons.display_settings,
            AppTheme.primaryNavy,
            [
              SwitchListTile(
                title: const Text('Actualisation automatique'),
                subtitle: const Text('Mettre à jour les données automatiquement'),
                value: _autoRefresh,
                onChanged: (value) {
                  setState(() {
                    _autoRefresh = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Intervalle d\'actualisation'),
                subtitle: Text('$_refreshInterval secondes'),
                trailing: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButton<int>(
                    value: _refreshInterval,
                    underline: const SizedBox(),
                    icon: Icon(Icons.expand_more, color: AppTheme.primaryNavy, size: 20),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1s')),
                      DropdownMenuItem(value: 5, child: Text('5s')),
                      DropdownMenuItem(value: 10, child: Text('10s')),
                      DropdownMenuItem(value: 30, child: Text('30s')),
                      DropdownMenuItem(value: 60, child: Text('1m')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _refreshInterval = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Thème'),
                subtitle: Text(_getThemeModeLabel()),
                trailing: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButton<String>(
                    value: _themeMode,
                    underline: const SizedBox(),
                    icon: Icon(Icons.expand_more, color: AppTheme.primaryNavy, size: 20),
                    items: const [
                      DropdownMenuItem(value: 'system', child: Text('Sys')),
                      DropdownMenuItem(value: 'light', child: Text('Clair')),
                      DropdownMenuItem(value: 'dark', child: Text('Sombre')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _themeMode = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Langue'),
                subtitle: Text(_getLanguageLabel()),
                trailing: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButton<String>(
                    value: _language,
                    underline: const SizedBox(),
                    icon: Icon(Icons.expand_more, color: AppTheme.primaryNavy, size: 20),
                    items: const [
                      DropdownMenuItem(value: 'fr', child: Text('FR')),
                      DropdownMenuItem(value: 'en', child: Text('EN')),
                      DropdownMenuItem(value: 'ar', child: Text('AR')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _language = value;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Information Section
          _buildSection(
            'Informations',
            Icons.info,
            AppTheme.infoBlue,
            [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Version'),
                subtitle: const Text('1.0.0'),
                trailing: Icon(Icons.check_circle, color: AppTheme.successGreen),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('À propos'),
                subtitle: const Text('OCP - KOFERT Energy Monitor'),
                trailing: Icon(Icons.business, color: AppTheme.primaryNavy),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _resetSettings,
                icon: const Icon(Icons.restore),
                label: const Text('Réinitialiser les paramètres'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorRed,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          ], // end admin/moderator only sections
        ],
      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    IconData icon,
    Color iconColor,
    List<Widget> children,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildThresholdSlider(
    String title,
    double value,
    double min,
    double max,
    String unit,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.darkGray,
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                '${value.toStringAsFixed(1)} $unit',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryNavy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 10).toInt(),
          onChanged: onChanged,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _getThemeModeLabel() {
    switch (_themeMode) {
      case 'light':
        return 'Clair';
      case 'dark':
        return 'Sombre';
      default:
        return 'Système';
    }
  }

  String _getLanguageLabel() {
    switch (_language) {
      case 'en':
        return 'English';
      case 'ar':
        return 'العربية';
      default:
        return 'Français';
    }
  }

  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la réinitialisation'),
        content: const Text('Tous les paramètres seront remis à leurs valeurs par défaut. Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _loadSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paramètres réinitialisés')),
        );
      }
    }
  }
}
