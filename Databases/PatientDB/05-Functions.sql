-- ============================================
-- PatientDB Functions
-- Lakeview Medical Center
-- Scalar and table-valued functions
-- ============================================
USE PatientDB;
GO

-- ============================================
-- fn_CalculateAge
-- Calculates exact age from date of birth
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_CalculateAge') AND type = 'FN')
    DROP FUNCTION dbo.fn_CalculateAge;
GO

CREATE FUNCTION dbo.fn_CalculateAge
(
    @DateOfBirth DATE,
    @AsOfDate DATE = NULL
)
RETURNS INT
AS
BEGIN
    IF @AsOfDate IS NULL
        SET @AsOfDate = GETDATE();
    
    RETURN DATEDIFF(YEAR, @DateOfBirth, @AsOfDate) 
        - CASE 
            WHEN DATEADD(YEAR, DATEDIFF(YEAR, @DateOfBirth, @AsOfDate), @DateOfBirth) > @AsOfDate 
            THEN 1 
            ELSE 0 
          END;
END
GO

PRINT 'Function dbo.fn_CalculateAge created.';
GO

-- ============================================
-- fn_CalculateBMI
-- Calculates BMI from height (inches) and weight (pounds)
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_CalculateBMI') AND type = 'FN')
    DROP FUNCTION dbo.fn_CalculateBMI;
GO

CREATE FUNCTION dbo.fn_CalculateBMI
(
    @HeightInches DECIMAL(5,2),
    @WeightPounds DECIMAL(6,2)
)
RETURNS DECIMAL(5,2)
AS
BEGIN
    IF @HeightInches IS NULL OR @HeightInches <= 0 OR @WeightPounds IS NULL OR @WeightPounds <= 0
        RETURN NULL;
    
    RETURN CAST((@WeightPounds * 703.0) / (@HeightInches * @HeightInches) AS DECIMAL(5,2));
END
GO

PRINT 'Function dbo.fn_CalculateBMI created.';
GO

-- ============================================
-- fn_FormatPatientName
-- Formats patient name in various styles
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_FormatPatientName') AND type = 'FN')
    DROP FUNCTION dbo.fn_FormatPatientName;
GO

CREATE FUNCTION dbo.fn_FormatPatientName
(
    @FirstName NVARCHAR(50),
    @MiddleName NVARCHAR(50),
    @LastName NVARCHAR(50),
    @Suffix NVARCHAR(10),
    @Format VARCHAR(20) = 'LAST_FIRST'  -- LAST_FIRST, FIRST_LAST, FULL, FORMAL
)
RETURNS NVARCHAR(200)
AS
BEGIN
    DECLARE @Result NVARCHAR(200);
    
    SET @Result = CASE @Format
        WHEN 'LAST_FIRST' THEN 
            @LastName + ', ' + @FirstName + ISNULL(' ' + LEFT(@MiddleName, 1) + '.', '')
        WHEN 'FIRST_LAST' THEN 
            @FirstName + ISNULL(' ' + @MiddleName, '') + ' ' + @LastName + ISNULL(' ' + @Suffix, '')
        WHEN 'FULL' THEN 
            @FirstName + ISNULL(' ' + @MiddleName, '') + ' ' + @LastName + ISNULL(', ' + @Suffix, '')
        WHEN 'FORMAL' THEN 
            @LastName + ', ' + @FirstName + ISNULL(' ' + @MiddleName, '') + ISNULL(', ' + @Suffix, '')
        ELSE 
            @LastName + ', ' + @FirstName
    END;
    
    RETURN @Result;
END
GO

PRINT 'Function dbo.fn_FormatPatientName created.';
GO

-- ============================================
-- fn_GetPatientEncounters (Table-valued function)
-- Returns encounter history for a patient
-- Legacy: multi-statement TVF (performance concern)
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_GetPatientEncounters') AND type = 'IF')
    DROP FUNCTION dbo.fn_GetPatientEncounters;
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_GetPatientEncounters') AND type = 'TF')
    DROP FUNCTION dbo.fn_GetPatientEncounters;
GO

