part of 'generated.dart';

class CreateEnergyUnitVariablesBuilder {
  String id;
  String unitName;
  String location;
  String deviceType;

  final FirebaseDataConnect _dataConnect;
  CreateEnergyUnitVariablesBuilder(this._dataConnect, {required  this.id,required  this.unitName,required  this.location,required  this.deviceType,});
  Deserializer<CreateEnergyUnitData> dataDeserializer = (dynamic json)  => CreateEnergyUnitData.fromJson(jsonDecode(json));
  Serializer<CreateEnergyUnitVariables> varsSerializer = (CreateEnergyUnitVariables vars) => jsonEncode(vars.toJson());
  Future<OperationResult<CreateEnergyUnitData, CreateEnergyUnitVariables>> execute() {
    return ref().execute();
  }

  MutationRef<CreateEnergyUnitData, CreateEnergyUnitVariables> ref() {
    CreateEnergyUnitVariables vars= CreateEnergyUnitVariables(id: id,unitName: unitName,location: location,deviceType: deviceType,);
    return _dataConnect.mutation("CreateEnergyUnit", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class CreateEnergyUnitEnergyUnitInsert {
  final String id;
  CreateEnergyUnitEnergyUnitInsert.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateEnergyUnitEnergyUnitInsert otherTyped = other as CreateEnergyUnitEnergyUnitInsert;
    return id == otherTyped.id;
    
  }
  @override
  int get hashCode => id.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    return json;
  }

  CreateEnergyUnitEnergyUnitInsert({
    required this.id,
  });
}

@immutable
class CreateEnergyUnitData {
  final CreateEnergyUnitEnergyUnitInsert energyUnit_insert;
  CreateEnergyUnitData.fromJson(dynamic json):
  
  energyUnit_insert = CreateEnergyUnitEnergyUnitInsert.fromJson(json['energyUnit_insert']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateEnergyUnitData otherTyped = other as CreateEnergyUnitData;
    return energyUnit_insert == otherTyped.energyUnit_insert;
    
  }
  @override
  int get hashCode => energyUnit_insert.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyUnit_insert'] = energyUnit_insert.toJson();
    return json;
  }

  CreateEnergyUnitData({
    required this.energyUnit_insert,
  });
}

@immutable
class CreateEnergyUnitVariables {
  final String id;
  final String unitName;
  final String location;
  final String deviceType;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  CreateEnergyUnitVariables.fromJson(Map<String, dynamic> json):
  
  id = nativeFromJson<String>(json['id']),
  unitName = nativeFromJson<String>(json['unitName']),
  location = nativeFromJson<String>(json['location']),
  deviceType = nativeFromJson<String>(json['deviceType']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateEnergyUnitVariables otherTyped = other as CreateEnergyUnitVariables;
    return id == otherTyped.id && 
    unitName == otherTyped.unitName && 
    location == otherTyped.location && 
    deviceType == otherTyped.deviceType;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, unitName.hashCode, location.hashCode, deviceType.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['unitName'] = nativeToJson<String>(unitName);
    json['location'] = nativeToJson<String>(location);
    json['deviceType'] = nativeToJson<String>(deviceType);
    return json;
  }

  CreateEnergyUnitVariables({
    required this.id,
    required this.unitName,
    required this.location,
    required this.deviceType,
  });
}

