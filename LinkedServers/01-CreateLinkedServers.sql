-- ============================================
-- Linked Server Definitions
-- Lakeview Medical Center
-- External system connections
-- Legacy: linked servers are a significant
-- migration challenge for Azure SQL MI
-- ============================================
USE master;
GO

-- ============================================
-- Linked Server: PHARMACY_SERVER
-- External pharmacy dispensing system
-- Used for real-time drug dispensing verification
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.servers WHERE name = 'PHARMACY_SERVER')
BEGIN
    EXEC sp_addlinkedserver 
        @server = N'PHARMACY_SERVER',
        @srvproduct = N'SQL Server',
        @provider = N'SQLNCLI11',
        @datasrc = N'PHARM-SQL-01.lakeviewmedical.local';
    
    EXEC sp_addlinkedsrvlogin 
        @rmtsrvname = N'PHARMACY_SERVER',
        @useself = N'FALSE',
        @locallogin = NULL,
        @rmtuser = N'pharmacy_interface',
        @rmtpassword = N'Ph@rm_Int3rf@c3_2016!';  -- Legacy: password in script
    
    -- Set RPC and RPC Out to enable stored procedure execution
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'rpc', @optvalue = 'true';
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'rpc out', @optvalue = 'true';
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'data access', @optvalue = 'true';
    
    -- Set query timeout
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'query timeout', @optvalue = '60';
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'connect timeout', @optvalue = '30';
    
    PRINT 'Linked server PHARMACY_SERVER created.';
END
ELSE
    PRINT 'Linked server PHARMACY_SERVER already exists.';
GO

-- ============================================
-- Linked Server: INSURANCE_CLEARINGHOUSE
-- Insurance claims clearinghouse (Availity/Change Healthcare)
-- Used for EDI claim submission and eligibility checks
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.servers WHERE name = 'INSURANCE_CLEARINGHOUSE')
BEGIN
    EXEC sp_addlinkedserver 
        @server = N'INSURANCE_CLEARINGHOUSE',
        @srvproduct = N'SQL Server',
        @provider = N'SQLNCLI11',
        @datasrc = N'CLH-SQL-01.clearinghouse.local';
    
    EXEC sp_addlinkedsrvlogin 
        @rmtsrvname = N'INSURANCE_CLEARINGHOUSE',
        @useself = N'FALSE',
        @locallogin = NULL,
        @rmtuser = N'lakeview_claims',
        @rmtpassword = N'Cl@ims_2016_Secure!';  -- Legacy: password in script
    
    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'rpc', @optvalue = 'true';
    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'rpc out', @optvalue = 'true';
    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'data access', @optvalue = 'true';
    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'query timeout', @optvalue = '120';
    
    PRINT 'Linked server INSURANCE_CLEARINGHOUSE created.';
END
ELSE
    PRINT 'Linked server INSURANCE_CLEARINGHOUSE already exists.';
GO

-- ============================================
-- Linked Server: LAB_SYSTEM
-- Laboratory Information System (LIS)
-- Used for lab order interfacing and result retrieval
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.servers WHERE name = 'LAB_SYSTEM')
BEGIN
    EXEC sp_addlinkedserver 
        @server = N'LAB_SYSTEM',
        @srvproduct = N'',
        @provider = N'SQLNCLI11',
        @datasrc = N'LAB-SQL-01.lakeviewmedical.local',
        @catalog = N'LabIS';
    
    EXEC sp_addlinkedsrvlogin 
        @rmtsrvname = N'LAB_SYSTEM',
        @useself = N'FALSE',
        @locallogin = NULL,
        @rmtuser = N'ehr_interface',
        @rmtpassword = N'L@b_Int3rf@c3!';
    
    EXEC sp_serveroption @server = N'LAB_SYSTEM', @optname = 'data access', @optvalue = 'true';
    EXEC sp_serveroption @server = N'LAB_SYSTEM', @optname = 'rpc', @optvalue = 'true';
    EXEC sp_serveroption @server = N'LAB_SYSTEM', @optname = 'rpc out', @optvalue = 'true';
    
    PRINT 'Linked server LAB_SYSTEM created.';
END
ELSE
    PRINT 'Linked server LAB_SYSTEM already exists.';
GO

-- ============================================
-- Linked Server: RADIOLOGY_PACS
-- Radiology PACS/RIS system
-- OLEDB provider for non-SQL Server database
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.servers WHERE name = 'RADIOLOGY_PACS')
BEGIN
    EXEC sp_addlinkedserver 
        @server = N'RADIOLOGY_PACS',
        @srvproduct = N'Oracle',
        @provider = N'OraOLEDB.Oracle',
        @datasrc = N'PACS-ORA-01.lakeviewmedical.local/PACSDB';
    
    EXEC sp_addlinkedsrvlogin 
        @rmtsrvname = N'RADIOLOGY_PACS',
        @useself = N'FALSE',
        @locallogin = NULL,
        @rmtuser = N'ehr_readonly',
        @rmtpassword = N'P@cs_R3@d0nly!';
    
    EXEC sp_serveroption @server = N'RADIOLOGY_PACS', @optname = 'data access', @optvalue = 'true';
    
    PRINT 'Linked server RADIOLOGY_PACS created.';
END
ELSE
    PRINT 'Linked server RADIOLOGY_PACS already exists.';
GO

-- ============================================
-- Test linked server connectivity
-- (run manually - will fail without actual servers)
-- ============================================
/*
EXEC sp_testlinkedserver N'PHARMACY_SERVER';
EXEC sp_testlinkedserver N'INSURANCE_CLEARINGHOUSE';
EXEC sp_testlinkedserver N'LAB_SYSTEM';
EXEC sp_testlinkedserver N'RADIOLOGY_PACS';
*/

-- ============================================
-- Example queries using linked servers
-- (for documentation / migration planning)
-- ============================================
/*
-- Query pharmacy system for medication stock
SELECT * FROM OPENQUERY(PHARMACY_SERVER, 
    'SELECT DrugCode, DrugName, StockQuantity, ExpirationDate 
     FROM PharmacyDB.dbo.DrugInventory 
     WHERE StockQuantity < 10');

-- Check insurance eligibility via clearinghouse
EXEC [INSURANCE_CLEARINGHOUSE].ClearinghouseDB.dbo.usp_CheckEligibility 
    @PayerID = 'BCBS001', 
    @MemberID = 'XYZ123456';

-- Get lab results from LIS
SELECT * FROM [LAB_SYSTEM].LabIS.dbo.LabResults
WHERE PatientMRN = 'LMC-000001' AND ResultDate >= DATEADD(DAY, -7, GETDATE());

-- Query radiology PACS for study metadata
SELECT * FROM OPENQUERY(RADIOLOGY_PACS,
    'SELECT AccessionNumber, StudyDate, Modality, StudyDescription
     FROM STUDIES WHERE PatientID = ''LMC-000001''');
*/

PRINT '========================================';
PRINT 'All linked servers created.';
PRINT '========================================';
GO
