-- =====================================================================
-- Migration Step 16: Reconfigure Linked Servers for Azure SQL MI
-- Lakeview Medical Center
--
-- Purpose: Recreate linked servers on Azure SQL Managed Instance
--          with cloud-appropriate endpoints, providers, and security.
--
-- Prerequisites:
--   - Azure SQL MI deployed inside a VNet
--   - Private endpoints or VNet peering configured for target systems
--   - Credentials stored in Azure Key Vault (referenced via comments)
--   - MSOLEDBSQL driver available on MI (replaces deprecated SQLNCLI11)
--
-- IMPORTANT: Replace placeholder values (<...>) before execution.
-- =====================================================================
USE master;
GO

-- =====================================================================
-- 1. Drop legacy linked servers (on-prem endpoints no longer reachable)
-- =====================================================================
PRINT '=== Dropping legacy linked servers ===';

IF EXISTS (SELECT 1 FROM sys.servers WHERE name = 'PHARMACY_SERVER')
BEGIN
    EXEC sp_dropserver @server = N'PHARMACY_SERVER', @droplogins = 'droplogins';
    PRINT 'Dropped legacy PHARMACY_SERVER.';
END
GO

IF EXISTS (SELECT 1 FROM sys.servers WHERE name = 'INSURANCE_CLEARINGHOUSE')
BEGIN
    EXEC sp_dropserver @server = N'INSURANCE_CLEARINGHOUSE', @droplogins = 'droplogins';
    PRINT 'Dropped legacy INSURANCE_CLEARINGHOUSE.';
END
GO

IF EXISTS (SELECT 1 FROM sys.servers WHERE name = 'LAB_SYSTEM')
BEGIN
    EXEC sp_dropserver @server = N'LAB_SYSTEM', @droplogins = 'droplogins';
    PRINT 'Dropped legacy LAB_SYSTEM.';
END
GO

IF EXISTS (SELECT 1 FROM sys.servers WHERE name = 'RADIOLOGY_PACS')
BEGIN
    EXEC sp_dropserver @server = N'RADIOLOGY_PACS', @droplogins = 'droplogins';
    PRINT 'Dropped legacy RADIOLOGY_PACS.';
END
GO

-- =====================================================================
-- 2. Create database-scoped credentials for secure authentication
--    Azure SQL MI supports database-scoped credentials for linked
--    server logins, keeping passwords out of plain-text scripts.
--    For production: rotate these credentials via Key Vault.
-- =====================================================================
PRINT '=== Creating database-scoped credentials ===';

-- Credential for Pharmacy system (Azure SQL Database via private endpoint)
IF NOT EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'PharmacyLinkedServerCredential')
BEGIN
    CREATE CREDENTIAL [PharmacyLinkedServerCredential]
        WITH IDENTITY = N'pharmacy_interface',
        SECRET = N'<REPLACE_WITH_KEYVAULT_SECRET>';    -- Retrieve from Key Vault
    PRINT 'Created credential PharmacyLinkedServerCredential.';
END
GO

-- Credential for Insurance Clearinghouse (Azure SQL Database via private endpoint)
IF NOT EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'InsuranceLinkedServerCredential')
BEGIN
    CREATE CREDENTIAL [InsuranceLinkedServerCredential]
        WITH IDENTITY = N'lakeview_claims',
        SECRET = N'<REPLACE_WITH_KEYVAULT_SECRET>';
    PRINT 'Created credential InsuranceLinkedServerCredential.';
END
GO

-- Credential for Lab Information System (Azure SQL Database via VNet peering)
IF NOT EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'LabSystemLinkedServerCredential')
BEGIN
    CREATE CREDENTIAL [LabSystemLinkedServerCredential]
        WITH IDENTITY = N'ehr_interface',
        SECRET = N'<REPLACE_WITH_KEYVAULT_SECRET>';
    PRINT 'Created credential LabSystemLinkedServerCredential.';
END
GO

