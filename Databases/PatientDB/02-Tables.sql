-- ============================================
-- PatientDB Tables
-- Lakeview Medical Center
-- SQL Server 2016 (Compatibility Level 130)
-- ============================================
USE PatientDB;
GO

-- ============================================
-- Departments
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Departments') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Departments (
        DepartmentID        INT IDENTITY(1,1) NOT NULL,
        DepartmentCode      VARCHAR(10) NOT NULL,
        DepartmentName      NVARCHAR(100) NOT NULL,
        CostCenter          VARCHAR(20) NULL,
        FloorNumber         INT NULL,
        PhoneExtension      VARCHAR(10) NULL,
        ManagerName         NVARCHAR(100) NULL,
        IsActive            BIT NOT NULL DEFAULT 1,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Departments PRIMARY KEY CLUSTERED (DepartmentID),
        CONSTRAINT UQ_Departments_Code UNIQUE (DepartmentCode)
    );
    PRINT 'Table dbo.Departments created.';
END
GO

-- ============================================
-- InsuranceProviders
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.InsuranceProviders') AND type = 'U')
BEGIN
    CREATE TABLE dbo.InsuranceProviders (
        InsuranceProviderID INT IDENTITY(1,1) NOT NULL,
        ProviderName        NVARCHAR(200) NOT NULL,
        ProviderCode        VARCHAR(20) NOT NULL,
        PayerID             VARCHAR(20) NULL,
        Address1            NVARCHAR(200) NULL,
        Address2            NVARCHAR(200) NULL,
        City                NVARCHAR(100) NULL,
        State               CHAR(2) NULL,
        ZipCode             VARCHAR(10) NULL,
        Phone               VARCHAR(20) NULL,
        Fax                 VARCHAR(20) NULL,
        ElectronicPayerID   VARCHAR(20) NULL,
        ClaimSubmissionType VARCHAR(20) NULL DEFAULT 'ELECTRONIC',
        IsActive            BIT NOT NULL DEFAULT 1,
        ContractStartDate   DATE NULL,
        ContractEndDate     DATE NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_InsuranceProviders PRIMARY KEY CLUSTERED (InsuranceProviderID),
        CONSTRAINT UQ_InsuranceProviders_Code UNIQUE (ProviderCode)
    );
    PRINT 'Table dbo.InsuranceProviders created.';
END
GO

-- ============================================
-- Patients
-- Legacy pattern: SSN stored as plain text (no encryption)
-- Legacy pattern: Multiple address fields instead of normalized
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Patients') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Patients (
        PatientID           INT IDENTITY(100000,1) NOT NULL,
        MRN                 VARCHAR(20) NOT NULL,               -- Medical Record Number
        SSN                 VARCHAR(11) NULL,                    -- Legacy: stored unencrypted
        FirstName           NVARCHAR(50) NOT NULL,
        MiddleName          NVARCHAR(50) NULL,
        LastName            NVARCHAR(50) NOT NULL,
        Suffix              NVARCHAR(10) NULL,
        DateOfBirth         DATE NOT NULL,
        Gender              CHAR(1) NOT NULL,                    -- M/F/U
        Race                VARCHAR(50) NULL,
        Ethnicity           VARCHAR(50) NULL,
        PreferredLanguage   VARCHAR(50) NULL DEFAULT 'English',
        MaritalStatus       VARCHAR(20) NULL,
        -- Legacy: denormalized address fields
        Address1            NVARCHAR(200) NULL,
        Address2            NVARCHAR(200) NULL,
        City                NVARCHAR(100) NULL,
        State               CHAR(2) NULL,
        ZipCode             VARCHAR(10) NULL,
        HomePhone           VARCHAR(20) NULL,
        WorkPhone           VARCHAR(20) NULL,
        MobilePhone         VARCHAR(20) NULL,
        Email               NVARCHAR(200) NULL,
        EmergencyContactName    NVARCHAR(100) NULL,
        EmergencyContactPhone   VARCHAR(20) NULL,
        EmergencyContactRelation VARCHAR(50) NULL,
        -- Insurance (Legacy: denormalized, should be separate table)
        PrimaryInsuranceID  INT NULL,
        PrimaryPolicyNumber VARCHAR(50) NULL,
        PrimaryGroupNumber  VARCHAR(50) NULL,
        SecondaryInsuranceID INT NULL,
        SecondaryPolicyNumber VARCHAR(50) NULL,
        SecondaryGroupNumber VARCHAR(50) NULL,
        -- Status
        PatientStatus       VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        DeceasedDate        DATE NULL,
        DeceasedIndicator   BIT NOT NULL DEFAULT 0,
        -- Legacy: blob storage for patient photo
        PatientPhoto        VARBINARY(MAX) NULL,
        -- Audit
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        CreatedBy           NVARCHAR(50) NOT NULL DEFAULT SUSER_SNAME(),
        ModifiedDate        DATETIME NULL,
        ModifiedBy          NVARCHAR(50) NULL,
        -- Legacy: TIMESTAMP column for optimistic concurrency
        RowVersion          TIMESTAMP NOT NULL,
        CONSTRAINT PK_Patients PRIMARY KEY CLUSTERED (PatientID),
        CONSTRAINT UQ_Patients_MRN UNIQUE (MRN),
        CONSTRAINT FK_Patients_PrimaryInsurance FOREIGN KEY (PrimaryInsuranceID) REFERENCES dbo.InsuranceProviders(InsuranceProviderID),
        CONSTRAINT FK_Patients_SecondaryInsurance FOREIGN KEY (SecondaryInsuranceID) REFERENCES dbo.InsuranceProviders(InsuranceProviderID),
        CONSTRAINT CK_Patients_Gender CHECK (Gender IN ('M', 'F', 'U')),
        CONSTRAINT CK_Patients_Status CHECK (PatientStatus IN ('ACTIVE', 'INACTIVE', 'DECEASED', 'MERGED'))
    );

    -- Legacy: non-clustered indexes with INCLUDE columns
    CREATE NONCLUSTERED INDEX IX_Patients_LastName ON dbo.Patients (LastName, FirstName) INCLUDE (DateOfBirth, MRN);
    CREATE NONCLUSTERED INDEX IX_Patients_SSN ON dbo.Patients (SSN) WHERE SSN IS NOT NULL;
    CREATE NONCLUSTERED INDEX IX_Patients_DOB ON dbo.Patients (DateOfBirth);
    CREATE NONCLUSTERED INDEX IX_Patients_Status ON dbo.Patients (PatientStatus) INCLUDE (LastName, FirstName);
    
    PRINT 'Table dbo.Patients created.';
