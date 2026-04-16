-- ============================================
-- TDE Validation Post-Migration
-- Lakeview Medical Center
-- Validates that Transparent Data Encryption is
-- functioning correctly on PatientDB after
-- migration to Azure SQL Managed Instance
-- ============================================
-- Run against the Azure SQL Managed Instance
-- Requires: VIEW SERVER STATE, VIEW ANY DEFINITION
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - TDE Post-Migration Validation';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Validation results staging table
-- ============================================
IF OBJECT_ID('tempdb..#TDEValidation') IS NOT NULL
    DROP TABLE #TDEValidation;

CREATE TABLE #TDEValidation (
    ValidationID    INT IDENTITY(1,1),
    CheckName       NVARCHAR(100)  NOT NULL,
    Status          NVARCHAR(20)   NOT NULL,  -- PASS, FAIL, WARNING, INFO
    Details         NVARCHAR(1000) NOT NULL,
    Recommendation  NVARCHAR(1000) NULL
);
GO

-- ============================================
-- 1. VERIFY RUNNING ON AZURE SQL MI
-- ============================================
PRINT '>> Check 1: Verify Azure SQL MI environment...';

IF SERVERPROPERTY('EngineEdition') = 8
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details)
    VALUES ('Environment Check', 'PASS',
        'Running on Azure SQL Managed Instance: ' + @@SERVERNAME);
END
ELSE
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
    VALUES ('Environment Check', 'WARNING',
        'Not running on Azure SQL MI (EngineEdition = ' +
            CAST(SERVERPROPERTY('EngineEdition') AS VARCHAR(10)) + ').',
        'This validation script is designed for Azure SQL MI. Results may vary on other platforms.');
END
GO

-- ============================================
-- 2. VERIFY PATIENTDB EXISTS
-- ============================================
PRINT '>> Check 2: Verify PatientDB exists...';

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'PatientDB')
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details)
    VALUES ('Database Exists', 'PASS', 'PatientDB is present on this instance.');
END
ELSE
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
    VALUES ('Database Exists', 'FAIL', 'PatientDB was NOT found on this instance.',
        'Restore or migrate PatientDB before running TDE validation.');
    -- Print results and exit early
    GOTO PrintResults;
END
GO

-- ============================================
-- 3. VERIFY DATABASE IS ONLINE
-- ============================================
PRINT '>> Check 3: Verify PatientDB is online...';

DECLARE @DbState NVARCHAR(60);
SELECT @DbState = state_desc FROM sys.databases WHERE name = 'PatientDB';

IF @DbState = 'ONLINE'
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details)
    VALUES ('Database Online', 'PASS', 'PatientDB state: ONLINE.');
END
ELSE
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
    VALUES ('Database Online', 'FAIL',
        'PatientDB state: ' + ISNULL(@DbState, 'UNKNOWN') + '.',
        'Database must be ONLINE for TDE validation. Check for restore errors or missing certificates.');
END
GO

-- ============================================
-- 4. VERIFY TDE ENCRYPTION STATE
-- ============================================
PRINT '>> Check 4: Verify TDE encryption state...';

DECLARE @EncState INT;
DECLARE @EncStateDesc NVARCHAR(100);

SELECT
    @EncState = dek.encryption_state
FROM sys.dm_database_encryption_keys dek
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
WHERE db.name = 'PatientDB';

SET @EncStateDesc = CASE @EncState
    WHEN 0 THEN 'No encryption key present'
    WHEN 1 THEN 'Unencrypted'
    WHEN 2 THEN 'Encryption in progress'
    WHEN 3 THEN 'Encrypted'
    WHEN 4 THEN 'Key change in progress'
    WHEN 5 THEN 'Decryption in progress'
    WHEN 6 THEN 'Protection change in progress'
    ELSE 'Unknown'
END;

IF @EncState = 3
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details)
    VALUES ('TDE Encryption State', 'PASS',
        'PatientDB encryption state: 3 (Encrypted).');
