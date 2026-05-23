part of 'generated.dart';

class GetLatestEnergyMetricsVariablesBuilder {
  String unitId;

  final FirebaseDataConnect _dataConnect;
  GetLatestEnergyMetricsVariablesBuilder(this._dataConnect, {required  this.unitId,});
  Deserializer<GetLatestEnergyMetricsData> dataDeserializer = (dynamic json)  => GetLatestEnergyMetricsData.fromJson(jsonDecode(json));
  Serializer<GetLatestEnergyMetricsVariables> varsSerializer = (GetLatestEnergyMetricsVariables vars) => jsonEncode(vars.toJson());
  Future<QueryResult<GetLatestEnergyMetricsData, GetLatestEnergyMetricsVariables>> execute() {
    return ref().execute();
  }

  QueryRef<GetLatestEnergyMetricsData, GetLatestEnergyMetricsVariables> ref() {
    GetLatestEnergyMetricsVariables vars= GetLatestEnergyMetricsVariables(unitId: unitId,);
    return _dataConnect.query("GetLatestEnergyMetrics", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class GetLatestEnergyMetricsEnergyMetrics {
  final String id;
  final Timestamp timestamp;
  final double voltage;
  final double current;
  final double? power;
  final double? energy;
  final double powerFactor;
  final double? frequency;
  GetLatestEnergyMetricsEnergyMetrics.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  timestamp = Timestamp.fromJson(json['timestamp']),
  voltage = nativeFromJson<double>(json['voltage']),
  current = nativeFromJson<double>(json['current']),
  power = json['power'] == null ? null : nativeFromJson<double>(json['power']),
  energy = json['energy'] == null ? null : nativeFromJson<double>(json['energy']),
  powerFactor = nativeFromJson<double>(json['powerFactor']),
  frequency = json['frequency'] == null ? null : nativeFromJson<double>(json['frequency']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetLatestEnergyMetricsEnergyMetrics otherTyped = other as GetLatestEnergyMetricsEnergyMetrics;
    return id == otherTyped.id && 
    timestamp == otherTyped.timestamp && 
    voltage == otherTyped.voltage && 
    current == otherTyped.current && 
    power == otherTyped.power && 
    energy == otherTyped.energy && 
    powerFactor == otherTyped.powerFactor && 
    frequency == otherTyped.frequency;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, timestamp.hashCode, voltage.hashCode, current.hashCode, power.hashCode, energy.hashCode, powerFactor.hashCode, frequency.hashCode]);
  

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
    return json;
  }

  GetLatestEnergyMetricsEnergyMetrics({
    required this.id,
    required this.timestamp,
    required this.voltage,
    required this.current,
    this.power,
    this.energy,
    required this.powerFactor,
    this.frequency,
  });
}

@immutable
class GetLatestEnergyMetricsData {
  final List<GetLatestEnergyMetricsEnergyMetrics> energyMetrics;
  GetLatestEnergyMetricsData.fromJson(dynamic json):
  
  energyMetrics = (json['energyMetrics'] as List<dynamic>)
        .map((e) => GetLatestEnergyMetricsEnergyMetrics.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetLatestEnergyMetricsData otherTyped = other as GetLatestEnergyMetricsData;
    return energyMetrics == otherTyped.energyMetrics;
    
  }
  @override
  int get hashCode => energyMetrics.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyMetrics'] = energyMetrics.map((e) => e.toJson()).toList();
    return json;
  }

  GetLatestEnergyMetricsData({
    required this.energyMetrics,
  });
}

@immutable
class GetLatestEnergyMetricsVariables {
  final String unitId;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  GetLatestEnergyMetricsVariables.fromJson(Map<String, dynamic> json):
  
  unitId = nativeFromJson<String>(json['unitId']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetLatestEnergyMetricsVariables otherTyped = other as GetLatestEnergyMetricsVariables;
    return unitId == otherTyped.unitId;
    
  }
  @override
  int get hashCode => unitId.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['unitId'] = nativeToJson<String>(unitId);
    return json;
  }

  GetLatestEnergyMetricsVariables({
    required this.unitId,
  });
}

