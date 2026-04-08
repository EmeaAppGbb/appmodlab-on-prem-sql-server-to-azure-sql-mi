-- ============================================
-- Seed Data for Lakeview Medical Center
-- Realistic healthcare sample data
-- ============================================

-- ============================================
-- PART 1: PatientDB Seed Data
-- ============================================
USE PatientDB;
GO

SET NOCOUNT ON;
PRINT 'Inserting PatientDB seed data...';
GO

-- Departments
SET IDENTITY_INSERT dbo.Departments ON;

INSERT INTO dbo.Departments (DepartmentID, DepartmentCode, DepartmentName, CostCenter, FloorNumber, PhoneExtension, ManagerName)
VALUES
    (1,  'ER',     'Emergency Department',        'CC-1001', 1, '1100', 'Sarah Mitchell'),
    (2,  'ICU',    'Intensive Care Unit',          'CC-1002', 3, '3100', 'David Patel'),
    (3,  'SURG',   'Surgery',                      'CC-1003', 4, '4100', 'Maria Gonzalez'),
    (4,  'MEDSRG', 'Medical-Surgical',             'CC-1004', 2, '2100', 'James Wilson'),
    (5,  'OB',     'Obstetrics',                    'CC-1005', 5, '5100', 'Lisa Chen'),
    (6,  'PEDS',   'Pediatrics',                    'CC-1006', 5, '5200', 'Robert Kim'),
    (7,  'CARD',   'Cardiology',                    'CC-1007', 3, '3200', 'Angela Brown'),
    (8,  'ORTH',   'Orthopedics',                   'CC-1008', 4, '4200', 'Thomas O''Brien'),
    (9,  'RAD',    'Radiology',                     'CC-1009', 1, '1200', 'Susan Park'),
    (10, 'LAB',    'Laboratory',                    'CC-1010', 1, '1300', 'Michael Santos'),
    (11, 'PHARM',  'Pharmacy',                      'CC-1011', 1, '1400', 'Jennifer Lee'),
    (12, 'PSYCH',  'Psychiatry',                    'CC-1012', 6, '6100', 'William Nguyen'),
    (13, 'ONCO',   'Oncology',                      'CC-1013', 3, '3300', 'Patricia Taylor'),
    (14, 'NEURO',  'Neurology',                     'CC-1014', 4, '4300', 'Daniel Rivera'),
    (15, 'REHAB',  'Rehabilitation',                'CC-1015', 2, '2200', 'Karen Wright');

SET IDENTITY_INSERT dbo.Departments OFF;
PRINT 'Departments inserted.';
GO

-- Insurance Providers
SET IDENTITY_INSERT dbo.InsuranceProviders ON;

INSERT INTO dbo.InsuranceProviders (InsuranceProviderID, ProviderName, ProviderCode, PayerID, Address1, City, State, ZipCode, Phone, ElectronicPayerID, ClaimSubmissionType)
VALUES
    (1,  'Blue Cross Blue Shield of Illinois', 'BCBS-IL',  'BCBS001', '300 E Randolph St', 'Chicago', 'IL', '60601', '800-538-8833', 'BCBS1001', 'ELECTRONIC'),
    (2,  'Aetna Health Insurance',             'AETNA',    'AET001',  '151 Farmington Ave', 'Hartford', 'CT', '06156', '800-872-3862', 'AET0001',  'ELECTRONIC'),
    (3,  'UnitedHealthcare',                    'UHC',      'UHC001',  '9900 Bren Rd E', 'Minnetonka', 'MN', '55343', '800-328-5979', 'UHC0001',  'ELECTRONIC'),
    (4,  'Cigna Healthcare',                    'CIGNA',    'CIG001',  '900 Cottage Grove Rd', 'Bloomfield', 'CT', '06002', '800-244-6224', 'CIG0001',  'ELECTRONIC'),
    (5,  'Humana',                              'HUMANA',   'HUM001',  '500 W Main St', 'Louisville', 'KY', '40202', '800-448-6262', 'HUM0001',  'ELECTRONIC'),
    (6,  'Medicare',                            'MEDICARE', 'CMS001',  '7500 Security Blvd', 'Baltimore', 'MD', '21244', '800-633-4227', 'CMS0001',  'ELECTRONIC'),
    (7,  'Medicaid - Illinois',                 'MDICAID',  'MCD001',  '201 S Grand Ave', 'Springfield', 'IL', '62763', '800-226-0768', 'MCD0001',  'ELECTRONIC'),
    (8,  'Tricare',                             'TRICARE',  'TRI001',  '7700 Arlington Blvd', 'Falls Church', 'VA', '22042', '800-874-2273', 'TRI0001',  'ELECTRONIC'),
    (9,  'Workers Compensation Fund',           'WC-FUND',  'WCF001',  '100 W Randolph St', 'Chicago', 'IL', '60601', '312-555-0199', 'WCF0001',  'PAPER'),
    (10, 'Self Pay',                            'SELFPAY',  NULL,      NULL, NULL, NULL, NULL, NULL, NULL, 'ELECTRONIC');

