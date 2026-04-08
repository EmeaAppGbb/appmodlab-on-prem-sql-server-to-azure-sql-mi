-- ============================================
-- BillingDB Tables
-- Lakeview Medical Center
-- ============================================
USE BillingDB;
GO

-- ============================================
-- Chargemaster (local copy synced from PatientDB)
-- Legacy: duplicated reference data across databases
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Chargemaster') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Chargemaster (
        ChargemasterID      INT IDENTITY(1,1) NOT NULL,
        ChargeCode          VARCHAR(20) NOT NULL,
        CPTCode             VARCHAR(10) NULL,
        HCPCSCode           VARCHAR(10) NULL,
        RevenueCode         VARCHAR(10) NULL,
        ChargeDescription   NVARCHAR(500) NOT NULL,
        StandardCharge      DECIMAL(10,2) NOT NULL,
        MedicareRate        DECIMAL(10,2) NULL,
        MedicaidRate        DECIMAL(10,2) NULL,
        CommercialRate      DECIMAL(10,2) NULL,
        EffectiveDate       DATE NOT NULL,
        ExpirationDate      DATE NULL,
        IsActive            BIT NOT NULL DEFAULT 1,
        GLAccountCode       VARCHAR(20) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_BillingChargemaster PRIMARY KEY CLUSTERED (ChargemasterID),
        CONSTRAINT UQ_BillingChargemaster_Code UNIQUE (ChargeCode, EffectiveDate)
    );
    PRINT 'Table dbo.Chargemaster created.';
END
GO

-- ============================================
-- BillingCharges
-- Individual charges posted to encounters
-- Legacy: cross-database FK reference to PatientDB
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.BillingCharges') AND type = 'U')
BEGIN
    CREATE TABLE dbo.BillingCharges (
        ChargeID            INT IDENTITY(1,1) NOT NULL,
        EncounterID         INT NOT NULL,                       -- References PatientDB.dbo.Encounters (no FK constraint cross-db)
        PatientID           INT NOT NULL,                       -- References PatientDB.dbo.Patients
        ChargeCode          VARCHAR(20) NOT NULL,
        CPTCode             VARCHAR(10) NULL,
        RevenueCode         VARCHAR(10) NULL,
        ChargeDescription   NVARCHAR(500) NOT NULL,
        ServiceDate         DATETIME NOT NULL,
        Quantity            INT NOT NULL DEFAULT 1,
        UnitPrice           DECIMAL(10,2) NOT NULL,
        ChargeAmount        DECIMAL(10,2) NOT NULL,
        AdjustmentAmount    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
        NetAmount           AS (ChargeAmount - AdjustmentAmount) PERSISTED,
        PostedDate          DATETIME NOT NULL DEFAULT GETDATE(),
        PostedBy            NVARCHAR(100) NOT NULL DEFAULT SUSER_SNAME(),
        DepartmentCode      VARCHAR(10) NULL,
        PerformingPhysicianNPI VARCHAR(10) NULL,
        -- Diagnosis codes for this charge (up to 4)
        DiagnosisCode1      VARCHAR(10) NULL,
        DiagnosisCode2      VARCHAR(10) NULL,
        DiagnosisCode3      VARCHAR(10) NULL,
        DiagnosisCode4      VARCHAR(10) NULL,
        ModifierCode1       VARCHAR(5) NULL,
        ModifierCode2       VARCHAR(5) NULL,
        ChargeStatus        VARCHAR(20) NOT NULL DEFAULT 'POSTED',
        VoidDate            DATETIME NULL,
        VoidReason          NVARCHAR(500) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_BillingCharges PRIMARY KEY CLUSTERED (ChargeID),
        CONSTRAINT CK_BillingCharges_Status CHECK (ChargeStatus IN ('POSTED', 'BILLED', 'PAID', 'ADJUSTED', 'VOIDED', 'TRANSFERRED'))
    );

    CREATE NONCLUSTERED INDEX IX_BillingCharges_Encounter ON dbo.BillingCharges (EncounterID, ServiceDate);
    CREATE NONCLUSTERED INDEX IX_BillingCharges_Patient ON dbo.BillingCharges (PatientID, PostedDate DESC);
    CREATE NONCLUSTERED INDEX IX_BillingCharges_Status ON dbo.BillingCharges (ChargeStatus) INCLUDE (EncounterID, ChargeAmount, NetAmount);
    CREATE NONCLUSTERED INDEX IX_BillingCharges_ServiceDate ON dbo.BillingCharges (ServiceDate) INCLUDE (PatientID, ChargeAmount);

    PRINT 'Table dbo.BillingCharges created.';
