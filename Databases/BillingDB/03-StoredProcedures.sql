-- ============================================
-- BillingDB Stored Procedures
-- Lakeview Medical Center
-- Contains CROSS-DATABASE QUERIES to PatientDB
-- ============================================
USE BillingDB;
GO

-- ============================================
-- usp_ProcessEncounterCharges
-- Posts charges for an encounter from chargemaster
-- Legacy: CROSS-DATABASE query to PatientDB for encounter/procedure data
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ProcessEncounterCharges')
    DROP PROCEDURE dbo.usp_ProcessEncounterCharges;
GO

CREATE PROCEDURE dbo.usp_ProcessEncounterCharges
    @EncounterID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PatientID INT;
    DECLARE @ChargeCount INT = 0;
    DECLARE @TotalCharges DECIMAL(12,2) = 0;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Legacy: CROSS-DATABASE QUERY to get patient and encounter info from PatientDB
        SELECT @PatientID = e.PatientID
        FROM PatientDB.dbo.Encounters e
        WHERE e.EncounterID = @EncounterID
          AND e.EncounterStatus = 'ACTIVE';
        
        IF @PatientID IS NULL
        BEGIN
            RAISERROR('Encounter %d not found or is not active in PatientDB.', 16, 1, @EncounterID);
            RETURN;
        END
        
        -- Legacy: CROSS-DATABASE QUERY - pull completed procedures from PatientDB
        -- and post charges in BillingDB
        INSERT INTO dbo.BillingCharges (
            EncounterID, PatientID, ChargeCode, CPTCode, RevenueCode,
            ChargeDescription, ServiceDate, Quantity, UnitPrice, ChargeAmount,
            DepartmentCode, PerformingPhysicianNPI, DiagnosisCode1, ChargeStatus
        )
        SELECT 
            p.EncounterID,
            p.PatientID,
            cm.ChargeCode,
            p.CPTCode,
            cm.RevenueCode,
            p.CPTDescription,
            p.ProcedureDate,
            1,
            cm.StandardCharge,
            cm.StandardCharge,
            -- Legacy: CROSS-DATABASE lookup for department code
            (SELECT TOP 1 d.DepartmentCode FROM PatientDB.dbo.Departments d 
             WHERE d.DepartmentID = e.DepartmentID),
            -- Legacy: CROSS-DATABASE lookup for physician NPI
            (SELECT TOP 1 ph.NPI FROM PatientDB.dbo.Physicians ph 
             WHERE ph.PhysicianID = p.PerformingPhysicianID),
            -- Legacy: CROSS-DATABASE lookup for primary diagnosis
            (SELECT TOP 1 dx.ICDCode FROM PatientDB.dbo.Diagnoses dx 
             WHERE dx.EncounterID = @EncounterID AND dx.DiagnosisType = 'PRIMARY'),
            'POSTED'
        FROM PatientDB.dbo.Procedures p
        INNER JOIN PatientDB.dbo.Encounters e ON p.EncounterID = e.EncounterID
        LEFT JOIN dbo.Chargemaster cm ON p.CPTCode = cm.CPTCode 
            AND cm.IsActive = 1 
            AND cm.EffectiveDate <= GETDATE()
            AND (cm.ExpirationDate IS NULL OR cm.ExpirationDate > GETDATE())
        WHERE p.EncounterID = @EncounterID
          AND p.ProcedureStatus = 'COMPLETED'
          AND NOT EXISTS (
              SELECT 1 FROM dbo.BillingCharges bc 
              WHERE bc.EncounterID = @EncounterID 
                AND bc.CPTCode = p.CPTCode 
                AND bc.ServiceDate = p.ProcedureDate
          );
        
        SET @ChargeCount = @@ROWCOUNT;
        
        -- Calculate total
        SELECT @TotalCharges = SUM(ChargeAmount)
        FROM dbo.BillingCharges
        WHERE EncounterID = @EncounterID AND ChargeStatus = 'POSTED';
        
        -- Legacy: CROSS-DATABASE UPDATE - write total charges back to PatientDB
        UPDATE PatientDB.dbo.Encounters
        SET TotalCharges = @TotalCharges,
            ModifiedDate = GETDATE()
        WHERE EncounterID = @EncounterID;
        
        -- Audit trail
        INSERT INTO dbo.BillingAudit (TableName, RecordID, Action, NewValues, ChangedBy)
        VALUES ('BillingCharges', @EncounterID, 'CHARGE_POSTING',
                'Posted ' + CAST(@ChargeCount AS VARCHAR) + ' charges totaling $' + 
                CAST(@TotalCharges AS VARCHAR(20)) + ' for encounter ' + CAST(@EncounterID AS VARCHAR),
                SUSER_SNAME());
        
        COMMIT TRANSACTION;
        
        PRINT 'Posted ' + CAST(@ChargeCount AS VARCHAR) + ' charges totaling $' + CAST(@TotalCharges AS VARCHAR(20));
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMsg, 16, 1);
    END CATCH
