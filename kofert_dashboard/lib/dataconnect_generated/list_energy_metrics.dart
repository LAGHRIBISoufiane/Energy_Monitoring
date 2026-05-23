part of 'generated.dart';

class ListEnergyMetricsVariablesBuilder {
  String unitId;

  final FirebaseDataConnect _dataConnect;
  ListEnergyMetricsVariablesBuilder(this._dataConnect, {required  this.unitId,});
  Deserializer<ListEnergyMetricsData> dataDeserializer = (dynamic json)  => ListEnergyMetricsData.fromJson(jsonDecode(json));
  Serializer<ListEnergyMetricsVariables> varsSerializer = (ListEnergyMetricsVariables vars) => jsonEncode(vars.toJson());
  Future<QueryResult<ListEnergyMetricsData, ListEnergyMetricsVariables>> execute() {
    return ref().execute();
  }

  QueryRef<ListEnergyMetricsData, ListEnergyMetricsVariables> ref() {
    ListEnergyMetricsVariables vars= ListEnergyMetricsVariables(unitId: unitId,);
    return _dataConnect.query("ListEnergyMetrics", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class ListEnergyMetricsEnergyMetrics {
  final String id;
  final Timestamp timestamp;
  final double voltage;
  final double current;
  final double? power;
  final double? energy;
  final double powerFactor;
  final double? frequency;
  final Timestamp recordedAt;
  ListEnergyMetricsEnergyMetrics.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  timestamp = Timestamp.fromJson(json['timestamp']),
  voltage = nativeFromJson<double>(json['voltage']),
  current = nativeFromJson<double>(json['current']),
  power = json['power'] == null ? null : nativeFromJson<double>(json['power']),
  energy = json['energy'] == null ? null : nativeFromJson<double>(json['energy']),
  powerFactor = nativeFromJson<double>(json['powerFactor']),
  frequency = json['frequency'] == null ? null : nativeFromJson<double>(json['frequency']),
  recordedAt = Timestamp.fromJson(json['recordedAt']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListEnergyMetricsEnergyMetrics otherTyped = other as ListEnergyMetricsEnergyMetrics;
    return id == otherTyped.id && 
    timestamp == otherTyped.timestamp && 
    voltage == otherTyped.voltage && 
    current == otherTyped.current && 
    power == otherTyped.power && 
    energy == otherTyped.energy && 
    powerFactor == otherTyped.powerFactor && 
    frequency == otherTyped.frequency && 
    recordedAt == otherTyped.recordedAt;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, timestamp.hashCode, voltage.hashCode, current.hashCode, power.hashCode, energy.hashCode, powerFactor.hashCode, frequency.hashCode, recordedAt.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['timestamp'] = timestamp.toJson();
    json['voltage'] = nativeToJson<double>(voltage);
    json['current'] = nativeToJson<double>(current);
    if (power != null) {
      json['power'] = nativeToJson<double?>(power);
    }
    if (energy != null) {
      json['energy'] = nativeToJson<double?>(energy);
    }
    json['powerFactor'] = nativeToJson<double>(powerFactor);
    if (frequency != null) {
      json['frequency'] = nativeToJson<double?>(frequency);
    }
    json['recordedAt'] = recordedAt.toJson();
    return json;
  }

  ListEnergyMetricsEnergyMetrics({
    required this.id,
    required this.timestamp,
    required this.voltage,
    required this.current,
    this.power,
    this.energy,
    required this.powerFactor,
    this.frequency,
    required this.recordedAt,
  });
}

@immutable
class ListEnergyMetricsData {
  final List<ListEnergyMetricsEnergyMetrics> energyMetrics;
  ListEnergyMetricsData.fromJson(dynamic json):
  
  energyMetrics = (json['energyMetrics'] as List<dynamic>)
        .map((e) => ListEnergyMetricsEnergyMetrics.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListEnergyMetricsData otherTyped = other as ListEnergyMetricsData;
    return energyMetrics == otherTyped.energyMetrics;
    
  }
  @override
  int get hashCode => energyMetrics.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyMetrics'] = energyMetrics.map((e) => e.toJson()).toList();
    return json;
  }

  ListEnergyMetricsData({
    required this.energyMetrics,
  });
}

@immutable
class ListEnergyMetricsVariables {
  final String unitId;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  ListEnergyMetricsVariables.fromJson(Map<String, dynamic> json):
  
  unitId = nativeFromJson<String>(json['unitId']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final ListEnergyMetricsVariables otherTyped = other as ListEnergyMetricsVariables;
    return unitId == otherTyped.unitId;
    
  }
  @override
  int get hashCode => unitId.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['unitId'] = nativeToJson<String>(unitId);
    return json;
  }

  ListEnergyMetricsVariables({
    required this.unitId,
  });
}