END
GO

-- ============================================
-- InsuranceClaims
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.InsuranceClaims') AND type = 'U')
BEGIN
    CREATE TABLE dbo.InsuranceClaims (
        ClaimID             INT IDENTITY(1,1) NOT NULL,
        ClaimNumber         VARCHAR(20) NOT NULL,
        EncounterID         INT NOT NULL,
        PatientID           INT NOT NULL,
        InsuranceProviderID INT NOT NULL,                       -- References PatientDB.dbo.InsuranceProviders
        PayerID             VARCHAR(20) NULL,
        PolicyNumber        VARCHAR(50) NULL,
        GroupNumber          VARCHAR(50) NULL,
        SubscriberName      NVARCHAR(200) NULL,
        SubscriberDOB       DATE NULL,
        SubscriberRelation  VARCHAR(20) NULL,
        ClaimType           VARCHAR(20) NOT NULL,               -- INSTITUTIONAL, PROFESSIONAL
        ClaimForm           VARCHAR(10) NULL,                   -- UB04, CMS1500
        TotalCharges        DECIMAL(12,2) NOT NULL,
        AllowedAmount       DECIMAL(12,2) NULL,
        PaidAmount          DECIMAL(12,2) NULL DEFAULT 0.00,
        PatientResponsibility DECIMAL(12,2) NULL,
        DeductibleAmount    DECIMAL(10,2) NULL,
        CoinsuranceAmount   DECIMAL(10,2) NULL,
        CopayAmount         DECIMAL(10,2) NULL,
        -- Claim lifecycle
        ClaimStatus         VARCHAR(20) NOT NULL DEFAULT 'CREATED',
        SubmittedDate       DATETIME NULL,
        AcknowledgedDate    DATETIME NULL,
        AdjudicatedDate     DATETIME NULL,
        PaidDate            DATETIME NULL,
        DeniedDate          DATETIME NULL,
        DenialReasonCode    VARCHAR(20) NULL,
        DenialReasonText    NVARCHAR(500) NULL,
        AppealDeadline      DATE NULL,
        AppealedDate        DATETIME NULL,
        -- EDI Tracking
        EDIBatchID          VARCHAR(50) NULL,
        EDITransactionID    VARCHAR(50) NULL,
        -- Legacy: full 837 EDI transaction stored as text
        EDI837Content       TEXT NULL,
        -- Legacy: full 835 remittance stored as text
        EDI835Content       TEXT NULL,
        PreAuthNumber       VARCHAR(50) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_InsuranceClaims PRIMARY KEY CLUSTERED (ClaimID),
        CONSTRAINT UQ_InsuranceClaims_Number UNIQUE (ClaimNumber),
        CONSTRAINT CK_InsuranceClaims_Status CHECK (ClaimStatus IN ('CREATED', 'SUBMITTED', 'ACKNOWLEDGED', 'ADJUDICATED', 'PAID', 'PARTIAL_PAID', 'DENIED', 'APPEALED', 'VOIDED'))
    );

    CREATE NONCLUSTERED INDEX IX_InsuranceClaims_Encounter ON dbo.InsuranceClaims (EncounterID);
    CREATE NONCLUSTERED INDEX IX_InsuranceClaims_Patient ON dbo.InsuranceClaims (PatientID, ClaimStatus);
    CREATE NONCLUSTERED INDEX IX_InsuranceClaims_Status ON dbo.InsuranceClaims (ClaimStatus, SubmittedDate);
    CREATE NONCLUSTERED INDEX IX_InsuranceClaims_Payer ON dbo.InsuranceClaims (InsuranceProviderID, ClaimStatus);

    PRINT 'Table dbo.InsuranceClaims created.';
END
GO

