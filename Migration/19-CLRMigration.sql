-- ============================================
-- 19 - CLR Assembly Migration to Azure SQL MI
-- Lakeview Medical Center
-- Deploys MedicalCalculations CLR assembly on MI
-- with MI-specific security requirements
-- ============================================
-- PREREQUISITES:
--   - MedicalCalculations.dll compiled from CLRAssemblies/MedicalCalculations.cs
--   - sysadmin or appropriate permissions on the MI instance
--   - PatientDB database restored/migrated to MI
--
-- MI CLR CONSIDERATIONS:
--   - CLR is enabled by default on Azure SQL MI
--   - sp_configure 'clr strict security' defaults to 1 on MI
--   - Assemblies must be signed OR database set TRUSTWORTHY
--   - SAFE assemblies still need signing when strict security = 1
--   - EXTERNAL_ACCESS / UNSAFE require additional trust chain
-- ============================================

USE PatientDB;
GO

PRINT '============================================';
PRINT ' CLR Assembly Migration to Azure SQL MI';
PRINT ' Started: ' + CONVERT(VARCHAR(30), GETDATE(), 121);
PRINT '============================================';
GO

-- ============================================
-- Step 1: Verify CLR is enabled on MI
-- (CLR is enabled by default, but verify)
-- ============================================
PRINT '';
PRINT '>> Step 1: Verifying CLR integration status...';

DECLARE @ClrEnabled INT;
SELECT @ClrEnabled = CAST(value_in_use AS INT)
FROM sys.configurations
WHERE name = 'clr enabled';

IF @ClrEnabled = 1
    PRINT '   CLR integration is ENABLED.';
ELSE
BEGIN
    PRINT '   CLR integration is DISABLED. Enabling...';
    EXEC sp_configure 'clr enabled', 1;
    RECONFIGURE;
    PRINT '   CLR integration enabled.';
END
GO

-- ============================================
-- Step 2: Check CLR strict security setting
-- On MI, strict security = 1 by default.
-- When enabled, ALL assemblies (even SAFE) must be
-- signed or the database must be TRUSTWORTHY.
-- ============================================
PRINT '';
PRINT '>> Step 2: Checking CLR strict security...';

DECLARE @StrictSecurity INT;
SELECT @StrictSecurity = CAST(value_in_use AS INT)
FROM sys.configurations
WHERE name = 'clr strict security';

IF @StrictSecurity = 1
    PRINT '   CLR strict security is ON (MI default). Assemblies must be authorized.';
ELSE
    PRINT '   CLR strict security is OFF.';
GO

-- ============================================
-- Step 3: Configure assembly authorization
-- APPROACH A (Preferred): Sign assembly with a certificate
--   - Create a certificate in master
--   - Create a login from that certificate
--   - Grant UNSAFE ASSEMBLY to that login
-- APPROACH B (Simpler): Set TRUSTWORTHY ON
--   - Simpler but less secure
--   - Acceptable for single-tenant MI instances
--
-- We implement BOTH approaches. Approach A is
-- preferred; Approach B is the fallback.
-- ============================================
PRINT '';
PRINT '>> Step 3: Configuring assembly authorization...';
PRINT '   Attempting Approach A: Certificate-based signing...';
GO

-- ============================================
-- Approach A: Certificate-based trust chain
-- ============================================

-- Step 3a: Create an asymmetric key or certificate in master
-- from the assembly DLL to establish trust.
-- NOTE: Replace the FROM path with the actual DLL location on MI.
USE master;
GO

-- Check if key/login already exist and skip if so
IF NOT EXISTS (SELECT 1 FROM sys.asymmetric_keys WHERE name = 'MedicalCalculationsKey')
BEGIN
    BEGIN TRY
        -- Create asymmetric key from the signed assembly DLL
        -- Replace path with the actual DLL path accessible to the MI instance
        CREATE ASYMMETRIC KEY [MedicalCalculationsKey]
        FROM FILE = 'C:\SQLAssemblies\MedicalCalculations.dll';
        PRINT '   Asymmetric key [MedicalCalculationsKey] created from assembly.';
    END TRY
    BEGIN CATCH
        PRINT '   NOTE: Could not create asymmetric key from file.';
        PRINT '   Error: ' + ERROR_MESSAGE();
        PRINT '   Falling back to Approach B (TRUSTWORTHY).';
    END CATCH