SET IDENTITY_INSERT dbo.InsuranceProviders OFF;
PRINT 'Insurance providers inserted.';
GO

-- Physicians
SET IDENTITY_INSERT dbo.Physicians ON;

INSERT INTO dbo.Physicians (PhysicianID, NPI, FirstName, LastName, Credentials, Specialty, DepartmentID, LicenseNumber, LicenseState, DEANumber, Phone, Email, HireDate, WeeklyScheduleXML)
VALUES
    (1,  '1234567890', 'Robert',   'Chen',       'MD',  'Emergency Medicine',     1,  'IL-EM-44521', 'IL', 'BC1234567', '312-555-0101', 'r.chen@lakeviewmed.org', '2008-06-15',
         '<Schedule><Day name="Monday" startTime="07:00" endTime="19:00" location="ER" onCall="0"/><Day name="Wednesday" startTime="07:00" endTime="19:00" location="ER" onCall="0"/><Day name="Friday" startTime="19:00" endTime="07:00" location="ER" onCall="1"/></Schedule>'),
    (2,  '2345678901', 'Sarah',    'Johnson',    'MD',  'Internal Medicine',       4,  'IL-IM-33412', 'IL', 'BJ2345678', '312-555-0102', 's.johnson@lakeviewmed.org', '2010-03-01', NULL),
    (3,  '3456789012', 'Michael',  'Patel',      'MD',  'Cardiology',              7,  'IL-CD-55623', 'IL', 'MP3456789', '312-555-0103', 'm.patel@lakeviewmed.org', '2005-09-15', NULL),
    (4,  '4567890123', 'Jennifer', 'Garcia',     'DO',  'Orthopedic Surgery',      8,  'IL-OS-66734', 'IL', 'JG4567890', '312-555-0104', 'j.garcia@lakeviewmed.org', '2012-01-10', NULL),
    (5,  '5678901234', 'David',    'Kim',        'MD',  'General Surgery',         3,  'IL-GS-77845', 'IL', 'DK5678901', '312-555-0105', 'd.kim@lakeviewmed.org', '2009-07-01', NULL),
    (6,  '6789012345', 'Lisa',     'Thompson',   'MD',  'Obstetrics & Gynecology', 5,  'IL-OB-88956', 'IL', 'LT6789012', '312-555-0106', 'l.thompson@lakeviewmed.org', '2011-04-15', NULL),
    (7,  '7890123456', 'William',  'Anderson',   'MD',  'Pediatrics',              6,  'IL-PD-99067', 'IL', 'WA7890123', '312-555-0107', 'w.anderson@lakeviewmed.org', '2007-11-01', NULL),
    (8,  '8901234567', 'Amanda',   'Martinez',   'MD',  'Neurology',               14, 'IL-NR-10178', 'IL', 'AM8901234', '312-555-0108', 'a.martinez@lakeviewmed.org', '2013-02-15', NULL),
    (9,  '9012345678', 'James',    'Brown',      'MD',  'Oncology',                13, 'IL-ON-21289', 'IL', 'JB9012345', '312-555-0109', 'j.brown@lakeviewmed.org', '2006-08-01', NULL),
    (10, '0123456789', 'Emily',    'Wilson',     'MD',  'Psychiatry',              12, 'IL-PS-32390', 'IL', 'EW0123456', '312-555-0110', 'e.wilson@lakeviewmed.org', '2014-05-01', NULL),
    (11, '1111111111', 'Daniel',   'Lee',        'MD',  'Radiology',               9,  'IL-RD-43401', 'IL', NULL,        '312-555-0111', 'd.lee@lakeviewmed.org', '2010-10-15', NULL),
    (12, '2222222222', 'Rachel',   'Taylor',     'NP',  'Family Practice',         4,  'IL-NP-54512', 'IL', NULL,        '312-555-0112', 'r.taylor@lakeviewmed.org', '2015-01-01', NULL),
    (13, '3333333333', 'Kevin',    'Nguyen',     'MD',  'Intensive Care',          2,  'IL-IC-65623', 'IL', 'KN3333333', '312-555-0113', 'k.nguyen@lakeviewmed.org', '2008-03-15', NULL),
    (14, '4444444444', 'Michelle', 'Robinson',   'PA',  'Emergency Medicine',      1,  'IL-PA-76734', 'IL', NULL,        '312-555-0114', 'm.robinson@lakeviewmed.org', '2016-06-01', NULL),
    (15, '5555555555', 'Andrew',   'Wright',     'MD',  'Pulmonology',             2,  'IL-PL-87845', 'IL', 'AW5555555', '312-555-0115', 'a.wright@lakeviewmed.org', '2011-09-01', NULL);

