# Firebase Data Connect Deployment Guide

## Current Status

**Prerequisites Met:**
- ✅ Firebase project created: `energymonitoring-fdc`
- ✅ Cloud SQL instance: `energymonitoring-fdc` (PostgreSQL)
- ✅ PostgreSQL database: `fdcdb`
- ✅ Data Connect schema defined: `schema/schema.gql`
- ✅ GraphQL operations ready: `example/queries.gql`, `example/mutations.gql`
- ✅ Seed data prepared: `seed_data.gql`
- ✅ SDK generation configured: `connector.yaml`
- ✅ Firebase CLI installed: v15.14.0

**Blockers:**
- ❌ Firebase CLI `data-connect deploy` command (not available in v15.14.0)
- ❌ Google Cloud SDK `gcloud` command (not installed)

---

## Option 1: Firebase CLI (When Available)

### Step 1: Install Latest Firebase CLI
```bash
# Check for updates
npm install -g firebase-tools@latest

# Verify new commands are available
npx firebase data-connect --help
```

### Step 2: Authenticate Firebase
```bash
# Login to Firebase
npx firebase login

# List available projects
npx firebase projects:list
```

### Step 3: Deploy Data Connect
```bash
# Navigate to project root
cd c:\Users\riosh\Documents\Energy_Monitoring

# Deploy the service
npx firebase data-connect deploy

# Follow prompts:
# - Confirm project: energymonitoring-fdc
# - Confirm region: us-east4
# - Confirm database: fdcdb on energymonitoring-fdc instance
```

### Step 4: Generate SDKs
```bash
# The deployment automatically generates SDKs, but if needed:
npx firebase data-connect sdk generate

# Output will be in configured directories from connector.yaml:
# - kofert_dashboard/lib/dataconnect_generated/
# - flutter/lib/dataconnect_generated/
# - flutter/dev/*/lib/dataconnect_generated/
# - etc.
```

### Step 5: Seed Database
```bash
# Insert test data
npx firebase data-connect:seed

# Or manually execute seed_data.gql
```

---

## Option 2: Manual Cloud SQL Deployment

### Prerequisites
Install Google Cloud SDK:
```bash
# Download from:
# https://cloud.google.com/sdk/docs/install

# Verify installation
gcloud --version
```

### Step 1: Authenticate with Google Cloud
```bash
# Login
gcloud auth login

# Set project
gcloud config set project energymonitoring-fdc
```

### Step 2: Create PostgreSQL Schema

**Method A: Using Cloud SQL Proxy**
```bash
# Start proxy
gcloud cloud-sql-proxy energymonitoring-fdc --port=5432

# In another terminal, connect using psql:
# (Requires PostgreSQL client tools)
psql -h localhost -U postgres -d fdcdb
```

**Then execute schema:**
```sql
-- From dataconnect/schema/schema.gql, create tables:

CREATE TABLE energy_unit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    location VARCHAR(255),
    install_date DATE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE energy_metric (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    unit_id UUID NOT NULL REFERENCES energy_unit(id),
    timestamp TIMESTAMP NOT NULL,
    power DOUBLE PRECISION NOT NULL,
    voltage DOUBLE PRECISION NOT NULL,
    current DOUBLE PRECISION NOT NULL,
    energy DOUBLE PRECISION NOT NULL,
    power_factor DOUBLE PRECISION NOT NULL,
    frequency DOUBLE PRECISION NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE energy_alert (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    unit_id UUID NOT NULL REFERENCES energy_unit(id),
    type VARCHAR(100) NOT NULL,
    severity VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX idx_metric_unit_id ON energy_metric(unit_id);
CREATE INDEX idx_metric_timestamp ON energy_metric(timestamp DESC);
CREATE INDEX idx_alert_unit_id ON energy_alert(unit_id);
CREATE INDEX idx_alert_resolved ON energy_alert(resolved_at);
```

**Method B: Using Cloud SQL Editor in Google Cloud Console**
1. Go to Cloud SQL in Google Cloud Console
2. Select instance: `energymonitoring-fdc`
3. Go to "Databases" tab
4. Select  `fdcdb` database
5. Open "SQL Editor"
6. Paste schema SQL above
7. Execute

### Step 3: Seed Data

```sql
-- Insert test KOFERT units
INSERT INTO energy_unit (name, location, install_date) VALUES
('KOFERT Unit 1', 'Factory Building A', '2024-01-15'),
('KOFERT Unit 2', 'Factory Building B', '2024-02-20'),
('KOFERT Unit 3', 'Distribution Center', '2024-03-10');

-- Insert sample metrics
INSERT INTO energy_metric (unit_id, timestamp, power, voltage, current, energy, power_factor, frequency)
SELECT 
    id,
    NOW() - INTERVAL '1 hour',
    2400.5,
    230.2,
    10.43,
    125.8,
    0.92,
    50.0
FROM energy_unit
LIMIT 1;

-- Insert sample alerts
INSERT INTO energy_alert (unit_id, type, severity, message, created_at)
SELECT 
    id,
    'voltage_high',
    'warning',
    'Voltage exceeds threshold: 245V > 250V limit',
    NOW() - INTERVAL '30 minutes'
FROM energy_unit
LIMIT 1;
```

