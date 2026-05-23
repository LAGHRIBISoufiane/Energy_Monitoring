part of 'generated.dart';

class CreateEnergyAlertVariablesBuilder {
  String unitId;
  String alertType;
  String severity;
  String message;

  final FirebaseDataConnect _dataConnect;
  CreateEnergyAlertVariablesBuilder(this._dataConnect, {required  this.unitId,required  this.alertType,required  this.severity,required  this.message,});
  Deserializer<CreateEnergyAlertData> dataDeserializer = (dynamic json)  => CreateEnergyAlertData.fromJson(jsonDecode(json));
  Serializer<CreateEnergyAlertVariables> varsSerializer = (CreateEnergyAlertVariables vars) => jsonEncode(vars.toJson());
  Future<OperationResult<CreateEnergyAlertData, CreateEnergyAlertVariables>> execute() {
    return ref().execute();
  }

  MutationRef<CreateEnergyAlertData, CreateEnergyAlertVariables> ref() {
    CreateEnergyAlertVariables vars= CreateEnergyAlertVariables(unitId: unitId,alertType: alertType,severity: severity,message: message,);
    return _dataConnect.mutation("CreateEnergyAlert", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class CreateEnergyAlertEnergyAlertInsert {
  final String id;
  CreateEnergyAlertEnergyAlertInsert.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateEnergyAlertEnergyAlertInsert otherTyped = other as CreateEnergyAlertEnergyAlertInsert;
    return id == otherTyped.id;
    
  }
  @override
  int get hashCode => id.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    return json;
  }

  CreateEnergyAlertEnergyAlertInsert({
    required this.id,
  });
}

@immutable
class CreateEnergyAlertData {
  final CreateEnergyAlertEnergyAlertInsert energyAlert_insert;
  CreateEnergyAlertData.fromJson(dynamic json):
  
  energyAlert_insert = CreateEnergyAlertEnergyAlertInsert.fromJson(json['energyAlert_insert']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateEnergyAlertData otherTyped = other as CreateEnergyAlertData;
    return energyAlert_insert == otherTyped.energyAlert_insert;
    
  }
  @override
  int get hashCode => energyAlert_insert.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyAlert_insert'] = energyAlert_insert.toJson();
    return json;
  }

  CreateEnergyAlertData({
    required this.energyAlert_insert,
  });
}

@immutable
class CreateEnergyAlertVariables {
  final String unitId;
  final String alertType;
  final String severity;
  final String message;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  CreateEnergyAlertVariables.fromJson(Map<String, dynamic> json):
  
  unitId = nativeFromJson<String>(json['unitId']),
  alertType = nativeFromJson<String>(json['alertType']),
  severity = nativeFromJson<String>(json['severity']),
  message = nativeFromJson<String>(json['message']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateEnergyAlertVariables otherTyped = other as CreateEnergyAlertVariables;
    return unitId == otherTyped.unitId && 
    alertType == otherTyped.alertType && 
    severity == otherTyped.severity && 
    message == otherTyped.message;
    
  }
  @override
  int get hashCode => Object.hashAll([unitId.hashCode, alertType.hashCode, severity.hashCode, message.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['unitId'] = nativeToJson<String>(unitId);
    json['alertType'] = nativeToJson<String>(alertType);
    json['severity'] = nativeToJson<String>(severity);
    json['message'] = nativeToJson<String>(message);
    return json;
  }

  CreateEnergyAlertVariables({
    required this.unitId,
    required this.alertType,
    required this.severity,
    required this.message,
  });
}