END
GO

-- ============================================
-- Physicians
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Physicians') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Physicians (
        PhysicianID         INT IDENTITY(1,1) NOT NULL,
        NPI                 VARCHAR(10) NOT NULL,               -- National Provider Identifier
        FirstName           NVARCHAR(50) NOT NULL,
        LastName            NVARCHAR(50) NOT NULL,
        MiddleName          NVARCHAR(50) NULL,
        Credentials         VARCHAR(20) NULL,                   -- MD, DO, NP, PA
        Specialty           NVARCHAR(100) NULL,
        DepartmentID        INT NULL,
        LicenseNumber       VARCHAR(50) NULL,
        LicenseState        CHAR(2) NULL,
        LicenseExpDate      DATE NULL,
        DEANumber           VARCHAR(20) NULL,                   -- Drug Enforcement Admin number
        Phone               VARCHAR(20) NULL,
        Email               NVARCHAR(200) NULL,
        -- Legacy: schedule stored as XML blob
        WeeklyScheduleXML   XML NULL,
        IsActive            BIT NOT NULL DEFAULT 1,
        HireDate            DATE NULL,
        TermDate            DATE NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Physicians PRIMARY KEY CLUSTERED (PhysicianID),
        CONSTRAINT UQ_Physicians_NPI UNIQUE (NPI),
        CONSTRAINT FK_Physicians_Department FOREIGN KEY (DepartmentID) REFERENCES dbo.Departments(DepartmentID)
    );
    PRINT 'Table dbo.Physicians created.';
END
GO

