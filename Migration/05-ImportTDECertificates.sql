-- ============================================
-- Import TDE Certificates into Azure SQL MI
-- Lakeview Medical Center
-- Imports the TDE certificate and private key
-- exported from the on-premises SQL Server so
-- that PatientDB can be restored/attached with
-- TDE encryption intact
-- ============================================
-- Run against the Azure SQL Managed Instance
-- Requires: sysadmin role on the MI
-- Input  : Certificate .cer and private key .pvk
--          from 04-ExportTDECertificates.sql
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - TDE Certificate Import (Azure SQL MI)';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Pre-flight validation
-- ============================================

-- Verify we are running on Azure SQL MI
IF SERVERPROPERTY('EngineEdition') <> 8
BEGIN
    RAISERROR('This script must be run on an Azure SQL Managed Instance (EngineEdition = 8).', 16, 1);
    RETURN;
END
GO

PRINT '>> Confirmed: Running on Azure SQL Managed Instance.';
PRINT '';
GO

-- ============================================
-- 1. CHECK FOR EXISTING CERTIFICATES
-- ============================================
PRINT '>> Step 1: Checking for existing TDE certificates...';
PRINT '';

SELECT
    c.name              AS CertificateName,
    c.certificate_id    AS CertificateID,
    c.thumbprint        AS Thumbprint,
    c.start_date        AS ValidFrom,
    c.expiry_date       AS ValidTo,
    c.pvt_key_encryption_type_desc AS PrivateKeyEncryption
FROM sys.certificates c
WHERE c.name NOT LIKE '##%'
ORDER BY c.name;

PRINT 'Existing certificates listed above (if any).';
PRINT '';
GO

-- ============================================
-- 2. VERIFY DATABASE MASTER KEY EXISTS
-- ============================================
PRINT '>> Step 2: Verifying database master key in master database...';
PRINT '';

IF NOT EXISTS (
    SELECT 1 FROM sys.symmetric_keys
    WHERE name = '##MS_DatabaseMasterKey##'
)
BEGIN
    PRINT 'No database master key found. Creating one...';
    PRINT '';

    -- *** CHANGE THIS PASSWORD TO A STRONG PASSWORD ***
    BEGIN TRY
        CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongMasterKeyPasswordHere>';
        PRINT 'SUCCESS: Database master key created.';
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: Failed to create database master key.';
        PRINT '  Error Number  : ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        PRINT '  Error Message : ' + ERROR_MESSAGE();
        RETURN;
    END CATCH
END
ELSE
BEGIN
    PRINT 'Database master key already exists. Continuing...';
END
PRINT '';
GO

-- ============================================
-- 3. IMPORT THE TDE CERTIFICATE
-- ============================================
PRINT '>> Step 3: Importing TDE certificate from backup files...';
PRINT '';
PRINT 'NOTE: On Azure SQL MI, certificate files must be accessible via';
PRINT '      a path that the MI can read. Use one of:';
PRINT '        - Azure Blob Storage with SAS token (recommended)';
PRINT '        - A share accessible to the MI service account';
PRINT '';

-- *** UPDATE THESE PATHS AND PASSWORDS ***
-- For Azure Blob Storage, use a SAS URL or credential-based access.
-- The file paths below assume the .cer and .pvk files have been staged
-- to an accessible location.
DECLARE @CertName NVARCHAR(256) = 'PatientDB_TDE_Certificate';
DECLARE @CertFile NVARCHAR(512) = 'C:\TDEMigration\PatientDB_TDE_Cert_PatientDB.cer';
DECLARE @KeyFile  NVARCHAR(512) = 'C:\TDEMigration\PatientDB_TDE_Cert_PatientDB.pvk';

-- Check if a certificate with the same name already exists
IF EXISTS (
    SELECT 1 FROM sys.certificates WHERE name = @CertName
)
BEGIN
    PRINT 'WARNING: Certificate [' + @CertName + '] already exists on this MI.';
    PRINT '         Checking if the thumbprint matches the source...';
    PRINT '';

    SELECT
        name            AS CertificateName,
        thumbprint      AS Thumbprint,
        start_date      AS ValidFrom,
        expiry_date     AS ValidTo
    FROM sys.certificates
    WHERE name = @CertName;

    PRINT 'If the thumbprint matches, no re-import is needed.';
    PRINT 'If it does not match, drop the existing certificate first or use a different name.';