END
GO

PRINT 'Procedure dbo.usp_ProcessEncounterCharges created.';
GO

-- ============================================
-- usp_CreateInsuranceClaim
-- Creates an insurance claim from encounter charges
-- Legacy: CROSS-DATABASE queries to PatientDB for patient/insurance info
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_CreateInsuranceClaim')
    DROP PROCEDURE dbo.usp_CreateInsuranceClaim;
GO

CREATE PROCEDURE dbo.usp_CreateInsuranceClaim
    @EncounterID INT,
    @ClaimType VARCHAR(20) = 'INSTITUTIONAL',
    @NewClaimID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ClaimNumber VARCHAR(20);
    DECLARE @PatientID INT;
    DECLARE @InsuranceProviderID INT;
    DECLARE @PolicyNumber VARCHAR(50);
    DECLARE @GroupNumber VARCHAR(50);
    DECLARE @TotalCharges DECIMAL(12,2);
    DECLARE @PayerID VARCHAR(20);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Legacy: CROSS-DATABASE QUERY - get patient insurance info from PatientDB
        SELECT 
            @PatientID = p.PatientID,
            @InsuranceProviderID = p.PrimaryInsuranceID,
            @PolicyNumber = p.PrimaryPolicyNumber,
            @GroupNumber = p.PrimaryGroupNumber,
            @PayerID = ip.PayerID
        FROM PatientDB.dbo.Patients p
        INNER JOIN PatientDB.dbo.Encounters e ON p.PatientID = e.PatientID
        LEFT JOIN PatientDB.dbo.InsuranceProviders ip ON p.PrimaryInsuranceID = ip.InsuranceProviderID
        WHERE e.EncounterID = @EncounterID;
        
        IF @PatientID IS NULL
        BEGIN
            RAISERROR('Patient not found for encounter %d.', 16, 1, @EncounterID);
            RETURN;
        END
        
        IF @InsuranceProviderID IS NULL
        BEGIN
            RAISERROR('No primary insurance on file for this patient.', 16, 1);
            RETURN;
        END
        
        -- Get total charges for this encounter
        SELECT @TotalCharges = ISNULL(SUM(ChargeAmount - AdjustmentAmount), 0)
        FROM dbo.BillingCharges
        WHERE EncounterID = @EncounterID AND ChargeStatus IN ('POSTED', 'BILLED');
        
        -- Generate claim number
        SET @ClaimNumber = 'CLM-' + FORMAT(GETDATE(), 'yyyyMMdd') + '-' +
            RIGHT('00000' + CAST(
                (SELECT ISNULL(MAX(CAST(RIGHT(ClaimNumber, 5) AS INT)), 0) + 1
                 FROM dbo.InsuranceClaims
                 WHERE ClaimNumber LIKE 'CLM-' + FORMAT(GETDATE(), 'yyyyMMdd') + '%')
            AS VARCHAR(5)), 5);
        
        -- Create the claim
        INSERT INTO dbo.InsuranceClaims (
            ClaimNumber, EncounterID, PatientID, InsuranceProviderID,
            PayerID, PolicyNumber, GroupNumber, ClaimType,
            ClaimForm, TotalCharges, ClaimStatus,
            PreAuthNumber
        )
        VALUES (
            @ClaimNumber, @EncounterID, @PatientID, @InsuranceProviderID,
            @PayerID, @PolicyNumber, @GroupNumber, @ClaimType,
            CASE @ClaimType WHEN 'INSTITUTIONAL' THEN 'UB04' ELSE 'CMS1500' END,
            @TotalCharges, 'CREATED',
            -- Legacy: CROSS-DATABASE - get pre-auth from encounter
            (SELECT PreAuthNumber FROM PatientDB.dbo.Encounters WHERE EncounterID = @EncounterID)
        );
        
        SET @NewClaimID = SCOPE_IDENTITY();
        
        -- Create claim line items from charges
        INSERT INTO dbo.ClaimLineItems (
            ClaimID, LineNumber, ChargeID, ServiceDate,
            CPTCode, ModifierCode1, ModifierCode2,
            DiagnosisPointer, Quantity, ChargeAmount, LineStatus
        )
        SELECT 
            @NewClaimID,
            ROW_NUMBER() OVER (ORDER BY bc.ServiceDate, bc.ChargeID),
            bc.ChargeID,
            CAST(bc.ServiceDate AS DATE),
            bc.CPTCode,
            bc.ModifierCode1,
            bc.ModifierCode2,
            '1',  -- Default to first diagnosis pointer
            bc.Quantity,
            bc.ChargeAmount - bc.AdjustmentAmount,
            'PENDING'
        FROM dbo.BillingCharges bc
        WHERE bc.EncounterID = @EncounterID
          AND bc.ChargeStatus IN ('POSTED', 'BILLED');
        
        -- Update charge status
        UPDATE dbo.BillingCharges
        SET ChargeStatus = 'BILLED', ModifiedDate = GETDATE()
        WHERE EncounterID = @EncounterID AND ChargeStatus = 'POSTED';
        
        COMMIT TRANSACTION;
        
        PRINT 'Claim ' + @ClaimNumber + ' created with total charges of $' + CAST(@TotalCharges AS VARCHAR(20));
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMsg, 16, 1);
    END CATCH
