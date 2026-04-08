-- ============================================
-- ReportingDB Cross-Database Views
-- Lakeview Medical Center
-- These views span PatientDB, BillingDB, and SchedulingDB
-- Legacy anti-pattern: cross-database views create
-- tight coupling and migration complexity
-- ============================================
USE ReportingDB;
GO

-- ============================================
-- vw_PatientFinancialSummary
-- Cross-database: PatientDB + BillingDB
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_PatientFinancialSummary')
    DROP VIEW dbo.vw_PatientFinancialSummary;
GO

CREATE VIEW dbo.vw_PatientFinancialSummary
AS
SELECT 
    p.PatientID,
    p.MRN,
    p.LastName + ', ' + p.FirstName AS PatientName,
    p.DateOfBirth,
    p.PatientStatus,
    ip.ProviderName AS PrimaryInsurance,
    p.PrimaryPolicyNumber,
    -- Encounter counts from PatientDB
    (SELECT COUNT(*) FROM PatientDB.dbo.Encounters e 
     WHERE e.PatientID = p.PatientID) AS TotalEncounters,
    (SELECT COUNT(*) FROM PatientDB.dbo.Encounters e 
     WHERE e.PatientID = p.PatientID AND e.EncounterStatus = 'ACTIVE') AS ActiveEncounters,
    -- Financial totals from BillingDB
    (SELECT ISNULL(SUM(bc.ChargeAmount), 0) FROM BillingDB.dbo.BillingCharges bc 
     WHERE bc.PatientID = p.PatientID AND bc.ChargeStatus <> 'VOIDED') AS TotalCharges,
    (SELECT ISNULL(SUM(bc.AdjustmentAmount), 0) FROM BillingDB.dbo.BillingCharges bc 
     WHERE bc.PatientID = p.PatientID AND bc.ChargeStatus <> 'VOIDED') AS TotalAdjustments,
    (SELECT ISNULL(SUM(py.PaymentAmount), 0) FROM BillingDB.dbo.Payments py 
     WHERE py.PatientID = p.PatientID AND py.PaymentStatus <> 'VOIDED') AS TotalPayments,
    -- Claims summary from BillingDB
    (SELECT COUNT(*) FROM BillingDB.dbo.InsuranceClaims ic 
     WHERE ic.PatientID = p.PatientID) AS TotalClaims,
    (SELECT COUNT(*) FROM BillingDB.dbo.InsuranceClaims ic 
     WHERE ic.PatientID = p.PatientID AND ic.ClaimStatus = 'DENIED') AS DeniedClaims,
    (SELECT ISNULL(SUM(ic.PaidAmount), 0) FROM BillingDB.dbo.InsuranceClaims ic 
     WHERE ic.PatientID = p.PatientID AND ic.ClaimStatus IN ('PAID', 'PARTIAL_PAID')) AS InsurancePaidTotal,
    -- Outstanding balance
    (SELECT ISNULL(SUM(inv.TotalAmount - inv.PaidAmount), 0) FROM BillingDB.dbo.Invoices inv 
     WHERE inv.PatientID = p.PatientID AND inv.InvoiceStatus = 'OPEN') AS OutstandingBalance,
    -- Collections
    (SELECT ISNULL(SUM(col.OriginalBalance), 0) FROM BillingDB.dbo.Collections col 
     WHERE col.PatientID = p.PatientID AND col.CollectionStatus = 'ACTIVE') AS InCollections
FROM PatientDB.dbo.Patients p
LEFT JOIN PatientDB.dbo.InsuranceProviders ip ON p.PrimaryInsuranceID = ip.InsuranceProviderID;
GO

PRINT 'View dbo.vw_PatientFinancialSummary created.';
GO

-- ============================================
-- vw_HospitalCensus
-- Cross-database: PatientDB + SchedulingDB
-- Real-time hospital census dashboard
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_HospitalCensus')
    DROP VIEW dbo.vw_HospitalCensus;
GO

