import 'package:flutter/material.dart';

/// Public alert entry — shared by DashboardScreen and AlertHistoryScreen.
class AlertEntry {
  final String title;
  final String detail;
  final Color color;
  final DateTime time;
  final String unitId;

  AlertEntry({
    required this.title,
    required this.detail,
    required this.color,
    required this.time,
    required this.unitId,
  });
}
