-- ============================================
-- PatientDB Views
-- Lakeview Medical Center
-- ============================================
USE PatientDB;
GO

-- ============================================
-- vw_ActivePatients
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_ActivePatients')
    DROP VIEW dbo.vw_ActivePatients;
GO

CREATE VIEW dbo.vw_ActivePatients
AS
SELECT 
    p.PatientID,
    p.MRN,
    p.FirstName,
    p.MiddleName,
    p.LastName,
    p.DateOfBirth,
    DATEDIFF(YEAR, p.DateOfBirth, GETDATE()) 
        - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.DateOfBirth, GETDATE()), p.DateOfBirth) > GETDATE() THEN 1 ELSE 0 END AS Age,
    p.Gender,
    p.Address1,
    p.City,
    p.State,
    p.ZipCode,
    p.HomePhone,
    p.MobilePhone,
    p.Email,
    ip.ProviderName AS PrimaryInsurance,
    p.PrimaryPolicyNumber,
    p.CreatedDate AS RegistrationDate
FROM dbo.Patients p
LEFT JOIN dbo.InsuranceProviders ip ON p.PrimaryInsuranceID = ip.InsuranceProviderID
WHERE p.PatientStatus = 'ACTIVE'
  AND p.DeceasedIndicator = 0;
GO

PRINT 'View dbo.vw_ActivePatients created.';
GO

-- ============================================
-- vw_InpatientCensus
-- Current hospital inpatient census
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_InpatientCensus')
    DROP VIEW dbo.vw_InpatientCensus;
GO

CREATE VIEW dbo.vw_InpatientCensus
AS
SELECT 
    e.EncounterID,
    e.EncounterNumber,
    p.PatientID,
    p.MRN,
    p.LastName + ', ' + p.FirstName AS PatientName,
    p.DateOfBirth,
    DATEDIFF(YEAR, p.DateOfBirth, GETDATE()) AS Age,
    p.Gender,
    e.EncounterType,
    e.AdmitDate,
    DATEDIFF(DAY, e.AdmitDate, GETDATE()) AS LengthOfStay,
    e.RoomNumber,
    e.BedNumber,
    d.DepartmentName,
    ph.LastName + ', ' + ph.FirstName + ' ' + ISNULL(ph.Credentials, '') AS AttendingPhysician,
    e.AdmitDiagnosis,
    ip.ProviderName AS Insurance,
    e.TotalCharges,
    -- Legacy: inline subquery for active medication count
    (SELECT COUNT(*) FROM dbo.Medications m 
     WHERE m.EncounterID = e.EncounterID AND m.MedicationStatus = 'ACTIVE') AS ActiveMedicationCount,
    -- Legacy: inline subquery for pending orders
    (SELECT COUNT(*) FROM dbo.Orders o 
     WHERE o.EncounterID = e.EncounterID AND o.OrderStatus IN ('ORDERED', 'IN_PROGRESS')) AS PendingOrderCount
FROM dbo.Encounters e
INNER JOIN dbo.Patients p ON e.PatientID = p.PatientID
INNER JOIN dbo.Physicians ph ON e.AttendingPhysicianID = ph.PhysicianID
LEFT JOIN dbo.Departments d ON e.DepartmentID = d.DepartmentID
LEFT JOIN dbo.InsuranceProviders ip ON p.PrimaryInsuranceID = ip.InsuranceProviderID
WHERE e.EncounterStatus = 'ACTIVE'
  AND e.EncounterType IN ('INPATIENT', 'OBSERVATION');
GO

PRINT 'View dbo.vw_InpatientCensus created.';
GO

-- ============================================
-- vw_PendingLabOrders
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_PendingLabOrders')
    DROP VIEW dbo.vw_PendingLabOrders;
GO

CREATE VIEW dbo.vw_PendingLabOrders
AS
SELECT 
    o.OrderID,
    o.EncounterID,
    p.MRN,
    p.LastName + ', ' + p.FirstName AS PatientName,
    o.OrderCode,
    o.OrderDescription,
    o.OrderPriority,
    o.IsStatOrder,
    o.OrderDate,
    DATEDIFF(MINUTE, o.OrderDate, GETDATE()) AS MinutesSinceOrdered,
    ph.LastName + ', ' + ph.FirstName AS OrderingPhysician,
    d.DepartmentName,
    e.RoomNumber,
    e.BedNumber
