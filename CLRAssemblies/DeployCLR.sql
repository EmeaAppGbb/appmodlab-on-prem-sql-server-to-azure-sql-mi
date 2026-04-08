-- ============================================
-- Deploy CLR Assembly
-- Lakeview Medical Center
-- Deploys the MedicalCalculations CLR assembly
-- Legacy: CLR requires special configuration
-- ============================================
USE PatientDB;
GO

-- ============================================
-- Step 1: Enable CLR Integration (server-level)
-- ============================================
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;
GO

-- For UNSAFE assemblies (SQL Server 2017+)
EXEC sp_configure 'clr strict security', 0;
RECONFIGURE;
GO

PRINT 'CLR integration enabled.';
GO

-- ============================================
-- Step 2: Set database as trustworthy
-- (Required for EXTERNAL_ACCESS and UNSAFE assemblies)
-- MIGRATION NOTE: Azure SQL MI supports CLR but
-- TRUSTWORTHY databases need careful review
-- ============================================
ALTER DATABASE PatientDB SET TRUSTWORTHY ON;
GO

PRINT 'Database set as TRUSTWORTHY.';
GO

-- ============================================
-- Step 3: Drop existing objects if they exist
-- ============================================
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_CLR_CheckDrugInteractions' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_CheckDrugInteractions;
GO
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_CLR_ValidateICDCode' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_ValidateICDCode;
GO
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_CLR_GetBMICategory' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_GetBMICategory;
GO
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_CLR_CalculateGFR' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_CalculateGFR;
GO
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_CLR_ParseHL7Segments' AND type = 'FT')
    DROP FUNCTION dbo.fn_CLR_ParseHL7Segments;
GO
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_CLR_NormalizeDrugName' AND type = 'FS')
    DROP FUNCTION dbo.fn_CLR_NormalizeDrugName;
GO

IF EXISTS (SELECT * FROM sys.assemblies WHERE name = 'MedicalCalculations')
    DROP ASSEMBLY MedicalCalculations;
GO

-- ============================================
-- Step 4: Create Assembly from DLL
-- NOTE: In production, the DLL would be compiled from
-- MedicalCalculations.cs and deployed from a known path.
-- The FROM clause uses the binary representation.
-- ============================================

-- Option A: Deploy from file path (on-premises)
-- CREATE ASSEMBLY MedicalCalculations
-- FROM 'C:\SQLAssemblies\MedicalCalculations.dll'
-- WITH PERMISSION_SET = SAFE;

-- Option B: Deploy from binary (for scripted deployment)
-- The binary below is a placeholder - replace with actual compiled DLL bytes
-- In practice, compile with:
--   csc /target:library /reference:System.Data.dll /out:MedicalCalculations.dll MedicalCalculations.cs

PRINT 'NOTE: Assembly binary must be generated from MedicalCalculations.cs';
PRINT 'Compile with: csc /target:library /reference:System.Data.dll MedicalCalculations.cs';
PRINT 'Then use CREATE ASSEMBLY FROM <path_to_dll>';
GO

-- Placeholder assembly creation (uncomment when DLL is available)
/*
CREATE ASSEMBLY MedicalCalculations
FROM 'C:\SQLAssemblies\MedicalCalculations.dll'
WITH PERMISSION_SET = SAFE;
GO

PRINT 'Assembly MedicalCalculations created.';
GO

-- ============================================
-- Step 5: Create CLR Functions
-- ============================================

-- Drug interaction check
CREATE FUNCTION dbo.fn_CLR_CheckDrugInteractions
(
    @DrugCode1 NVARCHAR(20),
    @DrugCode2 NVARCHAR(20)
)
RETURNS NVARCHAR(500)
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].CheckDrugInteractions;
GO

-- ICD-10 code validation
CREATE FUNCTION dbo.fn_CLR_ValidateICDCode
(
    @ICDCode NVARCHAR(10)
)
RETURNS BIT
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].ValidateICDCode;
GO

-- BMI category classification
CREATE FUNCTION dbo.fn_CLR_GetBMICategory
(
    @BMI FLOAT
)
RETURNS NVARCHAR(50)
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].GetBMICategory;
GO

-- GFR calculation
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

-- HL7 message parser (table-valued)
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

-- Drug name normalization
CREATE FUNCTION dbo.fn_CLR_NormalizeDrugName
(
    @DrugName NVARCHAR(200)
)
RETURNS NVARCHAR(200)
AS EXTERNAL NAME MedicalCalculations.[LakeviewMedical.CLR.MedicalCalculations].NormalizeDrugName;
GO

PRINT 'All CLR functions created successfully.';
*/
GO

PRINT '========================================';
PRINT 'CLR deployment script complete.';
PRINT 'Compile C# source and uncomment CREATE';
PRINT 'ASSEMBLY/FUNCTION statements to deploy.';
PRINT '========================================';
GO