-- ============================================
-- Encounters
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Encounters') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Encounters (
        EncounterID         INT IDENTITY(1,1) NOT NULL,
        EncounterNumber     VARCHAR(20) NOT NULL,
        PatientID           INT NOT NULL,
        EncounterType       VARCHAR(20) NOT NULL,               -- INPATIENT, OUTPATIENT, EMERGENCY, OBSERVATION
        AdmitDate           DATETIME NOT NULL,
        DischargeDate       DATETIME NULL,
        AttendingPhysicianID INT NOT NULL,
        AdmittingPhysicianID INT NULL,
        ReferringPhysicianID INT NULL,
        DepartmentID        INT NULL,
        RoomNumber          VARCHAR(10) NULL,
        BedNumber           VARCHAR(5) NULL,
        AdmitDiagnosis      NVARCHAR(500) NULL,
        DischargeDiagnosis  NVARCHAR(500) NULL,
        DischargeDisposition VARCHAR(50) NULL,
        EncounterStatus     VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        -- Legacy: financial class stored redundantly
        FinancialClass      VARCHAR(50) NULL,
        InsuranceVerified   BIT NOT NULL DEFAULT 0,
        PreAuthNumber       VARCHAR(50) NULL,
        -- Legacy: total charges calculated and stored (denormalized)
        TotalCharges        DECIMAL(12,2) NULL DEFAULT 0.00,
        TotalPayments       DECIMAL(12,2) NULL DEFAULT 0.00,
        PatientBalance      DECIMAL(12,2) NULL DEFAULT 0.00,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        RowVersion          TIMESTAMP NOT NULL,
        CONSTRAINT PK_Encounters PRIMARY KEY CLUSTERED (EncounterID),
        CONSTRAINT UQ_Encounters_Number UNIQUE (EncounterNumber),
        CONSTRAINT FK_Encounters_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT FK_Encounters_AttendingPhysician FOREIGN KEY (AttendingPhysicianID) REFERENCES dbo.Physicians(PhysicianID),
        CONSTRAINT FK_Encounters_AdmittingPhysician FOREIGN KEY (AdmittingPhysicianID) REFERENCES dbo.Physicians(PhysicianID),
        CONSTRAINT FK_Encounters_Department FOREIGN KEY (DepartmentID) REFERENCES dbo.Departments(DepartmentID),
        CONSTRAINT CK_Encounters_Type CHECK (EncounterType IN ('INPATIENT', 'OUTPATIENT', 'EMERGENCY', 'OBSERVATION')),
        CONSTRAINT CK_Encounters_Status CHECK (EncounterStatus IN ('ACTIVE', 'DISCHARGED', 'CANCELLED', 'PREADMIT'))
    );

    CREATE NONCLUSTERED INDEX IX_Encounters_Patient ON dbo.Encounters (PatientID, AdmitDate DESC);
    CREATE NONCLUSTERED INDEX IX_Encounters_Dates ON dbo.Encounters (AdmitDate, DischargeDate) INCLUDE (PatientID, EncounterType, EncounterStatus);
    CREATE NONCLUSTERED INDEX IX_Encounters_Status ON dbo.Encounters (EncounterStatus) INCLUDE (PatientID, DepartmentID, RoomNumber);
    CREATE NONCLUSTERED INDEX IX_Encounters_Physician ON dbo.Encounters (AttendingPhysicianID, AdmitDate DESC);
    
    PRINT 'Table dbo.Encounters created.';
END
GO

