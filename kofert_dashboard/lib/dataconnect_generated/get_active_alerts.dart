part of 'generated.dart';

class GetActiveAlertsVariablesBuilder {
  
  final FirebaseDataConnect _dataConnect;
  GetActiveAlertsVariablesBuilder(this._dataConnect, );
  Deserializer<GetActiveAlertsData> dataDeserializer = (dynamic json)  => GetActiveAlertsData.fromJson(jsonDecode(json));
  
  Future<QueryResult<GetActiveAlertsData, void>> execute() {
    return ref().execute();
  }

  QueryRef<GetActiveAlertsData, void> ref() {
    
    return _dataConnect.query("GetActiveAlerts", dataDeserializer, emptySerializer, null);
  }
}

@immutable
class GetActiveAlertsEnergyAlerts {
  final String id;
  final String alertType;
  final String severity;
  final String message;
  final Timestamp createdAt;
  GetActiveAlertsEnergyAlerts.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  alertType = nativeFromJson<String>(json['alertType']),
  severity = nativeFromJson<String>(json['severity']),
  message = nativeFromJson<String>(json['message']),
  createdAt = Timestamp.fromJson(json['createdAt']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetActiveAlertsEnergyAlerts otherTyped = other as GetActiveAlertsEnergyAlerts;
    return id == otherTyped.id && 
    alertType == otherTyped.alertType && 
    severity == otherTyped.severity && 
    message == otherTyped.message && 
    createdAt == otherTyped.createdAt;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, alertType.hashCode, severity.hashCode, message.hashCode, createdAt.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['alertType'] = nativeToJson<String>(alertType);
    json['severity'] = nativeToJson<String>(severity);
    json['message'] = nativeToJson<String>(message);
    json['createdAt'] = createdAt.toJson();
    return json;
  }

  GetActiveAlertsEnergyAlerts({
    required this.id,
    required this.alertType,
    required this.severity,
    required this.message,
    required this.createdAt,
  });
}

@immutable
class GetActiveAlertsData {
  final List<GetActiveAlertsEnergyAlerts> energyAlerts;
  GetActiveAlertsData.fromJson(dynamic json):
  
  energyAlerts = (json['energyAlerts'] as List<dynamic>)
        .map((e) => GetActiveAlertsEnergyAlerts.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetActiveAlertsData otherTyped = other as GetActiveAlertsData;
    return energyAlerts == otherTyped.energyAlerts;
    
  }
  @override
  int get hashCode => energyAlerts.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyAlerts'] = energyAlerts.map((e) => e.toJson()).toList();
    return json;
  }

  GetActiveAlertsData({
    required this.energyAlerts,
  });
}

