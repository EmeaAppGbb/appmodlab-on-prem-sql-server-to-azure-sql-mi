-- ============================================
-- Create PatientDB Database
-- ============================================
USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'PatientDB')
BEGIN
    CREATE DATABASE PatientDB
    ON PRIMARY 
    (
        NAME = N'PatientDB_Data',
        FILENAME = N'C:\SQLData\PatientDB_Data.mdf',
        SIZE = 1024MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 256MB
    )
    LOG ON 
    (
        NAME = N'PatientDB_Log',
        FILENAME = N'C:\SQLData\PatientDB_Log.ldf',
        SIZE = 512MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 128MB
    );
    
    PRINT 'PatientDB database created successfully.';
END
ELSE
BEGIN
    PRINT 'PatientDB database already exists.';
END
GO

-- Set database options
ALTER DATABASE PatientDB SET RECOVERY FULL;
ALTER DATABASE PatientDB SET COMPATIBILITY_LEVEL = 130; -- SQL Server 2016
ALTER DATABASE PatientDB SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE PatientDB SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE PatientDB SET AUTO_UPDATE_STATISTICS ON;
GO

USE PatientDB;
GO

-- Enable Service Broker for async messaging
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'PatientDB' AND is_broker_enabled = 1)
BEGIN
    ALTER DATABASE PatientDB SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;
    PRINT 'Service Broker enabled on PatientDB.';
END
GO