-- ============================================
-- Orders
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Orders') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Orders (
        OrderID             INT IDENTITY(1,1) NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,                       -- Legacy: denormalized from Encounter
        OrderType           VARCHAR(20) NOT NULL,               -- LAB, RADIOLOGY, MEDICATION, DIET, CONSULT, PROCEDURE
        OrderCode           VARCHAR(20) NOT NULL,
        OrderDescription    NVARCHAR(500) NOT NULL,
        OrderingPhysicianID INT NOT NULL,
        OrderDate           DATETIME NOT NULL DEFAULT GETDATE(),
        OrderPriority       VARCHAR(20) NOT NULL DEFAULT 'ROUTINE',
        OrderStatus         VARCHAR(20) NOT NULL DEFAULT 'ORDERED',
        ScheduledDate       DATETIME NULL,
        CompletedDate       DATETIME NULL,
        CancelledDate       DATETIME NULL,
        CancelledReason     NVARCHAR(500) NULL,
        -- Legacy: clinical notes stored as TEXT (deprecated type)
        ClinicalNotes       TEXT NULL,
        ResultsAvailable    BIT NOT NULL DEFAULT 0,
        IsStatOrder         BIT NOT NULL DEFAULT 0,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID),
        CONSTRAINT FK_Orders_Encounter FOREIGN KEY (EncounterID) REFERENCES dbo.Encounters(EncounterID),
        CONSTRAINT FK_Orders_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT FK_Orders_Physician FOREIGN KEY (OrderingPhysicianID) REFERENCES dbo.Physicians(PhysicianID),
        CONSTRAINT CK_Orders_Type CHECK (OrderType IN ('LAB', 'RADIOLOGY', 'MEDICATION', 'DIET', 'CONSULT', 'PROCEDURE')),
        CONSTRAINT CK_Orders_Priority CHECK (OrderPriority IN ('STAT', 'URGENT', 'ROUTINE', 'TIMED')),
        CONSTRAINT CK_Orders_Status CHECK (OrderStatus IN ('ORDERED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'DISCONTINUED'))
    );

    CREATE NONCLUSTERED INDEX IX_Orders_Encounter ON dbo.Orders (EncounterID, OrderType);
    CREATE NONCLUSTERED INDEX IX_Orders_Patient ON dbo.Orders (PatientID, OrderDate DESC);
    CREATE NONCLUSTERED INDEX IX_Orders_Status ON dbo.Orders (OrderStatus, OrderType) INCLUDE (EncounterID, PatientID);
    
    PRINT 'Table dbo.Orders created.';
END
GO

-- ============================================
-- Medications
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Medications') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Medications (
        MedicationID        INT IDENTITY(1,1) NOT NULL,
        OrderID             INT NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,
        DrugCode            VARCHAR(20) NOT NULL,               -- NDC code
        DrugName            NVARCHAR(200) NOT NULL,
        GenericName         NVARCHAR(200) NULL,
        DrugClass           VARCHAR(50) NULL,
        Dosage              NVARCHAR(100) NOT NULL,
        DosageUnit          VARCHAR(20) NULL,
        Route               VARCHAR(50) NOT NULL,               -- ORAL, IV, IM, SC, etc.
        Frequency           VARCHAR(50) NOT NULL,               -- BID, TID, QID, PRN, etc.
        StartDate           DATETIME NOT NULL,
        EndDate             DATETIME NULL,
        DiscontinuedDate    DATETIME NULL,
        DiscontinuedReason  NVARCHAR(500) NULL,
        PrescribingPhysicianID INT NOT NULL,
        PharmacyVerified    BIT NOT NULL DEFAULT 0,
        PharmacyVerifiedDate DATETIME NULL,
        MedicationStatus    VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        IsControlledSubstance BIT NOT NULL DEFAULT 0,
        DEASchedule         INT NULL,                           -- Schedule I-V
        RefillsAllowed      INT NULL DEFAULT 0,
        RefillsUsed         INT NULL DEFAULT 0,
        -- Legacy: drug interaction check results stored as XML
        InteractionCheckXML XML NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Medications PRIMARY KEY CLUSTERED (MedicationID),
        CONSTRAINT FK_Medications_Order FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
        CONSTRAINT FK_Medications_Encounter FOREIGN KEY (EncounterID) REFERENCES dbo.Encounters(EncounterID),
        CONSTRAINT FK_Medications_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT FK_Medications_Physician FOREIGN KEY (PrescribingPhysicianID) REFERENCES dbo.Physicians(PhysicianID),
        CONSTRAINT CK_Medications_Status CHECK (MedicationStatus IN ('ACTIVE', 'COMPLETED', 'DISCONTINUED', 'ON_HOLD'))
    );

    CREATE NONCLUSTERED INDEX IX_Medications_Patient ON dbo.Medications (PatientID, MedicationStatus);
    CREATE NONCLUSTERED INDEX IX_Medications_Drug ON dbo.Medications (DrugCode) INCLUDE (DrugName, Dosage, PatientID);
    
    PRINT 'Table dbo.Medications created.';
END
GO

-- ============================================
-- LabResults
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.LabResults') AND type = 'U')
BEGIN
    CREATE TABLE dbo.LabResults (
        LabResultID         INT IDENTITY(1,1) NOT NULL,
        OrderID             INT NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,
        TestCode            VARCHAR(20) NOT NULL,
        TestName            NVARCHAR(200) NOT NULL,
        TestCategory        VARCHAR(50) NULL,                   -- CHEMISTRY, HEMATOLOGY, MICROBIOLOGY, etc.
        ResultValue         NVARCHAR(200) NULL,
        ResultNumeric       DECIMAL(18,6) NULL,
        ResultUnit          VARCHAR(50) NULL,
        ReferenceRangeLow   DECIMAL(18,6) NULL,
        ReferenceRangeHigh  DECIMAL(18,6) NULL,
        ReferenceRangeText  NVARCHAR(200) NULL,
        AbnormalFlag        VARCHAR(5) NULL,                    -- H, L, HH, LL, A
        CriticalFlag        BIT NOT NULL DEFAULT 0,
        ResultStatus        VARCHAR(20) NOT NULL DEFAULT 'PRELIMINARY',
        OrderedDate         DATETIME NULL,
        CollectedDate       DATETIME NULL,
        ReceivedDate        DATETIME NULL,
        ReportedDate        DATETIME NULL,
        VerifiedBy          NVARCHAR(100) NULL,
        VerifiedDate        DATETIME NULL,
        -- Legacy: raw HL7 message stored for audit
        RawHL7Message       TEXT NULL,
        Comments            NVARCHAR(MAX) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_LabResults PRIMARY KEY CLUSTERED (LabResultID),
        CONSTRAINT FK_LabResults_Order FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
        CONSTRAINT FK_LabResults_Encounter FOREIGN KEY (EncounterID) REFERENCES dbo.Encounters(EncounterID),
        CONSTRAINT FK_LabResults_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT CK_LabResults_Status CHECK (ResultStatus IN ('PRELIMINARY', 'FINAL', 'CORRECTED', 'CANCELLED'))
    );

    CREATE NONCLUSTERED INDEX IX_LabResults_Patient ON dbo.LabResults (PatientID, ReportedDate DESC);
    CREATE NONCLUSTERED INDEX IX_LabResults_Critical ON dbo.LabResults (CriticalFlag, ResultStatus) WHERE CriticalFlag = 1;
    CREATE NONCLUSTERED INDEX IX_LabResults_TestCode ON dbo.LabResults (TestCode, ReportedDate DESC);
    
    PRINT 'Table dbo.LabResults created.';
