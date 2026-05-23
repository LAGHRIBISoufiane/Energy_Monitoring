library dataconnect_generated;
import 'package:firebase_data_connect/firebase_data_connect.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

part 'create_energy_unit.dart';

part 'record_energy_metric.dart';

part 'create_energy_alert.dart';

part 'resolve_alert.dart';

part 'list_energy_units.dart';

part 'list_energy_metrics.dart';

part 'get_latest_energy_metrics.dart';

part 'get_active_alerts.dart';







class ExampleConnector {
  
  
  CreateEnergyUnitVariablesBuilder createEnergyUnit ({required String id, required String unitName, required String location, required String deviceType, }) {
    return CreateEnergyUnitVariablesBuilder(dataConnect, id: id,unitName: unitName,location: location,deviceType: deviceType,);
  }
  
  
  RecordEnergyMetricVariablesBuilder recordEnergyMetric ({required String unitId, required double voltage, required double current, required double powerFactor, }) {
    return RecordEnergyMetricVariablesBuilder(dataConnect, unitId: unitId,voltage: voltage,current: current,powerFactor: powerFactor,);
  }
  
  
  CreateEnergyAlertVariablesBuilder createEnergyAlert ({required String unitId, required String alertType, required String severity, required String message, }) {
    return CreateEnergyAlertVariablesBuilder(dataConnect, unitId: unitId,alertType: alertType,severity: severity,message: message,);
  }
  
  
  ResolveAlertVariablesBuilder resolveAlert ({required String alertId, }) {
    return ResolveAlertVariablesBuilder(dataConnect, alertId: alertId,);
  }
  
  
  ListEnergyUnitsVariablesBuilder listEnergyUnits () {
    return ListEnergyUnitsVariablesBuilder(dataConnect, );
  }
  
  
  ListEnergyMetricsVariablesBuilder listEnergyMetrics ({required String unitId, }) {
    return ListEnergyMetricsVariablesBuilder(dataConnect, unitId: unitId,);
  }
  
  
  GetLatestEnergyMetricsVariablesBuilder getLatestEnergyMetrics ({required String unitId, }) {
    return GetLatestEnergyMetricsVariablesBuilder(dataConnect, unitId: unitId,);
  }
  
  
  GetActiveAlertsVariablesBuilder getActiveAlerts () {
    return GetActiveAlertsVariablesBuilder(dataConnect, );
  }
  

  static ConnectorConfig connectorConfig = ConnectorConfig(
    'us-east4',
    'example',
    'energymonitoring',
  );

  ExampleConnector({required this.dataConnect});
  static ExampleConnector get instance {
    
    return ExampleConnector(
        dataConnect: FirebaseDataConnect.instanceFor(
            connectorConfig: connectorConfig,
            
            sdkType: CallerSDKType.generated));
  }

  FirebaseDataConnect dataConnect;
}
