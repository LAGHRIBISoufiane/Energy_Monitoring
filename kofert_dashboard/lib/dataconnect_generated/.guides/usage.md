# Basic Usage

```dart
ExampleConnector.instance.CreateEnergyUnit(createEnergyUnitVariables).execute();
ExampleConnector.instance.RecordEnergyMetric(recordEnergyMetricVariables).execute();
ExampleConnector.instance.CreateEnergyAlert(createEnergyAlertVariables).execute();
ExampleConnector.instance.ResolveAlert(resolveAlertVariables).execute();
ExampleConnector.instance.ListEnergyUnits().execute();
ExampleConnector.instance.ListEnergyMetrics(listEnergyMetricsVariables).execute();
ExampleConnector.instance.GetLatestEnergyMetrics(getLatestEnergyMetricsVariables).execute();
ExampleConnector.instance.GetActiveAlerts().execute();
ExampleConnector.instance.GetAlertHistory(getAlertHistoryVariables).execute();
ExampleConnector.instance.GetMetricsByDateRange(getMetricsByDateRangeVariables).execute();

```

## Optional Fields

Some operations may have optional fields. In these cases, the Flutter SDK exposes a builder method, and will have to be set separately.

Optional fields can be discovered based on classes that have `Optional` object types.

This is an example of a mutation with an optional field:

```dart
await ExampleConnector.instance.GetAlertHistory({ ... })
.limit(...)
.execute();
```

Note: the above example is a mutation, but the same logic applies to query operations as well. Additionally, `createMovie` is an example, and may not be available to the user.

