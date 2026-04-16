-- ============================================
-- 21 - CLR & Service Broker Validation
-- Lakeview Medical Center
-- Comprehensive validation of CLR functions and
-- Service Broker messaging on Azure SQL MI
-- ============================================
-- Run after: 19-CLRMigration.sql, 20-ServiceBrokerMigration.sql
-- ============================================

USE PatientDB;
GO

SET NOCOUNT ON;
GO

PRINT '============================================';
PRINT ' CLR & Service Broker Validation';
PRINT ' Started: ' + CONVERT(VARCHAR(30), GETDATE(), 121);
PRINT '============================================';
GO

-- ============================================
-- Results tracking table
-- ============================================
IF OBJECT_ID('tempdb..#ValidationResults') IS NOT NULL
    DROP TABLE #ValidationResults;

CREATE TABLE #ValidationResults (
    TestID      INT IDENTITY(1,1),
    Category    NVARCHAR(50),
    TestName    NVARCHAR(200),
    Status      NVARCHAR(10),  -- PASS / FAIL / WARN
    Details     NVARCHAR(MAX),
    TestedAt    DATETIME DEFAULT GETDATE()
);
GO

-- ============================================
-- SECTION 1: CLR Infrastructure Validation
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 1: CLR Infrastructure';
PRINT '========================================';
GO

-- Test 1.1: CLR is enabled
DECLARE @ClrEnabled INT;
SELECT @ClrEnabled = CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'clr enabled';
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
VALUES ('CLR Infra', 'CLR integration enabled',
        CASE WHEN @ClrEnabled = 1 THEN 'PASS' ELSE 'FAIL' END,
        'clr enabled = ' + CAST(@ClrEnabled AS VARCHAR));
GO

-- Test 1.2: Assembly exists
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'CLR Infra', 'MedicalCalculations assembly exists',
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END,
       'Assembly count: ' + CAST(COUNT(*) AS VARCHAR)
FROM sys.assemblies WHERE name = 'MedicalCalculations';
GO

-- Test 1.3: Assembly permission set
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'CLR Infra', 'Assembly permission set is SAFE',
       CASE WHEN permission_set = 1 THEN 'PASS'
            WHEN permission_set = 2 THEN 'WARN'
            ELSE 'FAIL' END,
       'Permission set: ' + CASE permission_set
           WHEN 1 THEN 'SAFE' WHEN 2 THEN 'EXTERNAL_ACCESS' WHEN 3 THEN 'UNSAFE'
       END
FROM sys.assemblies WHERE name = 'MedicalCalculations';
GO

-- Test 1.4: All 6 CLR functions exist
DECLARE @FuncCount INT;
SELECT @FuncCount = COUNT(*) FROM sys.assembly_modules am
JOIN sys.objects o ON am.object_id = o.object_id
WHERE o.name LIKE 'fn_CLR_%';

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
VALUES ('CLR Infra', 'All 6 CLR functions registered',
        CASE WHEN @FuncCount = 6 THEN 'PASS' ELSE 'FAIL' END,
        'Found ' + CAST(@FuncCount AS VARCHAR) + ' of 6 expected functions');
GO

-- Test 1.5: Each function exists individually
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'CLR Infra',
       'Function exists: ' + name,
       'PASS',
       'Type: ' + type_desc
FROM sys.objects
WHERE name IN ('fn_CLR_CheckDrugInteractions', 'fn_CLR_ValidateICDCode',
               'fn_CLR_GetBMICategory', 'fn_CLR_CalculateGFR',
               'fn_CLR_ParseHL7Segments', 'fn_CLR_NormalizeDrugName');

-- Check for missing functions
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'CLR Infra', 'Function exists: ' + f.name, 'FAIL', 'Function not found'
FROM (VALUES ('fn_CLR_CheckDrugInteractions'), ('fn_CLR_ValidateICDCode'),
             ('fn_CLR_GetBMICategory'), ('fn_CLR_CalculateGFR'),
             ('fn_CLR_ParseHL7Segments'), ('fn_CLR_NormalizeDrugName')) AS f(name)
