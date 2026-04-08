-- ============================================
-- PatientDB Stored Procedures
-- Lakeview Medical Center
-- Contains legacy anti-patterns: cursors, dynamic SQL,
-- temp tables, cross-database queries
-- ============================================
USE PatientDB;
GO

-- ============================================
-- usp_RegisterPatient
-- Registers a new patient with MRN generation
-- Legacy: uses sp_executesql for MRN uniqueness check
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_RegisterPatient')
    DROP PROCEDURE dbo.usp_RegisterPatient;
GO

CREATE PROCEDURE dbo.usp_RegisterPatient
    @FirstName          NVARCHAR(50),
    @LastName           NVARCHAR(50),
    @MiddleName         NVARCHAR(50) = NULL,
    @DateOfBirth        DATE,
    @Gender             CHAR(1),
    @SSN                VARCHAR(11) = NULL,
    @Address1           NVARCHAR(200) = NULL,
    @City               NVARCHAR(100) = NULL,
    @State              CHAR(2) = NULL,
    @ZipCode            VARCHAR(10) = NULL,
    @HomePhone          VARCHAR(20) = NULL,
    @MobilePhone        VARCHAR(20) = NULL,
    @Email              NVARCHAR(200) = NULL,
    @PrimaryInsuranceID INT = NULL,
    @PrimaryPolicyNumber VARCHAR(50) = NULL,
    @NewPatientID       INT OUTPUT,
    @NewMRN             VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @MRNPrefix VARCHAR(4) = 'LMC-';
    DECLARE @MRNSequence INT;
    DECLARE @SQL NVARCHAR(500);
    DECLARE @ParamDef NVARCHAR(500);
    DECLARE @ExistingCount INT;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Legacy: Generate MRN using dynamic SQL and max value lookup
        -- (should use a SEQUENCE object instead)
        SET @SQL = N'SELECT @Count = COUNT(*) FROM dbo.Patients WHERE SSN = @SSNParam AND SSN IS NOT NULL';
        SET @ParamDef = N'@SSNParam VARCHAR(11), @Count INT OUTPUT';
        
        EXEC sp_executesql @SQL, @ParamDef, @SSNParam = @SSN, @Count = @ExistingCount OUTPUT;
        
        IF @ExistingCount > 0
        BEGIN
            RAISERROR('A patient with this SSN already exists.', 16, 1);
            RETURN;
        END
        
        -- Legacy: MRN generation using MAX+1 (race condition possible)
        SELECT @MRNSequence = ISNULL(MAX(CAST(REPLACE(MRN, @MRNPrefix, '') AS INT)), 0) + 1
        FROM dbo.Patients
        WHERE MRN LIKE @MRNPrefix + '%';
        
        SET @NewMRN = @MRNPrefix + RIGHT('000000' + CAST(@MRNSequence AS VARCHAR(6)), 6);
        
        INSERT INTO dbo.Patients (
            MRN, SSN, FirstName, MiddleName, LastName, DateOfBirth, Gender,
            Address1, City, State, ZipCode, HomePhone, MobilePhone, Email,
            PrimaryInsuranceID, PrimaryPolicyNumber, PatientStatus
        )
        VALUES (
            @NewMRN, @SSN, @FirstName, @MiddleName, @LastName, @DateOfBirth, @Gender,
            @Address1, @City, @State, @ZipCode, @HomePhone, @MobilePhone, @Email,
            @PrimaryInsuranceID, @PrimaryPolicyNumber, 'ACTIVE'
        );
        
        SET @NewPatientID = SCOPE_IDENTITY();
        
        -- Legacy: insert audit record manually (in addition to trigger)
        INSERT INTO dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
        VALUES ('Patients', @NewPatientID, 'REGISTER', 
                'New patient registered: ' + @FirstName + ' ' + @LastName + ' MRN: ' + @NewMRN,
                SUSER_SNAME());
        
        COMMIT TRANSACTION;
        
        PRINT 'Patient registered successfully. MRN: ' + @NewMRN;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
            
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO

PRINT 'Procedure dbo.usp_RegisterPatient created.';
GO

-- ============================================
-- usp_CreateEncounter
-- Creates a new encounter for an existing patient
-- Legacy: cross-database query to check BillingDB
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_CreateEncounter')
    DROP PROCEDURE dbo.usp_CreateEncounter;
GO