### Step 4: Deploy GraphQL API

Create a Cloud Run service to serve GraphQL queries:

```bash
# Clone or create GraphQL server repository
# For example, using hasura or Apollo Server

# Deploy to Cloud Run
gcloud run deploy dataconnect-api \
  --source . \
  --platform managed \
  --region us-east4 \
  --set-env-vars POSTGRES_URL=postgresql://user:pass@/instance/dbname
```

---

## Option 3: Cloud SQL Direct Connection

### Connect Dashboard Directly to Cloud SQL

**Step 1: Update Flutter App**

Modify dashboard to query PostgreSQL directly:

```dart
// lib/services/energy_service.dart
import 'package:postgres/postgres.dart';

class EnergyService {
  late final Connection _connection;

  Future<void> connect() async {
    _connection = await Connection.open(
      Endpoint(
        host: 'YOUR_CLOUD_SQL_CLOUDSQL_PROXY_IP',
        port: 5432,
        database: 'fdcdb',
        username: 'postgres',
        password: 'YOUR_PASSWORD',
      ),
    );
  }

  Future<List<EnergyData>> getMetrics(String unitId) async {
    final result = await _connection.execute(
      Sql.named('''
        SELECT * FROM energy_metric
        WHERE unit_id = @unit_id
        ORDER BY timestamp DESC
        LIMIT 100
      '''),
      parameters: {'unit_id': unitId},
    );
    
    return result.map((row) => EnergyData.fromRow(row)).toList();
  }

  Future<void> insertMetric(EnergyData data) async {
    await _connection.execute(
      Sql.named('''
        INSERT INTO energy_metric 
        (unit_id, timestamp, power, voltage, current, energy, power_factor, frequency)
        VALUES (@unit_id, @timestamp, @power, @voltage, @current, @energy, @power_factor, @frequency)
      '''),
      parameters: {
        'unit_id': data.unitId,
        'timestamp': data.timestamp,
        'power': data.power,
        'voltage': data.voltage,
        'current': data.current,
        'energy': data.energy,
        'power_factor': data.powerFactor,
        'frequency': data.frequency,
      },
    );
  }
}
```

**Step 2: Update pubspec.yaml**
```yaml
dependencies:
  postgres: ^3.0.0
  pool: ^1.5.0
```

**Step 3: Update Dashboard Screen**
```dart
// Replace Firebase StreamBuilder with PostgreSQL:
// old: _dbRef.onValue.listen(...)
// new: _energyService.getMetrics(_unitId).then(...)
```

---

## Step-by-Step Implementation Checklist

### Before Deployment
- [ ] Firebase project created and active
- [ ] Cloud SQL instance created: `energymonitoring-fdc`
- [ ] PostgreSQL database: `fdcdb`
- [ ] Network connectivity verified
- [ ] IAM permissions configured
- [ ] Cloud SQL Admin API enabled
- [ ] Data Connect API enabled (in Google Cloud Console)

### Deployment Phase (Choose One Option)
**Option 1:**
- [ ] Update Firebase CLI to latest version
- [ ] Run `firebase data-connect deploy`
- [ ] Verify deployment success
- [ ] Run `firebase data-connect sdk generate`

**Option 2:**
- [ ] Install Google Cloud SDK
- [ ] Authenticate gcloud CLI
- [ ] Create PostgreSQL schema
- [ ] Insert seed data
- [ ] Deploy GraphQL API to Cloud Run
- [ ] Update dashboard API endpoints

**Option 3:**
- [ ] Install Dart `postgres` package
- [ ] Create EnergyService class
- [ ] Update dashboard screens
- [ ] Test database connection
- [ ] Verify data synchronization

### Post-Deployment
- [ ] Test real-time data synchronization
- [ ] Verify alert triggering
- [ ] Test data export functionality
- [ ] Load test with simulated data
- [ ] Security audit of credentials
- [ ] Monitor error logs
- [ ] Document deployment steps
- [ ] Create runbook for operations

---

## Expected Outcomes

### After Successful Deployment

**Available GraphQL Endpoints:**
```graphql
query {
  listEnergyUnits {
    id
    name
    location
    installDate
  }
  
  listHistoricalMetrics(unitId: "...", startDate: "...", endDate: "...") {
    timestamp
    power
    voltage
    current
    energy
    powerFactor
    frequency
  }
  
  getLatestMetrics(unitId: "...") {
    timestamp
    power
    voltage
    current
  }
  
  getActiveAlerts {
    id
    unitId
    type
    severity
    message
    createdAt
  }
}

mutation {
  registerEnergyUnit(name: "Unit 4", location: "...") {
    id
    name
  }
  
  recordEnergyMetric(unitId: "...", power: 2400, voltage: 230, ...) {
    id
    timestamp
  }
  
  createEnergyAlert(unitId: "...", type: "...", message: "...") {
    id
    createdAt
  }
  
  resolveAlert(alertId: "...") {
    resolvedAt
  }
}
```