SET IDENTITY_INSERT dbo.Physicians OFF;
PRINT 'Physicians inserted.';
GO

-- Patients
DECLARE @PatientID INT, @MRN VARCHAR(20);

-- Patient 1
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Margaret', @LastName = 'Sullivan', @MiddleName = 'Anne',
    @DateOfBirth = '1948-03-15', @Gender = 'F', @SSN = '312-55-0001',
    @Address1 = '1247 Oak Park Ave', @City = 'Chicago', @State = 'IL', @ZipCode = '60302',
    @HomePhone = '312-555-1001', @MobilePhone = '312-555-2001', @Email = 'msullivan@email.com',
    @PrimaryInsuranceID = 6, @PrimaryPolicyNumber = 'MCR-44521-A',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 2
EXEC dbo.usp_RegisterPatient
    @FirstName = 'James', @LastName = 'Kowalski', @MiddleName = 'Edward',
    @DateOfBirth = '1962-07-22', @Gender = 'M', @SSN = '312-55-0002',
    @Address1 = '892 Lincoln Blvd', @City = 'Evanston', @State = 'IL', @ZipCode = '60201',
    @HomePhone = '847-555-1002', @MobilePhone = '847-555-2002', @Email = 'jkowalski@email.com',
    @PrimaryInsuranceID = 1, @PrimaryPolicyNumber = 'BCBS-XYZ-78901',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 3
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Maria', @LastName = 'Rodriguez', @MiddleName = 'Elena',
    @DateOfBirth = '1985-11-08', @Gender = 'F', @SSN = '312-55-0003',
    @Address1 = '3456 Division St', @City = 'Chicago', @State = 'IL', @ZipCode = '60651',
    @HomePhone = '773-555-1003', @MobilePhone = '773-555-2003',
    @PrimaryInsuranceID = 3, @PrimaryPolicyNumber = 'UHC-345-67890',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 4
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Robert', @LastName = 'Jackson', @MiddleName = 'Lee',
    @DateOfBirth = '1975-04-30', @Gender = 'M', @SSN = '312-55-0004',
    @Address1 = '567 Michigan Ave', @City = 'Chicago', @State = 'IL', @ZipCode = '60611',
    @MobilePhone = '312-555-2004', @Email = 'rjackson@email.com',
    @PrimaryInsuranceID = 2, @PrimaryPolicyNumber = 'AET-901-23456',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 5
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Dorothy', @LastName = 'Yamamoto',
    @DateOfBirth = '1940-12-25', @Gender = 'F', @SSN = '312-55-0005',
    @Address1 = '2100 Sheridan Rd', @City = 'Wilmette', @State = 'IL', @ZipCode = '60091',
    @HomePhone = '847-555-1005',
    @PrimaryInsuranceID = 6, @PrimaryPolicyNumber = 'MCR-88765-B',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 6
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Ahmed', @LastName = 'Hassan',
    @DateOfBirth = '1990-06-14', @Gender = 'M', @SSN = '312-55-0006',
    @Address1 = '4321 Devon Ave', @City = 'Chicago', @State = 'IL', @ZipCode = '60659',
    @MobilePhone = '773-555-2006', @Email = 'ahassan@email.com',
    @PrimaryInsuranceID = 4, @PrimaryPolicyNumber = 'CIG-567-89012',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 7
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Catherine', @LastName = 'O''Brien', @MiddleName = 'Mary',
    @DateOfBirth = '1958-09-03', @Gender = 'F', @SSN = '312-55-0007',
    @Address1 = '789 Lakeshore Dr', @City = 'Chicago', @State = 'IL', @ZipCode = '60611',
    @HomePhone = '312-555-1007', @MobilePhone = '312-555-2007',
    @PrimaryInsuranceID = 1, @PrimaryPolicyNumber = 'BCBS-ABC-11111',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 8
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Timothy', @LastName = 'Washington',
    @DateOfBirth = '2015-02-18', @Gender = 'M', @SSN = '312-55-0008',
    @Address1 = '1500 S State St', @City = 'Chicago', @State = 'IL', @ZipCode = '60605',
    @HomePhone = '312-555-1008',
    @PrimaryInsuranceID = 7, @PrimaryPolicyNumber = 'MCD-IL-99001',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 9
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Priya', @LastName = 'Sharma',
    @DateOfBirth = '1992-01-27', @Gender = 'F', @SSN = '312-55-0009',
    @Address1 = '6789 Touhy Ave', @City = 'Skokie', @State = 'IL', @ZipCode = '60077',
    @MobilePhone = '847-555-2009', @Email = 'psharma@email.com',
    @PrimaryInsuranceID = 3, @PrimaryPolicyNumber = 'UHC-789-01234',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

