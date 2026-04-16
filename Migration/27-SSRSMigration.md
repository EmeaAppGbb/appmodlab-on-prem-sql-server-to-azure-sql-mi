# Step 27: SSRS to Power BI Migration - Lakeview Medical Center

## Overview

Lakeview Medical Center currently uses three SQL Server Reporting Services (SSRS) reports connected to the on-premises SQL Server 2016 instance. With the migration to Azure SQL Managed Instance, these reports must be migrated to Power BI to align with the cloud-first strategy and eliminate the need for an on-premises SSRS server.

This guide covers the mapping of SSRS report types to Power BI equivalents, connection string updates, and a phased migration plan for all three reports.

---

## Current SSRS Report Inventory

| Report Name | Database(s) | Data Source | Report Type | Schedule | Primary Users |
|---|---|---|---|---|---|
| **PatientSummary** | PatientDB, SchedulingDB | Shared Data Source (on-prem) | Tabular with sub-reports | On-demand + daily snapshot | Clinical staff, physicians |
| **BillingReport** | BillingDB, PatientDB | Shared Data Source (on-prem) | Matrix with drill-through | Weekly (Monday 6 AM) | Finance department, billing team |
| **OccupancyReport** | SchedulingDB, PatientDB | Shared Data Source (on-prem) | Chart + tabular | Daily snapshot (7 AM) | Hospital administration, operations |

---

## SSRS to Power BI Feature Mapping

### Report Type Equivalents

| SSRS Feature | Power BI Equivalent | Notes |
|---|---|---|
| Tabular report | Table / Matrix visual | Direct mapping; Power BI tables support conditional formatting |
| Matrix (cross-tab) | Matrix visual | Native support with expand/collapse row groups |
| Sub-reports | Drill-through pages | Use drill-through or tooltip pages for detail views |
| Drill-through links | Drill-through / Bookmarks | Power BI drill-through passes filter context automatically |
| Charts (bar, line, pie) | Native chart visuals | Richer visualization options in Power BI |
| Parameters | Slicers / Filters | Replace SSRS parameters with Power BI slicers |
| Snapshots / subscriptions | Scheduled refresh + email subscriptions | Power BI Pro/Premium supports email subscriptions |
| Shared data sources | Datasets / Dataflows | Centralized datasets shared across reports |
| Expressions (VB.NET) | DAX measures / calculated columns | Rewrite VB.NET expressions as DAX |
| Page headers/footers | Report page headers | Limited in Power BI; consider using text boxes |
| Print-formatted layouts | Paginated reports (Power BI) | Use Power BI paginated reports for pixel-perfect output |

### Data Source Mapping

| Component | SSRS (Source) | Power BI (Target) |
|---|---|---|
| **Connection type** | SQL Server Native Client | Azure SQL Database connector |
| **Server** | `YOURSERVER\YOURINSTANCE` | `<mi-name>.database.windows.net` |
| **Authentication** | Windows Integrated | Azure AD / SQL Authentication |
| **Encryption** | Optional | Mandatory (TLS 1.2) |
| **Connection string** | See below | See below |

**SSRS connection string (before):**
```
Data Source=YOURSERVER\YOURINSTANCE;Initial Catalog=PatientDB;Integrated Security=True;
```

**Power BI connection string (after):**
```
Server=tcp:<mi-name>.database.windows.net,1433;
Initial Catalog=PatientDB;
Encrypt=True;
TrustServerCertificate=False;
Authentication=Active Directory Default;
```

> **Note:** Replace `<mi-name>` with the Managed Instance FQDN from Step 23 (ConnectionStringUpdate.ps1). For service accounts, use Azure AD service principals or managed identities.

---

## Report-by-Report Migration Plan

### Report 1: PatientSummary

**Current SSRS Implementation:**
- Tabular layout with patient demographics, encounter history, medications, and scheduling data
- Sub-reports for detailed encounter records and medication lists
- Parameters: PatientID, DateRange, Department
- Data sources: `PatientDB` (patients, encounters, medications), `SchedulingDB` (appointments)

