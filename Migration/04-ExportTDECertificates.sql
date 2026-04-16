-- ============================================
-- Export TDE Certificates from Source SQL Server
-- Lakeview Medical Center
-- Backs up the TDE certificate and private key
-- from the on-premises PatientDB for migration
-- to Azure SQL Managed Instance
-- ============================================
-- Run against the on-premises SQL Server instance
-- Requires: CONTROL SERVER or sysadmin role
-- Output : Certificate .cer and private key .pvk
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - TDE Certificate Export';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT ' Version : ' + @@VERSION;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Pre-flight validation
-- ============================================

-- Verify we are running on the source (on-prem) server
IF SERVERPROPERTY('EngineEdition') = 8
BEGIN
    RAISERROR('This script must be run on the on-premises SQL Server, not on Azure SQL MI.', 16, 1);
    RETURN;
END
GO

-- ============================================
-- 1. CHECK CURRENT TDE STATUS ON PATIENTDB
-- ============================================
PRINT '>> Step 1: Checking current TDE status on PatientDB...';
PRINT '';

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE name = 'PatientDB'
)
BEGIN
    RAISERROR('PatientDB does not exist on this server.', 16, 1);
    RETURN;
END
GO

-- Show database encryption state
SELECT
    db.name                     AS DatabaseName,
    dek.encryption_state        AS EncryptionState,
    CASE dek.encryption_state
        WHEN 0 THEN 'No encryption key present'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        WHEN 6 THEN 'Protection change in progress'
    END                         AS EncryptionStateDesc,
    dek.key_algorithm           AS KeyAlgorithm,
    dek.key_length              AS KeyLength,
    dek.encryptor_type          AS EncryptorType,
    c.name                      AS CertificateName,
    c.start_date                AS CertStartDate,
    c.expiry_date               AS CertExpiryDate,
    c.thumbprint                AS CertThumbprint
FROM sys.dm_database_encryption_keys dek
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
    LEFT JOIN sys.certificates c
        ON dek.encryptor_thumbprint = c.thumbprint
WHERE db.name = 'PatientDB';

IF NOT EXISTS (
    SELECT 1 FROM sys.dm_database_encryption_keys dek
        INNER JOIN sys.databases db ON dek.database_id = db.database_id
    WHERE db.name = 'PatientDB'
      AND dek.encryption_state = 3
)
BEGIN
    PRINT 'WARNING: PatientDB is not currently encrypted with TDE.';
    PRINT '         If TDE has not been configured yet, run the TDE setup first.';
    PRINT '';
END
ELSE
BEGIN
    PRINT 'PatientDB TDE encryption is active (state = 3).';
    PRINT '';
END
GO

-- ============================================
-- 2. IDENTIFY THE TDE CERTIFICATE
-- ============================================
PRINT '>> Step 2: Identifying TDE certificate...';
PRINT '';

-- Check for the server-level master key
IF NOT EXISTS (
    SELECT 1 FROM sys.symmetric_keys
    WHERE name = '##MS_DatabaseMasterKey##'
)
BEGIN
    RAISERROR('No database master key found in the master database. TDE cannot be configured without it.', 16, 1);
    RETURN;
END
GO

-- List all certificates that protect TDE database encryption keys
SELECT
    c.name              AS CertificateName,
    c.certificate_id    AS CertificateID,
    c.thumbprint        AS Thumbprint,
    c.start_date        AS ValidFrom,
    c.expiry_date       AS ValidTo,
    c.pvt_key_encryption_type_desc AS PrivateKeyEncryption,
    db.name             AS ProtectsDatabase
FROM sys.certificates c
    INNER JOIN sys.dm_database_encryption_keys dek
        ON c.thumbprint = dek.encryptor_thumbprint
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
WHERE db.name = 'PatientDB';

PRINT 'Certificate details listed above.';
PRINT '';
GO

-- ============================================
-- 3. BACKUP THE TDE CERTIFICATE AND PRIVATE KEY
-- ============================================
PRINT '>> Step 3: Backing up TDE certificate and private key...';
PRINT '';
PRINT 'IMPORTANT: Store backup files in a secure location.';
PRINT '           The private key password must be saved securely';
PRINT '           (e.g., Azure Key Vault) for the import step.';
PRINT '';

-- Determine the certificate name dynamically
DECLARE @CertName NVARCHAR(256);
DECLARE @BackupPath NVARCHAR(512) = 'C:\TDEMigration\';
DECLARE @CertFile NVARCHAR(512);
DECLARE @KeyFile NVARCHAR(512);
DECLARE @SQL NVARCHAR(MAX);

SELECT TOP 1 @CertName = c.name
FROM sys.certificates c
    INNER JOIN sys.dm_database_encryption_keys dek
        ON c.thumbprint = dek.encryptor_thumbprint
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
WHERE db.name = 'PatientDB';

IF @CertName IS NULL
BEGIN
    RAISERROR('No TDE certificate found protecting PatientDB. Cannot proceed with export.', 16, 1);
    RETURN;
END

