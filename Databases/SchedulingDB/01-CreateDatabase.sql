-- ============================================
-- Create SchedulingDB Database
-- Lakeview Medical Center
-- ============================================
USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'SchedulingDB')
BEGIN
    CREATE DATABASE SchedulingDB
    ON PRIMARY 
    (
        NAME = N'SchedulingDB_Data',
        FILENAME = N'C:\SQLData\SchedulingDB_Data.mdf',
        SIZE = 256MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 64MB
    )
    LOG ON 
    (
        NAME = N'SchedulingDB_Log',
        FILENAME = N'C:\SQLData\SchedulingDB_Log.ldf',
        SIZE = 128MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 32MB
    );
    
    PRINT 'SchedulingDB database created successfully.';
END
ELSE
BEGIN
    PRINT 'SchedulingDB database already exists.';
END
GO

ALTER DATABASE SchedulingDB SET RECOVERY FULL;
ALTER DATABASE SchedulingDB SET COMPATIBILITY_LEVEL = 130;
ALTER DATABASE SchedulingDB SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE SchedulingDB SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE SchedulingDB SET AUTO_UPDATE_STATISTICS ON;
GO

PRINT 'SchedulingDB setup complete.';
GO