**Power BI Migration:**

| SSRS Component | Power BI Replacement |
|---|---|
| Main tabular report | Table visual with conditional formatting |
| Encounter sub-report | Drill-through page: "Encounter Detail" |
| Medication sub-report | Drill-through page: "Medication History" |
| PatientID parameter | Slicer (dropdown) |
| DateRange parameter | Date slicer (range) |
| Department parameter | Slicer (dropdown) |
| Daily snapshot | Scheduled refresh (daily at 6 AM) |

**DAX Measures to Create:**
```dax
Total Encounters = COUNTROWS('Encounters')
Active Medications = CALCULATE(COUNTROWS('Medications'), 'Medications'[IsActive] = TRUE())
Avg Length of Stay = AVERAGE('Encounters'[LengthOfStayDays])
```

**Migration Steps:**
1. Create Power BI dataset connected to MI `PatientDB` and `SchedulingDB`
2. Build data model with relationships (PatientID keys)
3. Create main report page with patient table and KPI cards
4. Add drill-through pages for encounter and medication details
5. Replace parameters with slicers
6. Configure scheduled refresh via Power BI gateway or direct MI connection
7. Validate data matches SSRS output for a sample of patients

---

### Report 2: BillingReport

**Current SSRS Implementation:**
- Matrix report with billing charges grouped by department, insurance type, and time period
- Drill-through to individual claim details
- Parameters: DateRange, Department, InsuranceProvider, ClaimStatus
- Data sources: `BillingDB` (charges, claims, insurance), `PatientDB` (patient demographics)

**Power BI Migration:**

| SSRS Component | Power BI Replacement |
|---|---|
| Matrix cross-tab | Matrix visual with row/column groups |
| Drill-through to claims | Drill-through page: "Claim Detail" |
| Summary totals/subtotals | Matrix subtotals + DAX measures |
| DateRange parameter | Date slicer (range) |
| Department parameter | Slicer (list) |
| InsuranceProvider parameter | Slicer (dropdown) |
| ClaimStatus parameter | Slicer (buttons) |
| Weekly schedule | Scheduled refresh (Monday 5:30 AM) |

**DAX Measures to Create:**
```dax
Total Charges = SUM('BillingCharges'[Amount])
Claims Submitted = CALCULATE(COUNTROWS('Claims'), 'Claims'[Status] = "Submitted")
Claims Paid = CALCULATE(COUNTROWS('Claims'), 'Claims'[Status] = "Paid")
Collection Rate = DIVIDE([Claims Paid], [Claims Submitted], 0)
Outstanding Balance = CALCULATE(SUM('Claims'[Amount]), 'Claims'[Status] <> "Paid")
```

**Migration Steps:**
1. Create Power BI dataset connected to MI `BillingDB` and `PatientDB`
2. Build star-schema data model (fact: BillingCharges/Claims, dims: Department, Insurance, Dates)
3. Create matrix page with department rows, insurance columns, charge amounts
4. Add drill-through page for individual claim details
5. Create KPI dashboard page (total charges, collection rate, outstanding)
6. Replace parameters with slicers and add cross-filtering
7. Configure weekly refresh schedule
8. Validate totals match SSRS billing report for last 3 months

---

### Report 3: OccupancyReport

**Current SSRS Implementation:**
- Combined chart (line/bar) showing occupancy trends with tabular details below
- Parameters: DateRange, Department, Floor
- Data sources: `SchedulingDB` (room assignments, schedules), `PatientDB` (admissions, discharges)

**Power BI Migration:**

| SSRS Component | Power BI Replacement |
|---|---|
| Bar chart (daily occupancy) | Clustered bar chart visual |
| Line chart (trend) | Line chart visual |
| Tabular detail | Table visual with drill-through |
| DateRange parameter | Date slicer (range) |
| Department parameter | Slicer (dropdown) |
| Floor parameter | Slicer (buttons) |
| Daily snapshot | Scheduled refresh (daily at 6:30 AM) |