CREATE FUNCTION dbo.fn_GetPatientEncounters
(
    @PatientID INT,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
)
RETURNS @Encounters TABLE
(
    EncounterID         INT,
    EncounterNumber     VARCHAR(20),
    EncounterType       VARCHAR(20),
    AdmitDate           DATETIME,
    DischargeDate       DATETIME,
    LengthOfStay        INT,
    AttendingPhysician  NVARCHAR(100),
    DepartmentName      NVARCHAR(100),
    PrimaryDiagnosis    NVARCHAR(500),
    TotalCharges        DECIMAL(12,2),
    EncounterStatus     VARCHAR(20)
)
AS
BEGIN
    -- Legacy: multi-statement TVF populating table variable
    INSERT INTO @Encounters
    SELECT 
        e.EncounterID,
        e.EncounterNumber,
        e.EncounterType,
        e.AdmitDate,
        e.DischargeDate,
        DATEDIFF(DAY, e.AdmitDate, ISNULL(e.DischargeDate, GETDATE())),
        ph.LastName + ', ' + ph.FirstName + ' ' + ISNULL(ph.Credentials, ''),
        d.DepartmentName,
        (SELECT TOP 1 dx.ICDDescription FROM dbo.Diagnoses dx 
         WHERE dx.EncounterID = e.EncounterID AND dx.DiagnosisType = 'PRIMARY'),
        e.TotalCharges,
        e.EncounterStatus
    FROM dbo.Encounters e
    INNER JOIN dbo.Physicians ph ON e.AttendingPhysicianID = ph.PhysicianID
    LEFT JOIN dbo.Departments d ON e.DepartmentID = d.DepartmentID
    WHERE e.PatientID = @PatientID
      AND (@StartDate IS NULL OR e.AdmitDate >= @StartDate)
      AND (@EndDate IS NULL OR e.AdmitDate <= @EndDate)
    ORDER BY e.AdmitDate DESC;
    
    RETURN;
END
GO

PRINT 'Function dbo.fn_GetPatientEncounters created.';
GO

-- ============================================
-- fn_GetActiveMedications (Table-valued function)
-- Returns active medications for a patient
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_GetActiveMedications') AND type = 'TF')
    DROP FUNCTION dbo.fn_GetActiveMedications;
GO

CREATE FUNCTION dbo.fn_GetActiveMedications
(
    @PatientID INT
)
RETURNS @Medications TABLE
(
    MedicationID        INT,
    DrugName            NVARCHAR(200),
    GenericName         NVARCHAR(200),
    DrugClass           VARCHAR(50),
    Dosage              NVARCHAR(100),
    Route               VARCHAR(50),
    Frequency           VARCHAR(50),
    StartDate           DATETIME,
    DaysOnMedication    INT,
    PrescribingPhysician NVARCHAR(100),
    IsControlledSubstance BIT,
    HasAllergyConflict  BIT
)
AS
BEGIN
    INSERT INTO @Medications
    SELECT 
        m.MedicationID,
        m.DrugName,
        m.GenericName,
        m.DrugClass,
        m.Dosage,
        m.Route,
        m.Frequency,
        m.StartDate,
        DATEDIFF(DAY, m.StartDate, GETDATE()),
        ph.LastName + ', ' + ph.FirstName,
        m.IsControlledSubstance,
        CASE WHEN EXISTS (
            SELECT 1 FROM dbo.Allergies a 
            WHERE a.PatientID = @PatientID 
              AND a.AllergyType = 'DRUG' 
              AND a.AllergyStatus = 'ACTIVE'
              AND m.DrugName LIKE '%' + a.AllergenName + '%'
        ) THEN 1 ELSE 0 END
    FROM dbo.Medications m
    INNER JOIN dbo.Physicians ph ON m.PrescribingPhysicianID = ph.PhysicianID
    WHERE m.PatientID = @PatientID
      AND m.MedicationStatus = 'ACTIVE';
    
    RETURN;
END
GO

PRINT 'Function dbo.fn_GetActiveMedications created.';
GO

-- ============================================
-- fn_GetLabResultsSummary (Table-valued function)
-- Returns lab results summary with trending
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_GetLabResultsSummary') AND type = 'TF')
    DROP FUNCTION dbo.fn_GetLabResultsSummary;
GO

