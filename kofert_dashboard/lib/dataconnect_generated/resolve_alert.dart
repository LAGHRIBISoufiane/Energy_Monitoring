part of 'generated.dart';

class ResolveAlertVariablesBuilder {
  String alertId;

  final FirebaseDataConnect _dataConnect;
  ResolveAlertVariablesBuilder(this._dataConnect, {required  this.alertId,});
  Deserializer<ResolveAlertData> dataDeserializer = (dynamic json)  => ResolveAlertData.fromJson(jsonDecode(json));
  Serializer<ResolveAlertVariables> varsSerializer = (ResolveAlertVariables vars) => jsonEncode(vars.toJson());
  Future<OperationResult<ResolveAlertData, ResolveAlertVariables>> execute() {
    return ref().execute();
  }

  MutationRef<ResolveAlertData, ResolveAlertVariables> ref() {
    ResolveAlertVariables vars= ResolveAlertVariables(alertId: alertId,);
    return _dataConnect.mutation("ResolveAlert", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class ResolveAlertEnergyAlertUpdate {
  final String id;
  ResolveAlertEnergyAlertUpdate.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ResolveAlertEnergyAlertUpdate otherTyped = other as ResolveAlertEnergyAlertUpdate;
    return id == otherTyped.id;
    
  }
  @override
  int get hashCode => id.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    return json;
  }

  ResolveAlertEnergyAlertUpdate({
    required this.id,
  });
}

@immutable
class ResolveAlertData {
  final ResolveAlertEnergyAlertUpdate? energyAlert_update;
  ResolveAlertData.fromJson(dynamic json):
  
  energyAlert_update = json['energyAlert_update'] == null ? null : ResolveAlertEnergyAlertUpdate.fromJson(json['energyAlert_update']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ResolveAlertData otherTyped = other as ResolveAlertData;
    return energyAlert_update == otherTyped.energyAlert_update;
    
  }
  @override
  int get hashCode => energyAlert_update.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    if (energyAlert_update != null) {
      json['energyAlert_update'] = energyAlert_update!.toJson();
    }
    return json;
  }

  ResolveAlertData({
    this.energyAlert_update,
  });
}

@immutable
class ResolveAlertVariables {
  final String alertId;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  ResolveAlertVariables.fromJson(Map<String, dynamic> json):
  
  alertId = nativeFromJson<String>(json['alertId']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ResolveAlertVariables otherTyped = other as ResolveAlertVariables;
    return alertId == otherTyped.alertId;
    
  }
  @override
  int get hashCode => alertId.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['alertId'] = nativeToJson<String>(alertId);
    return json;
  }

  ResolveAlertVariables({
    required this.alertId,
  });
}

