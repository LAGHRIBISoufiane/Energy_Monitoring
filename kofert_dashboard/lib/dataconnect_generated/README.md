# dataconnect_generated SDK

## Installation
```sh
flutter pub get firebase_data_connect
flutterfire configure
```
For more information, see [Flutter for Firebase installation documentation](https://firebase.google.com/docs/data-connect/flutter-sdk#use-core).

## Data Connect instance
Each connector creates a static class, with an instance of the `DataConnect` class that can be used to connect to your Data Connect backend and call operations.

### Connecting to the emulator

```dart
String host = 'localhost'; // or your host name
int port = 9399; // or your port number
ExampleConnector.instance.dataConnect.useDataConnectEmulator(host, port);
```

You can also call queries and mutations by using the connector class.
## Queries

### ListEnergyUnits
#### Required Arguments
```dart
// No required arguments
ExampleConnector.instance.listEnergyUnits().execute();
```



#### Return Type
`execute()` returns a `QueryResult<ListEnergyUnitsData, void>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

/// Result of a query request. Created to hold extra variables in the future.
class QueryResult<Data, Variables> extends OperationResult<Data, Variables> {
  QueryResult(super.dataConnect, super.data, super.ref);
}

final result = await ExampleConnector.instance.listEnergyUnits();
ListEnergyUnitsData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
final ref = ExampleConnector.instance.listEnergyUnits().ref();
ref.execute();

ref.subscribe(...);
```


### ListEnergyMetrics
#### Required Arguments
```dart
String unitId = ...;
ExampleConnector.instance.listEnergyMetrics(
  unitId: unitId,
).execute();
```



#### Return Type
`execute()` returns a `QueryResult<ListEnergyMetricsData, ListEnergyMetricsVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

/// Result of a query request. Created to hold extra variables in the future.
class QueryResult<Data, Variables> extends OperationResult<Data, Variables> {
  QueryResult(super.dataConnect, super.data, super.ref);
}

final result = await ExampleConnector.instance.listEnergyMetrics(
  unitId: unitId,
);
ListEnergyMetricsData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String unitId = ...;

final ref = ExampleConnector.instance.listEnergyMetrics(
  unitId: unitId,
).ref();
ref.execute();

ref.subscribe(...);
```


### GetLatestEnergyMetrics
#### Required Arguments
```dart
String unitId = ...;
ExampleConnector.instance.getLatestEnergyMetrics(
  unitId: unitId,
).execute();
```



#### Return Type
`execute()` returns a `QueryResult<GetLatestEnergyMetricsData, GetLatestEnergyMetricsVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

/// Result of a query request. Created to hold extra variables in the future.
class QueryResult<Data, Variables> extends OperationResult<Data, Variables> {
  QueryResult(super.dataConnect, super.data, super.ref);
}

final result = await ExampleConnector.instance.getLatestEnergyMetrics(
  unitId: unitId,
);
GetLatestEnergyMetricsData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String unitId = ...;

final ref = ExampleConnector.instance.getLatestEnergyMetrics(
  unitId: unitId,
).ref();
ref.execute();

ref.subscribe(...);
```


### GetActiveAlerts
#### Required Arguments
```dart
// No required arguments
ExampleConnector.instance.getActiveAlerts().execute();
```



#### Return Type
`execute()` returns a `QueryResult<GetActiveAlertsData, void>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

/// Result of a query request. Created to hold extra variables in the future.
class QueryResult<Data, Variables> extends OperationResult<Data, Variables> {
  QueryResult(super.dataConnect, super.data, super.ref);
}

final result = await ExampleConnector.instance.getActiveAlerts();
GetActiveAlertsData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
final ref = ExampleConnector.instance.getActiveAlerts().ref();
ref.execute();

ref.subscribe(...);
```


### GetAlertHistory
#### Required Arguments
```dart
String unitId = ...;
ExampleConnector.instance.getAlertHistory(
  unitId: unitId,
).execute();
```

#### Optional Arguments
We return a builder for each query. For GetAlertHistory, we created `GetAlertHistoryBuilder`. For queries and mutations with optional parameters, we return a builder class.
The builder pattern allows Data Connect to distinguish between fields that haven't been set and fields that have been set to null. A field can be set by calling its respective setter method like below:
```dart
class GetAlertHistoryVariablesBuilder {
  ...
   GetAlertHistoryVariablesBuilder limit(int? t) {
   _limit.value = t;
   return this;
  }

  ...
}
ExampleConnector.instance.getAlertHistory(
  unitId: unitId,
)
.limit(limit)
.execute();
```

#### Return Type
`execute()` returns a `QueryResult<GetAlertHistoryData, GetAlertHistoryVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

/// Result of a query request. Created to hold extra variables in the future.
class QueryResult<Data, Variables> extends OperationResult<Data, Variables> {
  QueryResult(super.dataConnect, super.data, super.ref);
}

final result = await ExampleConnector.instance.getAlertHistory(
  unitId: unitId,
);
GetAlertHistoryData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String unitId = ...;

final ref = ExampleConnector.instance.getAlertHistory(
  unitId: unitId,
).ref();
ref.execute();

ref.subscribe(...);
```


### GetMetricsByDateRange
#### Required Arguments
```dart
String unitId = ...;
Timestamp startDate = ...;
Timestamp endDate = ...;
ExampleConnector.instance.getMetricsByDateRange(
  unitId: unitId,
  startDate: startDate,
  endDate: endDate,
).execute();
```



#### Return Type
`execute()` returns a `QueryResult<GetMetricsByDateRangeData, GetMetricsByDateRangeVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

/// Result of a query request. Created to hold extra variables in the future.
class QueryResult<Data, Variables> extends OperationResult<Data, Variables> {
  QueryResult(super.dataConnect, super.data, super.ref);
}

final result = await ExampleConnector.instance.getMetricsByDateRange(
  unitId: unitId,
  startDate: startDate,
  endDate: endDate,
);
GetMetricsByDateRangeData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String unitId = ...;
Timestamp startDate = ...;
Timestamp endDate = ...;

final ref = ExampleConnector.instance.getMetricsByDateRange(
  unitId: unitId,
  startDate: startDate,
  endDate: endDate,
).ref();
ref.execute();

ref.subscribe(...);
```


### GetEnergyUnit
#### Required Arguments
```dart
String unitId = ...;
ExampleConnector.instance.getEnergyUnit(
  unitId: unitId,
).execute();
```



#### Return Type
`execute()` returns a `QueryResult<GetEnergyUnitData, GetEnergyUnitVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

/// Result of a query request. Created to hold extra variables in the future.
class QueryResult<Data, Variables> extends OperationResult<Data, Variables> {
  QueryResult(super.dataConnect, super.data, super.ref);
}

final result = await ExampleConnector.instance.getEnergyUnit(
  unitId: unitId,
);
GetEnergyUnitData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String unitId = ...;

final ref = ExampleConnector.instance.getEnergyUnit(
  unitId: unitId,
).ref();
ref.execute();

ref.subscribe(...);
```

## Mutations

### CreateEnergyUnit
#### Required Arguments
```dart
String id = ...;
String unitName = ...;
String location = ...;
String deviceType = ...;
ExampleConnector.instance.createEnergyUnit(
  id: id,
  unitName: unitName,
  location: location,
  deviceType: deviceType,
).execute();
```



#### Return Type
`execute()` returns a `OperationResult<CreateEnergyUnitData, CreateEnergyUnitVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

final result = await ExampleConnector.instance.createEnergyUnit(
  id: id,
  unitName: unitName,
  location: location,
  deviceType: deviceType,
);
CreateEnergyUnitData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String id = ...;
String unitName = ...;
String location = ...;
String deviceType = ...;

final ref = ExampleConnector.instance.createEnergyUnit(
  id: id,
  unitName: unitName,
  location: location,
  deviceType: deviceType,
).ref();
ref.execute();
```


### RecordEnergyMetric
#### Required Arguments
```dart
String unitId = ...;
double voltage = ...;
double current = ...;
double powerFactor = ...;
ExampleConnector.instance.recordEnergyMetric(
  unitId: unitId,
  voltage: voltage,
  current: current,
  powerFactor: powerFactor,
).execute();
```

#### Optional Arguments
We return a builder for each query. For RecordEnergyMetric, we created `RecordEnergyMetricBuilder`. For queries and mutations with optional parameters, we return a builder class.
The builder pattern allows Data Connect to distinguish between fields that haven't been set and fields that have been set to null. A field can be set by calling its respective setter method like below:
```dart
class RecordEnergyMetricVariablesBuilder {
  ...
   RecordEnergyMetricVariablesBuilder power(double? t) {
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

  ...
}
ExampleConnector.instance.recordEnergyMetric(
  unitId: unitId,
  voltage: voltage,
  current: current,
  powerFactor: powerFactor,
)
.power(power)
.energy(energy)
.frequency(frequency)
.fanSpeed(fanSpeed)
.waterLevel(waterLevel)
.execute();
```

#### Return Type
`execute()` returns a `OperationResult<RecordEnergyMetricData, RecordEnergyMetricVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

final result = await ExampleConnector.instance.recordEnergyMetric(
  unitId: unitId,
  voltage: voltage,
  current: current,
  powerFactor: powerFactor,
);
RecordEnergyMetricData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String unitId = ...;
double voltage = ...;
double current = ...;
double powerFactor = ...;

final ref = ExampleConnector.instance.recordEnergyMetric(
  unitId: unitId,
  voltage: voltage,
  current: current,
  powerFactor: powerFactor,
).ref();
ref.execute();
```


### CreateEnergyAlert
#### Required Arguments
```dart
String unitId = ...;
String alertType = ...;
String severity = ...;
String message = ...;
ExampleConnector.instance.createEnergyAlert(
  unitId: unitId,
  alertType: alertType,
  severity: severity,
  message: message,
).execute();
```



#### Return Type
`execute()` returns a `OperationResult<CreateEnergyAlertData, CreateEnergyAlertVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

final result = await ExampleConnector.instance.createEnergyAlert(
  unitId: unitId,
  alertType: alertType,
  severity: severity,
  message: message,
);
CreateEnergyAlertData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String unitId = ...;
String alertType = ...;
String severity = ...;
String message = ...;

final ref = ExampleConnector.instance.createEnergyAlert(
  unitId: unitId,
  alertType: alertType,
  severity: severity,
  message: message,
).ref();
ref.execute();
```


### ResolveAlert
#### Required Arguments
```dart
String alertId = ...;
ExampleConnector.instance.resolveAlert(
  alertId: alertId,
).execute();
```



#### Return Type
`execute()` returns a `OperationResult<ResolveAlertData, ResolveAlertVariables>`
```dart
/// Result of an Operation Request (query/mutation).
class OperationResult<Data, Variables> {
  OperationResult(this.dataConnect, this.data, this.ref);
  Data data;
  OperationRef<Data, Variables> ref;
  FirebaseDataConnect dataConnect;
}

final result = await ExampleConnector.instance.resolveAlert(
  alertId: alertId,
);
ResolveAlertData data = result.data;
final ref = result.ref;
```

#### Getting the Ref
Each builder returns an `execute` function, which is a helper function that creates a `Ref` object, and executes the underlying operation.
An example of how to use the `Ref` object is shown below:
```dart
String alertId = ...;

final ref = ExampleConnector.instance.resolveAlert(
  alertId: alertId,
).ref();
ref.execute();
```