END
GO

-- ============================================
-- RadiologyStudies
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.RadiologyStudies') AND type = 'U')
BEGIN
    CREATE TABLE dbo.RadiologyStudies (
        StudyID             INT IDENTITY(1,1) NOT NULL,
        OrderID             INT NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,
        AccessionNumber     VARCHAR(20) NOT NULL,
        Modality            VARCHAR(10) NOT NULL,               -- XR, CT, MRI, US, NM, PET
        StudyDescription    NVARCHAR(500) NOT NULL,
        BodyPart            NVARCHAR(100) NULL,
        Laterality          VARCHAR(10) NULL,
        ContrastUsed        BIT NOT NULL DEFAULT 0,
        StudyDate           DATETIME NULL,
        ReadingPhysicianID  INT NULL,
        ReadDate            DATETIME NULL,
        StudyStatus         VARCHAR(20) NOT NULL DEFAULT 'ORDERED',
        CriticalFinding     BIT NOT NULL DEFAULT 0,
        -- Legacy: DICOM metadata stored as XML
        DICOMMetadataXML    XML NULL,
        -- Legacy: Report stored as NTEXT (deprecated type)
        ReportText          NTEXT NULL,
        Impression          NVARCHAR(MAX) NULL,
        -- Legacy: path to PACS image on file share
        PACSImagePath       NVARCHAR(500) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_RadiologyStudies PRIMARY KEY CLUSTERED (StudyID),
        CONSTRAINT FK_RadiologyStudies_Order FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
        CONSTRAINT FK_RadiologyStudies_Encounter FOREIGN KEY (EncounterID) REFERENCES dbo.Encounters(EncounterID),
        CONSTRAINT FK_RadiologyStudies_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT FK_RadiologyStudies_ReadingPhysician FOREIGN KEY (ReadingPhysicianID) REFERENCES dbo.Physicians(PhysicianID),
        CONSTRAINT CK_RadiologyStudies_Status CHECK (StudyStatus IN ('ORDERED', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'DICTATED', 'FINAL', 'CANCELLED'))
    );

    CREATE NONCLUSTERED INDEX IX_RadiologyStudies_Patient ON dbo.RadiologyStudies (PatientID, StudyDate DESC);
    CREATE NONCLUSTERED INDEX IX_RadiologyStudies_Accession ON dbo.RadiologyStudies (AccessionNumber);
    
    PRINT 'Table dbo.RadiologyStudies created.';
END
GO

-- ============================================
-- Diagnoses
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Diagnoses') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Diagnoses (
        DiagnosisID         INT IDENTITY(1,1) NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,
        ICDCode             VARCHAR(10) NOT NULL,               -- ICD-10 code
        ICDDescription      NVARCHAR(500) NOT NULL,
        DiagnosisType       VARCHAR(20) NOT NULL,               -- ADMITTING, PRIMARY, SECONDARY, WORKING
        DiagnosisSequence   INT NOT NULL DEFAULT 1,
        OnsetDate           DATE NULL,
        ResolvedDate        DATE NULL,
        DiagnosingPhysicianID INT NULL,
        IsPOA               CHAR(1) NULL,                       -- Present on Admission: Y/N/U/W
        ChronicIndicator    BIT NOT NULL DEFAULT 0,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Diagnoses PRIMARY KEY CLUSTERED (DiagnosisID),
        CONSTRAINT FK_Diagnoses_Encounter FOREIGN KEY (EncounterID) REFERENCES dbo.Encounters(EncounterID),
        CONSTRAINT FK_Diagnoses_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT FK_Diagnoses_Physician FOREIGN KEY (DiagnosingPhysicianID) REFERENCES dbo.Physicians(PhysicianID),
        CONSTRAINT CK_Diagnoses_Type CHECK (DiagnosisType IN ('ADMITTING', 'PRIMARY', 'SECONDARY', 'WORKING'))
    );

    CREATE NONCLUSTERED INDEX IX_Diagnoses_Patient ON dbo.Diagnoses (PatientID, ICDCode);
    CREATE NONCLUSTERED INDEX IX_Diagnoses_ICD ON dbo.Diagnoses (ICDCode) INCLUDE (ICDDescription, EncounterID);
    
    PRINT 'Table dbo.Diagnoses created.';