-- Credential for Radiology PACS (remains Oracle, accessed via Azure Relay or VPN)
IF NOT EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'RadiologyLinkedServerCredential')
BEGIN
    CREATE CREDENTIAL [RadiologyLinkedServerCredential]
        WITH IDENTITY = N'ehr_readonly',
        SECRET = N'<REPLACE_WITH_KEYVAULT_SECRET>';
    PRINT 'Created credential RadiologyLinkedServerCredential.';
END
GO

-- =====================================================================
-- 3. Recreate PHARMACY_SERVER
--    Target: Azure SQL Database via private endpoint
--    Provider: MSOLEDBSQL (modern replacement for SQLNCLI11)
-- =====================================================================
PRINT '=== Creating PHARMACY_SERVER linked server ===';

IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = 'PHARMACY_SERVER')
BEGIN
    EXEC sp_addlinkedserver
        @server     = N'PHARMACY_SERVER',
        @srvproduct = N'',
        @provider   = N'MSOLEDBSQL',
        @datasrc    = N'pharmacy-sql.privatelink.database.windows.net',
        @catalog    = N'PharmacyDB';

    -- Map login using the credential created above
    EXEC sp_addlinkedsrvlogin
        @rmtsrvname  = N'PHARMACY_SERVER',
        @useself     = N'FALSE',
        @locallogin  = NULL,
        @rmtuser     = N'pharmacy_interface',
        @rmtpassword = N'<REPLACE_WITH_KEYVAULT_SECRET>';

    -- Enable RPC for remote stored procedure execution
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'rpc',          @optvalue = 'true';
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'rpc out',      @optvalue = 'true';
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'data access',  @optvalue = 'true';

    -- Cloud-appropriate timeouts (higher latency than on-prem)
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'query timeout',   @optvalue = '120';
    EXEC sp_serveroption @server = N'PHARMACY_SERVER', @optname = 'connect timeout', @optvalue = '60';

    PRINT 'Linked server PHARMACY_SERVER created (Azure SQL private endpoint).';
END
ELSE
    PRINT 'Linked server PHARMACY_SERVER already exists.';
GO

-- =====================================================================
-- 4. Recreate INSURANCE_CLEARINGHOUSE
--    Target: Azure SQL Database via private endpoint
-- =====================================================================
PRINT '=== Creating INSURANCE_CLEARINGHOUSE linked server ===';

IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = 'INSURANCE_CLEARINGHOUSE')
BEGIN
    EXEC sp_addlinkedserver
        @server     = N'INSURANCE_CLEARINGHOUSE',
        @srvproduct = N'',
        @provider   = N'MSOLEDBSQL',
        @datasrc    = N'insurance-clh-sql.privatelink.database.windows.net',
        @catalog    = N'ClearinghouseDB';

    EXEC sp_addlinkedsrvlogin
        @rmtsrvname  = N'INSURANCE_CLEARINGHOUSE',
        @useself     = N'FALSE',
        @locallogin  = NULL,
        @rmtuser     = N'lakeview_claims',
        @rmtpassword = N'<REPLACE_WITH_KEYVAULT_SECRET>';

    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'rpc',          @optvalue = 'true';
    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'rpc out',      @optvalue = 'true';
    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'data access',  @optvalue = 'true';
    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'query timeout', @optvalue = '180';
    EXEC sp_serveroption @server = N'INSURANCE_CLEARINGHOUSE', @optname = 'connect timeout', @optvalue = '60';

    PRINT 'Linked server INSURANCE_CLEARINGHOUSE created (Azure SQL private endpoint).';
END
ELSE
    PRINT 'Linked server INSURANCE_CLEARINGHOUSE already exists.';
GO

-- =====================================================================
-- 5. Recreate LAB_SYSTEM
--    Target: Azure SQL Database via VNet peering
-- =====================================================================
PRINT '=== Creating LAB_SYSTEM linked server ===';

IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = 'LAB_SYSTEM')
BEGIN
    EXEC sp_addlinkedserver
        @server     = N'LAB_SYSTEM',
        @srvproduct = N'',
        @provider   = N'MSOLEDBSQL',
        @datasrc    = N'labsystem-sql.database.windows.net',
        @catalog    = N'LabIS';

    EXEC sp_addlinkedsrvlogin
        @rmtsrvname  = N'LAB_SYSTEM',
        @useself     = N'FALSE',
        @locallogin  = NULL,
        @rmtuser     = N'ehr_interface',
        @rmtpassword = N'<REPLACE_WITH_KEYVAULT_SECRET>';

    EXEC sp_serveroption @server = N'LAB_SYSTEM', @optname = 'data access',  @optvalue = 'true';
    EXEC sp_serveroption @server = N'LAB_SYSTEM', @optname = 'rpc',          @optvalue = 'true';
    EXEC sp_serveroption @server = N'LAB_SYSTEM', @optname = 'rpc out',      @optvalue = 'true';
    EXEC sp_serveroption @server = N'LAB_SYSTEM', @optname = 'query timeout', @optvalue = '120';
    EXEC sp_serveroption @server = N'LAB_SYSTEM', @optname = 'connect timeout', @optvalue = '60';

    PRINT 'Linked server LAB_SYSTEM created (Azure SQL via VNet peering).';
END
ELSE
    PRINT 'Linked server LAB_SYSTEM already exists.';
GO

-- =====================================================================
-- 6. Recreate RADIOLOGY_PACS
--    Target: Oracle PACS system still on-premises, accessed via
--            Azure Relay Hybrid Connection or site-to-site VPN.
--    Note:  OraOLEDB.Oracle provider must be available on MI.
--           If not, consider migrating this to an API-based integration.
-- =====================================================================
PRINT '=== Creating RADIOLOGY_PACS linked server ===';

IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = 'RADIOLOGY_PACS')
BEGIN
    EXEC sp_addlinkedserver
        @server     = N'RADIOLOGY_PACS',
        @srvproduct = N'Oracle',
        @provider   = N'MSOLEDBSQL',               -- Use MSOLEDBSQL with Oracle gateway
        @datasrc    = N'pacs-relay.servicebus.windows.net',  -- Azure Relay hybrid endpoint
        @provstr    = N'Provider=OraOLEDB.Oracle;Data Source=PACSDB';

    EXEC sp_addlinkedsrvlogin
        @rmtsrvname  = N'RADIOLOGY_PACS',
        @useself     = N'FALSE',
        @locallogin  = NULL,
        @rmtuser     = N'ehr_readonly',
        @rmtpassword = N'<REPLACE_WITH_KEYVAULT_SECRET>';

    EXEC sp_serveroption @server = N'RADIOLOGY_PACS', @optname = 'data access',     @optvalue = 'true';
    EXEC sp_serveroption @server = N'RADIOLOGY_PACS', @optname = 'query timeout',   @optvalue = '180';
    EXEC sp_serveroption @server = N'RADIOLOGY_PACS', @optname = 'connect timeout', @optvalue = '90';

    PRINT 'Linked server RADIOLOGY_PACS created (Oracle via Azure Relay).';
END
ELSE
    PRINT 'Linked server RADIOLOGY_PACS already exists.';
GO

-- =====================================================================
-- 7. Summary
-- =====================================================================
PRINT '=====================================================================';
PRINT 'Linked server reconfiguration complete.';
PRINT '';
PRINT 'Server                   | Target                                    | Method';
PRINT '-------------------------|-------------------------------------------|------------------';
PRINT 'PHARMACY_SERVER          | pharmacy-sql.privatelink.database...      | Private Endpoint';
PRINT 'INSURANCE_CLEARINGHOUSE  | insurance-clh-sql.privatelink.database... | Private Endpoint';
PRINT 'LAB_SYSTEM               | labsystem-sql.database.windows.net        | VNet Peering';
PRINT 'RADIOLOGY_PACS           | pacs-relay.servicebus.windows.net         | Azure Relay';
PRINT '';
PRINT 'Next: Run Migration/17-LinkedServerValidation.sql to verify.';
PRINT '=====================================================================';
GO