END
ELSE
BEGIN
    -- Import the certificate with private key
    -- *** CHANGE THE DECRYPTION PASSWORD TO MATCH THE ONE USED DURING EXPORT ***
    BEGIN TRY
        DECLARE @SQL NVARCHAR(MAX) = N'
            USE master;
            CREATE CERTIFICATE ' + QUOTENAME(@CertName) + N'
            FROM FILE = ''' + @CertFile + N'''
            WITH PRIVATE KEY (
                FILE = ''' + @KeyFile + N''',
                DECRYPTION BY PASSWORD = ''<StrongPasswordHere>''
            );';

        PRINT 'Executing certificate import...';
        EXEC sp_executesql @SQL;

        PRINT '';
        PRINT 'SUCCESS: Certificate [' + @CertName + '] imported.';
    END TRY
    BEGIN CATCH
        PRINT '';
        PRINT 'ERROR: Certificate import failed.';
        PRINT '  Error Number  : ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        PRINT '  Error Message : ' + ERROR_MESSAGE();
        PRINT '  Error Line    : ' + CAST(ERROR_LINE() AS VARCHAR(10));
        PRINT '';
        PRINT 'Troubleshooting:';
        PRINT '  1. Verify .cer and .pvk files are accessible from the MI.';
        PRINT '  2. Ensure the decryption password matches the export password.';
        PRINT '  3. Check that you have sysadmin privileges.';
        PRINT '  4. For Azure Blob Storage, ensure the credential/SAS token is valid.';
        RETURN;
    END CATCH
END
GO

-- ============================================
-- 4. VERIFY THE IMPORTED CERTIFICATE
-- ============================================
PRINT '';
PRINT '>> Step 4: Verifying imported certificate...';
PRINT '';

DECLARE @CertNameVerify NVARCHAR(256) = 'PatientDB_TDE_Certificate';

IF EXISTS (
    SELECT 1 FROM sys.certificates WHERE name = @CertNameVerify
)
BEGIN
    SELECT
        c.name              AS CertificateName,
        c.certificate_id    AS CertificateID,
        c.thumbprint        AS Thumbprint,
        c.start_date        AS ValidFrom,
        c.expiry_date       AS ValidTo,
        c.pvt_key_encryption_type_desc AS PrivateKeyEncryption
    FROM sys.certificates c
    WHERE c.name = @CertNameVerify;

    PRINT 'SUCCESS: Certificate is present on the Managed Instance.';
    PRINT '';
    PRINT 'IMPORTANT: Verify the thumbprint above matches the source server.';
    PRINT '           Compare with the output from 04-ExportTDECertificates.sql.';
END
ELSE
BEGIN
    PRINT 'ERROR: Certificate [' + @CertNameVerify + '] was not found after import.';
    PRINT '       Re-run the import step above.';
END
PRINT '';
GO

-- ============================================
-- 5. THUMBPRINT COMPARISON HELPER
-- ============================================
PRINT '>> Step 5: Thumbprint comparison...';
PRINT '';
PRINT 'Run the following on the SOURCE server to get the expected thumbprint:';
PRINT '';
PRINT '  SELECT c.name, c.thumbprint';
PRINT '  FROM sys.certificates c';
PRINT '    INNER JOIN sys.dm_database_encryption_keys dek';
PRINT '      ON c.thumbprint = dek.encryptor_thumbprint';
PRINT '    INNER JOIN sys.databases db';
PRINT '      ON dek.database_id = db.database_id';
PRINT '  WHERE db.name = ''PatientDB'';';
PRINT '';

DECLARE @CertNameThumb NVARCHAR(256) = 'PatientDB_TDE_Certificate';

SELECT
    'IMPORTED (MI)' AS Source,
    c.name          AS CertificateName,
    c.thumbprint    AS Thumbprint
FROM sys.certificates c
WHERE c.name = @CertNameThumb;

PRINT 'Compare the thumbprint above with the source server output.';
PRINT 'They MUST match for TDE-encrypted database restore to succeed.';
PRINT '';
GO

-- ============================================
-- 6. IMPORT SUMMARY AND NEXT STEPS
-- ============================================
PRINT '================================================================';
PRINT ' TDE Certificate Import - Summary';
PRINT '================================================================';
PRINT '';
PRINT ' Next Steps:';
PRINT '   1. Confirm the certificate thumbprint matches the source.';
PRINT '   2. Restore/migrate PatientDB to this Managed Instance.';
PRINT '      The TDE-encrypted backup will now be decryptable.';
PRINT '   3. Run 06-TDEValidation.sql to verify TDE is working.';
PRINT '';
PRINT ' Security Reminders:';
PRINT '   - Delete the .cer and .pvk files from any staging locations.';
PRINT '   - Rotate the TDE certificate after migration validation.';
PRINT '   - Consider migrating to Azure-managed TDE (service-managed';
PRINT '     keys) post-migration for simplified key management.';
PRINT '';
PRINT '================================================================';
PRINT ' Import complete.';
PRINT '================================================================';
GO