END
GO

PRINT 'Procedure dbo.usp_CreateInsuranceClaim created.';
GO

-- ============================================
-- usp_SubmitClaimToInsurance
-- Submits claims via linked server to insurance clearinghouse
-- Legacy: linked server dependency + EDI formatting
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SubmitClaimToInsurance')
    DROP PROCEDURE dbo.usp_SubmitClaimToInsurance;
GO

CREATE PROCEDURE dbo.usp_SubmitClaimToInsurance
    @ClaimID INT = NULL,
    @BatchSubmit BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ClaimIDLocal INT;
    DECLARE @ClaimNumber VARCHAR(20);
    DECLARE @PayerID VARCHAR(20);
    DECLARE @SubmittedCount INT = 0;
    DECLARE @ErrorCount INT = 0;
    DECLARE @EDIBatchID VARCHAR(50);
    
    SET @EDIBatchID = 'EDI-' + FORMAT(GETDATE(), 'yyyyMMddHHmmss');
    
    -- Legacy: CURSOR to process claims one at a time
    DECLARE claim_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ClaimID, ClaimNumber, PayerID
        FROM dbo.InsuranceClaims
        WHERE ClaimStatus = 'CREATED'
          AND (@ClaimID IS NULL OR ClaimID = @ClaimID)
        ORDER BY CreatedDate;
    
    OPEN claim_cursor;
    FETCH NEXT FROM claim_cursor INTO @ClaimIDLocal, @ClaimNumber, @PayerID;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- TODO: In production, this would call the insurance clearinghouse
            -- via linked server. The linked server call would look like:
            --
            -- EXEC [INSURANCE_CLEARINGHOUSE].ClearinghouseDB.dbo.usp_SubmitClaim
            --     @PayerID = @PayerID,
            --     @ClaimNumber = @ClaimNumber,
            --     @EDIContent = @EDI837;
            --
            -- For now, simulate the submission
            
            -- Legacy: Build EDI 837 content (simplified representation)
            DECLARE @EDI837 NVARCHAR(MAX) = '';
            SET @EDI837 = 'ISA*00*          *00*          *ZZ*LAKEVIEW       *ZZ*' + 
                          ISNULL(@PayerID, 'UNKNOWN') + '*' + FORMAT(GETDATE(), 'yyMMdd') + '*' +
                          FORMAT(GETDATE(), 'HHmm') + '~' + CHAR(13) + CHAR(10) +
                          'GS*HC*LAKEVIEW*' + ISNULL(@PayerID, 'UNKNOWN') + '*' + 
                          FORMAT(GETDATE(), 'yyyyMMdd') + '~' + CHAR(13) + CHAR(10) +
                          'ST*837*0001~' + CHAR(13) + CHAR(10) +
                          'CLM*' + @ClaimNumber + '~' + CHAR(13) + CHAR(10) +
                          'SE*4*0001~GE*1~IEA*1~';
            
            -- Update claim with submission info
            UPDATE dbo.InsuranceClaims
            SET ClaimStatus = 'SUBMITTED',
                SubmittedDate = GETDATE(),
                EDIBatchID = @EDIBatchID,
                EDI837Content = @EDI837,
                ModifiedDate = GETDATE()
            WHERE ClaimID = @ClaimIDLocal;
            
            SET @SubmittedCount = @SubmittedCount + 1;
            
            -- Audit
            INSERT INTO dbo.BillingAudit (TableName, RecordID, Action, NewValues)
            VALUES ('InsuranceClaims', @ClaimIDLocal, 'CLAIM_SUBMITTED',
                    'Claim ' + @ClaimNumber + ' submitted in batch ' + @EDIBatchID);
            
        END TRY
        BEGIN CATCH
            SET @ErrorCount = @ErrorCount + 1;
            
            INSERT INTO dbo.BillingAudit (TableName, RecordID, Action, NewValues)
            VALUES ('InsuranceClaims', @ClaimIDLocal, 'SUBMISSION_ERROR', ERROR_MESSAGE());
        END CATCH
        
        FETCH NEXT FROM claim_cursor INTO @ClaimIDLocal, @ClaimNumber, @PayerID;
    END
    
    CLOSE claim_cursor;
    DEALLOCATE claim_cursor;
    
    PRINT 'Batch ' + @EDIBatchID + ': Submitted ' + CAST(@SubmittedCount AS VARCHAR) + 
          ' claims, ' + CAST(@ErrorCount AS VARCHAR) + ' errors.';