-- Patient 10
EXEC dbo.usp_RegisterPatient
    @FirstName = 'Frank', @LastName = 'Novak', @MiddleName = 'Joseph',
    @DateOfBirth = '1955-08-11', @Gender = 'M', @SSN = '312-55-0010',
    @Address1 = '345 Harlem Ave', @City = 'Oak Park', @State = 'IL', @ZipCode = '60304',
    @HomePhone = '708-555-1010', @MobilePhone = '708-555-2010',
    @PrimaryInsuranceID = 5, @PrimaryPolicyNumber = 'HUM-456-78901',
    @NewPatientID = @PatientID OUTPUT, @NewMRN = @MRN OUTPUT;

PRINT 'Patients inserted.';
GO

-- Allergies
INSERT INTO dbo.Allergies (PatientID, AllergyType, AllergenName, Reaction, Severity, ReportedBy)
SELECT p.PatientID, a.AllergyType, a.AllergenName, a.Reaction, a.Severity, 'Registration'
FROM dbo.Patients p
CROSS APPLY (
    SELECT 'DRUG' AS AllergyType, 'Penicillin' AS AllergenName, 'Rash, hives' AS Reaction, 'MODERATE' AS Severity WHERE p.MRN = 'LMC-000001'
    UNION ALL
    SELECT 'DRUG', 'Sulfa Drugs', 'Anaphylaxis', 'LIFE_THREATENING' WHERE p.MRN = 'LMC-000001'
    UNION ALL
    SELECT 'FOOD', 'Shellfish', 'Throat swelling', 'SEVERE' WHERE p.MRN = 'LMC-000002'
    UNION ALL
    SELECT 'DRUG', 'Codeine', 'Nausea, vomiting', 'MODERATE' WHERE p.MRN = 'LMC-000003'
    UNION ALL
    SELECT 'ENVIRONMENTAL', 'Latex', 'Contact dermatitis', 'MODERATE' WHERE p.MRN = 'LMC-000004'
    UNION ALL
    SELECT 'DRUG', 'Aspirin', 'GI bleeding', 'SEVERE' WHERE p.MRN = 'LMC-000005'
    UNION ALL
    SELECT 'DRUG', 'Morphine', 'Respiratory depression', 'SEVERE' WHERE p.MRN = 'LMC-000005'
    UNION ALL
    SELECT 'DRUG', 'Ibuprofen', 'Stomach ulcer', 'MODERATE' WHERE p.MRN = 'LMC-000007'
    UNION ALL
    SELECT 'FOOD', 'Peanuts', 'Anaphylaxis', 'LIFE_THREATENING' WHERE p.MRN = 'LMC-000008'
) a;