CREATE PROCEDURE dbo.usp_CreateEncounter
    @PatientID          INT,
    @EncounterType      VARCHAR(20),
    @AttendingPhysicianID INT,
    @DepartmentID       INT = NULL,
    @RoomNumber         VARCHAR(10) = NULL,
    @BedNumber          VARCHAR(5) = NULL,
    @AdmitDiagnosis     NVARCHAR(500) = NULL,
    @NewEncounterID     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EncounterNumber VARCHAR(20);
    DECLARE @EncounterPrefix VARCHAR(2);
    DECLARE @OutstandingBalance DECIMAL(12,2);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Validate patient exists and is active
        IF NOT EXISTS (SELECT 1 FROM dbo.Patients WHERE PatientID = @PatientID AND PatientStatus = 'ACTIVE')
        BEGIN
            RAISERROR('Patient not found or inactive.', 16, 1);
            RETURN;
        END
        
        -- Check for existing active encounter (prevent duplicates)
        IF EXISTS (SELECT 1 FROM dbo.Encounters WHERE PatientID = @PatientID AND EncounterStatus = 'ACTIVE' AND EncounterType = @EncounterType)
        BEGIN
            RAISERROR('Patient already has an active encounter of this type.', 16, 1);
            RETURN;
        END
        
        -- Legacy: CROSS-DATABASE QUERY to check outstanding balance in BillingDB
        -- This creates a hard dependency on BillingDB being available
        BEGIN TRY
            SELECT @OutstandingBalance = ISNULL(SUM(TotalAmount - PaidAmount), 0)
            FROM BillingDB.dbo.Invoices
            WHERE PatientID = @PatientID AND InvoiceStatus = 'OPEN';
        END TRY
        BEGIN CATCH
            SET @OutstandingBalance = 0; -- Graceful fallback if BillingDB unavailable
        END CATCH
        
        -- Generate encounter number
        SET @EncounterPrefix = CASE @EncounterType
            WHEN 'INPATIENT' THEN 'IP'
            WHEN 'OUTPATIENT' THEN 'OP'
            WHEN 'EMERGENCY' THEN 'ER'
            WHEN 'OBSERVATION' THEN 'OB'
        END;
        
        -- Legacy: MAX+1 pattern for encounter number generation
        SELECT @EncounterNumber = @EncounterPrefix + '-' + 
               FORMAT(GETDATE(), 'yyyyMMdd') + '-' +
               RIGHT('0000' + CAST(ISNULL(MAX(CAST(RIGHT(EncounterNumber, 4) AS INT)), 0) + 1 AS VARCHAR(4)), 4)
        FROM dbo.Encounters
        WHERE EncounterNumber LIKE @EncounterPrefix + '-' + FORMAT(GETDATE(), 'yyyyMMdd') + '%';
        
        INSERT INTO dbo.Encounters (
            EncounterNumber, PatientID, EncounterType, AdmitDate,
            AttendingPhysicianID, DepartmentID, RoomNumber, BedNumber,
            AdmitDiagnosis, EncounterStatus, PatientBalance
        )
        VALUES (
            @EncounterNumber, @PatientID, @EncounterType, GETDATE(),
            @AttendingPhysicianID, @DepartmentID, @RoomNumber, @BedNumber,
            @AdmitDiagnosis, 'ACTIVE', @OutstandingBalance
        );
        
        SET @NewEncounterID = SCOPE_IDENTITY();
        
        -- Legacy: send notification via Service Broker to BillingDB
        -- for insurance verification
        IF EXISTS (SELECT 1 FROM sys.services WHERE name = 'PatientEventSendService')
        BEGIN
            DECLARE @MessageBody XML;
            SET @MessageBody = (
                SELECT @NewEncounterID AS EncounterID,
                       @PatientID AS PatientID,
                       @EncounterType AS EncounterType,
                       GETDATE() AS AdmitDate
                FOR XML PATH('NewEncounter')
            );
            
            DECLARE @ConversationHandle UNIQUEIDENTIFIER;
            
            BEGIN DIALOG CONVERSATION @ConversationHandle
                FROM SERVICE [PatientEventSendService]
                TO SERVICE N'BillingEventReceiveService'
                ON CONTRACT [PatientBillingContract]
                WITH ENCRYPTION = OFF;
            
            SEND ON CONVERSATION @ConversationHandle
                MESSAGE TYPE [PatientEncounterMessage] (@MessageBody);
        END
        
        COMMIT TRANSACTION;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        RAISERROR('Error creating encounter: %s', 16, 1, @ErrorMessage);
    END CATCH
END
GO

PRINT 'Procedure dbo.usp_CreateEncounter created.';
GO