END
ELSE
    PRINT '   Asymmetric key [MedicalCalculationsKey] already exists.';
GO

-- Create login from the asymmetric key (if key exists)
IF EXISTS (SELECT 1 FROM sys.asymmetric_keys WHERE name = 'MedicalCalculationsKey')
    AND NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'MedicalCalculationsLogin')
BEGIN
    CREATE LOGIN [MedicalCalculationsLogin] FROM ASYMMETRIC KEY [MedicalCalculationsKey];
    GRANT UNSAFE ASSEMBLY TO [MedicalCalculationsLogin];
    PRINT '   Login [MedicalCalculationsLogin] created and granted UNSAFE ASSEMBLY.';
END
GO

-- ============================================
-- Approach B (Fallback): TRUSTWORTHY database
-- Used when assembly is not signed or key creation fails
-- ============================================
USE PatientDB;
GO

-- Check if Approach A succeeded
DECLARE @KeyExists BIT = 0;
IF EXISTS (SELECT 1 FROM master.sys.asymmetric_keys WHERE name = 'MedicalCalculationsKey')
    SET @KeyExists = 1;

IF @KeyExists = 0
BEGIN
    PRINT '';
    PRINT '   Applying Approach B: Setting database TRUSTWORTHY...';

    -- Ensure database owner is a sysadmin login (required for TRUSTWORTHY)
    DECLARE @DbOwner NVARCHAR(128);
    SELECT @DbOwner = SUSER_SNAME(owner_sid) FROM sys.databases WHERE name = DB_NAME();
    PRINT '   Database owner: ' + ISNULL(@DbOwner, 'NULL');

    ALTER DATABASE PatientDB SET TRUSTWORTHY ON;
    PRINT '   Database PatientDB set to TRUSTWORTHY = ON.';

    -- Verify
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'PatientDB' AND is_trustworthy_on = 1)
        PRINT '   TRUSTWORTHY setting verified.';
    ELSE
        PRINT '   WARNING: TRUSTWORTHY could not be verified!';
END
ELSE
    PRINT '   Approach A succeeded. TRUSTWORTHY not required.';
GO

-- ============================================
-- Step 4: Drop existing CLR objects (if re-running)
-- Must drop functions before assembly
-- ============================================
PRINT '';
PRINT '>> Step 4: Dropping existing CLR objects (if any)...';

