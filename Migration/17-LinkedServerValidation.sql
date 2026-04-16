-- =====================================================================
-- Migration Step 17: Linked Server Connectivity Validation
-- Lakeview Medical Center
--
-- Purpose: Validate that all reconfigured linked servers on Azure SQL MI
--          are reachable, authenticated, and returning expected data.
--
-- Usage:   Run each section independently after completing Step 16.
--          Review output and address any failures before cutover.
-- =====================================================================
USE master;
GO

SET NOCOUNT ON;
GO

-- =====================================================================
-- Validation results table (temp)
-- =====================================================================
IF OBJECT_ID('tempdb..#LinkedServerValidation') IS NOT NULL
    DROP TABLE #LinkedServerValidation;

CREATE TABLE #LinkedServerValidation (
    TestID          INT IDENTITY(1,1),
    LinkedServer    NVARCHAR(128),
    TestName        NVARCHAR(256),
    Status          NVARCHAR(20),   -- PASS / FAIL / WARN
    Details         NVARCHAR(MAX),
    TestedAt        DATETIME DEFAULT GETDATE()
);
GO

-- =====================================================================
-- 1. Verify linked servers exist in sys.servers
-- =====================================================================
PRINT '=== Test 1: Linked server registration ===';

DECLARE @ExpectedServers TABLE (ServerName NVARCHAR(128));
INSERT INTO @ExpectedServers VALUES 
    ('PHARMACY_SERVER'), ('INSURANCE_CLEARINGHOUSE'), ('LAB_SYSTEM'), ('RADIOLOGY_PACS');

INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
SELECT 
    es.ServerName,
    'Server Registration',
    CASE WHEN s.server_id IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN s.server_id IS NOT NULL 
         THEN 'Registered with provider: ' + ISNULL(s.provider, 'N/A') + ', data source: ' + ISNULL(s.data_source, 'N/A')
         ELSE 'Linked server NOT found in sys.servers'
    END
FROM @ExpectedServers es
LEFT JOIN sys.servers s ON s.name = es.ServerName;
GO

-- =====================================================================
-- 2. Verify provider configuration
-- =====================================================================
PRINT '=== Test 2: Provider configuration ===';

INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
SELECT 
    s.name,
    'Provider Configuration',
    CASE 
        WHEN s.provider = 'MSOLEDBSQL' THEN 'PASS'
        WHEN s.provider = 'SQLNCLI11'  THEN 'WARN'
        ELSE 'WARN'
    END,
    'Provider: ' + ISNULL(s.provider, 'NULL') + 
    CASE 
        WHEN s.provider = 'SQLNCLI11' THEN ' (deprecated - migrate to MSOLEDBSQL)'
        WHEN s.provider = 'MSOLEDBSQL' THEN ' (recommended for Azure SQL MI)'
        ELSE ''
    END
FROM sys.servers s
WHERE s.name IN ('PHARMACY_SERVER', 'INSURANCE_CLEARINGHOUSE', 'LAB_SYSTEM', 'RADIOLOGY_PACS');
GO

-- =====================================================================
-- 3. Verify server options (RPC, data access)
-- =====================================================================
PRINT '=== Test 3: Server options ===';

INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
SELECT 
    s.name,
    'Server Options',
    CASE 
        WHEN s.is_data_access_enabled = 1 THEN 'PASS'
        ELSE 'FAIL'
    END,
    'data_access=' + CAST(s.is_data_access_enabled AS VARCHAR) +
    ', rpc=' + CAST(s.is_remote_login_enabled AS VARCHAR) +
    ', rpc_out=' + CAST(s.is_rpc_out_enabled AS VARCHAR) +
    ', connect_timeout=' + CAST(s.connect_timeout AS VARCHAR) +
    ', query_timeout=' + CAST(s.query_timeout AS VARCHAR)
FROM sys.servers s
WHERE s.name IN ('PHARMACY_SERVER', 'INSURANCE_CLEARINGHOUSE', 'LAB_SYSTEM', 'RADIOLOGY_PACS');
GO

-- =====================================================================
-- 4. Test connectivity with sp_testlinkedserver
-- =====================================================================
PRINT '=== Test 4: Connectivity (sp_testlinkedserver) ===';

DECLARE @server NVARCHAR(128);
DECLARE @msg NVARCHAR(MAX);

-- PHARMACY_SERVER
BEGIN TRY
    SET @server = 'PHARMACY_SERVER';
    EXEC sp_testlinkedserver @server;
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@server, 'Connectivity Test', 'PASS', 'sp_testlinkedserver succeeded');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@server, 'Connectivity Test', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH

-- INSURANCE_CLEARINGHOUSE
BEGIN TRY
    SET @server = 'INSURANCE_CLEARINGHOUSE';
    EXEC sp_testlinkedserver @server;
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@server, 'Connectivity Test', 'PASS', 'sp_testlinkedserver succeeded');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@server, 'Connectivity Test', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH

-- LAB_SYSTEM
BEGIN TRY
    SET @server = 'LAB_SYSTEM';
    EXEC sp_testlinkedserver @server;
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@server, 'Connectivity Test', 'PASS', 'sp_testlinkedserver succeeded');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@server, 'Connectivity Test', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH

-- RADIOLOGY_PACS
BEGIN TRY
    SET @server = 'RADIOLOGY_PACS';
    EXEC sp_testlinkedserver @server;
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@server, 'Connectivity Test', 'PASS', 'sp_testlinkedserver succeeded');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@server, 'Connectivity Test', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH
GO

-- =====================================================================
-- 5. Sample data queries against each linked server
-- =====================================================================
PRINT '=== Test 5: Sample data queries ===';

-- 5a. Pharmacy: query drug inventory
BEGIN TRY
    DECLARE @pharma_count INT;
    SELECT @pharma_count = COUNT(*) FROM OPENQUERY(PHARMACY_SERVER,
        'SELECT TOP 5 DrugCode, DrugName, StockQuantity FROM PharmacyDB.dbo.DrugInventory');
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('PHARMACY_SERVER', 'Sample Data Query', 'PASS', 
        'DrugInventory returned ' + CAST(@pharma_count AS VARCHAR) + ' rows');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('PHARMACY_SERVER', 'Sample Data Query', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH
GO

-- 5b. Insurance: query claims tables
BEGIN TRY
    DECLARE @ins_count INT;
    SELECT @ins_count = COUNT(*) FROM OPENQUERY(INSURANCE_CLEARINGHOUSE,
        'SELECT TOP 5 ClaimID, PayerID, SubmissionDate FROM ClearinghouseDB.dbo.Claims');
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('INSURANCE_CLEARINGHOUSE', 'Sample Data Query', 'PASS', 
        'Claims returned ' + CAST(@ins_count AS VARCHAR) + ' rows');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('INSURANCE_CLEARINGHOUSE', 'Sample Data Query', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH
GO

-- 5c. Lab System: query lab results
BEGIN TRY
    DECLARE @lab_count INT;
    SELECT @lab_count = COUNT(*) FROM OPENQUERY(LAB_SYSTEM,
        'SELECT TOP 5 OrderID, TestCode, ResultValue FROM LabIS.dbo.LabResults');
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('LAB_SYSTEM', 'Sample Data Query', 'PASS', 
        'LabResults returned ' + CAST(@lab_count AS VARCHAR) + ' rows');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('LAB_SYSTEM', 'Sample Data Query', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH
GO

-- 5d. Radiology PACS: query studies
BEGIN TRY
    DECLARE @rad_count INT;
    SELECT @rad_count = COUNT(*) FROM OPENQUERY(RADIOLOGY_PACS,
        'SELECT AccessionNumber, StudyDate, Modality FROM STUDIES WHERE ROWNUM <= 5');
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('RADIOLOGY_PACS', 'Sample Data Query', 'PASS', 
        'STUDIES returned ' + CAST(@rad_count AS VARCHAR) + ' rows');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('RADIOLOGY_PACS', 'Sample Data Query', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH
GO

-- =====================================================================
-- 6. RPC execution test (stored procedure calls)
-- =====================================================================
PRINT '=== Test 6: Remote stored procedure execution ===';

-- 6a. Pharmacy: test RPC capability
BEGIN TRY
    EXEC PHARMACY_SERVER.PharmacyDB.dbo.usp_GetDrugInfo @DrugCode = 'AMOX500';
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('PHARMACY_SERVER', 'RPC Execution', 'PASS', 'usp_GetDrugInfo executed successfully');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('PHARMACY_SERVER', 'RPC Execution', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH

-- 6b. Insurance: test eligibility check
BEGIN TRY
    EXEC [INSURANCE_CLEARINGHOUSE].ClearinghouseDB.dbo.usp_CheckEligibility 
        @PayerID = 'BCBS001', @MemberID = 'XYZ123456';
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('INSURANCE_CLEARINGHOUSE', 'RPC Execution', 'PASS', 'usp_CheckEligibility executed successfully');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES ('INSURANCE_CLEARINGHOUSE', 'RPC Execution', 'FAIL', 
        'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE());
END CATCH
GO

-- =====================================================================
-- 7. Latency measurement
-- =====================================================================
PRINT '=== Test 7: Latency measurement ===';

DECLARE @start DATETIME2, @end DATETIME2, @latency_ms INT;
DECLARE @srv NVARCHAR(128);

-- Pharmacy latency
BEGIN TRY
    SET @srv = 'PHARMACY_SERVER';
    SET @start = SYSDATETIME();
    EXEC sp_testlinkedserver @srv;
    SET @end = SYSDATETIME();
    SET @latency_ms = DATEDIFF(MILLISECOND, @start, @end);
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@srv, 'Latency Test', 
        CASE WHEN @latency_ms < 500 THEN 'PASS' WHEN @latency_ms < 2000 THEN 'WARN' ELSE 'FAIL' END,
        'Round-trip: ' + CAST(@latency_ms AS VARCHAR) + ' ms' +
        CASE WHEN @latency_ms >= 2000 THEN ' (exceeds 2s threshold - check network path)' ELSE '' END);
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@srv, 'Latency Test', 'FAIL', 'Could not measure - connection failed');
END CATCH

-- Insurance latency
BEGIN TRY
    SET @srv = 'INSURANCE_CLEARINGHOUSE';
    SET @start = SYSDATETIME();
    EXEC sp_testlinkedserver @srv;
    SET @end = SYSDATETIME();
    SET @latency_ms = DATEDIFF(MILLISECOND, @start, @end);
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@srv, 'Latency Test',
        CASE WHEN @latency_ms < 500 THEN 'PASS' WHEN @latency_ms < 2000 THEN 'WARN' ELSE 'FAIL' END,
        'Round-trip: ' + CAST(@latency_ms AS VARCHAR) + ' ms');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@srv, 'Latency Test', 'FAIL', 'Could not measure - connection failed');
END CATCH

-- Lab System latency
BEGIN TRY
    SET @srv = 'LAB_SYSTEM';
    SET @start = SYSDATETIME();
    EXEC sp_testlinkedserver @srv;
    SET @end = SYSDATETIME();
    SET @latency_ms = DATEDIFF(MILLISECOND, @start, @end);
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@srv, 'Latency Test',
        CASE WHEN @latency_ms < 500 THEN 'PASS' WHEN @latency_ms < 2000 THEN 'WARN' ELSE 'FAIL' END,
        'Round-trip: ' + CAST(@latency_ms AS VARCHAR) + ' ms');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@srv, 'Latency Test', 'FAIL', 'Could not measure - connection failed');