-- ============================================
-- usp_DischargePatient
-- Complex discharge process with multiple updates
-- Legacy: uses cursor to process charges
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_DischargePatient')
    DROP PROCEDURE dbo.usp_DischargePatient;
GO

CREATE PROCEDURE dbo.usp_DischargePatient
    @EncounterID        INT,
    @DischargeDiagnosis NVARCHAR(500) = NULL,
    @DischargeDisposition VARCHAR(50) = 'HOME',
    @DischargePhysicianID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PatientID INT;
    DECLARE @TotalCharges DECIMAL(12,2) = 0;
    DECLARE @MedicationID INT;
    DECLARE @OrderID INT;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Get patient info
        SELECT @PatientID = PatientID 
        FROM dbo.Encounters 
        WHERE EncounterID = @EncounterID AND EncounterStatus = 'ACTIVE';
        
        IF @PatientID IS NULL
        BEGIN
            RAISERROR('Active encounter not found.', 16, 1);
            RETURN;
        END
        
        -- Legacy: CURSOR to discontinue all active medications
        DECLARE med_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT MedicationID 
            FROM dbo.Medications 
            WHERE EncounterID = @EncounterID AND MedicationStatus = 'ACTIVE';
        
        OPEN med_cursor;
        FETCH NEXT FROM med_cursor INTO @MedicationID;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            UPDATE dbo.Medications 
            SET MedicationStatus = 'COMPLETED',
                EndDate = GETDATE(),
                ModifiedDate = GETDATE()
            WHERE MedicationID = @MedicationID;
            
            FETCH NEXT FROM med_cursor INTO @MedicationID;
        END
        
        CLOSE med_cursor;
        DEALLOCATE med_cursor;
        
        -- Legacy: CURSOR to cancel pending orders
        DECLARE order_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT OrderID 
            FROM dbo.Orders 
            WHERE EncounterID = @EncounterID AND OrderStatus IN ('ORDERED', 'IN_PROGRESS');
        
        OPEN order_cursor;
        FETCH NEXT FROM order_cursor INTO @OrderID;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            UPDATE dbo.Orders 
            SET OrderStatus = 'CANCELLED',
                CancelledDate = GETDATE(),
                CancelledReason = 'Patient discharged',
                ModifiedDate = GETDATE()
            WHERE OrderID = @OrderID;
            
            FETCH NEXT FROM order_cursor INTO @OrderID;
        END
        
        CLOSE order_cursor;
        DEALLOCATE order_cursor;
        
        -- Legacy: CROSS-DATABASE QUERY to calculate total charges from BillingDB
        BEGIN TRY
            SELECT @TotalCharges = ISNULL(SUM(ChargeAmount), 0)
            FROM BillingDB.dbo.BillingCharges
            WHERE EncounterID = @EncounterID;
        END TRY
        BEGIN CATCH
            -- Fallback: calculate from local procedure charges
            SELECT @TotalCharges = ISNULL(SUM(ChargeAmount), 0)
            FROM dbo.Procedures
            WHERE EncounterID = @EncounterID AND ProcedureStatus = 'COMPLETED';
        END CATCH
        
        -- Update encounter
        UPDATE dbo.Encounters
        SET EncounterStatus = 'DISCHARGED',
            DischargeDate = GETDATE(),
            DischargeDiagnosis = @DischargeDiagnosis,
            DischargeDisposition = @DischargeDisposition,
            TotalCharges = @TotalCharges,
            ModifiedDate = GETDATE()
        WHERE EncounterID = @EncounterID;
        
        -- Legacy: create discharge summary clinical note
        INSERT INTO dbo.ClinicalNotes (EncounterID, PatientID, NoteType, AuthorID, NoteContent, NoteStatus)
        VALUES (@EncounterID, @PatientID, 'DISCHARGE_SUMMARY',
                ISNULL(@DischargePhysicianID, (SELECT AttendingPhysicianID FROM dbo.Encounters WHERE EncounterID = @EncounterID)),
                N'Auto-generated discharge summary. Disposition: ' + @DischargeDisposition + 
                N'. Diagnosis: ' + ISNULL(@DischargeDiagnosis, 'Not specified'),
                'DRAFT');
        
        COMMIT TRANSACTION;
        
        PRINT 'Patient discharged successfully from encounter ' + CAST(@EncounterID AS VARCHAR(10));
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSev INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMsg, @ErrorSev, @ErrorState);
    END CATCH
END
GO

PRINT 'Procedure dbo.usp_DischargePatient created.';
GO