IF EXISTS (SELECT 1 FROM sys.objects WHERE name = 'fn_CLR_CheckDrugInteractions' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_CheckDrugInteractions;
IF EXISTS (SELECT 1 FROM sys.objects WHERE name = 'fn_CLR_ValidateICDCode' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_ValidateICDCode;
IF EXISTS (SELECT 1 FROM sys.objects WHERE name = 'fn_CLR_GetBMICategory' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_GetBMICategory;
IF EXISTS (SELECT 1 FROM sys.objects WHERE name = 'fn_CLR_CalculateGFR' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_CalculateGFR;
IF EXISTS (SELECT 1 FROM sys.objects WHERE name = 'fn_CLR_ParseHL7Segments' AND type = 'FT')
    DROP FUNCTION dbo.fn_CLR_ParseHL7Segments;
IF EXISTS (SELECT 1 FROM sys.objects WHERE name = 'fn_CLR_NormalizeDrugName' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_NormalizeDrugName;

IF EXISTS (SELECT 1 FROM sys.assemblies WHERE name = 'MedicalCalculations')
    DROP ASSEMBLY MedicalCalculations;

PRINT '   Existing CLR objects dropped.';
GO

-- ============================================
-- Step 5: Create Assembly on MI
-- Use PERMISSION_SET = SAFE for this assembly.
-- MedicalCalculations uses only:
--   - System.Text.RegularExpressions
--   - System.Collections.Generic
--   - No file/network I/O, no unsafe code
-- Therefore SAFE is sufficient.
--
-- NOTE: If the assembly accessed external resources
-- (files, network, COM), EXTERNAL_ACCESS would be needed.
-- If it used unmanaged code, UNSAFE would be required.
-- ============================================
PRINT '';
PRINT '>> Step 5: Creating CLR assembly on MI...';
GO

-- Option A: From file path (if DLL is accessible on MI storage)
-- CREATE ASSEMBLY MedicalCalculations
-- FROM 'C:\SQLAssemblies\MedicalCalculations.dll'
-- WITH PERMISSION_SET = SAFE;

-- Option B: From binary literal (recommended for MI deployment)
-- Generate the hex string from the DLL with PowerShell:
--   [System.IO.File]::ReadAllBytes("MedicalCalculations.dll") |
--   ForEach-Object { $_.ToString("X2") } | Join-String -Separator ''
-- Then embed as: FROM 0x<hex_bytes>

-- Placeholder: uncomment and replace with actual binary or path
/*
CREATE ASSEMBLY MedicalCalculations
FROM 0x4D5A... -- Replace with actual DLL binary hex
WITH PERMISSION_SET = SAFE;
*/

-- For scripted deployment, use file path:
CREATE ASSEMBLY MedicalCalculations
FROM 'C:\SQLAssemblies\MedicalCalculations.dll'
WITH PERMISSION_SET = SAFE;
GO

PRINT '   Assembly MedicalCalculations created with PERMISSION_SET = SAFE.';
GO

-- Verify assembly was created
IF EXISTS (SELECT 1 FROM sys.assemblies WHERE name = 'MedicalCalculations')
BEGIN
    DECLARE @PermSet NVARCHAR(30);
    SELECT @PermSet = CASE permission_set
        WHEN 1 THEN 'SAFE'
        WHEN 2 THEN 'EXTERNAL_ACCESS'
        WHEN 3 THEN 'UNSAFE'
    END
    FROM sys.assemblies WHERE name = 'MedicalCalculations';
    PRINT '   Verified: Assembly exists with PERMISSION_SET = ' + @PermSet;
END
ELSE
    PRINT '   ERROR: Assembly was not created!';
GO

-- ============================================
-- Step 6: Create CLR Functions
-- ============================================
PRINT '';
PRINT '>> Step 6: Creating CLR functions...';
GO

-- 6a: Drug Interaction Check (scalar, reads data)
CREATE FUNCTION dbo.fn_CLR_CheckDrugInteractions
(
    @DrugCode1 NVARCHAR(20),
    @DrugCode2 NVARCHAR(20)
)
RETURNS NVARCHAR(500)
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].CheckDrugInteractions;
GO
PRINT '   Created: fn_CLR_CheckDrugInteractions';
GO

-- 6b: ICD-10 Code Validation (scalar, deterministic)
CREATE FUNCTION dbo.fn_CLR_ValidateICDCode
(
    @ICDCode NVARCHAR(10)
)
RETURNS BIT
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].ValidateICDCode;
GO
PRINT '   Created: fn_CLR_ValidateICDCode';
GO

-- 6c: BMI Category Classification (scalar, deterministic)
CREATE FUNCTION dbo.fn_CLR_GetBMICategory
(
    @BMI FLOAT
)
RETURNS NVARCHAR(50)
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].GetBMICategory;
GO
PRINT '   Created: fn_CLR_GetBMICategory';
GO

-- 6d: GFR Calculation (scalar, deterministic)
CREATE FUNCTION dbo.fn_CLR_CalculateGFR
(
    @Creatinine FLOAT,
    @Age INT,
    @IsFemale BIT,
    @IsBlack BIT
)
RETURNS FLOAT
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].CalculateGFR;
GO
PRINT '   Created: fn_CLR_CalculateGFR';
GO

-- 6e: HL7 Message Parser (table-valued)
CREATE FUNCTION dbo.fn_CLR_ParseHL7Segments
(
    @HL7Message NVARCHAR(MAX)
)
RETURNS TABLE (
    SegmentIndex INT,
    SegmentType NVARCHAR(10),
    FieldCount INT,
    RawSegment NVARCHAR(MAX)
)
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].ParseHL7Segments;
GO
PRINT '   Created: fn_CLR_ParseHL7Segments';
GO

-- 6f: Drug Name Normalization (scalar, deterministic)
CREATE FUNCTION dbo.fn_CLR_NormalizeDrugName
(
    @DrugName NVARCHAR(200)
)
RETURNS NVARCHAR(200)
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].NormalizeDrugName;
GO
PRINT '   Created: fn_CLR_NormalizeDrugName';
GO

-- ============================================
-- Step 7: Smoke-test all CLR functions
-- ============================================
PRINT '';
PRINT '>> Step 7: Running CLR function smoke tests...';
PRINT '';