CREATE FUNCTION dbo.fn_GetLabResultsSummary
(
    @PatientID INT,
    @TestCode VARCHAR(20) = NULL,
    @DaysBack INT = 90
)
RETURNS @Results TABLE
(
    TestCode            VARCHAR(20),
    TestName            NVARCHAR(200),
    LatestValue         NVARCHAR(200),
    LatestNumeric       DECIMAL(18,6),
    LatestDate          DATETIME,
    PreviousValue       NVARCHAR(200),
    PreviousDate        DATETIME,
    ReferenceRangeLow   DECIMAL(18,6),
    ReferenceRangeHigh  DECIMAL(18,6),
    AbnormalFlag        VARCHAR(5),
    TrendDirection      VARCHAR(10),   -- UP, DOWN, STABLE
    ResultCount         INT
)
AS
BEGIN
    -- Legacy: complex multi-statement TVF with self-join for trending
    INSERT INTO @Results
    SELECT 
        lr.TestCode,
        lr.TestName,
        lr.ResultValue,
        lr.ResultNumeric,
        lr.ReportedDate,
        prev.ResultValue,
        prev.ReportedDate,
        lr.ReferenceRangeLow,
        lr.ReferenceRangeHigh,
        lr.AbnormalFlag,
        CASE 
            WHEN lr.ResultNumeric IS NOT NULL AND prev.ResultNumeric IS NOT NULL THEN
                CASE 
                    WHEN lr.ResultNumeric > prev.ResultNumeric * 1.05 THEN 'UP'
                    WHEN lr.ResultNumeric < prev.ResultNumeric * 0.95 THEN 'DOWN'
                    ELSE 'STABLE'
                END
            ELSE NULL
        END,
        (SELECT COUNT(*) FROM dbo.LabResults lr3 
         WHERE lr3.PatientID = @PatientID AND lr3.TestCode = lr.TestCode)
    FROM dbo.LabResults lr
    OUTER APPLY (
        SELECT TOP 1 lr2.ResultValue, lr2.ResultNumeric, lr2.ReportedDate
        FROM dbo.LabResults lr2
        WHERE lr2.PatientID = @PatientID
          AND lr2.TestCode = lr.TestCode
          AND lr2.ReportedDate < lr.ReportedDate
          AND lr2.ResultStatus = 'FINAL'
        ORDER BY lr2.ReportedDate DESC
    ) prev
    WHERE lr.PatientID = @PatientID
      AND lr.ResultStatus = 'FINAL'
      AND lr.ReportedDate >= DATEADD(DAY, -@DaysBack, GETDATE())
      AND (@TestCode IS NULL OR lr.TestCode = @TestCode)
      AND lr.LabResultID = (
          SELECT TOP 1 lr4.LabResultID FROM dbo.LabResults lr4
          WHERE lr4.PatientID = @PatientID AND lr4.TestCode = lr.TestCode AND lr4.ResultStatus = 'FINAL'
          ORDER BY lr4.ReportedDate DESC
      );
    
    RETURN;
END
GO

PRINT 'Function dbo.fn_GetLabResultsSummary created.';
GO

-- ============================================
-- fn_GetPhysicianSchedule (Table-valued function)
-- Parses XML schedule blob for a physician
-- Legacy: XML parsing in a function
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_GetPhysicianSchedule') AND type = 'TF')
    DROP FUNCTION dbo.fn_GetPhysicianSchedule;
GO

CREATE FUNCTION dbo.fn_GetPhysicianSchedule
(
    @PhysicianID INT,
    @WeekDate DATE = NULL
)
RETURNS @Schedule TABLE
(
    DayOfWeek       VARCHAR(10),
    StartTime       TIME,
    EndTime         TIME,
    Location        NVARCHAR(100),
    IsOnCall        BIT
)
AS
BEGIN
    DECLARE @ScheduleXML XML;
    
    SELECT @ScheduleXML = WeeklyScheduleXML
    FROM dbo.Physicians
    WHERE PhysicianID = @PhysicianID;
    
    IF @ScheduleXML IS NOT NULL
    BEGIN
        INSERT INTO @Schedule
        SELECT 
            Day.value('@name', 'VARCHAR(10)'),
            Day.value('@startTime', 'TIME'),
            Day.value('@endTime', 'TIME'),
            Day.value('@location', 'NVARCHAR(100)'),
            CAST(Day.value('@onCall', 'VARCHAR(5)') AS BIT)
        FROM @ScheduleXML.nodes('/Schedule/Day') AS T(Day);
    END
    
    RETURN;
END
GO

PRINT 'Function dbo.fn_GetPhysicianSchedule created.';
GO

-- ============================================
-- fn_ValidateICDCode
-- Validates ICD-10 code format
-- Legacy: regex-like validation in T-SQL
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_ValidateICDCode') AND type = 'FN')
    DROP FUNCTION dbo.fn_ValidateICDCode;