**Auto-Generated Dart SDK:**
```dart
// In kofert_dashboard/lib/dataconnect_generated/generated.dart
class DataConnectClient {
  Future<ListEnergyUnitsResponse> listEnergyUnits();
  Future<ListHistoricalMetricsResponse> listHistoricalMetrics(...);
  Future<GetLatestMetricsResponse> getLatestMetrics(...);
  Future<GetActiveAlertsResponse> getActiveAlerts();
  
  Future<RegisterEnergyUnitResponse> registerEnergyUnit(...);
  Future<RecordEnergyMetricResponse> recordEnergyMetric(...);
  Future<CreateEnergyAlertResponse> createEnergyAlert(...);
  Future<ResolveAlertResponse> resolveAlert(...);
}
```

**Dashboard Updated:**
- Replace Firebase Realtime Database with GraphQL
- Real-time subscriptions available
- Multi-unit support functional
- Full audit trail in PostgreSQL

---

## Troubleshooting Deployment

### Firebase CLI Command Not Found
```bash
# Solution 1: Update Firebase CLI
npm install -g firebase-tools@latest

# Solution 2: Use npx
npx firebase@latest data-connect deploy

# Solution 3: Check installation
npm list -g firebase-tools
```

### Cloud SQL Connection Error
```bash
# Verify instance is running
gcloud sql instances describe energymonitoring-fdc

# Check IP whitelist
gcloud sql instances describe energymonitoring-fdc --format="value(settings.ipConfiguration)"

# Enable access from your IP
gcloud sql instances patch energymonitoring-fdc \
  --allowed-networks YOUR_IP_ADDRESS
```

### Permission Denied
```bash
# Ensure proper IAM roles
gcloud projects add-iam-policy-binding energymonitoring-fdc \
  --member=user:YOUR_EMAIL \
  --role=roles/cloudsql.admin

gcloud projects add-iam-policy-binding energymonitoring-fdc \
  --member=user:YOUR_EMAIL \
  --role=roles/dataconnect.admin
```

### PostgreSQL Schema Errors
```bash
# Validate schema syntax
psql -f schema.sql --dry-run

# Check existing tables
psql -h PROXY_IP -d fdcdb -c "\dt"

# Show errors
psql -h PROXY_IP -d fdcdb -c "\set ON_ERROR_STOP on" < schema.sql
```

---

## Monitoring & Maintenance

### Monitor Deployment Health
```bash
# Check API usage
npx firebase data-connect stats

# View recent operations
gcloud sql operations list --instance=energymonitoring-fdc

# Monitor database performance
gcloud sql instances describe energymonitoring-fdc --format="value(settings.backupConfiguration)"
```

### Backup & Recovery
```bash
# Create backup
gcloud sql backups create --instance=energymonitoring-fdc

# List backups
gcloud sql backups list --instance=energymonitoring-fdc

# Restore from backup
gcloud sql backups restore BACKUP_ID \
  --backup-instance=energymonitoring-fdc
```

### Update SDKs
```bash
# After schema changes, regenerate SDKs
npx firebase data-connect sdk generate

# Or for specific directories
npx firebase data-connect sdk generate --output-dir=kofert_dashboard/lib/dataconnect_generated
```

---

## Next Actions

1. **Immediate (This Week):**
   - [ ] Check Firebase CLI release notes for Data Connect support
   - [ ] Contact Firebase Support about `firebase data-connect deploy`
   - [ ] Decide on deployment strategy (Option 1, 2, or 3)

2. **Short Term (Next 2 Weeks):**
   - [ ] Execute chosen deployment method
   - [ ] Regenerate SDKs with latest schema
   - [ ] Update dashboard to use GraphQL

3. **Medium Term (Month 2):**
   - [ ] Migrate Realtime Database calls to Data Connect
   - [ ] Implement multi-unit support
   - [ ] Set up monitoring and alerts

4. **Long Term:**
   - [ ] Production hardening
   - [ ] Performance optimization
   - [ ] Compliance certification (if needed)

---

## Resources

- **Firebase Data Connect Docs:** https://firebase.google.com/docs/data-connect
- **Cloud SQL Documentation:** https://cloud.google.com/sql/docs
- **PostgreSQL Documentation:** https://www.postgresql.org/docs/
- **GraphQL Specification:** https://graphql.org/learn/
- **Dart PostgreSQL Client:** https://pub.dev/packages/postgres

---

**Last Updated:** April 12, 2026  
**Status:** Ready for Deployment (Awaiting CLI Support)  
**Author:** Development Team
