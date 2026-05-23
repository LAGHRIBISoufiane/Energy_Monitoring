part of 'generated.dart';

class ListEnergyUnitsVariablesBuilder {
  
  final FirebaseDataConnect _dataConnect;
  ListEnergyUnitsVariablesBuilder(this._dataConnect, );
  Deserializer<ListEnergyUnitsData> dataDeserializer = (dynamic json)  => ListEnergyUnitsData.fromJson(jsonDecode(json));
  
  Future<QueryResult<ListEnergyUnitsData, void>> execute() {
    return ref().execute();
  }

  QueryRef<ListEnergyUnitsData, void> ref() {
    
    return _dataConnect.query("ListEnergyUnits", dataDeserializer, emptySerializer, null);
  }
}

@immutable
class ListEnergyUnitsEnergyUnits {
  final String id;
  final String unitName;
  final String location;
  final bool isActive;
  final Timestamp createdAt;
  ListEnergyUnitsEnergyUnits.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  unitName = nativeFromJson<String>(json['unitName']),
  location = nativeFromJson<String>(json['location']),
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

    final ListEnergyUnitsEnergyUnits otherTyped = other as ListEnergyUnitsEnergyUnits;
    return id == otherTyped.id && 
    unitName == otherTyped.unitName && 
    location == otherTyped.location && 
    isActive == otherTyped.isActive && 
    createdAt == otherTyped.createdAt;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, unitName.hashCode, location.hashCode, isActive.hashCode, createdAt.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['unitName'] = nativeToJson<String>(unitName);
    json['location'] = nativeToJson<String>(location);
    json['isActive'] = nativeToJson<bool>(isActive);
    json['createdAt'] = createdAt.toJson();
    return json;
  }

  ListEnergyUnitsEnergyUnits({
    required this.id,
    required this.unitName,
    required this.location,
    required this.isActive,
    required this.createdAt,
  });
}

@immutable
class ListEnergyUnitsData {
  final List<ListEnergyUnitsEnergyUnits> energyUnits;
  ListEnergyUnitsData.fromJson(dynamic json):
  
  energyUnits = (json['energyUnits'] as List<dynamic>)
        .map((e) => ListEnergyUnitsEnergyUnits.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListEnergyUnitsData otherTyped = other as ListEnergyUnitsData;
    return energyUnits == otherTyped.energyUnits;
    
  }
  @override
  int get hashCode => energyUnits.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyUnits'] = energyUnits.map((e) => e.toJson()).toList();
    return json;
  }

  ListEnergyUnitsData({
    required this.energyUnits,
  });
}