END CATCH

-- PACS latency
BEGIN TRY
    SET @srv = 'RADIOLOGY_PACS';
    SET @start = SYSDATETIME();
    EXEC sp_testlinkedserver @srv;
    SET @end = SYSDATETIME();
    SET @latency_ms = DATEDIFF(MILLISECOND, @start, @end);
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@srv, 'Latency Test',
        CASE WHEN @latency_ms < 1000 THEN 'PASS' WHEN @latency_ms < 3000 THEN 'WARN' ELSE 'FAIL' END,
        'Round-trip: ' + CAST(@latency_ms AS VARCHAR) + ' ms (higher threshold for hybrid relay)');
END TRY
BEGIN CATCH
    INSERT INTO #LinkedServerValidation (LinkedServer, TestName, Status, Details)
    VALUES (@srv, 'Latency Test', 'FAIL', 'Could not measure - connection failed');
END CATCH
GO

-- =====================================================================
-- 8. Validation Summary Report
-- =====================================================================
PRINT '';
PRINT '=====================================================================';
PRINT '  LINKED SERVER VALIDATION REPORT';
PRINT '=====================================================================';
PRINT '';

SELECT 
    TestID,
    LinkedServer,
    TestName,
    Status,
    Details,
    FORMAT(TestedAt, 'yyyy-MM-dd HH:mm:ss') AS TestedAt
FROM #LinkedServerValidation
ORDER BY LinkedServer, TestID;

-- Summary counts
PRINT '';
PRINT '--- Summary ---';
SELECT 
    Status,
    COUNT(*) AS TestCount
FROM #LinkedServerValidation
GROUP BY Status
ORDER BY 
    CASE Status WHEN 'FAIL' THEN 1 WHEN 'WARN' THEN 2 WHEN 'PASS' THEN 3 END;

-- Failures requiring attention
IF EXISTS (SELECT 1 FROM #LinkedServerValidation WHERE Status = 'FAIL')
BEGIN
    PRINT '';
    PRINT '!!! FAILURES DETECTED - Review the following before cutover: !!!';
    SELECT LinkedServer, TestName, Details 
    FROM #LinkedServerValidation 
    WHERE Status = 'FAIL'
    ORDER BY LinkedServer;
END
ELSE
BEGIN
    PRINT '';
    PRINT 'All linked server tests passed. Ready for cutover.';
END

-- Cleanup
DROP TABLE #LinkedServerValidation;
GO

PRINT '=====================================================================';
PRINT 'Validation complete. Review results above.';
PRINT '=====================================================================';
GO