-- ============================================
-- usp_OrderMedication
-- Orders a medication with drug interaction check
-- Legacy: calls CLR function for interaction checking
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_OrderMedication')
    DROP PROCEDURE dbo.usp_OrderMedication;
GO

CREATE PROCEDURE dbo.usp_OrderMedication
    @EncounterID        INT,
    @DrugCode           VARCHAR(20),
    @DrugName           NVARCHAR(200),
    @GenericName        NVARCHAR(200) = NULL,
    @Dosage             NVARCHAR(100),
    @Route              VARCHAR(50),
    @Frequency          VARCHAR(50),
    @PrescribingPhysicianID INT,
    @NewMedicationID    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PatientID INT;
    DECLARE @OrderID INT;
    DECLARE @AllergyCount INT;
    DECLARE @InteractionXML XML;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Get patient from encounter
        SELECT @PatientID = PatientID 
        FROM dbo.Encounters 
        WHERE EncounterID = @EncounterID AND EncounterStatus = 'ACTIVE';
        
        IF @PatientID IS NULL
        BEGIN
            RAISERROR('Active encounter not found.', 16, 1);
            RETURN;
        END
        
        -- Legacy: check for drug allergies using temp table
        CREATE TABLE #DrugAllergyCheck (
            AllergyID INT,
            AllergenName NVARCHAR(200),
            Severity VARCHAR(20),
            Reaction NVARCHAR(500)
        );
        
        INSERT INTO #DrugAllergyCheck
        SELECT AllergyID, AllergenName, Severity, Reaction
        FROM dbo.Allergies
        WHERE PatientID = @PatientID
          AND AllergyType = 'DRUG'
          AND AllergyStatus = 'ACTIVE'
          AND (@DrugName LIKE '%' + AllergenName + '%' OR @GenericName LIKE '%' + AllergenName + '%');
        
        SET @AllergyCount = @@ROWCOUNT;
        
        IF @AllergyCount > 0
        BEGIN
            -- Build allergy warning XML
            SET @InteractionXML = (
                SELECT AllergyID, AllergenName, Severity, Reaction
                FROM #DrugAllergyCheck
                FOR XML PATH('AllergyWarning'), ROOT('Warnings')
            );
            
            -- Log the warning but don't block (physician override assumed)
            INSERT INTO dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
            VALUES ('Medications', 0, 'ALLERGY_WARNING',
                    'Drug allergy warning for patient ' + CAST(@PatientID AS VARCHAR) + 
                    ': ' + @DrugName + ' - ' + CAST(@AllergyCount AS VARCHAR) + ' allergy match(es)',
                    SUSER_SNAME());
        END
        
        DROP TABLE #DrugAllergyCheck;
        
        -- Create the medication order
        INSERT INTO dbo.Orders (EncounterID, PatientID, OrderType, OrderCode, OrderDescription, 
                               OrderingPhysicianID, OrderPriority, OrderStatus)
        VALUES (@EncounterID, @PatientID, 'MEDICATION', @DrugCode, @DrugName + ' ' + @Dosage + ' ' + @Route,
                @PrescribingPhysicianID, 'ROUTINE', 'ORDERED');
        
        SET @OrderID = SCOPE_IDENTITY();
        
        -- Create the medication record
        INSERT INTO dbo.Medications (OrderID, EncounterID, PatientID, DrugCode, DrugName, GenericName,
                                    Dosage, Route, Frequency, StartDate, PrescribingPhysicianID,
                                    MedicationStatus, InteractionCheckXML)
        VALUES (@OrderID, @EncounterID, @PatientID, @DrugCode, @DrugName, @GenericName,
                @Dosage, @Route, @Frequency, GETDATE(), @PrescribingPhysicianID,
                'ACTIVE', @InteractionXML);
        
        SET @NewMedicationID = SCOPE_IDENTITY();
        
        -- Legacy: CROSS-DATABASE notification to pharmacy system via linked server
        -- This would normally call the linked server, wrapped in try/catch
        BEGIN TRY
            -- TODO: Replace with actual linked server call when pharmacy system is connected
            -- EXEC [PHARMACY_SERVER].PharmacyDB.dbo.usp_QueueMedicationOrder @NewMedicationID, @DrugCode, @Dosage;
            PRINT 'Pharmacy notification would be sent here.';
        END TRY
        BEGIN CATCH
            -- Log but don't fail - pharmacy integration is non-critical
            PRINT 'Warning: Could not notify pharmacy system.';
        END CATCH
        
        COMMIT TRANSACTION;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMsg, 16, 1);
    END CATCH