END
GO

PRINT 'Procedure dbo.usp_SubmitClaimToInsurance created.';
GO

-- ============================================
-- usp_BatchNightlyBilling
-- Nightly batch billing process
-- Legacy: CURSOR-heavy, CROSS-DATABASE, temp tables
-- Called by SQL Agent job
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_BatchNightlyBilling')
    DROP PROCEDURE dbo.usp_BatchNightlyBilling;
GO

CREATE PROCEDURE dbo.usp_BatchNightlyBilling
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @BatchDate DATETIME = GETDATE();
    DECLARE @EncounterID INT;
    DECLARE @PatientID INT;
    DECLARE @EncounterType VARCHAR(20);
    DECLARE @ProcessedCount INT = 0;
    DECLARE @ErrorCount INT = 0;
    DECLARE @ClaimID INT;
    
    PRINT '========================================';
    PRINT 'Nightly Billing Batch Started: ' + CONVERT(VARCHAR(30), @BatchDate, 120);
    PRINT '========================================';
    
    -- Legacy: temp table for batch tracking
    CREATE TABLE #BatchLog (
        EncounterID INT,
        PatientID INT,
        Action VARCHAR(50),
        Result VARCHAR(20),
        Details NVARCHAR(500),
        ProcessedDate DATETIME DEFAULT GETDATE()
    );
    
    -- STEP 1: Process charges for all active inpatient encounters (daily room charges)
    PRINT 'Step 1: Posting daily room charges...';
    
    -- Legacy: CURSOR over active encounters from PatientDB (CROSS-DATABASE)
    DECLARE encounter_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT e.EncounterID, e.PatientID, e.EncounterType
        FROM PatientDB.dbo.Encounters e
        WHERE e.EncounterStatus = 'ACTIVE'
          AND e.EncounterType IN ('INPATIENT', 'OBSERVATION');
    
    OPEN encounter_cursor;
    FETCH NEXT FROM encounter_cursor INTO @EncounterID, @PatientID, @EncounterType;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Post daily room charge
            DECLARE @RoomCharge DECIMAL(10,2);
            DECLARE @RoomChargeCode VARCHAR(20) = CASE @EncounterType 
                WHEN 'INPATIENT' THEN 'RC-SEMI-PRIV' 
                WHEN 'OBSERVATION' THEN 'RC-OBS' 
            END;
            
            SELECT @RoomCharge = StandardCharge 
            FROM dbo.Chargemaster 
            WHERE ChargeCode = @RoomChargeCode AND IsActive = 1;
            
            IF @RoomCharge IS NOT NULL
            BEGIN
                -- Only post if not already posted today
                IF NOT EXISTS (
                    SELECT 1 FROM dbo.BillingCharges 
                    WHERE EncounterID = @EncounterID 
                      AND ChargeCode = @RoomChargeCode
                      AND CAST(ServiceDate AS DATE) = CAST(GETDATE() AS DATE)
                )
                BEGIN
                    INSERT INTO dbo.BillingCharges (
                        EncounterID, PatientID, ChargeCode, ChargeDescription,
                        ServiceDate, UnitPrice, ChargeAmount, ChargeStatus
                    )
                    VALUES (
                        @EncounterID, @PatientID, @RoomChargeCode,
                        CASE @EncounterType WHEN 'INPATIENT' THEN 'Room & Board - Semi-Private' ELSE 'Observation Room' END,
                        GETDATE(), @RoomCharge, @RoomCharge, 'POSTED'
                    );
                    
                    INSERT INTO #BatchLog VALUES (@EncounterID, @PatientID, 'ROOM_CHARGE', 'SUCCESS', 
                        'Posted $' + CAST(@RoomCharge AS VARCHAR), GETDATE());
                END
            END
            
            -- Process any unposted procedure charges
            EXEC dbo.usp_ProcessEncounterCharges @EncounterID = @EncounterID;
            
            SET @ProcessedCount = @ProcessedCount + 1;
            
        END TRY
        BEGIN CATCH
            SET @ErrorCount = @ErrorCount + 1;
            INSERT INTO #BatchLog VALUES (@EncounterID, @PatientID, 'ROOM_CHARGE', 'ERROR', 
                ERROR_MESSAGE(), GETDATE());
        END CATCH
        
        FETCH NEXT FROM encounter_cursor INTO @EncounterID, @PatientID, @EncounterType;
    END
    
    CLOSE encounter_cursor;
    DEALLOCATE encounter_cursor;
    
    -- STEP 2: Create claims for recently discharged encounters
    PRINT 'Step 2: Creating insurance claims for discharged encounters...';
    
    DECLARE discharge_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT e.EncounterID
        FROM PatientDB.dbo.Encounters e
        WHERE e.EncounterStatus = 'DISCHARGED'
          AND e.DischargeDate >= DATEADD(DAY, -1, GETDATE())
          AND NOT EXISTS (
              SELECT 1 FROM dbo.InsuranceClaims ic 
              WHERE ic.EncounterID = e.EncounterID
          )
          -- Only if patient has insurance
          AND EXISTS (
              SELECT 1 FROM PatientDB.dbo.Patients p 
              WHERE p.PatientID = e.PatientID 
                AND p.PrimaryInsuranceID IS NOT NULL
          );
    
    OPEN discharge_cursor;
    FETCH NEXT FROM discharge_cursor INTO @EncounterID;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC dbo.usp_CreateInsuranceClaim @EncounterID = @EncounterID, @NewClaimID = @ClaimID OUTPUT;
            
            INSERT INTO #BatchLog VALUES (@EncounterID, NULL, 'CLAIM_CREATED', 'SUCCESS',
                'Claim ID: ' + CAST(@ClaimID AS VARCHAR), GETDATE());
        END TRY
        BEGIN CATCH
            INSERT INTO #BatchLog VALUES (@EncounterID, NULL, 'CLAIM_CREATED', 'ERROR',
                ERROR_MESSAGE(), GETDATE());
        END CATCH
        
        FETCH NEXT FROM discharge_cursor INTO @EncounterID;
    END
    
    CLOSE discharge_cursor;
    DEALLOCATE discharge_cursor;
    
    -- STEP 3: Submit pending claims
    PRINT 'Step 3: Submitting pending claims...';
    EXEC dbo.usp_SubmitClaimToInsurance @BatchSubmit = 1;
    
    -- STEP 4: Generate patient invoices for self-pay balances
    PRINT 'Step 4: Generating patient invoices...';
    
    DECLARE selfpay_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT bc.PatientID, bc.EncounterID
        FROM dbo.BillingCharges bc
        LEFT JOIN dbo.InsuranceClaims ic ON bc.EncounterID = ic.EncounterID
        LEFT JOIN dbo.Invoices inv ON bc.EncounterID = inv.EncounterID
        WHERE ic.ClaimID IS NULL  -- No insurance claim
          AND inv.InvoiceID IS NULL  -- No invoice yet
          AND bc.ChargeStatus = 'POSTED'
        -- Check patient has no insurance (CROSS-DATABASE)
          AND NOT EXISTS (
              SELECT 1 FROM PatientDB.dbo.Patients p 
              WHERE p.PatientID = bc.PatientID AND p.PrimaryInsuranceID IS NOT NULL
          );
    
    OPEN selfpay_cursor;
    FETCH NEXT FROM selfpay_cursor INTO @PatientID, @EncounterID;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC dbo.usp_GeneratePatientInvoice @PatientID = @PatientID, @EncounterID = @EncounterID;
        END TRY
        BEGIN CATCH
            INSERT INTO #BatchLog VALUES (@EncounterID, @PatientID, 'INVOICE', 'ERROR',
                ERROR_MESSAGE(), GETDATE());
        END CATCH
        
        FETCH NEXT FROM selfpay_cursor INTO @PatientID, @EncounterID;
    END
    
    CLOSE selfpay_cursor;
    DEALLOCATE selfpay_cursor;
    
    -- Print summary
    PRINT '========================================';
    PRINT 'Nightly Billing Summary:';
    SELECT Action, Result, COUNT(*) AS Count FROM #BatchLog GROUP BY Action, Result ORDER BY Action;
    PRINT 'Total processed: ' + CAST(@ProcessedCount AS VARCHAR) + ', Errors: ' + CAST(@ErrorCount AS VARCHAR);
    PRINT '========================================';
    
    DROP TABLE #BatchLog;