FROM dbo.Orders o
INNER JOIN dbo.Encounters e ON o.EncounterID = e.EncounterID
INNER JOIN dbo.Patients p ON o.PatientID = p.PatientID
INNER JOIN dbo.Physicians ph ON o.OrderingPhysicianID = ph.PhysicianID
LEFT JOIN dbo.Departments d ON e.DepartmentID = d.DepartmentID
WHERE o.OrderType = 'LAB'
  AND o.OrderStatus IN ('ORDERED', 'IN_PROGRESS');
GO

PRINT 'View dbo.vw_PendingLabOrders created.';
GO

-- ============================================
-- vw_CriticalLabResults
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_CriticalLabResults')
    DROP VIEW dbo.vw_CriticalLabResults;
GO

CREATE VIEW dbo.vw_CriticalLabResults
AS
SELECT 
    lr.LabResultID,
    p.MRN,
    p.LastName + ', ' + p.FirstName AS PatientName,
    e.RoomNumber,
    e.BedNumber,
    lr.TestCode,
    lr.TestName,
    lr.ResultValue,
    lr.ResultUnit,
    lr.AbnormalFlag,
    lr.ReferenceRangeLow,
    lr.ReferenceRangeHigh,
    lr.ReportedDate,
    DATEDIFF(MINUTE, lr.ReportedDate, GETDATE()) AS MinutesSinceReported,
    ph.LastName + ', ' + ph.FirstName AS AttendingPhysician,
    ph.Phone AS PhysicianPhone
FROM dbo.LabResults lr
INNER JOIN dbo.Encounters e ON lr.EncounterID = e.EncounterID
INNER JOIN dbo.Patients p ON lr.PatientID = p.PatientID
INNER JOIN dbo.Physicians ph ON e.AttendingPhysicianID = ph.PhysicianID
WHERE lr.CriticalFlag = 1
  AND lr.ResultStatus IN ('PRELIMINARY', 'FINAL');
GO

PRINT 'View dbo.vw_CriticalLabResults created.';
GO

-- ============================================
-- vw_ActiveMedications
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_ActiveMedications')
    DROP VIEW dbo.vw_ActiveMedications;
GO

CREATE VIEW dbo.vw_ActiveMedications
AS
SELECT 
    m.MedicationID,
    p.MRN,
    p.LastName + ', ' + p.FirstName AS PatientName,
    m.DrugCode,
    m.DrugName,
    m.GenericName,
    m.DrugClass,
    m.Dosage,
    m.DosageUnit,
    m.Route,
    m.Frequency,
    m.StartDate,
    DATEDIFF(DAY, m.StartDate, GETDATE()) AS DaysOnMedication,
    ph.LastName + ', ' + ph.FirstName AS PrescribingPhysician,
    m.IsControlledSubstance,
    m.DEASchedule,
    m.PharmacyVerified,
    -- Legacy: check for drug allergies via correlated subquery
    CASE WHEN EXISTS (
        SELECT 1 FROM dbo.Allergies a 
        WHERE a.PatientID = m.PatientID 
          AND a.AllergyType = 'DRUG' 
          AND a.AllergyStatus = 'ACTIVE'
          AND m.DrugName LIKE '%' + a.AllergenName + '%'
    ) THEN 1 ELSE 0 END AS PotentialAllergyConflict
FROM dbo.Medications m
INNER JOIN dbo.Patients p ON m.PatientID = p.PatientID
INNER JOIN dbo.Physicians ph ON m.PrescribingPhysicianID = ph.PhysicianID
WHERE m.MedicationStatus = 'ACTIVE';
GO

PRINT 'View dbo.vw_ActiveMedications created.';
GO

-- ============================================
-- vw_PatientEncounterSummary
-- Legacy: complex view with multiple aggregations
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_PatientEncounterSummary')
    DROP VIEW dbo.vw_PatientEncounterSummary;
GO

CREATE VIEW dbo.vw_PatientEncounterSummary
AS
SELECT 
    p.PatientID,
    p.MRN,
    p.LastName + ', ' + p.FirstName AS PatientName,
    p.DateOfBirth,
    p.Gender,
    p.PatientStatus,
    -- Encounter statistics
    COUNT(DISTINCT e.EncounterID) AS TotalEncounters,
    SUM(CASE WHEN e.EncounterType = 'INPATIENT' THEN 1 ELSE 0 END) AS InpatientCount,
    SUM(CASE WHEN e.EncounterType = 'OUTPATIENT' THEN 1 ELSE 0 END) AS OutpatientCount,
    SUM(CASE WHEN e.EncounterType = 'EMERGENCY' THEN 1 ELSE 0 END) AS EmergencyCount,
    MIN(e.AdmitDate) AS FirstVisitDate,
    MAX(e.AdmitDate) AS LastVisitDate,
    -- Financial totals (Legacy: aggregating denormalized values)
    SUM(ISNULL(e.TotalCharges, 0)) AS LifetimeCharges,
    SUM(ISNULL(e.TotalPayments, 0)) AS LifetimePayments,
    SUM(ISNULL(e.PatientBalance, 0)) AS OutstandingBalance,
    -- Active encounter indicator
    MAX(CASE WHEN e.EncounterStatus = 'ACTIVE' THEN 1 ELSE 0 END) AS HasActiveEncounter