END
GO

PRINT 'Procedure dbo.usp_OrderMedication created.';
GO

-- ============================================
-- usp_GetPatientSummary
-- Comprehensive patient summary using CURSOR
-- Legacy anti-pattern: cursor-based data assembly
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_GetPatientSummary')
    DROP PROCEDURE dbo.usp_GetPatientSummary;
GO

CREATE PROCEDURE dbo.usp_GetPatientSummary
    @PatientID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Legacy: build result using temp tables and cursors
    CREATE TABLE #PatientSummary (
        SectionName     VARCHAR(50),
        SectionOrder    INT,
        DetailLine      NVARCHAR(MAX)
    );
    
    DECLARE @MRN VARCHAR(20), @PatientName NVARCHAR(150), @DOB DATE, @Gender CHAR(1);
    DECLARE @EncounterID INT, @EncounterNumber VARCHAR(20), @EncType VARCHAR(20), @AdmitDate DATETIME;
    DECLARE @DrugName NVARCHAR(200), @Dosage NVARCHAR(100), @Frequency VARCHAR(50);
    DECLARE @AllergenName NVARCHAR(200), @Severity VARCHAR(20);
    DECLARE @TestName NVARCHAR(200), @ResultValue NVARCHAR(200), @ReportedDate DATETIME;
    DECLARE @LineNum INT = 0;
    
    -- Get patient demographics
    SELECT @MRN = MRN, 
           @PatientName = LastName + ', ' + FirstName + ' ' + ISNULL(MiddleName, ''),
           @DOB = DateOfBirth, 
           @Gender = Gender
    FROM dbo.Patients 
    WHERE PatientID = @PatientID;
    
    IF @MRN IS NULL
    BEGIN
        RAISERROR('Patient not found.', 16, 1);
        RETURN;
    END
    
    INSERT INTO #PatientSummary VALUES ('DEMOGRAPHICS', 1, 'Patient: ' + @PatientName);
    INSERT INTO #PatientSummary VALUES ('DEMOGRAPHICS', 2, 'MRN: ' + @MRN);
    INSERT INTO #PatientSummary VALUES ('DEMOGRAPHICS', 3, 'DOB: ' + CONVERT(VARCHAR(10), @DOB, 101) + ' | Gender: ' + @Gender);
    
    -- Legacy: CURSOR for encounter history
    SET @LineNum = 0;
    DECLARE enc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TOP 10 EncounterID, EncounterNumber, EncounterType, AdmitDate
        FROM dbo.Encounters
        WHERE PatientID = @PatientID
        ORDER BY AdmitDate DESC;
    
    OPEN enc_cursor;
    FETCH NEXT FROM enc_cursor INTO @EncounterID, @EncounterNumber, @EncType, @AdmitDate;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @LineNum = @LineNum + 1;
        INSERT INTO #PatientSummary VALUES ('ENCOUNTERS', 10 + @LineNum,
            @EncounterNumber + ' | ' + @EncType + ' | ' + CONVERT(VARCHAR(10), @AdmitDate, 101));
        FETCH NEXT FROM enc_cursor INTO @EncounterID, @EncounterNumber, @EncType, @AdmitDate;
    END
    
    CLOSE enc_cursor;
    DEALLOCATE enc_cursor;
    
    -- Legacy: CURSOR for active medications
    SET @LineNum = 0;
    DECLARE med_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DrugName, Dosage, Frequency
        FROM dbo.Medications
        WHERE PatientID = @PatientID AND MedicationStatus = 'ACTIVE';
    
    OPEN med_cursor;
    FETCH NEXT FROM med_cursor INTO @DrugName, @Dosage, @Frequency;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @LineNum = @LineNum + 1;
        INSERT INTO #PatientSummary VALUES ('MEDICATIONS', 20 + @LineNum,
            @DrugName + ' ' + @Dosage + ' ' + @Frequency);
        FETCH NEXT FROM med_cursor INTO @DrugName, @Dosage, @Frequency;
    END
    
    CLOSE med_cursor;
    DEALLOCATE med_cursor;
    
    -- Legacy: CURSOR for allergies
    SET @LineNum = 0;
    DECLARE allergy_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT AllergenName, Severity
        FROM dbo.Allergies
        WHERE PatientID = @PatientID AND AllergyStatus = 'ACTIVE';
    
    OPEN allergy_cursor;
    FETCH NEXT FROM allergy_cursor INTO @AllergenName, @Severity;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @LineNum = @LineNum + 1;
        INSERT INTO #PatientSummary VALUES ('ALLERGIES', 30 + @LineNum,
            @AllergenName + ' [' + @Severity + ']');
        FETCH NEXT FROM allergy_cursor INTO @AllergenName, @Severity;
    END
    
    CLOSE allergy_cursor;
    DEALLOCATE allergy_cursor;
    
    -- Legacy: CURSOR for recent lab results
    SET @LineNum = 0;
    DECLARE lab_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TOP 20 TestName, ResultValue, ReportedDate
        FROM dbo.LabResults
        WHERE PatientID = @PatientID AND ResultStatus = 'FINAL'
        ORDER BY ReportedDate DESC;
    
    OPEN lab_cursor;
    FETCH NEXT FROM lab_cursor INTO @TestName, @ResultValue, @ReportedDate;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @LineNum = @LineNum + 1;
        INSERT INTO #PatientSummary VALUES ('LAB_RESULTS', 40 + @LineNum,
            @TestName + ': ' + ISNULL(@ResultValue, 'Pending') + ' (' + CONVERT(VARCHAR(10), @ReportedDate, 101) + ')');
        FETCH NEXT FROM lab_cursor INTO @TestName, @ResultValue, @ReportedDate;
    END
    
    CLOSE lab_cursor;
    DEALLOCATE lab_cursor;
    
    -- Return the assembled summary
    SELECT SectionName, DetailLine
    FROM #PatientSummary
    ORDER BY SectionOrder;
    
    DROP TABLE #PatientSummary;