PRINT 'Allergies inserted.';
GO

-- Chargemaster (fee schedule)
INSERT INTO dbo.Chargemaster (ChargeCode, CPTCode, RevenueCode, ChargeDescription, DepartmentID, StandardCharge, MedicareRate, MedicaidRate, EffectiveDate)
VALUES
    ('RC-SEMI-PRIV', NULL,    '0120', 'Room & Board - Semi-Private',    4, 2500.00, 1800.00, 1200.00, '2024-01-01'),
    ('RC-PRIV',      NULL,    '0110', 'Room & Board - Private',         4, 3500.00, 2200.00, 1500.00, '2024-01-01'),
    ('RC-ICU',       NULL,    '0200', 'ICU Room',                       2, 6500.00, 4500.00, 3200.00, '2024-01-01'),
    ('RC-OBS',       NULL,    '0762', 'Observation Room',               1, 1800.00, 1200.00, 900.00,  '2024-01-01'),
    ('ER-VISIT-3',   '99283', '0450', 'ED Visit - Moderate',           1, 850.00,  550.00,  400.00,  '2024-01-01'),
    ('ER-VISIT-4',   '99284', '0450', 'ED Visit - High',               1, 1450.00, 950.00,  700.00,  '2024-01-01'),
    ('ER-VISIT-5',   '99285', '0450', 'ED Visit - Critical',           1, 2200.00, 1500.00, 1100.00, '2024-01-01'),
    ('LAB-CBC',      '85025', '0300', 'CBC with Differential',         10, 125.00,  85.00,   60.00,  '2024-01-01'),
    ('LAB-BMP',      '80048', '0300', 'Basic Metabolic Panel',         10, 175.00,  120.00,  85.00,  '2024-01-01'),
    ('LAB-CMP',      '80053', '0300', 'Comprehensive Metabolic Panel', 10, 225.00,  155.00,  110.00, '2024-01-01'),
    ('LAB-TROPI',    '84484', '0300', 'Troponin I',                    10, 250.00,  175.00,  125.00, '2024-01-01'),
    ('RAD-CXR',      '71046', '0320', 'Chest X-Ray 2 views',          9,  350.00,  240.00,  175.00, '2024-01-01'),
    ('RAD-CTHEAD',   '70450', '0350', 'CT Head without contrast',     9,  1800.00, 1250.00, 900.00, '2024-01-01'),
    ('RAD-CTCHEST',  '71250', '0350', 'CT Chest without contrast',    9,  2200.00, 1500.00, 1100.00, '2024-01-01'),
    ('RAD-MRI-BRAIN','70553', '0610', 'MRI Brain with/without',       9,  3500.00, 2400.00, 1750.00, '2024-01-01'),
    ('SURG-APPY',    '44950', '0360', 'Appendectomy',                 3,  15000.00, 10500.00, 7500.00, '2024-01-01'),
    ('SURG-CHOLE',   '47562', '0360', 'Lap Cholecystectomy',          3,  12000.00, 8400.00, 6000.00, '2024-01-01'),
    ('CARD-EKG',     '93000', '0730', '12-Lead EKG',                  7,  275.00,  190.00,  135.00, '2024-01-01'),
    ('CARD-ECHO',    '93306', '0480', 'Echocardiogram',               7,  1200.00, 840.00,  600.00, '2024-01-01'),
    ('CARD-CATH',    '93458', '0480', 'Cardiac Catheterization',      7,  8500.00, 5950.00, 4250.00, '2024-01-01');