END
ELSE IF @EncState IS NULL
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
    VALUES ('TDE Encryption State', 'FAIL',
        'No database encryption key found for PatientDB.',
        'The database may not have been restored from a TDE-encrypted backup, or the certificate is missing.');
END
ELSE
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
    VALUES ('TDE Encryption State', 'WARNING',
        'PatientDB encryption state: ' + CAST(@EncState AS VARCHAR(2)) + ' (' + @EncStateDesc + ').',
        'Expected state 3 (Encrypted). Current state may indicate an in-progress operation. Re-check after a few minutes.');
END
GO

-- ============================================
-- 5. VERIFY ENCRYPTION KEY DETAILS
-- ============================================
PRINT '>> Check 5: Verify encryption key algorithm and length...';

SELECT
    db.name                     AS DatabaseName,
    dek.key_algorithm           AS KeyAlgorithm,
    dek.key_length              AS KeyLength,
    dek.encryptor_type          AS EncryptorType,
    dek.encryption_state        AS EncryptionState,
    dek.percent_complete        AS PercentComplete,
    dek.create_date             AS KeyCreateDate,
    dek.regenerate_date         AS KeyRegenerateDate
FROM sys.dm_database_encryption_keys dek
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
WHERE db.name = 'PatientDB';

DECLARE @KeyAlgo NVARCHAR(50);
DECLARE @KeyLen INT;

SELECT
    @KeyAlgo = dek.key_algorithm,
    @KeyLen  = dek.key_length
FROM sys.dm_database_encryption_keys dek
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
WHERE db.name = 'PatientDB';

IF @KeyAlgo IS NOT NULL
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details)
    VALUES ('Encryption Key Details', 'INFO',
        'Algorithm: ' + @KeyAlgo + ', Key Length: ' + CAST(ISNULL(@KeyLen, 0) AS VARCHAR(10)) + ' bits.');

    IF @KeyLen < 256
    BEGIN
        INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
        VALUES ('Key Strength', 'WARNING',
            'Encryption key length is ' + CAST(@KeyLen AS VARCHAR(10)) + ' bits.',
            'Consider using AES_256 for stronger encryption.');
    END
    ELSE
    BEGIN
        INSERT INTO #TDEValidation (CheckName, Status, Details)
        VALUES ('Key Strength', 'PASS',
            'Encryption key length (' + CAST(@KeyLen AS VARCHAR(10)) + ' bits) meets minimum recommendation.');
    END
END
GO

-- ============================================
-- 6. VERIFY CERTIFICATE ASSOCIATION
-- ============================================
PRINT '>> Check 6: Verify TDE certificate is properly associated...';

DECLARE @CertName NVARCHAR(256);
DECLARE @CertExpiry DATETIME;

SELECT
    @CertName   = c.name,
    @CertExpiry = c.expiry_date
FROM sys.certificates c
    INNER JOIN sys.dm_database_encryption_keys dek
        ON c.thumbprint = dek.encryptor_thumbprint
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
WHERE db.name = 'PatientDB';

IF @CertName IS NOT NULL
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details)
    VALUES ('Certificate Association', 'PASS',
        'TDE certificate [' + @CertName + '] is associated with PatientDB.');

    -- Check certificate expiry
    IF @CertExpiry < GETDATE()
    BEGIN
        INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
        VALUES ('Certificate Expiry', 'WARNING',
            'Certificate [' + @CertName + '] expired on ' +
                CONVERT(VARCHAR(30), @CertExpiry, 120) + '.',
            'TDE continues to work with expired certificates, but rotate the certificate as a best practice.');
    END
    ELSE IF @CertExpiry < DATEADD(DAY, 90, GETDATE())
    BEGIN
        INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
        VALUES ('Certificate Expiry', 'WARNING',
            'Certificate [' + @CertName + '] expires on ' +
                CONVERT(VARCHAR(30), @CertExpiry, 120) + ' (within 90 days).',
            'Plan to rotate the TDE certificate before expiry.');
    END
    ELSE
    BEGIN
        INSERT INTO #TDEValidation (CheckName, Status, Details)
        VALUES ('Certificate Expiry', 'PASS',
            'Certificate [' + @CertName + '] valid until ' +
                CONVERT(VARCHAR(30), @CertExpiry, 120) + '.');
    END