END
GO

PRINT 'Procedure dbo.usp_GetPatientSummary created.';
GO

-- ============================================
-- usp_SearchPatients
-- Dynamic SQL search with multiple optional filters
-- Legacy anti-pattern: string concatenation for dynamic SQL
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SearchPatients')
    DROP PROCEDURE dbo.usp_SearchPatients;
GO

CREATE PROCEDURE dbo.usp_SearchPatients
    @LastName           NVARCHAR(50) = NULL,
    @FirstName          NVARCHAR(50) = NULL,
    @MRN                VARCHAR(20) = NULL,
    @SSN                VARCHAR(11) = NULL,
    @DateOfBirth        DATE = NULL,
    @PhoneNumber        VARCHAR(20) = NULL,
    @InsurancePolicyNum VARCHAR(50) = NULL,
    @PatientStatus      VARCHAR(20) = NULL,
    @DepartmentID       INT = NULL,
    @AttendingPhysicianID INT = NULL,
    @MaxResults         INT = 100,
    @SortColumn         VARCHAR(50) = 'LastName',
    @SortDirection      VARCHAR(4) = 'ASC'
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Legacy: dynamic SQL built with string concatenation
    -- (vulnerable to SQL injection if not parameterized, but uses sp_executesql)
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @WhereClause NVARCHAR(MAX) = N'';
    DECLARE @OrderClause NVARCHAR(200);
    DECLARE @ParamDefinition NVARCHAR(MAX);
    
    -- Validate sort column (prevent injection)
    IF @SortColumn NOT IN ('LastName', 'FirstName', 'MRN', 'DateOfBirth', 'PatientID', 'CreatedDate')
        SET @SortColumn = 'LastName';
    IF @SortDirection NOT IN ('ASC', 'DESC')
        SET @SortDirection = 'ASC';
    
    SET @SQL = N'
        SELECT TOP (@MaxResults)
            p.PatientID,
            p.MRN,
            p.LastName,
            p.FirstName,
            p.MiddleName,
            p.DateOfBirth,
            DATEDIFF(YEAR, p.DateOfBirth, GETDATE()) AS Age,
            p.Gender,
            p.Address1,
            p.City,
            p.State,
            p.ZipCode,
            p.HomePhone,
            p.MobilePhone,
            p.Email,
            p.PatientStatus,
            ip.ProviderName AS PrimaryInsurance,
            p.PrimaryPolicyNumber,
            -- Legacy: subquery for last encounter
            (SELECT TOP 1 e.AdmitDate FROM dbo.Encounters e 
             WHERE e.PatientID = p.PatientID ORDER BY e.AdmitDate DESC) AS LastEncounterDate,
            (SELECT TOP 1 e.EncounterType FROM dbo.Encounters e 
             WHERE e.PatientID = p.PatientID ORDER BY e.AdmitDate DESC) AS LastEncounterType
        FROM dbo.Patients p
        LEFT JOIN dbo.InsuranceProviders ip ON p.PrimaryInsuranceID = ip.InsuranceProviderID
    ';
    
    -- Build WHERE clause dynamically
    IF @LastName IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND p.LastName LIKE @LastName + ''%''';
    IF @FirstName IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND p.FirstName LIKE @FirstName + ''%''';
    IF @MRN IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND p.MRN = @MRN';
    IF @SSN IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND p.SSN = @SSN';
    IF @DateOfBirth IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND p.DateOfBirth = @DateOfBirth';
    IF @PhoneNumber IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND (p.HomePhone LIKE ''%'' + @PhoneNumber + ''%'' OR p.MobilePhone LIKE ''%'' + @PhoneNumber + ''%'' OR p.WorkPhone LIKE ''%'' + @PhoneNumber + ''%'')';
    IF @InsurancePolicyNum IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND (p.PrimaryPolicyNumber = @InsurancePolicyNum OR p.SecondaryPolicyNumber = @InsurancePolicyNum)';
    IF @PatientStatus IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND p.PatientStatus = @PatientStatus';
    IF @DepartmentID IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND EXISTS (SELECT 1 FROM dbo.Encounters e WHERE e.PatientID = p.PatientID AND e.DepartmentID = @DepartmentID AND e.EncounterStatus = ''ACTIVE'')';
    IF @AttendingPhysicianID IS NOT NULL
        SET @WhereClause = @WhereClause + N' AND EXISTS (SELECT 1 FROM dbo.Encounters e WHERE e.PatientID = p.PatientID AND e.AttendingPhysicianID = @AttendingPhysicianID AND e.EncounterStatus = ''ACTIVE'')';
    
    -- Apply WHERE clause
    IF LEN(@WhereClause) > 0
        SET @SQL = @SQL + N' WHERE 1=1 ' + @WhereClause;
    
    -- Apply ORDER BY (using dynamic column name - validated above)
    SET @SQL = @SQL + N' ORDER BY p.' + @SortColumn + N' ' + @SortDirection;
    
    SET @ParamDefinition = N'
        @MaxResults INT,
        @LastName NVARCHAR(50),
        @FirstName NVARCHAR(50),
        @MRN VARCHAR(20),
        @SSN VARCHAR(11),
        @DateOfBirth DATE,
        @PhoneNumber VARCHAR(20),
        @InsurancePolicyNum VARCHAR(50),
        @PatientStatus VARCHAR(20),
        @DepartmentID INT,
        @AttendingPhysicianID INT';
    
    EXEC sp_executesql @SQL, @ParamDefinition,
        @MaxResults = @MaxResults,
        @LastName = @LastName,
        @FirstName = @FirstName,
        @MRN = @MRN,
        @SSN = @SSN,
        @DateOfBirth = @DateOfBirth,
        @PhoneNumber = @PhoneNumber,
        @InsurancePolicyNum = @InsurancePolicyNum,
        @PatientStatus = @PatientStatus,
        @DepartmentID = @DepartmentID,
        @AttendingPhysicianID = @AttendingPhysicianID;