END
GO

-- ============================================
-- Procedures (clinical procedures, not to be confused with stored procs)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Procedures') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Procedures (
        ProcedureID         INT IDENTITY(1,1) NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,
        CPTCode             VARCHAR(10) NOT NULL,
        CPTDescription      NVARCHAR(500) NOT NULL,
        ProcedureDate       DATETIME NOT NULL,
        PerformingPhysicianID INT NOT NULL,
        AssistingPhysicianID INT NULL,
        AnesthesiaType      VARCHAR(50) NULL,
        Duration            INT NULL,                           -- minutes
        ProcedureStatus     VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED',
        Complications       NVARCHAR(MAX) NULL,
        -- Legacy: procedure notes stored as IMAGE type (really deprecated)
        ProcedureNotesBlob  IMAGE NULL,
        ChargeAmount        DECIMAL(10,2) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Procedures PRIMARY KEY CLUSTERED (ProcedureID),
        CONSTRAINT FK_Procedures_Encounter FOREIGN KEY (EncounterID) REFERENCES dbo.Encounters(EncounterID),
        CONSTRAINT FK_Procedures_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT FK_Procedures_PerformingPhysician FOREIGN KEY (PerformingPhysicianID) REFERENCES dbo.Physicians(PhysicianID),
        CONSTRAINT CK_Procedures_Status CHECK (ProcedureStatus IN ('SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'))
    );

    CREATE NONCLUSTERED INDEX IX_Procedures_Patient ON dbo.Procedures (PatientID, ProcedureDate DESC);
    CREATE NONCLUSTERED INDEX IX_Procedures_CPT ON dbo.Procedures (CPTCode);
    
    PRINT 'Table dbo.Procedures created.';
END
GO

-- ============================================
-- Vitals
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Vitals') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Vitals (
        VitalID             INT IDENTITY(1,1) NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,
        RecordedDate        DATETIME NOT NULL DEFAULT GETDATE(),
        RecordedBy          NVARCHAR(100) NOT NULL,
        Temperature         DECIMAL(5,2) NULL,                  -- Fahrenheit
        TemperatureSource   VARCHAR(20) NULL,                   -- ORAL, TYMPANIC, RECTAL, AXILLARY
        HeartRate           INT NULL,
        RespiratoryRate     INT NULL,
        SystolicBP          INT NULL,
        DiastolicBP         INT NULL,
        O2Saturation        DECIMAL(5,2) NULL,
        O2Delivery          VARCHAR(50) NULL,
        PainLevel           INT NULL,                           -- 0-10 scale
        HeightInches        DECIMAL(5,2) NULL,
        WeightPounds        DECIMAL(6,2) NULL,
        BMI                 AS (CASE 
                                WHEN HeightInches > 0 AND WeightPounds > 0 
                                THEN CAST((WeightPounds * 703.0) / (HeightInches * HeightInches) AS DECIMAL(5,2))
                                ELSE NULL 
                              END) PERSISTED,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_Vitals PRIMARY KEY CLUSTERED (VitalID),
        CONSTRAINT FK_Vitals_Encounter FOREIGN KEY (EncounterID) REFERENCES dbo.Encounters(EncounterID),
        CONSTRAINT FK_Vitals_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID)
    );

    CREATE NONCLUSTERED INDEX IX_Vitals_Patient ON dbo.Vitals (PatientID, RecordedDate DESC);
    CREATE NONCLUSTERED INDEX IX_Vitals_Encounter ON dbo.Vitals (EncounterID, RecordedDate DESC);
    
    PRINT 'Table dbo.Vitals created.';
END
GO