END
GO

PRINT 'Procedure dbo.usp_BatchNightlyBilling created.';
GO

-- ============================================
-- usp_GeneratePatientInvoice
-- Generates a patient invoice/statement
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_GeneratePatientInvoice')
    DROP PROCEDURE dbo.usp_GeneratePatientInvoice;
GO

CREATE PROCEDURE dbo.usp_GeneratePatientInvoice
    @PatientID INT,
    @EncounterID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @InvoiceNumber VARCHAR(20);
    DECLARE @TotalAmount DECIMAL(12,2);
    DECLARE @PaidAmount DECIMAL(12,2);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Calculate unbilled balance
        SELECT @TotalAmount = ISNULL(SUM(bc.ChargeAmount - bc.AdjustmentAmount), 0)
        FROM dbo.BillingCharges bc
        WHERE bc.PatientID = @PatientID
          AND (@EncounterID IS NULL OR bc.EncounterID = @EncounterID)
          AND bc.ChargeStatus IN ('POSTED', 'BILLED');
        
        -- Subtract any payments
        SELECT @PaidAmount = ISNULL(SUM(py.PaymentAmount), 0)
        FROM dbo.Payments py
        WHERE py.PatientID = @PatientID
          AND (@EncounterID IS NULL OR py.EncounterID = @EncounterID)
          AND py.PaymentStatus IN ('POSTED', 'APPLIED');
        
        SET @TotalAmount = @TotalAmount - @PaidAmount;
        
        IF @TotalAmount <= 0
        BEGIN
            PRINT 'No balance due for patient.';
            COMMIT TRANSACTION;
            RETURN;
        END
        
        -- Generate invoice number
        SET @InvoiceNumber = 'INV-' + FORMAT(GETDATE(), 'yyyyMM') + '-' +
            RIGHT('00000' + CAST(
                (SELECT ISNULL(MAX(CAST(RIGHT(InvoiceNumber, 5) AS INT)), 0) + 1
                 FROM dbo.Invoices WHERE InvoiceNumber LIKE 'INV-' + FORMAT(GETDATE(), 'yyyyMM') + '%')
            AS VARCHAR(5)), 5);
        
        INSERT INTO dbo.Invoices (
            InvoiceNumber, PatientID, EncounterID, InvoiceDate, DueDate,
            TotalAmount, PaidAmount, InvoiceStatus
        )
        VALUES (
            @InvoiceNumber, @PatientID, @EncounterID, GETDATE(), 
            DATEADD(DAY, 30, GETDATE()), @TotalAmount, 0.00, 'OPEN'
        );
        
        COMMIT TRANSACTION;
        
        PRINT 'Invoice ' + @InvoiceNumber + ' created for $' + CAST(@TotalAmount AS VARCHAR(20));
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMsg, 16, 1);
    END CATCH
END
GO

PRINT 'Procedure dbo.usp_GeneratePatientInvoice created.';
GO

PRINT '========================================';
PRINT 'All BillingDB stored procedures created.';
PRINT '========================================';
GO