PRINT 'Chargemaster inserted.';
GO

PRINT '========================================';
PRINT 'PatientDB seed data complete.';
PRINT '========================================';
GO

-- ============================================
-- PART 2: BillingDB Seed Data
-- ============================================
USE BillingDB;
GO

SET NOCOUNT ON;
PRINT 'Inserting BillingDB seed data...';
GO

-- Copy chargemaster to BillingDB
INSERT INTO dbo.Chargemaster (ChargeCode, CPTCode, RevenueCode, ChargeDescription, StandardCharge, MedicareRate, MedicaidRate, CommercialRate, EffectiveDate)
SELECT ChargeCode, CPTCode, RevenueCode, ChargeDescription, StandardCharge, MedicareRate, MedicaidRate, 
       StandardCharge * 0.85,  -- Commercial rate is 85% of standard
       EffectiveDate
FROM PatientDB.dbo.Chargemaster;

PRINT 'BillingDB chargemaster synced.';
GO

PRINT '========================================';
PRINT 'BillingDB seed data complete.';
PRINT '========================================';
GO

-- ============================================
-- PART 3: SchedulingDB Seed Data
-- ============================================
USE SchedulingDB;
GO

SET NOCOUNT ON;
PRINT 'Inserting SchedulingDB seed data...';
GO

-- Rooms
INSERT INTO dbo.Rooms (RoomNumber, FloorNumber, RoomType, DepartmentCode, Capacity, HasOxygen, HasSuction, HasMonitoring)
VALUES
    ('ER-01',  1, 'ED_BAY',    'ER',     1, 1, 1, 1),
    ('ER-02',  1, 'ED_BAY',    'ER',     1, 1, 1, 1),
    ('ER-03',  1, 'ED_BAY',    'ER',     1, 1, 1, 1),
    ('ER-04',  1, 'ED_BAY',    'ER',     1, 1, 1, 1),
    ('ER-05',  1, 'ED_BAY',    'ER',     1, 1, 1, 1),
    ('ER-06',  1, 'ED_BAY',    'ER',     1, 1, 1, 1),
    ('201',    2, 'EXAM',      'MEDSRG', 2, 1, 1, 0),
    ('202',    2, 'EXAM',      'MEDSRG', 2, 1, 1, 0),
    ('203',    2, 'EXAM',      'MEDSRG', 2, 1, 1, 0),
    ('204',    2, 'EXAM',      'MEDSRG', 2, 1, 1, 0),
    ('205',    2, 'EXAM',      'MEDSRG', 1, 1, 1, 0),
    ('206',    2, 'EXAM',      'REHAB',  1, 0, 0, 0),
    ('301',    3, 'ICU',       'ICU',    1, 1, 1, 1),
    ('302',    3, 'ICU',       'ICU',    1, 1, 1, 1),
    ('303',    3, 'ICU',       'ICU',    1, 1, 1, 1),
    ('304',    3, 'ICU',       'ICU',    1, 1, 1, 1),
    ('310',    3, 'EXAM',      'CARD',   1, 1, 1, 1),
    ('311',    3, 'EXAM',      'CARD',   1, 1, 1, 1),
    ('312',    3, 'PROCEDURE', 'CARD',   1, 1, 1, 1),
    ('320',    3, 'EXAM',      'ONCO',   2, 1, 0, 0),
    ('OR-01',  4, 'OR',        'SURG',   1, 1, 1, 1),
    ('OR-02',  4, 'OR',        'SURG',   1, 1, 1, 1),
    ('OR-03',  4, 'OR',        'SURG',   1, 1, 1, 1),
    ('401',    4, 'EXAM',      'ORTH',   1, 0, 0, 0),
    ('402',    4, 'EXAM',      'ORTH',   1, 0, 0, 0),
    ('410',    4, 'EXAM',      'NEURO',  1, 1, 0, 1),
    ('501',    5, 'EXAM',      'OB',     1, 1, 1, 1),
    ('502',    5, 'EXAM',      'OB',     1, 1, 1, 1),
    ('510',    5, 'EXAM',      'PEDS',   2, 1, 1, 0),
    ('511',    5, 'EXAM',      'PEDS',   2, 1, 1, 0),
    ('RAD-01', 1, 'IMAGING',   'RAD',    1, 0, 0, 0),
    ('RAD-02', 1, 'IMAGING',   'RAD',    1, 0, 0, 0),
    ('MRI-01', 1, 'IMAGING',   'RAD',    1, 0, 0, 0);