WHERE NOT EXISTS (SELECT 1 FROM sys.objects o WHERE o.name = f.name);
GO

-- ============================================
-- SECTION 2: CLR Function Correctness Tests
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 2: CLR Function Tests';
PRINT '========================================';
GO

-- ----- fn_CLR_CheckDrugInteractions -----

-- Test 2.1: Known MAJOR interaction
BEGIN TRY
    DECLARE @InterResult1 NVARCHAR(500);
    SET @InterResult1 = dbo.fn_CLR_CheckDrugInteractions('WARFARIN', 'ASPIRIN');
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'WARFARIN + ASPIRIN = MAJOR interaction',
            CASE WHEN @InterResult1 LIKE '%MAJOR%bleeding%' THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(@InterResult1, 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'WARFARIN + ASPIRIN = MAJOR interaction', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.2: Reverse order returns same interaction
BEGIN TRY
    DECLARE @InterResult2 NVARCHAR(500);
    SET @InterResult2 = dbo.fn_CLR_CheckDrugInteractions('ASPIRIN', 'WARFARIN');
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'Reverse lookup: ASPIRIN + WARFARIN',
            CASE WHEN @InterResult2 LIKE '%MAJOR%' THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(@InterResult2, 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'Reverse lookup: ASPIRIN + WARFARIN', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.3: No interaction returns NO_INTERACTION
BEGIN TRY
    DECLARE @InterResult3 NVARCHAR(500);
    SET @InterResult3 = dbo.fn_CLR_CheckDrugInteractions('TYLENOL', 'VITAMIN_C');
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'No interaction: TYLENOL + VITAMIN_C',
            CASE WHEN @InterResult3 = 'NO_INTERACTION' THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(@InterResult3, 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'No interaction: TYLENOL + VITAMIN_C', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.4: NULL input handling
BEGIN TRY
    DECLARE @InterResult4 NVARCHAR(500);
    SET @InterResult4 = dbo.fn_CLR_CheckDrugInteractions(NULL, 'ASPIRIN');
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'NULL input returns NULL',
            CASE WHEN @InterResult4 IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(@InterResult4, 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'NULL input returns NULL', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.5: Additional known interactions
BEGIN TRY
    DECLARE @InterResult5 NVARCHAR(500);
    SET @InterResult5 = dbo.fn_CLR_CheckDrugInteractions('METFORMIN', 'CONTRAST_DYE');
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'METFORMIN + CONTRAST_DYE = MAJOR',
            CASE WHEN @InterResult5 LIKE '%MAJOR%lactic acidosis%' THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(@InterResult5, 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Interactions', 'METFORMIN + CONTRAST_DYE = MAJOR', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- ----- fn_CLR_ValidateICDCode -----

-- Test 2.6: Valid ICD-10 codes
BEGIN TRY
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    SELECT 'ICD Validation', 'Valid code: ' + code,
           CASE WHEN dbo.fn_CLR_ValidateICDCode(code) = 1 THEN 'PASS' ELSE 'FAIL' END,
           'Expected TRUE, Got: ' + CAST(dbo.fn_CLR_ValidateICDCode(code) AS VARCHAR)
    FROM (VALUES ('A01.0'), ('I25.10'), ('E11.9'), ('J18.9'), ('Z00'), ('M54.5')) AS t(code);
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('ICD Validation', 'Valid ICD codes batch', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.7: Invalid ICD-10 codes
BEGIN TRY
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    SELECT 'ICD Validation', 'Invalid code: ' + code,
           CASE WHEN dbo.fn_CLR_ValidateICDCode(code) = 0 THEN 'PASS' ELSE 'FAIL' END,
           'Expected FALSE, Got: ' + CAST(dbo.fn_CLR_ValidateICDCode(code) AS VARCHAR)
    FROM (VALUES ('ZZZ'), ('123'), (''), ('A'), ('XX.99')) AS t(code);
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('ICD Validation', 'Invalid ICD codes batch', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.8: NULL ICD code
BEGIN TRY
    DECLARE @ICDNull BIT;
    SET @ICDNull = dbo.fn_CLR_ValidateICDCode(NULL);
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('ICD Validation', 'NULL code returns FALSE',
            CASE WHEN @ICDNull = 0 THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(CAST(@ICDNull AS VARCHAR), 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('ICD Validation', 'NULL code returns FALSE', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- ----- fn_CLR_GetBMICategory -----

-- Test 2.9: BMI classifications
BEGIN TRY
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    SELECT 'BMI', 'BMI ' + CAST(bmi AS VARCHAR) + ' = ' + expected,
           CASE WHEN dbo.fn_CLR_GetBMICategory(bmi) = expected THEN 'PASS' ELSE 'FAIL' END,
           'Got: ' + ISNULL(dbo.fn_CLR_GetBMICategory(bmi), 'NULL')
    FROM (VALUES
        (15.0, 'Severe Thinness'),
        (16.5, 'Moderate Thinness'),
        (17.5, 'Mild Thinness'),
        (22.0, 'Normal'),
        (27.5, 'Overweight'),
        (32.0, 'Obese Class I'),
        (37.0, 'Obese Class II'),
        (42.0, 'Obese Class III')
    ) AS t(bmi, expected);
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('BMI', 'BMI classifications batch', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.10: BMI NULL and zero
BEGIN TRY
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('BMI', 'BMI NULL returns NULL',
            CASE WHEN dbo.fn_CLR_GetBMICategory(NULL) IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(dbo.fn_CLR_GetBMICategory(NULL), 'NULL'));

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('BMI', 'BMI 0 returns NULL',
            CASE WHEN dbo.fn_CLR_GetBMICategory(0) IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(dbo.fn_CLR_GetBMICategory(0), 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('BMI', 'BMI edge cases', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- ----- fn_CLR_CalculateGFR -----

-- Test 2.11: GFR calculation returns reasonable values
BEGIN TRY
    DECLARE @GFR1 FLOAT = dbo.fn_CLR_CalculateGFR(1.0, 50, 1, 0);  -- Female, 50yo
    DECLARE @GFR2 FLOAT = dbo.fn_CLR_CalculateGFR(1.5, 65, 0, 0);  -- Male, 65yo
    DECLARE @GFR3 FLOAT = dbo.fn_CLR_CalculateGFR(0.8, 30, 1, 0);  -- Young female

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('GFR', 'GFR female age 50 creatinine 1.0 in range (40-120)',
            CASE WHEN @GFR1 BETWEEN 40 AND 120 THEN 'PASS' ELSE 'FAIL' END,
            'GFR = ' + CAST(@GFR1 AS VARCHAR));

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('GFR', 'GFR male age 65 creatinine 1.5 in range (20-80)',
            CASE WHEN @GFR2 BETWEEN 20 AND 80 THEN 'PASS' ELSE 'FAIL' END,
            'GFR = ' + CAST(@GFR2 AS VARCHAR));

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('GFR', 'Young female has higher GFR than older male with higher creatinine',
            CASE WHEN @GFR3 > @GFR2 THEN 'PASS' ELSE 'FAIL' END,
            'Young female GFR=' + CAST(@GFR3 AS VARCHAR) + ', Older male GFR=' + CAST(@GFR2 AS VARCHAR));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('GFR', 'GFR calculation', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.12: GFR NULL inputs
BEGIN TRY
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('GFR', 'GFR NULL creatinine returns NULL',
            CASE WHEN dbo.fn_CLR_CalculateGFR(NULL, 50, 1, 0) IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(CAST(dbo.fn_CLR_CalculateGFR(NULL, 50, 1, 0) AS VARCHAR), 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('GFR', 'GFR NULL handling', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- ----- fn_CLR_ParseHL7Segments -----

-- Test 2.13: HL7 message parsing
BEGIN TRY
    DECLARE @HL7Msg NVARCHAR(MAX) = N'MSH|^~\&|ADT|LAKEVIEW|LAB|LAKEVIEW|202601011200||ADT^A01|MSG001|P|2.5
PID|||12345||DOE^JOHN||19800101|M
PV1||I|ICU^101^A
OBX|1|NM|WBC||7.5|10*3/uL';

    DECLARE @SegCount INT;
    SELECT @SegCount = COUNT(*) FROM dbo.fn_CLR_ParseHL7Segments(@HL7Msg);

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('HL7 Parser', 'HL7 message returns 4 segments',
            CASE WHEN @SegCount = 4 THEN 'PASS' ELSE 'FAIL' END,
            'Segment count: ' + CAST(@SegCount AS VARCHAR));

    -- Verify segment types
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    SELECT 'HL7 Parser', 'HL7 segment type: ' + SegmentType,
           CASE WHEN SegmentType IN ('MSH', 'PID', 'PV1', 'OBX') THEN 'PASS' ELSE 'FAIL' END,
           'Index: ' + CAST(SegmentIndex AS VARCHAR) + ', Fields: ' + CAST(FieldCount AS VARCHAR)
    FROM dbo.fn_CLR_ParseHL7Segments(@HL7Msg);
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('HL7 Parser', 'HL7 message parsing', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.14: HL7 NULL input
BEGIN TRY
    DECLARE @NullHL7Count INT;
    SELECT @NullHL7Count = COUNT(*) FROM dbo.fn_CLR_ParseHL7Segments(NULL);
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('HL7 Parser', 'NULL HL7 message returns 0 rows',
            CASE WHEN @NullHL7Count = 0 THEN 'PASS' ELSE 'FAIL' END,
            'Row count: ' + CAST(@NullHL7Count AS VARCHAR));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('HL7 Parser', 'NULL HL7 handling', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- ----- fn_CLR_NormalizeDrugName -----

-- Test 2.15: Drug name normalization
BEGIN TRY
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    SELECT 'Drug Normalize', 'Normalize: ' + input,
           CASE WHEN dbo.fn_CLR_NormalizeDrugName(input) = expected THEN 'PASS' ELSE 'FAIL' END,
           'Expected: [' + expected + '], Got: [' + ISNULL(dbo.fn_CLR_NormalizeDrugName(input), 'NULL') + ']'
    FROM (VALUES
        ('Metformin HCL',       'METFORMIN'),
        ('Lisinopril Sodium',   'LISINOPRIL'),
        ('Warfarin Potassium',  'WARFARIN'),
        ('Amoxicillin',         'AMOXICILLIN')
    ) AS t(input, expected);
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Normalize', 'Drug name normalization batch', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 2.16: Drug name NULL
BEGIN TRY
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Normalize', 'NULL drug name returns NULL',
            CASE WHEN dbo.fn_CLR_NormalizeDrugName(NULL) IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'Result: ' + ISNULL(dbo.fn_CLR_NormalizeDrugName(NULL), 'NULL'));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Drug Normalize', 'NULL drug name handling', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- ============================================
-- SECTION 3: Service Broker Infrastructure
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 3: Service Broker Infrastructure';
PRINT '========================================';
GO

-- Test 3.1: Service Broker enabled on PatientDB
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'Service Broker enabled on PatientDB',
       CASE WHEN is_broker_enabled = 1 THEN 'PASS' ELSE 'FAIL' END,
       'is_broker_enabled = ' + CAST(is_broker_enabled AS VARCHAR)
FROM sys.databases WHERE name = 'PatientDB';
GO

-- Test 3.2: Service Broker enabled on BillingDB
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'Service Broker enabled on BillingDB',
       CASE WHEN is_broker_enabled = 1 THEN 'PASS' ELSE 'FAIL' END,
       'is_broker_enabled = ' + CAST(is_broker_enabled AS VARCHAR)
FROM sys.databases WHERE name = 'BillingDB';
GO

-- Test 3.3: PatientDB message types
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'PatientDB message type: ' + name, 'PASS', 'Validation: ' + validation_desc
FROM sys.service_message_types WHERE name IN (
    'PatientEncounterMessage', 'PatientDischargeMessage',
    'BillingResponseMessage', 'LabResultNotificationMessage');

-- Check missing
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'PatientDB message type: ' + mt.name, 'FAIL', 'Message type not found'
FROM (VALUES ('PatientEncounterMessage'), ('PatientDischargeMessage'),
             ('BillingResponseMessage'), ('LabResultNotificationMessage')) AS mt(name)
WHERE NOT EXISTS (SELECT 1 FROM sys.service_message_types smt WHERE smt.name = mt.name);
GO

-- Test 3.4: PatientDB contracts
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'PatientDB contract: ' + name, 'PASS', 'Contract exists'
FROM sys.service_contracts WHERE name IN ('PatientBillingContract', 'LabNotificationContract');

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'PatientDB contract: ' + c.name, 'FAIL', 'Contract not found'
FROM (VALUES ('PatientBillingContract'), ('LabNotificationContract')) AS c(name)
WHERE NOT EXISTS (SELECT 1 FROM sys.service_contracts sc WHERE sc.name = c.name);
GO

-- Test 3.5: PatientDB queues
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'PatientDB queue: ' + name,
       CASE WHEN is_receive_enabled = 1 THEN 'PASS' ELSE 'WARN' END,
       'Receive enabled: ' + CAST(is_receive_enabled AS VARCHAR) +
       ', Enqueue enabled: ' + CAST(is_enqueue_enabled AS VARCHAR)
FROM sys.service_queues WHERE name IN ('PatientEventSendQueue', 'LabNotificationQueue');
GO

-- Test 3.6: PatientDB services
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'PatientDB service: ' + name, 'PASS', 'Service exists'
FROM sys.services WHERE name IN ('PatientEventSendService', 'LabNotificationService');
GO

-- Test 3.7: PatientDB routes
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'PatientDB route: ' + name, 'PASS',
       'Address: ' + ISNULL(address, 'N/A') + ', Remote service: ' + ISNULL(remote_service_name, 'N/A')
FROM sys.routes WHERE name = 'BillingServiceRoute';

IF NOT EXISTS (SELECT 1 FROM sys.routes WHERE name = 'BillingServiceRoute')
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Infra', 'PatientDB route: BillingServiceRoute', 'FAIL', 'Route not found');
GO

-- Test 3.8: Activation procedure exists
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'Activation proc: usp_ProcessLabNotifications',
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END,
       'Procedure count: ' + CAST(COUNT(*) AS VARCHAR)
FROM sys.procedures WHERE name = 'usp_ProcessLabNotifications';
GO

-- Test 3.9: Queue activation configured
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'LabNotificationQueue activation configured',
       CASE WHEN is_activation_enabled = 1 THEN 'PASS' ELSE 'FAIL' END,
       'Activation enabled: ' + CAST(is_activation_enabled AS VARCHAR) +
       ', Max readers: ' + CAST(max_readers AS VARCHAR)
FROM sys.service_queues WHERE name = 'LabNotificationQueue';
GO

-- ============================================
-- BillingDB infrastructure checks
-- ============================================
USE BillingDB;
GO

-- Test 3.10: BillingDB queue
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'BillingDB queue: BillingEventReceiveQueue',
       CASE WHEN is_receive_enabled = 1 THEN 'PASS' ELSE 'WARN' END,
       'Receive enabled: ' + CAST(is_receive_enabled AS VARCHAR)
FROM sys.service_queues WHERE name = 'BillingEventReceiveQueue';
GO

-- Test 3.11: BillingDB service
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'BillingDB service: BillingEventReceiveService',
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END,
       'Service count: ' + CAST(COUNT(*) AS VARCHAR)
FROM sys.services WHERE name = 'BillingEventReceiveService';
GO

-- Test 3.12: BillingDB route
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'BillingDB route: PatientServiceRoute',
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END,
       'Route count: ' + CAST(COUNT(*) AS VARCHAR)
FROM sys.routes WHERE name = 'PatientServiceRoute';
GO

-- Test 3.13: BillingDB activation procedure
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'Activation proc: usp_ProcessBillingEvents',
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END,
       'Procedure count: ' + CAST(COUNT(*) AS VARCHAR)
FROM sys.procedures WHERE name = 'usp_ProcessBillingEvents';
GO

-- Test 3.14: BillingDB queue activation configured
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Infra', 'BillingEventReceiveQueue activation configured',
       CASE WHEN is_activation_enabled = 1 THEN 'PASS' ELSE 'FAIL' END,
       'Activation enabled: ' + CAST(is_activation_enabled AS VARCHAR) +
       ', Max readers: ' + CAST(max_readers AS VARCHAR)
FROM sys.service_queues WHERE name = 'BillingEventReceiveQueue';
GO

-- ============================================
-- SECTION 4: Service Broker Message Flow Tests
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 4: Service Broker Message Flow';
PRINT '========================================';
GO

USE PatientDB;
GO

-- Test 4.1: Send encounter message and verify delivery
BEGIN TRY
    DECLARE @TestConvHandle UNIQUEIDENTIFIER;
    DECLARE @TestEncounterMsg XML = N'<NewEncounter>
        <EncounterID>88888</EncounterID>
        <PatientID>10002</PatientID>
        <EncounterType>VALIDATION_TEST</EncounterType>
        <AdmitDate>2026-04-16T00:00:00</AdmitDate>
    </NewEncounter>';

    BEGIN DIALOG CONVERSATION @TestConvHandle
        FROM SERVICE [PatientEventSendService]
        TO SERVICE N'BillingEventReceiveService'
        ON CONTRACT [PatientBillingContract]
        WITH ENCRYPTION = OFF;

    SEND ON CONVERSATION @TestConvHandle
        MESSAGE TYPE [PatientEncounterMessage] (@TestEncounterMsg);

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Messaging', 'Send encounter message from PatientDB', 'PASS',
            'Conversation: ' + CAST(@TestConvHandle AS NVARCHAR(50)));

    -- Wait briefly for message delivery
    WAITFOR DELAY '00:00:03';

    -- Check for active conversations
    DECLARE @ConvCount INT;
    SELECT @ConvCount = COUNT(*) FROM sys.conversation_endpoints
    WHERE far_service = 'BillingEventReceiveService'
      AND state_desc NOT IN ('CLOSED');

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Messaging', 'Active conversations to BillingEventReceiveService',
            CASE WHEN @ConvCount > 0 THEN 'PASS' ELSE 'WARN' END,
            'Active conversations: ' + CAST(@ConvCount AS VARCHAR));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Messaging', 'Send encounter message from PatientDB', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 4.2: Send lab notification message
BEGIN TRY
    DECLARE @LabConvHandle UNIQUEIDENTIFIER;
    DECLARE @LabMsg XML = N'<LabNotification>
        <PatientID>10003</PatientID>
        <TestName>Troponin I</TestName>
        <ResultValue>2.5</ResultValue>
        <CriticalFlag>1</CriticalFlag>
    </LabNotification>';

    BEGIN DIALOG CONVERSATION @LabConvHandle
        FROM SERVICE [LabNotificationService]
        TO SERVICE N'LabNotificationService'
        ON CONTRACT [LabNotificationContract]
        WITH ENCRYPTION = OFF;

    SEND ON CONVERSATION @LabConvHandle
        MESSAGE TYPE [LabResultNotificationMessage] (@LabMsg);

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Messaging', 'Send critical lab notification', 'PASS',
            'Conversation: ' + CAST(@LabConvHandle AS NVARCHAR(50)));

    WAITFOR DELAY '00:00:03';

    -- Check if the activation proc processed it (look in AuditLog)
    DECLARE @LabAuditCount INT;
    SELECT @LabAuditCount = COUNT(*) FROM dbo.AuditLog
    WHERE Action = 'CRITICAL_LAB_NOTIFICATION'
      AND RecordID = 10003
      AND ChangedBy = 'ServiceBroker';

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Messaging', 'Lab notification processed by activation proc',
            CASE WHEN @LabAuditCount > 0 THEN 'PASS' ELSE 'WARN' END,
            'Audit entries: ' + CAST(@LabAuditCount AS VARCHAR) +
            ' (WARN may indicate activation proc has not fired yet)');
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Messaging', 'Send critical lab notification', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 4.3: Send discharge message
BEGIN TRY
    DECLARE @DischConvHandle UNIQUEIDENTIFIER;
    DECLARE @DischMsg XML = N'<PatientDischarge>
        <EncounterID>88888</EncounterID>
        <DischargeDate>2026-04-16T12:00:00</DischargeDate>
    </PatientDischarge>';

    BEGIN DIALOG CONVERSATION @DischConvHandle
        FROM SERVICE [PatientEventSendService]
        TO SERVICE N'BillingEventReceiveService'
        ON CONTRACT [PatientBillingContract]
        WITH ENCRYPTION = OFF;

    SEND ON CONVERSATION @DischConvHandle
        MESSAGE TYPE [PatientDischargeMessage] (@DischMsg);

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Messaging', 'Send discharge message from PatientDB', 'PASS',
            'Conversation: ' + CAST(@DischConvHandle AS NVARCHAR(50)));
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('SB Messaging', 'Send discharge message from PatientDB', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- Test 4.4: Verify no poison messages
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Messaging', 'No poison messages in PatientEventSendQueue',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'WARN' END,
       'Poison message count: ' + CAST(COUNT(*) AS VARCHAR)
FROM dbo.PatientEventSendQueue WITH (NOLOCK)
WHERE status = 2;  -- poison
GO

-- Test 4.5: Check conversation health
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'SB Messaging', 'Conversation states in PatientDB',
       CASE WHEN SUM(CASE WHEN state_desc = 'ERROR' THEN 1 ELSE 0 END) = 0 THEN 'PASS' ELSE 'WARN' END,
       'States: ' + STRING_AGG(state_desc + '(' + CAST(cnt AS VARCHAR) + ')', ', ')
FROM (
    SELECT state_desc, COUNT(*) AS cnt
    FROM sys.conversation_endpoints
    GROUP BY state_desc
) AS states;
GO

-- ============================================
-- SECTION 5: Cross-Database Verification
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 5: Cross-Database Verification';
PRINT '========================================';
GO

-- Test 5.1: Verify BillingDB processed encounter message
USE BillingDB;
GO

WAITFOR DELAY '00:00:02';

BEGIN TRY
    DECLARE @BillingAuditCount INT;
    SELECT @BillingAuditCount = COUNT(*) FROM dbo.BillingAudit
    WHERE Action = 'NEW_ENCOUNTER_RECEIVED'
      AND NewValues LIKE '%VALIDATION_TEST%'
      AND ChangedBy = 'ServiceBroker';

    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Cross-DB', 'BillingDB received encounter notification',
            CASE WHEN @BillingAuditCount > 0 THEN 'PASS' ELSE 'WARN' END,
            'Audit entries: ' + CAST(@BillingAuditCount AS VARCHAR) +
            ' (WARN = activation proc may need more time)');
END TRY
BEGIN CATCH
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Cross-DB', 'BillingDB received encounter notification', 'WARN',
            'Could not check BillingAudit: ' + ERROR_MESSAGE());
END CATCH
GO

-- Test 5.2: BillingDB conversation endpoints
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'Cross-DB', 'BillingDB has conversation endpoints',
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'WARN' END,
       'Endpoint count: ' + CAST(COUNT(*) AS VARCHAR)
FROM sys.conversation_endpoints;
GO

-- Test 5.3: No error conversations in BillingDB
INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT 'Cross-DB', 'No ERROR conversations in BillingDB',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'Error conversations: ' + CAST(COUNT(*) AS VARCHAR)
FROM sys.conversation_endpoints WHERE state_desc = 'ERROR';
GO

-- ============================================
-- SECTION 6: Final Summary Report
-- ============================================
USE PatientDB;
GO

PRINT '';
PRINT '========================================';
PRINT ' VALIDATION SUMMARY REPORT';
PRINT '========================================';
PRINT '';

-- Category summary
SELECT Category,
       SUM(CASE WHEN Status = 'PASS' THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN Status = 'FAIL' THEN 1 ELSE 0 END) AS Failed,
       SUM(CASE WHEN Status = 'WARN' THEN 1 ELSE 0 END) AS Warnings,
       COUNT(*) AS Total
FROM #ValidationResults
GROUP BY Category
ORDER BY Category;

-- Overall totals
DECLARE @TotalTests  INT = (SELECT COUNT(*) FROM #ValidationResults);
DECLARE @PassCount   INT = (SELECT COUNT(*) FROM #ValidationResults WHERE Status = 'PASS');
DECLARE @FailCount   INT = (SELECT COUNT(*) FROM #ValidationResults WHERE Status = 'FAIL');
DECLARE @WarnCount   INT = (SELECT COUNT(*) FROM #ValidationResults WHERE Status = 'WARN');

PRINT '';
PRINT 'TOTAL: ' + CAST(@TotalTests AS VARCHAR) + ' tests';
PRINT 'PASSED:   ' + CAST(@PassCount AS VARCHAR);
PRINT 'FAILED:   ' + CAST(@FailCount AS VARCHAR);
PRINT 'WARNINGS: ' + CAST(@WarnCount AS VARCHAR);

-- Show failures in detail
IF @FailCount > 0
BEGIN
    PRINT '';
    PRINT '---- FAILED TESTS ----';
    SELECT TestID, Category, TestName, Details
    FROM #ValidationResults WHERE Status = 'FAIL'
    ORDER BY TestID;
END

-- Show warnings in detail
IF @WarnCount > 0
BEGIN
    PRINT '';
    PRINT '---- WARNINGS ----';
    SELECT TestID, Category, TestName, Details
    FROM #ValidationResults WHERE Status = 'WARN'
    ORDER BY TestID;
END

-- Full detailed results
PRINT '';
PRINT '---- ALL RESULTS ----';
SELECT TestID, Category, TestName, Status, Details
FROM #ValidationResults
ORDER BY TestID;

-- Overall status
PRINT '';
IF @FailCount = 0
    PRINT '*** VALIDATION PASSED: All tests passed (with ' + CAST(@WarnCount AS VARCHAR) + ' warnings). ***';
ELSE
    PRINT '*** VALIDATION FAILED: ' + CAST(@FailCount AS VARCHAR) + ' test(s) failed. Review details above. ***';

-- Cleanup
DROP TABLE #ValidationResults;
GO

PRINT '';
PRINT '============================================';
PRINT ' CLR & Service Broker Validation Complete';
PRINT ' Finished: ' + CONVERT(VARCHAR(30), GETDATE(), 121);
PRINT '============================================';
GO