**DAX Measures to Create:**
```dax
Occupancy Rate = DIVIDE([Occupied Beds], [Total Beds], 0)
Occupied Beds = COUNTROWS(FILTER('RoomAssignments', 'RoomAssignments'[IsOccupied] = TRUE()))
Total Beds = COUNTROWS('Beds')
Avg Daily Occupancy = AVERAGEX(VALUES('Calendar'[Date]), [Occupancy Rate])
```

**Migration Steps:**
1. Create Power BI dataset connected to MI `SchedulingDB` and `PatientDB`
2. Build data model with calendar table for time intelligence
3. Create occupancy dashboard with trend lines and current-state KPIs
4. Add department/floor breakdown page
5. Create tabular detail with drill-through to room-level data
6. Replace parameters with slicers
7. Configure daily refresh schedule
8. Validate occupancy numbers match SSRS report for last 30 days

---

## Phased Migration Timeline

| Phase | Duration | Activities | Reports |
|---|---|---|---|
| **Phase 1: Setup** | Week 1 | Install Power BI Gateway (if needed), configure MI data source, create workspace | — |
| **Phase 2: PatientSummary** | Weeks 2–3 | Build dataset, create visuals, validate with clinical staff | PatientSummary |
| **Phase 3: BillingReport** | Weeks 3–4 | Build dataset, create matrix/drillthrough, validate with finance | BillingReport |
| **Phase 4: OccupancyReport** | Weeks 4–5 | Build dataset, create charts/KPIs, validate with operations | OccupancyReport |
| **Phase 5: Parallel Run** | Weeks 5–6 | Run SSRS and Power BI side-by-side, compare outputs | All |
| **Phase 6: Cutover** | Week 7 | Redirect users to Power BI, disable SSRS subscriptions | All |
| **Phase 7: Decommission** | Week 8 | Archive SSRS .rdl files, decommission SSRS server | — |

---

## Power BI Gateway Configuration

If the Managed Instance is on a private VNet without public endpoint, a Power BI On-premises Data Gateway is required:

1. **Install gateway** on a VM in the same VNet as the MI (or peered VNet)
2. **Register gateway** in Power BI service under Settings > Manage gateways
3. **Add data source** using MI FQDN: `<mi-name>.database.windows.net`
4. **Authentication:** Azure AD or SQL Authentication (use Key Vault for credentials)
5. **Test connection** for each database: PatientDB, BillingDB, SchedulingDB, ReportingDB

> **Alternative:** If the MI public endpoint is enabled, Power BI can connect directly without a gateway. Ensure NSG rules allow traffic from Power BI service IPs.

---

## Validation Checklist

- [ ] Power BI datasets connect to MI successfully (all 4 databases)
- [ ] PatientSummary report matches SSRS output for 10 sample patients
- [ ] BillingReport totals match SSRS for the last 3 monthly periods
- [ ] OccupancyReport daily rates match SSRS for the last 30 days
- [ ] All slicers/filters work correctly (replacing SSRS parameters)
- [ ] Drill-through navigation functions properly on all reports
- [ ] Scheduled refresh runs without errors
- [ ] Email subscriptions deliver reports to the correct recipients
- [ ] Row-level security (RLS) applied where needed (department-based access)
- [ ] SSRS .rdl files archived to Azure Blob Storage for reference
- [ ] SSRS server decommission plan approved by IT management

---

## Post-Migration Considerations

- **Training:** Schedule Power BI training for clinical, finance, and operations staff
- **Licensing:** Ensure Power BI Pro licenses for all report consumers (or use Premium capacity)
- **RLS:** Implement row-level security for department-based data access
- **Monitoring:** Use Power BI admin portal to track report usage and refresh health
- **Archival:** Keep SSRS .rdl files in version control or Azure Blob Storage for audit purposes