-- ============================================
-- ClaimLineItems
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.ClaimLineItems') AND type = 'U')
BEGIN
    CREATE TABLE dbo.ClaimLineItems (
        LineItemID          INT IDENTITY(1,1) NOT NULL,
        ClaimID             INT NOT NULL,
        LineNumber          INT NOT NULL,
        ChargeID            INT NOT NULL,
        ServiceDate         DATE NOT NULL,
        PlaceOfService      VARCHAR(5) NULL,
        CPTCode             VARCHAR(10) NOT NULL,
        ModifierCode1       VARCHAR(5) NULL,
        ModifierCode2       VARCHAR(5) NULL,
        DiagnosisPointer    VARCHAR(10) NULL,                   -- e.g., "1,2" pointing to claim-level DX
        Quantity            INT NOT NULL DEFAULT 1,
        ChargeAmount        DECIMAL(10,2) NOT NULL,
        AllowedAmount       DECIMAL(10,2) NULL,
        PaidAmount          DECIMAL(10,2) NULL DEFAULT 0.00,
        AdjustmentReason    VARCHAR(10) NULL,                   -- CARC/RARC codes
        AdjustmentAmount    DECIMAL(10,2) NULL DEFAULT 0.00,
        LineStatus          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_ClaimLineItems PRIMARY KEY CLUSTERED (LineItemID),
        CONSTRAINT FK_ClaimLineItems_Claim FOREIGN KEY (ClaimID) REFERENCES dbo.InsuranceClaims(ClaimID),
        CONSTRAINT FK_ClaimLineItems_Charge FOREIGN KEY (ChargeID) REFERENCES dbo.BillingCharges(ChargeID)
    );

    CREATE NONCLUSTERED INDEX IX_ClaimLineItems_Claim ON dbo.ClaimLineItems (ClaimID, LineNumber);

    PRINT 'Table dbo.ClaimLineItems created.';
END
GO

-- ============================================
-- Payments
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Payments') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Payments (
        PaymentID           INT IDENTITY(1,1) NOT NULL,
        PaymentNumber       VARCHAR(20) NOT NULL,
        PatientID           INT NOT NULL,
        EncounterID         INT NULL,
        ClaimID             INT NULL,
        PaymentSource       VARCHAR(20) NOT NULL,               -- INSURANCE, PATIENT, COLLECTION_AGENCY
        PayerName           NVARCHAR(200) NULL,
        PaymentMethod       VARCHAR(20) NOT NULL,               -- CHECK, EFT, CREDIT_CARD, CASH, WIRE
        PaymentAmount       DECIMAL(10,2) NOT NULL,
        PaymentDate         DATE NOT NULL,
        PostedDate          DATETIME NOT NULL DEFAULT GETDATE(),
        PostedBy            NVARCHAR(100) NOT NULL DEFAULT SUSER_SNAME(),
        CheckNumber         VARCHAR(50) NULL,
        EFTTraceNumber      VARCHAR(50) NULL,
        BatchNumber         VARCHAR(20) NULL,
        DepositDate         DATE NULL,
        PaymentStatus       VARCHAR(20) NOT NULL DEFAULT 'POSTED',
        VoidDate            DATETIME NULL,
        VoidReason          NVARCHAR(500) NULL,
        Comments            NVARCHAR(500) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Payments PRIMARY KEY CLUSTERED (PaymentID),
        CONSTRAINT UQ_Payments_Number UNIQUE (PaymentNumber),
        CONSTRAINT CK_Payments_Status CHECK (PaymentStatus IN ('POSTED', 'APPLIED', 'VOIDED', 'REFUNDED'))
    );

    CREATE NONCLUSTERED INDEX IX_Payments_Patient ON dbo.Payments (PatientID, PaymentDate DESC);
    CREATE NONCLUSTERED INDEX IX_Payments_Encounter ON dbo.Payments (EncounterID) WHERE EncounterID IS NOT NULL;
    CREATE NONCLUSTERED INDEX IX_Payments_Date ON dbo.Payments (PaymentDate, PaymentSource);

    PRINT 'Table dbo.Payments created.';
END
GO

-- ============================================
-- Invoices (Patient statements)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Invoices') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Invoices (
        InvoiceID           INT IDENTITY(1,1) NOT NULL,
        InvoiceNumber       VARCHAR(20) NOT NULL,
        PatientID           INT NOT NULL,
        EncounterID         INT NULL,
        InvoiceDate         DATE NOT NULL DEFAULT GETDATE(),
        DueDate             DATE NOT NULL,
        TotalAmount         DECIMAL(12,2) NOT NULL,
        PaidAmount          DECIMAL(12,2) NOT NULL DEFAULT 0.00,
        BalanceDue          AS (TotalAmount - PaidAmount) PERSISTED,
        StatementCount      INT NOT NULL DEFAULT 1,
        LastStatementDate   DATE NULL,
        InvoiceStatus       VARCHAR(20) NOT NULL DEFAULT 'OPEN',
        SentToCollections   BIT NOT NULL DEFAULT 0,
        CollectionDate      DATETIME NULL,
        PaymentPlanID       INT NULL,
        Comments            NVARCHAR(500) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Invoices PRIMARY KEY CLUSTERED (InvoiceID),
        CONSTRAINT UQ_Invoices_Number UNIQUE (InvoiceNumber),
        CONSTRAINT CK_Invoices_Status CHECK (InvoiceStatus IN ('OPEN', 'PAID', 'PARTIAL', 'COLLECTIONS', 'WRITTEN_OFF', 'VOIDED'))
    );

    CREATE NONCLUSTERED INDEX IX_Invoices_Patient ON dbo.Invoices (PatientID, InvoiceStatus);
    CREATE NONCLUSTERED INDEX IX_Invoices_Status ON dbo.Invoices (InvoiceStatus, DueDate);

    PRINT 'Table dbo.Invoices created.';
