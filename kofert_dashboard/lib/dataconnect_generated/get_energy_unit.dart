part of 'generated.dart';

class GetEnergyUnitVariablesBuilder {
  String unitId;

  final FirebaseDataConnect _dataConnect;
  GetEnergyUnitVariablesBuilder(this._dataConnect, {required  this.unitId,});
  Deserializer<GetEnergyUnitData> dataDeserializer = (dynamic json)  => GetEnergyUnitData.fromJson(jsonDecode(json));
  Serializer<GetEnergyUnitVariables> varsSerializer = (GetEnergyUnitVariables vars) => jsonEncode(vars.toJson());
  Future<QueryResult<GetEnergyUnitData, GetEnergyUnitVariables>> execute() {
    return ref().execute();
  }

  QueryRef<GetEnergyUnitData, GetEnergyUnitVariables> ref() {
    GetEnergyUnitVariables vars= GetEnergyUnitVariables(unitId: unitId,);
    return _dataConnect.query("GetEnergyUnit", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class GetEnergyUnitEnergyUnit {
  final String id;
  final String unitName;
  final String location;
  final String deviceType;
  final bool isActive;
  final Timestamp createdAt;
  GetEnergyUnitEnergyUnit.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  unitName = nativeFromJson<String>(json['unitName']),
  location = nativeFromJson<String>(json['location']),
  deviceType = nativeFromJson<String>(json['deviceType']),
  isActive = nativeFromJson<bool>(json['isActive']),
  createdAt = Timestamp.fromJson(json['createdAt']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetEnergyUnitEnergyUnit otherTyped = other as GetEnergyUnitEnergyUnit;
    return id == otherTyped.id && 
    unitName == otherTyped.unitName && 
    location == otherTyped.location && 
    deviceType == otherTyped.deviceType && 
    isActive == otherTyped.isActive && 
    createdAt == otherTyped.createdAt;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, unitName.hashCode, location.hashCode, deviceType.hashCode, isActive.hashCode, createdAt.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['unitName'] = nativeToJson<String>(unitName);
    json['location'] = nativeToJson<String>(location);
    json['deviceType'] = nativeToJson<String>(deviceType);
    json['isActive'] = nativeToJson<bool>(isActive);
    json['createdAt'] = createdAt.toJson();
    return json;
  }

  GetEnergyUnitEnergyUnit({
    required this.id,
    required this.unitName,
    required this.location,
    required this.deviceType,
    required this.isActive,
    required this.createdAt,
  });
}

@immutable
class GetEnergyUnitData {
  final GetEnergyUnitEnergyUnit? energyUnit;
  GetEnergyUnitData.fromJson(dynamic json):
  
  energyUnit = json['energyUnit'] == null ? null : GetEnergyUnitEnergyUnit.fromJson(json['energyUnit']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetEnergyUnitData otherTyped = other as GetEnergyUnitData;
    return energyUnit == otherTyped.energyUnit;
    
  }
  @override
  int get hashCode => energyUnit.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    if (energyUnit != null) {
      json['energyUnit'] = energyUnit!.toJson();
    }
    return json;
  }

  GetEnergyUnitData({
    this.energyUnit,
  });
}

@immutable
class GetEnergyUnitVariables {
  final String unitId;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  GetEnergyUnitVariables.fromJson(Map<String, dynamic> json):
  
  unitId = nativeFromJson<String>(json['unitId']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetEnergyUnitVariables otherTyped = other as GetEnergyUnitVariables;
    return unitId == otherTyped.unitId;
    
  }
  @override
  int get hashCode => unitId.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['unitId'] = nativeToJson<String>(unitId);
    return json;
  }

  GetEnergyUnitVariables({
    required this.unitId,
  });
}

