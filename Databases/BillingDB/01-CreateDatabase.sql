-- ============================================
-- Create BillingDB Database
-- Lakeview Medical Center
-- ============================================
USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'BillingDB')
BEGIN
    CREATE DATABASE BillingDB
    ON PRIMARY 
    (
        NAME = N'BillingDB_Data',
        FILENAME = N'C:\SQLData\BillingDB_Data.mdf',
        SIZE = 512MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 128MB
    )
    LOG ON 
    (
        NAME = N'BillingDB_Log',
        FILENAME = N'C:\SQLData\BillingDB_Log.ldf',
        SIZE = 256MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 64MB
    );
    
    PRINT 'BillingDB database created successfully.';
END
ELSE
BEGIN
    PRINT 'BillingDB database already exists.';
END
GO

-- Set database options
ALTER DATABASE BillingDB SET RECOVERY FULL;
ALTER DATABASE BillingDB SET COMPATIBILITY_LEVEL = 130; -- SQL Server 2016
ALTER DATABASE BillingDB SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE BillingDB SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE BillingDB SET AUTO_UPDATE_STATISTICS ON;
GO

USE BillingDB;
GO

-- Enable Service Broker
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingDB' AND is_broker_enabled = 1)
BEGIN
    ALTER DATABASE BillingDB SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;
    PRINT 'Service Broker enabled on BillingDB.';
END
GO

-- Enable Transparent Data Encryption (TDE) - legacy on-prem pattern
-- Requires master key and certificate to be set up at the server level
/*
USE master;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Lak3v!ew_Master_2016!';
GO
CREATE CERTIFICATE BillingDB_TDE_Cert WITH SUBJECT = 'BillingDB TDE Certificate';
GO
USE BillingDB;
GO
CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE BillingDB_TDE_Cert;
GO
ALTER DATABASE BillingDB SET ENCRYPTION ON;
GO
*/

PRINT 'BillingDB setup complete.';
GO