SET @CertFile = @BackupPath + @CertName + '_PatientDB.cer';
SET @KeyFile  = @BackupPath + @CertName + '_PatientDB.pvk';

PRINT 'Certificate Name : ' + @CertName;
PRINT 'Certificate File : ' + @CertFile;
PRINT 'Private Key File : ' + @KeyFile;
PRINT '';

-- Create the backup directory (requires xp_cmdshell or pre-create manually)
-- Uncomment the following if xp_cmdshell is enabled:
-- EXEC xp_cmdshell 'IF NOT EXIST "C:\TDEMigration" MKDIR "C:\TDEMigration"';

-- Back up the certificate with private key
-- *** CHANGE THE PASSWORD BELOW TO A STRONG PASSWORD ***
BEGIN TRY
    SET @SQL = N'
        USE master;
        BACKUP CERTIFICATE ' + QUOTENAME(@CertName) + N'
        TO FILE = ''' + @CertFile + N'''
        WITH PRIVATE KEY (
            FILE = ''' + @KeyFile + N''',
            ENCRYPTION BY PASSWORD = ''<StrongPasswordHere>''
        );';

    PRINT 'Executing certificate backup...';
    EXEC sp_executesql @SQL;

    PRINT '';
    PRINT 'SUCCESS: Certificate and private key backed up.';
    PRINT '  Certificate : ' + @CertFile;
    PRINT '  Private Key : ' + @KeyFile;
    PRINT '';
END TRY
BEGIN CATCH
    PRINT '';
    PRINT 'ERROR: Certificate backup failed.';
    PRINT '  Error Number  : ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
    PRINT '  Error Message : ' + ERROR_MESSAGE();
    PRINT '  Error Line    : ' + CAST(ERROR_LINE() AS VARCHAR(10));
    PRINT '';
    PRINT 'Troubleshooting:';
    PRINT '  1. Ensure the backup directory exists: C:\TDEMigration\';
    PRINT '  2. SQL Server service account needs write access to the directory.';
    PRINT '  3. Verify you have CONTROL SERVER permission.';
    RETURN;
END CATCH
GO

-- ============================================
-- 4. VERIFY THE BACKUP FILES
-- ============================================
PRINT '>> Step 4: Verifying backup files exist...';
PRINT '';

DECLARE @CertFileCheck NVARCHAR(512);
DECLARE @KeyFileCheck NVARCHAR(512);
DECLARE @CertNameCheck NVARCHAR(256);

SELECT TOP 1 @CertNameCheck = c.name
FROM sys.certificates c
    INNER JOIN sys.dm_database_encryption_keys dek
        ON c.thumbprint = dek.encryptor_thumbprint
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
WHERE db.name = 'PatientDB';

SET @CertFileCheck = 'C:\TDEMigration\' + @CertNameCheck + '_PatientDB.cer';
SET @KeyFileCheck  = 'C:\TDEMigration\' + @CertNameCheck + '_PatientDB.pvk';

-- Use xp_fileexist to verify (works without xp_cmdshell)
DECLARE @FileExists TABLE (
    FileExists      INT,
    IsDirectory     INT,
    ParentDirExists INT
);

INSERT INTO @FileExists EXEC master.dbo.xp_fileexist @CertFileCheck;
IF NOT EXISTS (SELECT 1 FROM @FileExists WHERE FileExists = 1)
BEGIN
    PRINT 'WARNING: Certificate file not found at ' + @CertFileCheck;
    PRINT '         Verify the backup completed successfully.';
END
ELSE
    PRINT 'VERIFIED: Certificate file exists at ' + @CertFileCheck;

DELETE FROM @FileExists;
INSERT INTO @FileExists EXEC master.dbo.xp_fileexist @KeyFileCheck;
IF NOT EXISTS (SELECT 1 FROM @FileExists WHERE FileExists = 1)
BEGIN
    PRINT 'WARNING: Private key file not found at ' + @KeyFileCheck;
    PRINT '         Verify the backup completed successfully.';
END
ELSE
    PRINT 'VERIFIED: Private key file exists at ' + @KeyFileCheck;

PRINT '';
GO

-- ============================================
-- 5. EXPORT SUMMARY AND NEXT STEPS
-- ============================================
PRINT '================================================================';
PRINT ' TDE Certificate Export - Summary';
PRINT '================================================================';
PRINT '';
PRINT ' Next Steps:';
PRINT '   1. Securely transfer the .cer and .pvk files to a location';
PRINT '      accessible by the Azure SQL MI (e.g., Azure Blob Storage).';
PRINT '   2. Store the private key password in Azure Key Vault.';
PRINT '   3. Run 05-ImportTDECertificates.sql on Azure SQL MI.';
PRINT '';
PRINT ' Security Reminders:';
PRINT '   - Do NOT transmit certificate files over unencrypted channels.';
PRINT '   - Delete local copies after successful import to SQL MI.';
PRINT '   - Rotate the TDE certificate after migration is complete.';
PRINT '';
PRINT '================================================================';
PRINT ' Export complete.';
PRINT '================================================================';
GO