CREATE VIEW dbo.vw_HospitalCensus
AS
SELECT 
    d.DepartmentName,
    d.DepartmentCode,
    d.FloorNumber,
    -- Current inpatient counts
    COUNT(DISTINCT CASE WHEN e.EncounterType = 'INPATIENT' AND e.EncounterStatus = 'ACTIVE' 
          THEN e.EncounterID END) AS InpatientCount,
    COUNT(DISTINCT CASE WHEN e.EncounterType = 'OBSERVATION' AND e.EncounterStatus = 'ACTIVE' 
          THEN e.EncounterID END) AS ObservationCount,
    COUNT(DISTINCT CASE WHEN e.EncounterType = 'EMERGENCY' AND e.EncounterStatus = 'ACTIVE' 
          THEN e.EncounterID END) AS EmergencyCount,
    -- Room utilization from SchedulingDB
    (SELECT COUNT(*) FROM SchedulingDB.dbo.Rooms r 
     WHERE r.DepartmentCode = d.DepartmentCode AND r.IsActive = 1) AS TotalRooms,
    (SELECT COUNT(*) FROM SchedulingDB.dbo.RoomAssignments ra 
     INNER JOIN SchedulingDB.dbo.Rooms r ON ra.RoomID = r.RoomID
     WHERE r.DepartmentCode = d.DepartmentCode AND ra.AssignmentStatus = 'ACTIVE') AS OccupiedRooms,
    -- Admissions/discharges today
    SUM(CASE WHEN CAST(e.AdmitDate AS DATE) = CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS AdmissionsToday,
    SUM(CASE WHEN CAST(e.DischargeDate AS DATE) = CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS DischargesToday,
    -- Avg LOS for department
    AVG(CASE WHEN e.EncounterStatus = 'ACTIVE' 
        THEN CAST(DATEDIFF(DAY, e.AdmitDate, GETDATE()) AS FLOAT) END) AS AvgCurrentLOS
FROM PatientDB.dbo.Departments d
LEFT JOIN PatientDB.dbo.Encounters e ON d.DepartmentID = e.DepartmentID
WHERE d.IsActive = 1
GROUP BY d.DepartmentName, d.DepartmentCode, d.FloorNumber;
GO

PRINT 'View dbo.vw_HospitalCensus created.';
GO

-- ============================================
-- vw_PhysicianProductivity
-- Cross-database: PatientDB + BillingDB + SchedulingDB
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_PhysicianProductivity')
    DROP VIEW dbo.vw_PhysicianProductivity;
GO

CREATE VIEW dbo.vw_PhysicianProductivity
AS
SELECT 
    ph.PhysicianID,
    ph.NPI,
    ph.LastName + ', ' + ph.FirstName + ' ' + ISNULL(ph.Credentials, '') AS PhysicianName,
    ph.Specialty,
    d.DepartmentName,
    -- Current month metrics from PatientDB
    (SELECT COUNT(*) FROM PatientDB.dbo.Encounters e 
     WHERE e.AttendingPhysicianID = ph.PhysicianID 
       AND e.AdmitDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MonthlyEncounters,
    (SELECT COUNT(*) FROM PatientDB.dbo.Orders o 
     WHERE o.OrderingPhysicianID = ph.PhysicianID 
       AND o.OrderDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MonthlyOrders,
    (SELECT COUNT(*) FROM PatientDB.dbo.Procedures pr 
     WHERE pr.PerformingPhysicianID = ph.PhysicianID 
       AND pr.ProcedureDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)
       AND pr.ProcedureStatus = 'COMPLETED') AS MonthlyProcedures,
    -- Revenue from BillingDB
    (SELECT ISNULL(SUM(bc.ChargeAmount), 0) FROM BillingDB.dbo.BillingCharges bc 
     WHERE bc.PerformingPhysicianNPI = ph.NPI 
       AND bc.ServiceDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)
       AND bc.ChargeStatus <> 'VOIDED') AS MonthlyCharges,
    (SELECT ISNULL(SUM(bc.ChargeAmount), 0) FROM BillingDB.dbo.BillingCharges bc 
     WHERE bc.PerformingPhysicianNPI = ph.NPI 
       AND bc.ServiceDate >= DATEADD(YEAR, DATEDIFF(YEAR, 0, GETDATE()), 0)
       AND bc.ChargeStatus <> 'VOIDED') AS YTDCharges,
    -- Scheduling from SchedulingDB
    (SELECT COUNT(*) FROM SchedulingDB.dbo.Appointments a 
     WHERE a.PhysicianID = ph.PhysicianID 
       AND a.AppointmentDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)
       AND a.AppointmentStatus NOT IN ('CANCELLED', 'NO_SHOW')) AS MonthlyAppointments,
    (SELECT COUNT(*) FROM SchedulingDB.dbo.Appointments a 
     WHERE a.PhysicianID = ph.PhysicianID 
       AND a.AppointmentDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)
       AND a.AppointmentStatus = 'NO_SHOW') AS MonthlyNoShows,
    -- Unsigned notes (compliance metric)
    (SELECT COUNT(*) FROM PatientDB.dbo.ClinicalNotes cn 
     WHERE cn.AuthorID = ph.PhysicianID AND cn.NoteStatus = 'DRAFT') AS UnsignedNotes