FROM dbo.Patients p
LEFT JOIN dbo.Encounters e ON p.PatientID = e.PatientID
GROUP BY p.PatientID, p.MRN, p.LastName, p.FirstName, p.DateOfBirth, p.Gender, p.PatientStatus;
GO

PRINT 'View dbo.vw_PatientEncounterSummary created.';
GO

-- ============================================
-- vw_PhysicianWorkload
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_PhysicianWorkload')
    DROP VIEW dbo.vw_PhysicianWorkload;
GO

CREATE VIEW dbo.vw_PhysicianWorkload
AS
SELECT 
    ph.PhysicianID,
    ph.NPI,
    ph.LastName + ', ' + ph.FirstName + ' ' + ISNULL(ph.Credentials, '') AS PhysicianName,
    ph.Specialty,
    d.DepartmentName,
    -- Current active patients
    (SELECT COUNT(*) FROM dbo.Encounters e2 
     WHERE e2.AttendingPhysicianID = ph.PhysicianID AND e2.EncounterStatus = 'ACTIVE') AS ActivePatientCount,
    -- Today's orders
    (SELECT COUNT(*) FROM dbo.Orders o 
     WHERE o.OrderingPhysicianID = ph.PhysicianID AND CAST(o.OrderDate AS DATE) = CAST(GETDATE() AS DATE)) AS TodaysOrderCount,
    -- Unsigned notes
    (SELECT COUNT(*) FROM dbo.ClinicalNotes cn 
     WHERE cn.AuthorID = ph.PhysicianID AND cn.NoteStatus = 'DRAFT') AS UnsignedNoteCount,
    -- This month's encounters
    (SELECT COUNT(*) FROM dbo.Encounters e3 
     WHERE e3.AttendingPhysicianID = ph.PhysicianID 
       AND e3.AdmitDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MonthlyEncounterCount
FROM dbo.Physicians ph
LEFT JOIN dbo.Departments d ON ph.DepartmentID = d.DepartmentID
WHERE ph.IsActive = 1;
GO

PRINT 'View dbo.vw_PhysicianWorkload created.';
GO

-- ============================================
-- vw_DepartmentStatistics
-- ============================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_DepartmentStatistics')
    DROP VIEW dbo.vw_DepartmentStatistics;
GO

CREATE VIEW dbo.vw_DepartmentStatistics
AS
SELECT 
    d.DepartmentID,
    d.DepartmentCode,
    d.DepartmentName,
    d.FloorNumber,
    -- Current census
    (SELECT COUNT(*) FROM dbo.Encounters e 
     WHERE e.DepartmentID = d.DepartmentID AND e.EncounterStatus = 'ACTIVE') AS CurrentCensus,
    -- Average length of stay (discharged in last 30 days)
    (SELECT AVG(CAST(DATEDIFF(DAY, e2.AdmitDate, e2.DischargeDate) AS FLOAT)) 
     FROM dbo.Encounters e2 
     WHERE e2.DepartmentID = d.DepartmentID 
       AND e2.EncounterStatus = 'DISCHARGED'
       AND e2.DischargeDate >= DATEADD(DAY, -30, GETDATE())) AS AvgLengthOfStay30Days,
    -- Total charges this month
    (SELECT ISNULL(SUM(e3.TotalCharges), 0) FROM dbo.Encounters e3 
     WHERE e3.DepartmentID = d.DepartmentID 
       AND e3.AdmitDate >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)) AS MonthlyCharges,
    -- Active physician count
    (SELECT COUNT(DISTINCT ph.PhysicianID) FROM dbo.Physicians ph 
     WHERE ph.DepartmentID = d.DepartmentID AND ph.IsActive = 1) AS ActivePhysicianCount,
    d.IsActive
FROM dbo.Departments d
WHERE d.IsActive = 1;
GO

PRINT 'View dbo.vw_DepartmentStatistics created.';
GO

PRINT '========================================';
PRINT 'All PatientDB views created successfully.';
PRINT '========================================';
GO