END
GO

PRINT 'Procedure dbo.usp_SearchPatients created.';
GO

-- ============================================
-- usp_UpdateStatistics
-- Updates statistics on key tables
-- Legacy: maintenance stored procedure
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_UpdateStatistics')
    DROP PROCEDURE dbo.usp_UpdateStatistics;
GO

CREATE PROCEDURE dbo.usp_UpdateStatistics
    @FullScan BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TableName NVARCHAR(256);
    DECLARE @SQL NVARCHAR(500);
    DECLARE @StartTime DATETIME = GETDATE();
    
    -- Legacy: CURSOR over sys.tables for statistics updates
    DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT QUOTENAME(s.name) + '.' + QUOTENAME(t.name)
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE t.is_ms_shipped = 0
        ORDER BY t.name;
    
    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @TableName;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            IF @FullScan = 1
                SET @SQL = N'UPDATE STATISTICS ' + @TableName + N' WITH FULLSCAN';
            ELSE
                SET @SQL = N'UPDATE STATISTICS ' + @TableName + N' WITH SAMPLE 30 PERCENT';
            
            EXEC sp_executesql @SQL;
            PRINT 'Updated statistics on ' + @TableName;
        END TRY
        BEGIN CATCH
            PRINT 'Error updating statistics on ' + @TableName + ': ' + ERROR_MESSAGE();
        END CATCH
        
        FETCH NEXT FROM table_cursor INTO @TableName;
    END
    
    CLOSE table_cursor;
    DEALLOCATE table_cursor;
    
    PRINT 'Statistics update completed in ' + CAST(DATEDIFF(SECOND, @StartTime, GETDATE()) AS VARCHAR(10)) + ' seconds.';