END
ELSE
BEGIN
    INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
    VALUES ('Certificate Association', 'FAIL',
        'No certificate found protecting PatientDB encryption key.',
        'Re-import the TDE certificate using 05-ImportTDECertificates.sql.');
END
GO

-- ============================================
-- 7. DATA ACCESS VALIDATION
-- ============================================
PRINT '>> Check 7: Verify data is accessible in PatientDB...';

DECLARE @TableCount INT = 0;
DECLARE @AccessSQL NVARCHAR(MAX);
DECLARE @AccessError NVARCHAR(1000);

BEGIN TRY
    SET @AccessSQL = N'
        SELECT @cnt = COUNT(*)
        FROM PatientDB.sys.tables
        WHERE is_ms_shipped = 0;';

    EXEC sp_executesql @AccessSQL, N'@cnt INT OUTPUT', @cnt = @TableCount OUTPUT;

    INSERT INTO #TDEValidation (CheckName, Status, Details)
    VALUES ('Data Accessibility', 'PASS',
        'Successfully queried PatientDB. Found ' + CAST(@TableCount AS VARCHAR(10)) + ' user table(s).');
END TRY
BEGIN CATCH
    SET @AccessError = ERROR_MESSAGE();
    INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
    VALUES ('Data Accessibility', 'FAIL',
        'Failed to query PatientDB: ' + LEFT(@AccessError, 500),
        'This may indicate a missing or mismatched TDE certificate. Verify the certificate thumbprint.');
END CATCH
GO

-- ============================================
-- 8. SAMPLE DATA READ TEST
-- ============================================
PRINT '>> Check 8: Performing sample data read test...';

DECLARE @ReadSQL NVARCHAR(MAX);
DECLARE @ReadError NVARCHAR(1000);
DECLARE @SampleTable NVARCHAR(256);

BEGIN TRY
    -- Find the first user table in PatientDB to do a sample read
    SET @ReadSQL = N'
        SELECT TOP 1 @tbl = QUOTENAME(s.name) + ''.'' + QUOTENAME(t.name)
        FROM PatientDB.sys.tables t
            INNER JOIN PatientDB.sys.schemas s ON t.schema_id = s.schema_id
        WHERE t.is_ms_shipped = 0
        ORDER BY t.name;';

    EXEC sp_executesql @ReadSQL, N'@tbl NVARCHAR(256) OUTPUT', @tbl = @SampleTable OUTPUT;

    IF @SampleTable IS NOT NULL
    BEGIN
        SET @ReadSQL = N'SELECT TOP 1 * FROM PatientDB.' + @SampleTable + ';';
        EXEC sp_executesql @ReadSQL;

        INSERT INTO #TDEValidation (CheckName, Status, Details)
        VALUES ('Sample Data Read', 'PASS',
            'Successfully read data from PatientDB.' + @SampleTable + '.');
    END
    ELSE
    BEGIN
        INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
        VALUES ('Sample Data Read', 'WARNING',
            'No user tables found in PatientDB to perform sample read.',
            'This may be expected if the database was just created or is empty.');
    END
END TRY
BEGIN CATCH
    SET @ReadError = ERROR_MESSAGE();
    INSERT INTO #TDEValidation (CheckName, Status, Details, Recommendation)
    VALUES ('Sample Data Read', 'FAIL',
        'Sample data read failed: ' + LEFT(@ReadError, 500),
        'TDE decryption may not be working. Verify the certificate and encryption key.');
END CATCH
GO

-- ============================================
-- 9. CHECK ALL TDE-ENCRYPTED DATABASES
-- ============================================
PRINT '>> Check 9: Listing all TDE-encrypted databases on this instance...';