-- ============================================
-- ClinicalNotes
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.ClinicalNotes') AND type = 'U')
BEGIN
    CREATE TABLE dbo.ClinicalNotes (
        NoteID              INT IDENTITY(1,1) NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,
        NoteType            VARCHAR(50) NOT NULL,               -- PROGRESS, H&P, DISCHARGE_SUMMARY, CONSULT, OPERATIVE
        AuthorID            INT NOT NULL,
        NoteDate            DATETIME NOT NULL DEFAULT GETDATE(),
        -- Legacy: note content stored as NTEXT
        NoteContent         NTEXT NOT NULL,
        NoteStatus          VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
        SignedBy            INT NULL,
        SignedDate          DATETIME NULL,
        CoSignedBy          INT NULL,
        CoSignedDate        DATETIME NULL,
        Addendum            NTEXT NULL,
        AddendumDate        DATETIME NULL,
        IsConfidential      BIT NOT NULL DEFAULT 0,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_ClinicalNotes PRIMARY KEY CLUSTERED (NoteID),
        CONSTRAINT FK_ClinicalNotes_Encounter FOREIGN KEY (EncounterID) REFERENCES dbo.Encounters(EncounterID),
        CONSTRAINT FK_ClinicalNotes_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT FK_ClinicalNotes_Author FOREIGN KEY (AuthorID) REFERENCES dbo.Physicians(PhysicianID),
        CONSTRAINT CK_ClinicalNotes_Status CHECK (NoteStatus IN ('DRAFT', 'SIGNED', 'COSIGNED', 'AMENDED', 'ADDENDED'))
    );

    CREATE NONCLUSTERED INDEX IX_ClinicalNotes_Patient ON dbo.ClinicalNotes (PatientID, NoteDate DESC);
    CREATE NONCLUSTERED INDEX IX_ClinicalNotes_Encounter ON dbo.ClinicalNotes (EncounterID, NoteType);
    
    PRINT 'Table dbo.ClinicalNotes created.';
END
GO

-- ============================================
-- Allergies
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Allergies') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Allergies (
        AllergyID           INT IDENTITY(1,1) NOT NULL,
        PatientID           INT NOT NULL,
        AllergyType         VARCHAR(20) NOT NULL,               -- DRUG, FOOD, ENVIRONMENTAL
        AllergenName        NVARCHAR(200) NOT NULL,
        AllergenCode        VARCHAR(20) NULL,
        Reaction            NVARCHAR(500) NULL,
        Severity            VARCHAR(20) NOT NULL DEFAULT 'MODERATE',
        OnsetDate           DATE NULL,
        ReportedDate        DATETIME NOT NULL DEFAULT GETDATE(),
        ReportedBy          NVARCHAR(100) NULL,
        VerifiedBy          INT NULL,
        VerifiedDate        DATETIME NULL,
        AllergyStatus       VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        Comments            NVARCHAR(MAX) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Allergies PRIMARY KEY CLUSTERED (AllergyID),
        CONSTRAINT FK_Allergies_Patient FOREIGN KEY (PatientID) REFERENCES dbo.Patients(PatientID),
        CONSTRAINT CK_Allergies_Type CHECK (AllergyType IN ('DRUG', 'FOOD', 'ENVIRONMENTAL', 'LATEX', 'CONTRAST')),
        CONSTRAINT CK_Allergies_Severity CHECK (Severity IN ('MILD', 'MODERATE', 'SEVERE', 'LIFE_THREATENING'))
    );

    CREATE NONCLUSTERED INDEX IX_Allergies_Patient ON dbo.Allergies (PatientID, AllergyStatus);
    
    PRINT 'Table dbo.Allergies created.';
END
GO

-- ============================================
-- AuditLog
-- Legacy pattern: trigger-based audit logging
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.AuditLog') AND type = 'U')
BEGIN
    CREATE TABLE dbo.AuditLog (
        AuditLogID          BIGINT IDENTITY(1,1) NOT NULL,
        TableName           VARCHAR(128) NOT NULL,
        RecordID            INT NOT NULL,
        Action              VARCHAR(10) NOT NULL,               -- INSERT, UPDATE, DELETE
        OldValues           NVARCHAR(MAX) NULL,
        NewValues           NVARCHAR(MAX) NULL,
        ChangedBy           NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
        ChangedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ApplicationName     NVARCHAR(128) NULL DEFAULT APP_NAME(),
        HostName            NVARCHAR(128) NULL DEFAULT HOST_NAME(),
        CONSTRAINT PK_AuditLog PRIMARY KEY CLUSTERED (AuditLogID)
    );

    -- Partitioned-like index for date-based queries (no real partitioning on Standard Edition)
    CREATE NONCLUSTERED INDEX IX_AuditLog_Date ON dbo.AuditLog (ChangedDate DESC) INCLUDE (TableName, Action);
    CREATE NONCLUSTERED INDEX IX_AuditLog_Table ON dbo.AuditLog (TableName, RecordID) INCLUDE (Action, ChangedDate);
    
    PRINT 'Table dbo.AuditLog created.';
