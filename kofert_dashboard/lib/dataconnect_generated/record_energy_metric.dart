part of 'generated.dart';

class RecordEnergyMetricVariablesBuilder {
  String unitId;
  double voltage;
  double current;
  double powerFactor;
  Optional<double> _power = Optional.optional(nativeFromJson, nativeToJson);
  Optional<double> _energy = Optional.optional(nativeFromJson, nativeToJson);
  Optional<double> _frequency = Optional.optional(nativeFromJson, nativeToJson);
  Optional<int> _fanSpeed = Optional.optional(nativeFromJson, nativeToJson);
  Optional<int> _waterLevel = Optional.optional(nativeFromJson, nativeToJson);

  final FirebaseDataConnect _dataConnect;  RecordEnergyMetricVariablesBuilder power(double? t) {
   _power.value = t;
   return this;
  }
  RecordEnergyMetricVariablesBuilder energy(double? t) {
   _energy.value = t;
   return this;
  }
  RecordEnergyMetricVariablesBuilder frequency(double? t) {
   _frequency.value = t;
   return this;
  }
  RecordEnergyMetricVariablesBuilder fanSpeed(int? t) {
   _fanSpeed.value = t;
   return this;
  }
  RecordEnergyMetricVariablesBuilder waterLevel(int? t) {
   _waterLevel.value = t;
   return this;
  }

  RecordEnergyMetricVariablesBuilder(this._dataConnect, {required  this.unitId,required  this.voltage,required  this.current,required  this.powerFactor,});
  Deserializer<RecordEnergyMetricData> dataDeserializer = (dynamic json)  => RecordEnergyMetricData.fromJson(jsonDecode(json));
  Serializer<RecordEnergyMetricVariables> varsSerializer = (RecordEnergyMetricVariables vars) => jsonEncode(vars.toJson());
  Future<OperationResult<RecordEnergyMetricData, RecordEnergyMetricVariables>> execute() {
    return ref().execute();
  }

  MutationRef<RecordEnergyMetricData, RecordEnergyMetricVariables> ref() {
    RecordEnergyMetricVariables vars= RecordEnergyMetricVariables(unitId: unitId,voltage: voltage,current: current,powerFactor: powerFactor,power: _power,energy: _energy,frequency: _frequency,fanSpeed: _fanSpeed,waterLevel: _waterLevel,);
    return _dataConnect.mutation("RecordEnergyMetric", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class RecordEnergyMetricEnergyMetricInsert {
  final String id;
  RecordEnergyMetricEnergyMetricInsert.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final RecordEnergyMetricEnergyMetricInsert otherTyped = other as RecordEnergyMetricEnergyMetricInsert;
    return id == otherTyped.id;
    
  }
  @override
  int get hashCode => id.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    return json;
  }

  RecordEnergyMetricEnergyMetricInsert({
    required this.id,
  });
}

@immutable
class RecordEnergyMetricData {
  final RecordEnergyMetricEnergyMetricInsert energyMetric_insert;
  RecordEnergyMetricData.fromJson(dynamic json):
  
  energyMetric_insert = RecordEnergyMetricEnergyMetricInsert.fromJson(json['energyMetric_insert']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final RecordEnergyMetricData otherTyped = other as RecordEnergyMetricData;
    return energyMetric_insert == otherTyped.energyMetric_insert;
    
  }
  @override
  int get hashCode => energyMetric_insert.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['energyMetric_insert'] = energyMetric_insert.toJson();
    return json;
  }

  RecordEnergyMetricData({
    required this.energyMetric_insert,
  });
}

@immutable
class RecordEnergyMetricVariables {
  final String unitId;
  final double voltage;
  final double current;
  final double powerFactor;
  late final Optional<double>power;
  late final Optional<double>energy;
  late final Optional<double>frequency;
  late final Optional<int>fanSpeed;
  late final Optional<int>waterLevel;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  RecordEnergyMetricVariables.fromJson(Map<String, dynamic> json):
  
  unitId = nativeFromJson<String>(json['unitId']),
  voltage = nativeFromJson<double>(json['voltage']),
  current = nativeFromJson<double>(json['current']),
  powerFactor = nativeFromJson<double>(json['powerFactor']) {
  
  
  
  
  
  
    power = Optional.optional(nativeFromJson, nativeToJson);
    power.value = json['power'] == null ? null : nativeFromJson<double>(json['power']);
  
  
    energy = Optional.optional(nativeFromJson, nativeToJson);
    energy.value = json['energy'] == null ? null : nativeFromJson<double>(json['energy']);
  
  
    frequency = Optional.optional(nativeFromJson, nativeToJson);
    frequency.value = json['frequency'] == null ? null : nativeFromJson<double>(json['frequency']);
  
  
    fanSpeed = Optional.optional(nativeFromJson, nativeToJson);
    fanSpeed.value = json['fanSpeed'] == null ? null : nativeFromJson<int>(json['fanSpeed']);
  
  
    waterLevel = Optional.optional(nativeFromJson, nativeToJson);
    waterLevel.value = json['waterLevel'] == null ? null : nativeFromJson<int>(json['waterLevel']);
  
  }
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final RecordEnergyMetricVariables otherTyped = other as RecordEnergyMetricVariables;
    return unitId == otherTyped.unitId && 
    voltage == otherTyped.voltage && 
    current == otherTyped.current && 
    powerFactor == otherTyped.powerFactor && 
    power == otherTyped.power && 
    energy == otherTyped.energy && 
    frequency == otherTyped.frequency && 
    fanSpeed == otherTyped.fanSpeed && 
    waterLevel == otherTyped.waterLevel;
    
  }
  @override
  int get hashCode => Object.hashAll([unitId.hashCode, voltage.hashCode, current.hashCode, powerFactor.hashCode, power.hashCode, energy.hashCode, frequency.hashCode, fanSpeed.hashCode, waterLevel.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['unitId'] = nativeToJson<String>(unitId);
    json['voltage'] = nativeToJson<double>(voltage);
    json['current'] = nativeToJson<double>(current);
    json['powerFactor'] = nativeToJson<double>(powerFactor);
    if(power.state == OptionalState.set) {
      json['power'] = power.toJson();
    }
    if(energy.state == OptionalState.set) {
      json['energy'] = energy.toJson();
    }
    if(frequency.state == OptionalState.set) {
      json['frequency'] = frequency.toJson();
    }
    if(fanSpeed.state == OptionalState.set) {
      json['fanSpeed'] = fanSpeed.toJson();
    }
    if(waterLevel.state == OptionalState.set) {
      json['waterLevel'] = waterLevel.toJson();
    }
    return json;
  }

  RecordEnergyMetricVariables({
    required this.unitId,
    required this.voltage,
    required this.current,
    required this.powerFactor,
    required this.power,
    required this.energy,
    required this.frequency,
    required this.fanSpeed,
    required this.waterLevel,
  });
}