END
GO

PRINT 'Procedure dbo.usp_UpdateStatistics created.';
GO

-- ============================================
-- usp_ArchiveOldRecords
-- Archives records older than retention period
-- Legacy: uses cursor and temp tables extensively
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ArchiveOldRecords')
    DROP PROCEDURE dbo.usp_ArchiveOldRecords;
GO

CREATE PROCEDURE dbo.usp_ArchiveOldRecords
    @RetentionMonths INT = 84,  -- 7 years default for healthcare
    @BatchSize INT = 1000,
    @DryRun BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CutoffDate DATE = DATEADD(MONTH, -@RetentionMonths, GETDATE());
    DECLARE @EncounterID INT;
    DECLARE @ArchivedCount INT = 0;
    DECLARE @ErrorCount INT = 0;
    
    PRINT 'Archive process started. Cutoff date: ' + CONVERT(VARCHAR(10), @CutoffDate, 101);
    PRINT 'Dry run mode: ' + CASE @DryRun WHEN 1 THEN 'YES' ELSE 'NO' END;
    
    -- Legacy: create archive tracking temp table
    CREATE TABLE #ArchiveLog (
        EncounterID INT,
        PatientID INT,
        AdmitDate DATETIME,
        ArchiveStatus VARCHAR(20),
        ErrorMessage NVARCHAR(500)
    );
    
    -- Legacy: CURSOR to process encounters one at a time
    DECLARE archive_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TOP (@BatchSize) e.EncounterID
        FROM dbo.Encounters e
        WHERE e.DischargeDate < @CutoffDate
          AND e.EncounterStatus = 'DISCHARGED'
        ORDER BY e.DischargeDate;
    
    OPEN archive_cursor;
    FETCH NEXT FROM archive_cursor INTO @EncounterID;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            IF @DryRun = 0
            BEGIN
                BEGIN TRANSACTION;
                
                -- Archive related records (would move to archive tables in production)
                DELETE FROM dbo.Vitals WHERE EncounterID = @EncounterID;
                DELETE FROM dbo.LabResults WHERE EncounterID = @EncounterID;
                DELETE FROM dbo.Medications WHERE EncounterID = @EncounterID;
                DELETE FROM dbo.Orders WHERE EncounterID = @EncounterID;
                DELETE FROM dbo.ClinicalNotes WHERE EncounterID = @EncounterID;
                DELETE FROM dbo.RadiologyStudies WHERE EncounterID = @EncounterID;
                DELETE FROM dbo.Diagnoses WHERE EncounterID = @EncounterID;
                DELETE FROM dbo.Procedures WHERE EncounterID = @EncounterID;
                
                -- Mark encounter as archived
                UPDATE dbo.Encounters 
                SET EncounterStatus = 'ARCHIVED',
                    ModifiedDate = GETDATE()
                WHERE EncounterID = @EncounterID;
                
                COMMIT TRANSACTION;
            END
            
            INSERT INTO #ArchiveLog (EncounterID, PatientID, AdmitDate, ArchiveStatus)
            SELECT @EncounterID, PatientID, AdmitDate, 
                   CASE @DryRun WHEN 1 THEN 'WOULD_ARCHIVE' ELSE 'ARCHIVED' END
            FROM dbo.Encounters WHERE EncounterID = @EncounterID;
            
            SET @ArchivedCount = @ArchivedCount + 1;
            
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            
            INSERT INTO #ArchiveLog VALUES (@EncounterID, NULL, NULL, 'ERROR', ERROR_MESSAGE());
            SET @ErrorCount = @ErrorCount + 1;
        END CATCH
        
        FETCH NEXT FROM archive_cursor INTO @EncounterID;
    END
    
    CLOSE archive_cursor;
    DEALLOCATE archive_cursor;
    
    -- Return summary
    SELECT ArchiveStatus, COUNT(*) AS RecordCount
    FROM #ArchiveLog
    GROUP BY ArchiveStatus;
    
    PRINT 'Archive complete. Processed: ' + CAST(@ArchivedCount AS VARCHAR) + ', Errors: ' + CAST(@ErrorCount AS VARCHAR);
    
    DROP TABLE #ArchiveLog;
END
GO

PRINT 'Procedure dbo.usp_ArchiveOldRecords created.';
GO

PRINT '========================================';
PRINT 'All PatientDB stored procedures created.';
PRINT '========================================';
GO