END
GO

-- ============================================
-- Chargemaster (fee schedule)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Chargemaster') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Chargemaster (
        ChargemasterID      INT IDENTITY(1,1) NOT NULL,
        ChargeCode          VARCHAR(20) NOT NULL,
        CPTCode             VARCHAR(10) NULL,
        RevenueCode         VARCHAR(10) NULL,
        ChargeDescription   NVARCHAR(500) NOT NULL,
        DepartmentID        INT NULL,
        StandardCharge      DECIMAL(10,2) NOT NULL,
        MedicareRate        DECIMAL(10,2) NULL,
        MedicaidRate        DECIMAL(10,2) NULL,
        EffectiveDate       DATE NOT NULL,
        ExpirationDate      DATE NULL,
        IsActive            BIT NOT NULL DEFAULT 1,
        GLAccountCode       VARCHAR(20) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Chargemaster PRIMARY KEY CLUSTERED (ChargemasterID),
        CONSTRAINT UQ_Chargemaster_Code UNIQUE (ChargeCode, EffectiveDate),
        CONSTRAINT FK_Chargemaster_Department FOREIGN KEY (DepartmentID) REFERENCES dbo.Departments(DepartmentID)
    );

    CREATE NONCLUSTERED INDEX IX_Chargemaster_CPT ON dbo.Chargemaster (CPTCode) WHERE CPTCode IS NOT NULL;
    CREATE NONCLUSTERED INDEX IX_Chargemaster_Active ON dbo.Chargemaster (IsActive, EffectiveDate) INCLUDE (ChargeCode, StandardCharge);
    
    PRINT 'Table dbo.Chargemaster created.';
END
GO

-- ============================================
-- Audit Triggers (Legacy anti-pattern: heavy triggers on critical tables)
-- ============================================
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_Patients_Audit')
    DROP TRIGGER dbo.trg_Patients_Audit;
GO

CREATE TRIGGER dbo.trg_Patients_Audit
ON dbo.Patients
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Action VARCHAR(10);
    
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @Action = 'INSERT';
    ELSE
        SET @Action = 'DELETE';
    
    -- Legacy: serialize row data to XML for audit trail
    IF @Action IN ('UPDATE', 'DELETE')
    BEGIN
        INSERT INTO dbo.AuditLog (TableName, RecordID, Action, OldValues, ChangedBy)
        SELECT 'Patients', d.PatientID, @Action,
               (SELECT d.* FOR XML RAW('OldRecord')),
               SUSER_SNAME()
        FROM deleted d;
    END
    
    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        UPDATE dbo.AuditLog 
        SET NewValues = (SELECT i.* FOR XML RAW('NewRecord'))
        FROM dbo.AuditLog a
        INNER JOIN inserted i ON a.RecordID = i.PatientID
        WHERE a.TableName = 'Patients' 
          AND a.Action = @Action
          AND a.ChangedDate >= DATEADD(SECOND, -1, GETDATE());
          
        -- Insert for new records (INSERT action)
        IF @Action = 'INSERT'
        BEGIN
            INSERT INTO dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
            SELECT 'Patients', i.PatientID, @Action,
                   (SELECT i.* FOR XML RAW('NewRecord')),
                   SUSER_SNAME()
            FROM inserted i;
        END
    END
END
GO

PRINT 'Audit trigger on Patients created.';
GO

-- ============================================
-- Trigger: Auto-update ModifiedDate 
-- Legacy pattern: triggers instead of application logic
-- ============================================
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_Patients_ModifiedDate')
    DROP TRIGGER dbo.trg_Patients_ModifiedDate;
GO

CREATE TRIGGER dbo.trg_Patients_ModifiedDate
ON dbo.Patients
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE p SET ModifiedDate = GETDATE(), ModifiedBy = SUSER_SNAME()
    FROM dbo.Patients p
    INNER JOIN inserted i ON p.PatientID = i.PatientID;
END
GO

PRINT 'ModifiedDate trigger on Patients created.';
GO

PRINT '========================================';
PRINT 'All PatientDB tables created successfully.';
PRINT '========================================';
GO