PRINT 'Rooms inserted.';
GO

-- Sample appointments for today and upcoming days
DECLARE @Today DATE = CAST(GETDATE() AS DATE);
DECLARE @PatientID INT;

-- Get first few patient IDs
SELECT TOP 1 @PatientID = PatientID FROM PatientDB.dbo.Patients ORDER BY PatientID;

IF @PatientID IS NOT NULL
BEGIN
    INSERT INTO dbo.Appointments (PatientID, PhysicianID, AppointmentDate, StartTime, EndTime, Duration, AppointmentType, RoomID, ReasonForVisit, AppointmentStatus, PatientName, PatientPhone)
    SELECT 
        p.PatientID,
        a.PhysicianID,
        DATEADD(DAY, a.DayOffset, @Today),
        a.StartTime,
        a.EndTime,
        a.Duration,
        a.AppointmentType,
        r.RoomID,
        a.Reason,
        a.Status,
        p.LastName + ', ' + p.FirstName,
        COALESCE(p.MobilePhone, p.HomePhone)
    FROM PatientDB.dbo.Patients p
    CROSS APPLY (
        SELECT 2 AS PhysicianID, 0 AS DayOffset, '09:00' AS StartTime, '09:30' AS EndTime, 30 AS Duration, 'FOLLOW_UP' AS AppointmentType, 'Diabetes management' AS Reason, 'COMPLETED' AS Status WHERE p.MRN = 'LMC-000001'
        UNION ALL SELECT 3, 1, '10:00', '11:00', 60, 'PROCEDURE', 'Cardiac stress test', 'SCHEDULED' WHERE p.MRN = 'LMC-000002'
        UNION ALL SELECT 6, 2, '14:00', '14:45', 45, 'NEW_PATIENT', 'Prenatal checkup', 'CONFIRMED' WHERE p.MRN = 'LMC-000003'
        UNION ALL SELECT 4, 3, '08:30', '09:00', 30, 'FOLLOW_UP', 'Post-surgical follow-up', 'SCHEDULED' WHERE p.MRN = 'LMC-000004'
        UNION ALL SELECT 7, 1, '11:00', '11:30', 30, 'FOLLOW_UP', 'Well-child visit', 'SCHEDULED' WHERE p.MRN = 'LMC-000008'
        UNION ALL SELECT 8, 4, '13:00', '14:00', 60, 'CONSULT', 'Headache evaluation', 'SCHEDULED' WHERE p.MRN = 'LMC-000009'
    ) a
    CROSS APPLY (
        SELECT TOP 1 RoomID FROM dbo.Rooms WHERE RoomType = 'EXAM' ORDER BY RoomNumber
    ) r;
    
    PRINT 'Appointments inserted.';
END
GO

PRINT '========================================';
PRINT 'SchedulingDB seed data complete.';
PRINT '========================================';
GO

PRINT '';
PRINT '╔══════════════════════════════════════╗';
PRINT '║  ALL SEED DATA LOADED SUCCESSFULLY   ║';
PRINT '╚══════════════════════════════════════╝';
GO