SELECT
    db.name                     AS DatabaseName,
    dek.encryption_state        AS EncryptionState,
    CASE dek.encryption_state
        WHEN 3 THEN 'Encrypted'
        ELSE 'Other (' + CAST(dek.encryption_state AS VARCHAR(2)) + ')'
    END                         AS StateDescription,
    c.name                      AS CertificateName,
    dek.key_algorithm           AS Algorithm,
    dek.key_length              AS KeyBits
FROM sys.dm_database_encryption_keys dek
    INNER JOIN sys.databases db
        ON dek.database_id = db.database_id
    LEFT JOIN sys.certificates c
        ON dek.encryptor_thumbprint = c.thumbprint
ORDER BY db.name;

INSERT INTO #TDEValidation (CheckName, Status, Details)
VALUES ('Instance TDE Overview', 'INFO', 'See result set above for all TDE-encrypted databases.');
GO

-- ============================================
-- PRINT VALIDATION RESULTS
-- ============================================
PrintResults:

PRINT '';
PRINT '================================================================';
PRINT ' TDE Validation Results';
PRINT '================================================================';
PRINT '';

-- Summary counts
DECLARE @PassCount INT, @FailCount INT, @WarnCount INT, @InfoCount INT;

SELECT
    @PassCount = SUM(CASE WHEN Status = 'PASS' THEN 1 ELSE 0 END),
    @FailCount = SUM(CASE WHEN Status = 'FAIL' THEN 1 ELSE 0 END),
    @WarnCount = SUM(CASE WHEN Status = 'WARNING' THEN 1 ELSE 0 END),
    @InfoCount = SUM(CASE WHEN Status = 'INFO' THEN 1 ELSE 0 END)
FROM #TDEValidation;

PRINT ' PASS    : ' + CAST(ISNULL(@PassCount, 0) AS VARCHAR(5));
PRINT ' FAIL    : ' + CAST(ISNULL(@FailCount, 0) AS VARCHAR(5));
PRINT ' WARNING : ' + CAST(ISNULL(@WarnCount, 0) AS VARCHAR(5));
PRINT ' INFO    : ' + CAST(ISNULL(@InfoCount, 0) AS VARCHAR(5));
PRINT '';

-- Detailed results
SELECT
    ValidationID,
    CheckName,
    Status,
    Details,
    ISNULL(Recommendation, '') AS Recommendation
FROM #TDEValidation
ORDER BY ValidationID;

-- Overall verdict
IF @FailCount > 0
BEGIN
    PRINT '';
    PRINT '*** VALIDATION FAILED ***';
    PRINT 'There are ' + CAST(@FailCount AS VARCHAR(5)) + ' failed check(s).';
    PRINT 'Review the FAIL items above and take corrective action.';
END
ELSE IF @WarnCount > 0
BEGIN
    PRINT '';
    PRINT '*** VALIDATION PASSED WITH WARNINGS ***';
    PRINT 'TDE is functional but there are ' + CAST(@WarnCount AS VARCHAR(5)) + ' warning(s) to review.';
END
ELSE
BEGIN
    PRINT '';
    PRINT '*** VALIDATION PASSED ***';
    PRINT 'TDE is fully operational on PatientDB.';
END

PRINT '';
PRINT '================================================================';
PRINT ' Post-Migration Recommendations';
PRINT '================================================================';
PRINT '';
PRINT '  1. Consider migrating to service-managed TDE keys for';
PRINT '     simplified key management on Azure SQL MI.';
PRINT '  2. Enable Azure Defender for SQL for threat detection.';
PRINT '  3. Configure TDE protector rotation policy.';
PRINT '  4. Delete exported .cer/.pvk files from all staging locations.';
PRINT '  5. Document the certificate thumbprint and expiry for tracking.';
PRINT '';
PRINT '================================================================';
PRINT ' Validation complete.';
PRINT '================================================================';
GO

-- Cleanup
IF OBJECT_ID('tempdb..#TDEValidation') IS NOT NULL
    DROP TABLE #TDEValidation;
GO