END
GO

-- ============================================
-- PaymentPlans
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PaymentPlans') AND type = 'U')
BEGIN
    CREATE TABLE dbo.PaymentPlans (
        PaymentPlanID       INT IDENTITY(1,1) NOT NULL,
        PatientID           INT NOT NULL,
        InvoiceID           INT NULL,
        TotalBalance        DECIMAL(12,2) NOT NULL,
        MonthlyPayment      DECIMAL(10,2) NOT NULL,
        NumberOfPayments    INT NOT NULL,
        PaymentsCompleted   INT NOT NULL DEFAULT 0,
        RemainingBalance    DECIMAL(12,2) NOT NULL,
        StartDate           DATE NOT NULL,
        NextPaymentDate     DATE NULL,
        PlanStatus          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        DefaultedDate       DATETIME NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_PaymentPlans PRIMARY KEY CLUSTERED (PaymentPlanID),
        CONSTRAINT CK_PaymentPlans_Status CHECK (PlanStatus IN ('ACTIVE', 'COMPLETED', 'DEFAULTED', 'CANCELLED'))
    );

    CREATE NONCLUSTERED INDEX IX_PaymentPlans_Patient ON dbo.PaymentPlans (PatientID, PlanStatus);

    PRINT 'Table dbo.PaymentPlans created.';
END
GO

-- ============================================
-- Collections
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Collections') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Collections (
        CollectionID        INT IDENTITY(1,1) NOT NULL,
        PatientID           INT NOT NULL,
        InvoiceID           INT NOT NULL,
        CollectionAgency    NVARCHAR(200) NOT NULL,
        AgencyAccountNumber VARCHAR(50) NULL,
        OriginalBalance     DECIMAL(12,2) NOT NULL,
        CurrentBalance      DECIMAL(12,2) NOT NULL,
        SentDate            DATE NOT NULL,
        LastContactDate     DATE NULL,
        CollectionStatus    VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        RecoveredAmount     DECIMAL(12,2) NOT NULL DEFAULT 0.00,
        AgencyFeePercent    DECIMAL(5,2) NULL DEFAULT 25.00,
        Comments            NVARCHAR(MAX) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Collections PRIMARY KEY CLUSTERED (CollectionID),
        CONSTRAINT FK_Collections_Invoice FOREIGN KEY (InvoiceID) REFERENCES dbo.Invoices(InvoiceID),
        CONSTRAINT CK_Collections_Status CHECK (CollectionStatus IN ('ACTIVE', 'RECOVERED', 'WRITTEN_OFF', 'RECALLED'))
    );

    PRINT 'Table dbo.Collections created.';
END
GO

-- ============================================
-- BillingAudit
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.BillingAudit') AND type = 'U')
BEGIN
    CREATE TABLE dbo.BillingAudit (
        AuditID             BIGINT IDENTITY(1,1) NOT NULL,
        TableName           VARCHAR(128) NOT NULL,
        RecordID            INT NOT NULL,
        Action              VARCHAR(20) NOT NULL,
        OldValues           NVARCHAR(MAX) NULL,
        NewValues           NVARCHAR(MAX) NULL,
        ChangedBy           NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
        ChangedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        IPAddress           VARCHAR(45) NULL,
        ApplicationName     NVARCHAR(128) NULL DEFAULT APP_NAME(),
        CONSTRAINT PK_BillingAudit PRIMARY KEY CLUSTERED (AuditID)
    );

    CREATE NONCLUSTERED INDEX IX_BillingAudit_Date ON dbo.BillingAudit (ChangedDate DESC);
    CREATE NONCLUSTERED INDEX IX_BillingAudit_Table ON dbo.BillingAudit (TableName, RecordID);

    PRINT 'Table dbo.BillingAudit created.';
END
GO

PRINT '========================================';
PRINT 'All BillingDB tables created successfully.';
PRINT '========================================';
GO