GO

CREATE FUNCTION dbo.fn_ValidateICDCode
(
    @ICDCode VARCHAR(10)
)
RETURNS BIT
AS
BEGIN
    -- ICD-10 format: A00-Z99.xx (letter followed by 2 digits, optional decimal and up to 4 more characters)
    IF @ICDCode IS NULL OR LEN(@ICDCode) < 3
        RETURN 0;
    
    -- First character must be a letter
    IF PATINDEX('[A-Z]', LEFT(@ICDCode, 1)) = 0
        RETURN 0;
    
    -- Characters 2-3 must be digits
    IF PATINDEX('[0-9]', SUBSTRING(@ICDCode, 2, 1)) = 0 OR PATINDEX('[0-9]', SUBSTRING(@ICDCode, 3, 1)) = 0
        RETURN 0;
    
    -- If longer than 3, character 4 must be a dot
    IF LEN(@ICDCode) > 3 AND SUBSTRING(@ICDCode, 4, 1) <> '.'
        RETURN 0;
    
    -- Remaining characters after dot must be alphanumeric
    IF LEN(@ICDCode) > 4
    BEGIN
        DECLARE @Remainder VARCHAR(6) = SUBSTRING(@ICDCode, 5, LEN(@ICDCode) - 4);
        IF PATINDEX('%[^A-Za-z0-9]%', @Remainder) > 0
            RETURN 0;
    END
    
    RETURN 1;
END
GO

PRINT 'Function dbo.fn_ValidateICDCode created.';
GO

-- ============================================
-- fn_CalculateReadmissionRisk
-- Calculates 30-day readmission risk score
-- Legacy: complex scalar function with data access
-- (causes performance issues when called per-row)
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_CalculateReadmissionRisk') AND type = 'FN')
    DROP FUNCTION dbo.fn_CalculateReadmissionRisk;
GO

CREATE FUNCTION dbo.fn_CalculateReadmissionRisk
(
    @PatientID INT
)
RETURNS DECIMAL(5,2)
AS
BEGIN
    DECLARE @RiskScore DECIMAL(5,2) = 0.0;
    DECLARE @Age INT;
    DECLARE @EncounterCount30Days INT;
    DECLARE @ChronicConditionCount INT;
    DECLARE @ActiveMedCount INT;
    
    -- Age factor
    SELECT @Age = dbo.fn_CalculateAge(DateOfBirth, GETDATE())
    FROM dbo.Patients WHERE PatientID = @PatientID;
    
    IF @Age >= 75 SET @RiskScore = @RiskScore + 15.0;
    ELSE IF @Age >= 65 SET @RiskScore = @RiskScore + 10.0;
    ELSE IF @Age >= 50 SET @RiskScore = @RiskScore + 5.0;
    
    -- Recent encounter frequency
    SELECT @EncounterCount30Days = COUNT(*)
    FROM dbo.Encounters
    WHERE PatientID = @PatientID
      AND AdmitDate >= DATEADD(DAY, -30, GETDATE());
    
    SET @RiskScore = @RiskScore + (@EncounterCount30Days * 8.0);
    
    -- Chronic condition count
    SELECT @ChronicConditionCount = COUNT(DISTINCT ICDCode)
    FROM dbo.Diagnoses
    WHERE PatientID = @PatientID AND ChronicIndicator = 1;
    
    IF @ChronicConditionCount >= 5 SET @RiskScore = @RiskScore + 20.0;
    ELSE IF @ChronicConditionCount >= 3 SET @RiskScore = @RiskScore + 12.0;
    ELSE IF @ChronicConditionCount >= 1 SET @RiskScore = @RiskScore + 5.0;
    
    -- Polypharmacy factor
    SELECT @ActiveMedCount = COUNT(*)
    FROM dbo.Medications
    WHERE PatientID = @PatientID AND MedicationStatus = 'ACTIVE';
    
    IF @ActiveMedCount >= 10 SET @RiskScore = @RiskScore + 15.0;
    ELSE IF @ActiveMedCount >= 5 SET @RiskScore = @RiskScore + 8.0;
    
    -- Cap at 100
    IF @RiskScore > 100.0 SET @RiskScore = 100.0;
    
    RETURN @RiskScore;
END
GO

PRINT 'Function dbo.fn_CalculateReadmissionRisk created.';
GO

PRINT '========================================';
PRINT 'All PatientDB functions created.';
PRINT '========================================';
GO
