part of 'generated.dart';

class GetMetricsByDateRangeVariablesBuilder {
  String unitId;
  Timestamp startDate;
  Timestamp endDate;

  final FirebaseDataConnect _dataConnect;
  GetMetricsByDateRangeVariablesBuilder(this._dataConnect, {required  this.unitId,required  this.startDate,required  this.endDate,});
  Deserializer<GetMetricsByDateRangeData> dataDeserializer = (dynamic json)  => GetMetricsByDateRangeData.fromJson(jsonDecode(json));
  Serializer<GetMetricsByDateRangeVariables> varsSerializer = (GetMetricsByDateRangeVariables vars) => jsonEncode(vars.toJson());
  Future<QueryResult<GetMetricsByDateRangeData, GetMetricsByDateRangeVariables>> execute() {
    return ref().execute();
  }

  QueryRef<GetMetricsByDateRangeData, GetMetricsByDateRangeVariables> ref() {
    GetMetricsByDateRangeVariables vars= GetMetricsByDateRangeVariables(unitId: unitId,startDate: startDate,endDate: endDate,);
    return _dataConnect.query("GetMetricsByDateRange", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class GetMetricsByDateRangeEnergyMetrics {
  final String id;
  final Timestamp timestamp;
  final double voltage;
  final double current;
  final double? power;
  final double? energy;
  final double powerFactor;
  final double? frequency;
  final int? fanSpeed;
  final int? waterLevel;
  final Timestamp recordedAt;
  GetMetricsByDateRangeEnergyMetrics.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  timestamp = Timestamp.fromJson(json['timestamp']),
  voltage = nativeFromJson<double>(json['voltage']),
  current = nativeFromJson<double>(json['current']),
  power = json['power'] == null ? null : nativeFromJson<double>(json['power']),
  energy = json['energy'] == null ? null : nativeFromJson<double>(json['energy']),
  powerFactor = nativeFromJson<double>(json['powerFactor']),
  frequency = json['frequency'] == null ? null : nativeFromJson<double>(json['frequency']),
  fanSpeed = json['fanSpeed'] == null ? null : nativeFromJson<int>(json['fanSpeed']),
  waterLevel = json['waterLevel'] == null ? null : nativeFromJson<int>(json['waterLevel']),
  recordedAt = Timestamp.fromJson(json['recordedAt']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetMetricsByDateRangeEnergyMetrics otherTyped = other as GetMetricsByDateRangeEnergyMetrics;
    return id == otherTyped.id && 
    timestamp == otherTyped.timestamp && 
    voltage == otherTyped.voltage && 
    current == otherTyped.current && 
    power == otherTyped.power && 
    energy == otherTyped.energy && 
    powerFactor == otherTyped.powerFactor && 
    frequency == otherTyped.frequency && 
    fanSpeed == otherTyped.fanSpeed && 
    waterLevel == otherTyped.waterLevel && 
    recordedAt == otherTyped.recordedAt;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, timestamp.hashCode, voltage.hashCode, current.hashCode, power.hashCode, energy.hashCode, powerFactor.hashCode, frequency.hashCode, fanSpeed.hashCode, waterLevel.hashCode, recordedAt.hashCode]);
  

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
    if (fanSpeed != null) {
      json['fanSpeed'] = nativeToJson<int?>(fanSpeed);
    }
    if (waterLevel != null) {
      json['waterLevel'] = nativeToJson<int?>(waterLevel);
    }
    json['recordedAt'] = recordedAt.toJson();
    return json;
  }

  GetMetricsByDateRangeEnergyMetrics({
    required this.id,
    required this.timestamp,
    required this.voltage,
    required this.current,
    this.power,
    this.energy,
    required this.powerFactor,
    this.frequency,
    this.fanSpeed,
    this.waterLevel,
    required this.recordedAt,
  });
}

@immutable
class GetMetricsByDateRangeData {
  final List<GetMetricsByDateRangeEnergyMetrics> energyMetrics;
  GetMetricsByDateRangeData.fromJson(dynamic json):
  
  energyMetrics = (json['energyMetrics'] as List<dynamic>)
        .map((e) => GetMetricsByDateRangeEnergyMetrics.fromJson(e))
        .toList();
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetMetricsByDateRangeData otherTyped = other as GetMetricsByDateRangeData;
    return energyMetrics == otherTyped.energyMetrics;
    
  }
  @override
  int get hashCode => energyMetrics.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyMetrics'] = energyMetrics.map((e) => e.toJson()).toList();
    return json;
  }

  GetMetricsByDateRangeData({
    required this.energyMetrics,
  });
}

@immutable
class GetMetricsByDateRangeVariables {
  final String unitId;
  final Timestamp startDate;
  final Timestamp endDate;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  GetMetricsByDateRangeVariables.fromJson(Map<String, dynamic> json):
  
  unitId = nativeFromJson<String>(json['unitId']),
  startDate = Timestamp.fromJson(json['startDate']),
  endDate = Timestamp.fromJson(json['endDate']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetMetricsByDateRangeVariables otherTyped = other as GetMetricsByDateRangeVariables;
    return unitId == otherTyped.unitId && 
    startDate == otherTyped.startDate && 
    endDate == otherTyped.endDate;
    
  }
  @override
  int get hashCode => Object.hashAll([unitId.hashCode, startDate.hashCode, endDate.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['unitId'] = nativeToJson<String>(unitId);
    json['startDate'] = startDate.toJson();
    json['endDate'] = endDate.toJson();
    return json;
  }

  GetMetricsByDateRangeVariables({
    required this.unitId,
    required this.startDate,
    required this.endDate,
  });
}