FROM PatientDB.dbo.Physicians ph
LEFT JOIN PatientDB.dbo.Departments d ON ph.DepartmentID = d.DepartmentID
WHERE ph.IsActive = 1;
GO

PRINT 'View dbo.vw_PhysicianProductivity created.';
GO

-- ============================================
-- vw_RevenueCycleSummary
-- Cross-database: BillingDB primary, PatientDB secondary
-- Dashboard view for revenue cycle management
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_RevenueCycleSummary')
    DROP VIEW dbo.vw_RevenueCycleSummary;
GO

CREATE VIEW dbo.vw_RevenueCycleSummary
AS
SELECT 
    CAST(GETDATE() AS DATE) AS ReportDate,
    -- Charges
    (SELECT ISNULL(SUM(ChargeAmount), 0) FROM BillingDB.dbo.BillingCharges 
     WHERE ChargeStatus <> 'VOIDED' AND CAST(PostedDate AS DATE) = CAST(GETDATE() AS DATE)) AS TodayCharges,
    (SELECT ISNULL(SUM(ChargeAmount), 0) FROM BillingDB.dbo.BillingCharges 
     WHERE ChargeStatus <> 'VOIDED' 
       AND PostedDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MTDCharges,
    (SELECT ISNULL(SUM(ChargeAmount), 0) FROM BillingDB.dbo.BillingCharges 
     WHERE ChargeStatus <> 'VOIDED' 
       AND PostedDate >= DATEADD(YEAR, DATEDIFF(YEAR, 0, GETDATE()), 0)) AS YTDCharges,
    -- Payments
    (SELECT ISNULL(SUM(PaymentAmount), 0) FROM BillingDB.dbo.Payments 
     WHERE PaymentStatus <> 'VOIDED' AND CAST(PostedDate AS DATE) = CAST(GETDATE() AS DATE)) AS TodayPayments,
    (SELECT ISNULL(SUM(PaymentAmount), 0) FROM BillingDB.dbo.Payments 
     WHERE PaymentStatus <> 'VOIDED' 
       AND PostedDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MTDPayments,
    -- Claims pipeline
    (SELECT COUNT(*) FROM BillingDB.dbo.InsuranceClaims WHERE ClaimStatus = 'CREATED') AS ClaimsPendingSubmission,
    (SELECT COUNT(*) FROM BillingDB.dbo.InsuranceClaims WHERE ClaimStatus = 'SUBMITTED') AS ClaimsSubmitted,
    (SELECT COUNT(*) FROM BillingDB.dbo.InsuranceClaims WHERE ClaimStatus = 'DENIED') AS ClaimsDenied,
    (SELECT ISNULL(SUM(TotalCharges), 0) FROM BillingDB.dbo.InsuranceClaims WHERE ClaimStatus = 'DENIED') AS DeniedClaimsValue,
    -- AR Aging
    (SELECT ISNULL(SUM(TotalAmount - PaidAmount), 0) FROM BillingDB.dbo.Invoices 
     WHERE InvoiceStatus = 'OPEN' AND DATEDIFF(DAY, InvoiceDate, GETDATE()) <= 30) AS AR_0_30,
    (SELECT ISNULL(SUM(TotalAmount - PaidAmount), 0) FROM BillingDB.dbo.Invoices 
     WHERE InvoiceStatus = 'OPEN' AND DATEDIFF(DAY, InvoiceDate, GETDATE()) BETWEEN 31 AND 60) AS AR_31_60,
    (SELECT ISNULL(SUM(TotalAmount - PaidAmount), 0) FROM BillingDB.dbo.Invoices 
     WHERE InvoiceStatus = 'OPEN' AND DATEDIFF(DAY, InvoiceDate, GETDATE()) BETWEEN 61 AND 90) AS AR_61_90,
    (SELECT ISNULL(SUM(TotalAmount - PaidAmount), 0) FROM BillingDB.dbo.Invoices 
     WHERE InvoiceStatus = 'OPEN' AND DATEDIFF(DAY, InvoiceDate, GETDATE()) > 90) AS AR_Over90,
    -- Collections
    (SELECT COUNT(*) FROM BillingDB.dbo.Collections WHERE CollectionStatus = 'ACTIVE') AS ActiveCollectionAccounts,
    (SELECT ISNULL(SUM(CurrentBalance), 0) FROM BillingDB.dbo.Collections WHERE CollectionStatus = 'ACTIVE') AS TotalInCollections,
    -- Patient volume from PatientDB
    (SELECT COUNT(*) FROM PatientDB.dbo.Encounters 
     WHERE EncounterStatus = 'ACTIVE') AS CurrentActiveEncounters,
    (SELECT COUNT(*) FROM PatientDB.dbo.Encounters 
     WHERE CAST(AdmitDate AS DATE) = CAST(GETDATE() AS DATE)) AS TodayAdmissions;
GO

PRINT 'View dbo.vw_RevenueCycleSummary created.';
GO

-- ============================================
-- vw_QualityMetrics
-- Cross-database: PatientDB + BillingDB
-- Quality and compliance reporting
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_QualityMetrics')
    DROP VIEW dbo.vw_QualityMetrics;
GO

CREATE VIEW dbo.vw_QualityMetrics
AS
SELECT 
    CAST(GETDATE() AS DATE) AS ReportDate,
    -- 30-day readmission rate (last 90 days)
    (SELECT CAST(
        COUNT(CASE WHEN EXISTS (
            SELECT 1 FROM PatientDB.dbo.Encounters e2 
            WHERE e2.PatientID = e.PatientID 
              AND e2.EncounterID <> e.EncounterID
              AND e2.AdmitDate BETWEEN e.DischargeDate AND DATEADD(DAY, 30, e.DischargeDate)
              AND e2.EncounterType = 'INPATIENT'
        ) THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0) AS DECIMAL(5,2))
     FROM PatientDB.dbo.Encounters e
     WHERE e.EncounterType = 'INPATIENT'
       AND e.EncounterStatus = 'DISCHARGED'
       AND e.DischargeDate >= DATEADD(DAY, -90, GETDATE())
       AND e.DischargeDate <= DATEADD(DAY, -30, GETDATE())
    ) AS ReadmissionRate30Day,
    -- Average length of stay
    (SELECT AVG(CAST(DATEDIFF(DAY, AdmitDate, DischargeDate) AS FLOAT))
     FROM PatientDB.dbo.Encounters 
     WHERE EncounterType = 'INPATIENT' AND EncounterStatus = 'DISCHARGED'
       AND DischargeDate >= DATEADD(MONTH, -1, GETDATE())) AS AvgLOS_Last30Days,
    -- ED wait time (admit to first order)
    (SELECT AVG(CAST(DATEDIFF(MINUTE, e.AdmitDate, 
        (SELECT MIN(o.OrderDate) FROM PatientDB.dbo.Orders o WHERE o.EncounterID = e.EncounterID)
     ) AS FLOAT))
     FROM PatientDB.dbo.Encounters e
     WHERE e.EncounterType = 'EMERGENCY' 
       AND e.AdmitDate >= DATEADD(DAY, -30, GETDATE())) AS AvgEDTimeToFirstOrder_Minutes,
    -- Unsigned note compliance
    (SELECT COUNT(*) FROM PatientDB.dbo.ClinicalNotes WHERE NoteStatus = 'DRAFT') AS TotalUnsignedNotes,
    (SELECT COUNT(*) FROM PatientDB.dbo.ClinicalNotes 
     WHERE NoteStatus = 'DRAFT' AND DATEDIFF(DAY, NoteDate, GETDATE()) > 7) AS UnsignedNotesOver7Days,
    -- Critical lab notification time
    (SELECT AVG(CAST(DATEDIFF(MINUTE, ReportedDate, GETDATE()) AS FLOAT))
     FROM PatientDB.dbo.LabResults 
     WHERE CriticalFlag = 1 AND ResultStatus IN ('PRELIMINARY', 'FINAL')
       AND ReportedDate >= DATEADD(DAY, -30, GETDATE())) AS AvgCriticalLabAge_Minutes,
    -- Medication error indicators
    (SELECT COUNT(*) FROM PatientDB.dbo.AuditLog 
     WHERE Action = 'ALLERGY_WARNING' 
       AND ChangedDate >= DATEADD(DAY, -30, GETDATE())) AS AllergyWarningsLast30Days,
    -- Claim denial rate
    (SELECT CAST(
        COUNT(CASE WHEN ClaimStatus = 'DENIED' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0)
     AS DECIMAL(5,2))
     FROM BillingDB.dbo.InsuranceClaims 
     WHERE SubmittedDate >= DATEADD(MONTH, -3, GETDATE())) AS ClaimDenialRate_Last90Days;
GO

PRINT 'View dbo.vw_QualityMetrics created.';
GO

PRINT '========================================';
PRINT 'All ReportingDB views created.';
PRINT '========================================';
GO
