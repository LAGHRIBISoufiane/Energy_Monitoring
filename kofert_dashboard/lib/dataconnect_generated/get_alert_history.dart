part of 'generated.dart';

class GetAlertHistoryVariablesBuilder {
  String unitId;
  Optional<int> _limit = Optional.optional(nativeFromJson, nativeToJson);

  final FirebaseDataConnect _dataConnect;  GetAlertHistoryVariablesBuilder limit(int? t) {
   _limit.value = t;
   return this;
  }

  GetAlertHistoryVariablesBuilder(this._dataConnect, {required  this.unitId,});
  Deserializer<GetAlertHistoryData> dataDeserializer = (dynamic json)  => GetAlertHistoryData.fromJson(jsonDecode(json));
  Serializer<GetAlertHistoryVariables> varsSerializer = (GetAlertHistoryVariables vars) => jsonEncode(vars.toJson());
  Future<QueryResult<GetAlertHistoryData, GetAlertHistoryVariables>> execute() {
    return ref().execute();
  }

  QueryRef<GetAlertHistoryData, GetAlertHistoryVariables> ref() {
    GetAlertHistoryVariables vars= GetAlertHistoryVariables(unitId: unitId,limit: _limit,);
    return _dataConnect.query("GetAlertHistory", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class GetAlertHistoryEnergyAlerts {
  final String id;
  final String alertType;
  final String severity;
  final String message;
  final bool isResolved;
  final Timestamp createdAt;
  final Timestamp? resolvedAt;
  final String? resolvedByUid;
  GetAlertHistoryEnergyAlerts.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  alertType = nativeFromJson<String>(json['alertType']),
  severity = nativeFromJson<String>(json['severity']),
  message = nativeFromJson<String>(json['message']),
  isResolved = nativeFromJson<bool>(json['isResolved']),
  createdAt = Timestamp.fromJson(json['createdAt']),
  resolvedAt = json['resolvedAt'] == null ? null : Timestamp.fromJson(json['resolvedAt']),
  resolvedByUid = json['resolvedByUid'] == null ? null : nativeFromJson<String>(json['resolvedByUid']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetAlertHistoryEnergyAlerts otherTyped = other as GetAlertHistoryEnergyAlerts;
    return id == otherTyped.id && 
    alertType == otherTyped.alertType && 
    severity == otherTyped.severity && 
    message == otherTyped.message && 
    isResolved == otherTyped.isResolved && 
    createdAt == otherTyped.createdAt && 
    resolvedAt == otherTyped.resolvedAt && 
    resolvedByUid == otherTyped.resolvedByUid;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, alertType.hashCode, severity.hashCode, message.hashCode, isResolved.hashCode, createdAt.hashCode, resolvedAt.hashCode, resolvedByUid.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['alertType'] = nativeToJson<String>(alertType);
    json['severity'] = nativeToJson<String>(severity);
    json['message'] = nativeToJson<String>(message);
    json['isResolved'] = nativeToJson<bool>(isResolved);
    json['createdAt'] = createdAt.toJson();
    if (resolvedAt != null) {
      json['resolvedAt'] = resolvedAt!.toJson();
    }
    if (resolvedByUid != null) {
      json['resolvedByUid'] = nativeToJson<String?>(resolvedByUid);
    }
    return json;
  }

  GetAlertHistoryEnergyAlerts({
    required this.id,
    required this.alertType,
    required this.severity,
    required this.message,
    required this.isResolved,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedByUid,
  });
}

@immutable
class GetAlertHistoryData {
  final List<GetAlertHistoryEnergyAlerts> energyAlerts;
  GetAlertHistoryData.fromJson(dynamic json):
  
  energyAlerts = (json['energyAlerts'] as List<dynamic>)
        .map((e) => GetAlertHistoryEnergyAlerts.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetAlertHistoryData otherTyped = other as GetAlertHistoryData;
    return energyAlerts == otherTyped.energyAlerts;
    
  }
  @override
  int get hashCode => energyAlerts.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyAlerts'] = energyAlerts.map((e) => e.toJson()).toList();
    return json;
  }

  GetAlertHistoryData({
    required this.energyAlerts,
  });
}

@immutable
class GetAlertHistoryVariables {
  final String unitId;
  late final Optional<int>limit;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  GetAlertHistoryVariables.fromJson(Map<String, dynamic> json):
  
  unitId = nativeFromJson<String>(json['unitId']) {
  
  
  
    limit = Optional.optional(nativeFromJson, nativeToJson);
    limit.value = json['limit'] == null ? null : nativeFromJson<int>(json['limit']);
  
  }
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetAlertHistoryVariables otherTyped = other as GetAlertHistoryVariables;
    return unitId == otherTyped.unitId && 
    limit == otherTyped.limit;
    
  }
  @override
  int get hashCode => Object.hashAll([unitId.hashCode, limit.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['unitId'] = nativeToJson<String>(unitId);
    if(limit.state == OptionalState.set) {
      json['limit'] = limit.toJson();
    }
    return json;
  }

  GetAlertHistoryVariables({
    required this.unitId,
    required this.limit,
  });
}

