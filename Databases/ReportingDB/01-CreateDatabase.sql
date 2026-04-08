-- ============================================
-- Create ReportingDB Database
-- Lakeview Medical Center
-- ============================================
USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ReportingDB')
BEGIN
    CREATE DATABASE ReportingDB
    ON PRIMARY 
    (
        NAME = N'ReportingDB_Data',
        FILENAME = N'C:\SQLData\ReportingDB_Data.mdf',
        SIZE = 256MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 64MB
    )
    LOG ON 
    (
        NAME = N'ReportingDB_Log',
        FILENAME = N'C:\SQLData\ReportingDB_Log.ldf',
        SIZE = 128MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 32MB
    );
    
    PRINT 'ReportingDB database created successfully.';
END
ELSE
BEGIN
    PRINT 'ReportingDB database already exists.';
END
GO

ALTER DATABASE ReportingDB SET RECOVERY SIMPLE;  -- Reporting DB uses simple recovery
ALTER DATABASE ReportingDB SET COMPATIBILITY_LEVEL = 130;
ALTER DATABASE ReportingDB SET READ_COMMITTED_SNAPSHOT ON;  -- Reduce locking for reports
ALTER DATABASE ReportingDB SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE ReportingDB SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE ReportingDB SET AUTO_UPDATE_STATISTICS ON;
GO

PRINT 'ReportingDB setup complete.';
GO
