import 'package:flutter_test/flutter_test.dart';
import 'package:kofert_dashboard/models/energy_data.dart';
import 'package:kofert_dashboard/services/energy_predictor.dart';
import 'package:kofert_dashboard/utils/energy_format.dart';

void main() {
  group('energy normalization', () {
    test('normalizes mixed Firestore kWh and mWh values', () {
      expect(normalizeStoredEnergyMwh(0.092, 'KOFERT_Unit_1'), 92000);
      expect(normalizeStoredEnergyMwh(92000, 'KOFERT_Unit_1'), 92000);
      expect(normalizeStoredEnergyMwh(0.00292, 'KOFERT_Unit_2'), 2920);
      expect(normalizeStoredEnergyMwh(2920, 'KOFERT_Unit_2'), 2920);
      expect(normalizeStoredEnergyMwh(0.00062, 'KOFERT_Unit_3'), 620);
      expect(normalizeStoredEnergyMwh(620, 'KOFERT_Unit_3'), 620);
    });

    test('parses RTDB kWh and cached mWh without double scaling', () {
      final rtdb = EnergyData.fromJson({
        'voltage': 211.6,
        'current': 0.027,
        'power': 4.9,
        'power_factor': 0.86,
        'energy': 0.092,
        'frequency': 49.9,
        'timestamp': '2026-06-14T22:06:56Z',
      }, 'KOFERT_Unit_1');

      final cache = EnergyData.fromJson({
        'voltage': 211.6,
        'current': 0.027,
        'power': 4.9,
        'power_factor': 0.86,
        'energy_mwh': 92000,
        'energy': 0.092,
        'frequency': 49.9,
        'timestamp': '2026-06-14T22:06:56Z',
        'unit_id': 'KOFERT_Unit_1',
      }, 'KOFERT_Unit_1');

      final oldCache = EnergyData.fromJson({
        'voltage': 211.6,
        'current': 0.027,
        'power': 4.9,
        'power_factor': 0.86,
        'energy': 92000,
        'frequency': 49.9,
        'timestamp': '2026-06-14T22:06:56Z',
        'unit_id': 'KOFERT_Unit_1',
        'apparent_power': 5.71,
      }, 'KOFERT_Unit_1');

      expect(rtdb.energy, 92000);
      expect(cache.energy, 92000);
      expect(oldCache.energy, 92000);
    });

    test('keeps explicit mWh values as mWh', () {
      final reading = EnergyData.fromJson({
        'voltage': 220.1,
        'current': 2.148,
        'power': 1111,
        'power_factor': 0.92,
        'energy': 1407.02,
        'energy_unit': 'mWh',
        'timestamp': '2026-05-28T20:57:33Z',
      }, 'KOFERT_Unit_1');

      expect(reading.energy, closeTo(1407.02, 0.001));
      expect(fmtEnergyUnit(reading.energy, 'kWh'), '0.0014 kWh');
    });

    test('keeps low Unit1 lamp readings but zeros near-zero noise', () {
      final off = EnergyData.fromJson({
        'voltage': 221.0,
        'current': 0.003,
        'power': 0.2,
        'power_factor': 0.83,
        'energy': 0.12,
        'frequency': 50.0,
      }, 'KOFERT_Unit_1');

      final on = EnergyData.fromJson({
        'voltage': 221.0,
        'current': 0.027,
        'power': 4.8,
        'power_factor': 0.85,
        'energy': 0.12,
        'frequency': 50.0,
      }, 'KOFERT_Unit_1');

      expect(off.current, 0);
      expect(off.power, 0);
      expect(off.powerFactor, 0);
      expect(off.voltage, 221.0);
      expect(on.current, 0.027);
      expect(on.power, 4.8);
      expect(on.powerFactor, 0.85);
    });

    test('monthly consumption uses positive cumulative meter delta', () {
      expect(consumptionSinceBaselineMwh(125000, 120000), 5000);
      expect(consumptionSinceBaselineMwh(125000, null), 0);
      expect(consumptionSinceBaselineMwh(1000, 120000), 0);
      expect(sumPositiveEnergyDeltasMwh([1000, 1500, 120, 260]), 640);
    });

    test(
      'monthly consumption keeps Unit2 and Unit3 live value after refresh',
      () {
        expect(
          monthConsumptionWithLiveMwh(
            historyMwh: 5000,
            currentMeterMwh: 5600,
            lastLoggedMeterMwh: 5000,
            historyReadings: 4,
            preferLiveWhenSparse: true,
          ),
          5600,
        );
        expect(
          monthConsumptionWithLiveMwh(
            historyMwh: 5000,
            currentMeterMwh: 300,
            lastLoggedMeterMwh: 5600,
            historyReadings: 4,
            preferLiveWhenSparse: true,
          ),
          5000,
        );
        expect(
          monthConsumptionWithLiveMwh(
            historyMwh: 0,
            currentMeterMwh: 2920,
            lastLoggedMeterMwh: 2920,
            historyReadings: 1,
            preferLiveWhenSparse: true,
          ),
          2920,
        );
      },
    );

    test('daily consumption resets by day but survives tab refresh', () {
      expect(
        periodConsumptionWithLiveMwh(
          historyMwh: 1200,
          currentMeterMwh: 1500,
          lastLoggedMeterMwh: 1200,
          historyReadings: 3,
        ),
        1500,
      );
      expect(
        periodConsumptionWithLiveMwh(
          historyMwh: 1200,
          currentMeterMwh: 100,
          lastLoggedMeterMwh: 1500,
          historyReadings: 4,
          preferLiveWhenSparse: true,
        ),
        1200,
      );
      expect(
        periodConsumptionWithLiveMwh(
          historyMwh: 0,
          currentMeterMwh: 900,
          lastLoggedMeterMwh: 900,
          historyReadings: 1,
          preferLiveWhenSparse: true,
        ),
        900,
      );
    });

    test('falls back to power integration when meter delta is impossible', () {
      final start = DateTime(2026, 5, 28, 8);
      final total = periodConsumptionFromSeriesMwh(
        meterReadingsMwh: [0, 700000000, 1407020000],
        timestamps: [
          start,
          start.add(const Duration(hours: 1)),
          start.add(const Duration(hours: 2)),
        ],
        powersW: [1111, 1111, 1111],
      );

      expect(total, closeTo(2222000, 0.001));
      expect(fmtEnergyUnit(total, 'kWh'), '2.22 kWh');
    });

    test('monthly display is never lower than daily display', () {
      expect(monthAtLeastDayMwh(111000, 115000), 115000);
      expect(monthAtLeastDayMwh(150000, 115000), 150000);
    });
  });

  group('energy predictor', () {
    test('uses cumulative meter deltas for next-day energy', () {
      final now = DateTime.now();
      final data = List.generate(25, (i) {
        return EnergyData(
          unitId: 'KOFERT_Unit_1',
          timestamp: now.subtract(Duration(hours: 24 - i)),
          voltage: 220,
          current: 0.2,
          power: 10,
          powerFactor: 0.9,
          energy: i * 1000,
          frequency: 50,
        );
      });

      final result = EnergyPredictor(tariffRate: 1.15).predict(data);

      expect(result.nextDayEnergyMwh, closeTo(24000, 0.001));
      expect(result.nextDayCost, closeTo(0.0276, 0.0001));
      expect(result.costConfidence, greaterThan(0.7));
    });
  });
}