-- Test 1: Drug Interaction Check
PRINT '-- Test: fn_CLR_CheckDrugInteractions';
SELECT 'WARFARIN + ASPIRIN' AS TestCase,
       dbo.fn_CLR_CheckDrugInteractions('WARFARIN', 'ASPIRIN') AS Result;
SELECT 'METFORMIN + CONTRAST_DYE' AS TestCase,
       dbo.fn_CLR_CheckDrugInteractions('METFORMIN', 'CONTRAST_DYE') AS Result;
SELECT 'ASPIRIN + TYLENOL (no interaction)' AS TestCase,
       dbo.fn_CLR_CheckDrugInteractions('ASPIRIN', 'TYLENOL') AS Result;
GO

-- Test 2: ICD-10 Validation
PRINT '-- Test: fn_CLR_ValidateICDCode';
SELECT 'A01.0 (valid)' AS TestCase,
       dbo.fn_CLR_ValidateICDCode('A01.0') AS Result;
SELECT 'I25.10 (valid)' AS TestCase,
       dbo.fn_CLR_ValidateICDCode('I25.10') AS Result;
SELECT 'ZZZ (invalid)' AS TestCase,
       dbo.fn_CLR_ValidateICDCode('ZZZ') AS Result;
GO

-- Test 3: BMI Category
PRINT '-- Test: fn_CLR_GetBMICategory';
SELECT 'BMI 22.5 (Normal)' AS TestCase,
       dbo.fn_CLR_GetBMICategory(22.5) AS Result;
SELECT 'BMI 31.0 (Obese I)' AS TestCase,
       dbo.fn_CLR_GetBMICategory(31.0) AS Result;
GO

-- Test 4: GFR Calculation
PRINT '-- Test: fn_CLR_CalculateGFR';
SELECT 'Creatinine 1.0, Age 50, Female, Not Black' AS TestCase,
       dbo.fn_CLR_CalculateGFR(1.0, 50, 1, 0) AS Result;
SELECT 'Creatinine 1.5, Age 65, Male, Not Black' AS TestCase,
       dbo.fn_CLR_CalculateGFR(1.5, 65, 0, 0) AS Result;
GO

-- Test 5: HL7 Message Parser
PRINT '-- Test: fn_CLR_ParseHL7Segments';
SELECT * FROM dbo.fn_CLR_ParseHL7Segments(
    N'MSH|^~\&|ADT|LAKEVIEW|LAB|LAKEVIEW|202601011200||ADT^A01|MSG001|P|2.5
PID|||12345||DOE^JOHN||19800101|M
PV1||I|ICU^101^A');
GO

-- Test 6: Drug Name Normalization
PRINT '-- Test: fn_CLR_NormalizeDrugName';
SELECT 'Metformin HCL 500 MG Tablet' AS TestCase,
       dbo.fn_CLR_NormalizeDrugName('Metformin HCL 500 MG Tablet') AS Result;
SELECT 'Lisinopril Sodium 10 MG' AS TestCase,
       dbo.fn_CLR_NormalizeDrugName('Lisinopril Sodium 10 MG') AS Result;
GO

-- ============================================
-- Step 8: Document MI-specific CLR metadata
-- ============================================
PRINT '';
PRINT '>> Step 8: CLR assembly metadata on MI:';

SELECT a.name AS AssemblyName,
       a.clr_name AS CLRName,
       CASE a.permission_set
           WHEN 1 THEN 'SAFE'
           WHEN 2 THEN 'EXTERNAL_ACCESS'
           WHEN 3 THEN 'UNSAFE'
       END AS PermissionSet,
       a.is_visible AS IsVisible,
       a.create_date AS CreatedDate
FROM sys.assemblies a
WHERE a.is_user_defined = 1;

SELECT o.name AS FunctionName,
       o.type_desc AS ObjectType,
       am.assembly_class AS AssemblyClass,
       am.assembly_method AS AssemblyMethod
FROM sys.assembly_modules am
JOIN sys.objects o ON am.object_id = o.object_id
ORDER BY o.name;
GO

PRINT '';
PRINT '============================================';
PRINT ' CLR Assembly Migration Complete';
PRINT ' Finished: ' + CONVERT(VARCHAR(30), GETDATE(), 121);
PRINT '============================================';
GO
