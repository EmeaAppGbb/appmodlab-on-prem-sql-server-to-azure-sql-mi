-- ============================================
-- Service Broker Setup
-- Lakeview Medical Center
-- Async messaging between PatientDB and BillingDB
-- Legacy: Service Broker is a migration challenge
-- ============================================

-- ============================================
-- PART 1: PatientDB Service Broker Objects
-- ============================================
USE PatientDB;
GO

-- Message Types
IF NOT EXISTS (SELECT * FROM sys.service_message_types WHERE name = 'PatientEncounterMessage')
BEGIN
    CREATE MESSAGE TYPE [PatientEncounterMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT 'Message type [PatientEncounterMessage] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.service_message_types WHERE name = 'PatientDischargeMessage')
BEGIN
    CREATE MESSAGE TYPE [PatientDischargeMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT 'Message type [PatientDischargeMessage] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.service_message_types WHERE name = 'BillingResponseMessage')
BEGIN
    CREATE MESSAGE TYPE [BillingResponseMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT 'Message type [BillingResponseMessage] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.service_message_types WHERE name = 'LabResultNotificationMessage')
BEGIN
    CREATE MESSAGE TYPE [LabResultNotificationMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT 'Message type [LabResultNotificationMessage] created.';
END
GO

-- Contracts
IF NOT EXISTS (SELECT * FROM sys.service_contracts WHERE name = 'PatientBillingContract')
BEGIN
    CREATE CONTRACT [PatientBillingContract]
    (
        [PatientEncounterMessage] SENT BY INITIATOR,
        [PatientDischargeMessage] SENT BY INITIATOR,
        [BillingResponseMessage] SENT BY TARGET
    );
    PRINT 'Contract [PatientBillingContract] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.service_contracts WHERE name = 'LabNotificationContract')
BEGIN
    CREATE CONTRACT [LabNotificationContract]
    (
        [LabResultNotificationMessage] SENT BY INITIATOR
    );
    PRINT 'Contract [LabNotificationContract] created.';
END
GO

-- Queues
IF NOT EXISTS (SELECT * FROM sys.service_queues WHERE name = 'PatientEventSendQueue')
BEGIN
    CREATE QUEUE dbo.PatientEventSendQueue
    WITH 
        STATUS = ON,
        RETENTION = OFF,
        POISON_MESSAGE_HANDLING (STATUS = ON);
    PRINT 'Queue [PatientEventSendQueue] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.service_queues WHERE name = 'LabNotificationQueue')
BEGIN
    CREATE QUEUE dbo.LabNotificationQueue
    WITH 
        STATUS = ON,
        RETENTION = OFF,
        POISON_MESSAGE_HANDLING (STATUS = ON);
    PRINT 'Queue [LabNotificationQueue] created.';
END
GO

-- Services
IF NOT EXISTS (SELECT * FROM sys.services WHERE name = 'PatientEventSendService')
BEGIN
    CREATE SERVICE [PatientEventSendService]
    ON QUEUE dbo.PatientEventSendQueue
    (
        [PatientBillingContract]
    );
    PRINT 'Service [PatientEventSendService] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.services WHERE name = 'LabNotificationService')
BEGIN
    CREATE SERVICE [LabNotificationService]
    ON QUEUE dbo.LabNotificationQueue
    (
        [LabNotificationContract]
    );
    PRINT 'Service [LabNotificationService] created.';
END
GO

-- ============================================
-- Activation procedure for Lab Notification Queue
-- Processes critical lab result notifications
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ProcessLabNotifications')
    DROP PROCEDURE dbo.usp_ProcessLabNotifications;
GO

CREATE PROCEDURE dbo.usp_ProcessLabNotifications
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ConversationHandle UNIQUEIDENTIFIER;
    DECLARE @MessageBody XML;
    DECLARE @MessageTypeName NVARCHAR(256);
    
    WHILE (1 = 1)
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            
            WAITFOR (
                RECEIVE TOP(1)
                    @ConversationHandle = conversation_handle,
                    @MessageBody = CAST(message_body AS XML),
                    @MessageTypeName = message_type_name
                FROM dbo.LabNotificationQueue
            ), TIMEOUT 5000;
            
            IF @@ROWCOUNT = 0
            BEGIN
                COMMIT TRANSACTION;
                BREAK;
            END
            
            IF @MessageTypeName = N'LabResultNotificationMessage'
            BEGIN
                -- Process the lab notification
                DECLARE @PatientID INT = @MessageBody.value('(/LabNotification/PatientID)[1]', 'INT');
                DECLARE @TestName NVARCHAR(200) = @MessageBody.value('(/LabNotification/TestName)[1]', 'NVARCHAR(200)');
                DECLARE @CriticalFlag BIT = @MessageBody.value('(/LabNotification/CriticalFlag)[1]', 'BIT');
                
                IF @CriticalFlag = 1
                BEGIN
                    -- Log critical lab notification for physician alert
                    INSERT INTO dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
                    VALUES ('LabResults', @PatientID, 'CRITICAL_LAB_NOTIFICATION',
                            'Critical lab result notification processed: ' + @TestName,
                            'ServiceBroker');
                END
                
                END CONVERSATION @ConversationHandle;
            END
            ELSE IF @MessageTypeName = N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
            BEGIN
                END CONVERSATION @ConversationHandle;
            END
            ELSE IF @MessageTypeName = N'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
            BEGIN
                END CONVERSATION @ConversationHandle;
            END
            
            COMMIT TRANSACTION;
            
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            
            -- Log error but don't crash the activation proc
            INSERT INTO dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
            VALUES ('ServiceBroker', 0, 'ACTIVATION_ERROR', ERROR_MESSAGE(), 'ServiceBroker');
            
            BREAK;
        END CATCH
    END
END
GO

-- Enable activation on lab notification queue
ALTER QUEUE dbo.LabNotificationQueue
WITH ACTIVATION (
    STATUS = ON,
    PROCEDURE_NAME = dbo.usp_ProcessLabNotifications,
    MAX_QUEUE_READERS = 2,
    EXECUTE AS SELF
);
GO

PRINT 'PatientDB Service Broker objects created.';
GO

-- ============================================
-- PART 2: BillingDB Service Broker Objects
-- ============================================
USE BillingDB;
GO

-- Message Types (must match PatientDB definitions)
IF NOT EXISTS (SELECT * FROM sys.service_message_types WHERE name = 'PatientEncounterMessage')
BEGIN
    CREATE MESSAGE TYPE [PatientEncounterMessage]
    VALIDATION = WELL_FORMED_XML;
END
GO

IF NOT EXISTS (SELECT * FROM sys.service_message_types WHERE name = 'PatientDischargeMessage')
BEGIN
    CREATE MESSAGE TYPE [PatientDischargeMessage]
    VALIDATION = WELL_FORMED_XML;
END
GO

IF NOT EXISTS (SELECT * FROM sys.service_message_types WHERE name = 'BillingResponseMessage')
BEGIN
    CREATE MESSAGE TYPE [BillingResponseMessage]
    VALIDATION = WELL_FORMED_XML;
END
GO

-- Contract
IF NOT EXISTS (SELECT * FROM sys.service_contracts WHERE name = 'PatientBillingContract')
BEGIN
    CREATE CONTRACT [PatientBillingContract]
    (
        [PatientEncounterMessage] SENT BY INITIATOR,
        [PatientDischargeMessage] SENT BY INITIATOR,
        [BillingResponseMessage] SENT BY TARGET
    );
END
GO

-- Queue
IF NOT EXISTS (SELECT * FROM sys.service_queues WHERE name = 'BillingEventReceiveQueue')
BEGIN
    CREATE QUEUE dbo.BillingEventReceiveQueue
    WITH 
        STATUS = ON,
        RETENTION = OFF,
        POISON_MESSAGE_HANDLING (STATUS = ON);
    PRINT 'Queue [BillingEventReceiveQueue] created.';
END
GO

-- Service
IF NOT EXISTS (SELECT * FROM sys.services WHERE name = 'BillingEventReceiveService')
BEGIN
    CREATE SERVICE [BillingEventReceiveService]
    ON QUEUE dbo.BillingEventReceiveQueue
    (
        [PatientBillingContract]
    );
    PRINT 'Service [BillingEventReceiveService] created.';
END
GO

-- ============================================
-- Activation procedure for Billing Event Queue
-- Processes encounter/discharge notifications from PatientDB
-- ============================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ProcessBillingEvents')
    DROP PROCEDURE dbo.usp_ProcessBillingEvents;
GO

CREATE PROCEDURE dbo.usp_ProcessBillingEvents
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ConversationHandle UNIQUEIDENTIFIER;
    DECLARE @MessageBody XML;
    DECLARE @MessageTypeName NVARCHAR(256);
    
    WHILE (1 = 1)
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            
            WAITFOR (
                RECEIVE TOP(1)
                    @ConversationHandle = conversation_handle,
                    @MessageBody = CAST(message_body AS XML),
                    @MessageTypeName = message_type_name
                FROM dbo.BillingEventReceiveQueue
            ), TIMEOUT 5000;
            
            IF @@ROWCOUNT = 0
            BEGIN
                COMMIT TRANSACTION;
                BREAK;
            END
            
            IF @MessageTypeName = N'PatientEncounterMessage'
            BEGIN
                -- New encounter - verify insurance eligibility
                DECLARE @EncounterID INT = @MessageBody.value('(/NewEncounter/EncounterID)[1]', 'INT');
                DECLARE @PatientID INT = @MessageBody.value('(/NewEncounter/PatientID)[1]', 'INT');
                DECLARE @EncounterType NVARCHAR(20) = @MessageBody.value('(/NewEncounter/EncounterType)[1]', 'NVARCHAR(20)');
                
                -- Log the event
                INSERT INTO dbo.BillingAudit (TableName, RecordID, Action, NewValues, ChangedBy)
                VALUES ('Encounters', @EncounterID, 'NEW_ENCOUNTER_RECEIVED',
                        'Encounter notification received via Service Broker. Patient: ' + CAST(@PatientID AS VARCHAR) +
                        ', Type: ' + @EncounterType,
                        'ServiceBroker');
                
                -- Send response
                DECLARE @ResponseBody XML = (
                    SELECT @EncounterID AS EncounterID,
                           'RECEIVED' AS Status,
                           GETDATE() AS ProcessedDate
                    FOR XML PATH('BillingResponse')
                );
                
                SEND ON CONVERSATION @ConversationHandle
                    MESSAGE TYPE [BillingResponseMessage] (@ResponseBody);
                
                END CONVERSATION @ConversationHandle;
            END
            ELSE IF @MessageTypeName = N'PatientDischargeMessage'
            BEGIN
                -- Patient discharged - trigger charge processing
                DECLARE @DischargeEncounterID INT = @MessageBody.value('(/PatientDischarge/EncounterID)[1]', 'INT');
                
                -- Queue charge processing
                BEGIN TRY
                    EXEC dbo.usp_ProcessEncounterCharges @EncounterID = @DischargeEncounterID;
                END TRY
                BEGIN CATCH
                    INSERT INTO dbo.BillingAudit (TableName, RecordID, Action, NewValues, ChangedBy)
                    VALUES ('Encounters', @DischargeEncounterID, 'CHARGE_PROCESSING_ERROR',
                            ERROR_MESSAGE(), 'ServiceBroker');
                END CATCH
                
                END CONVERSATION @ConversationHandle;
            END
            ELSE IF @MessageTypeName = N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
            BEGIN
                END CONVERSATION @ConversationHandle;
            END
            ELSE IF @MessageTypeName = N'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
            BEGIN
                END CONVERSATION @ConversationHandle;
            END
            
            COMMIT TRANSACTION;
            
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            
            INSERT INTO dbo.BillingAudit (TableName, RecordID, Action, NewValues, ChangedBy)
            VALUES ('ServiceBroker', 0, 'ACTIVATION_ERROR', ERROR_MESSAGE(), 'ServiceBroker');
            
            BREAK;
        END CATCH
    END
END
GO

-- Enable activation
ALTER QUEUE dbo.BillingEventReceiveQueue
WITH ACTIVATION (
    STATUS = ON,
    PROCEDURE_NAME = dbo.usp_ProcessBillingEvents,
    MAX_QUEUE_READERS = 3,
    EXECUTE AS SELF
);
GO

PRINT 'BillingDB Service Broker objects created.';
GO

-- ============================================
-- Route setup (for cross-database communication)
-- ============================================
USE PatientDB;
GO

IF NOT EXISTS (SELECT * FROM sys.routes WHERE name = 'BillingServiceRoute')
BEGIN
    CREATE ROUTE [BillingServiceRoute]
    WITH SERVICE_NAME = N'BillingEventReceiveService',
         ADDRESS = N'LOCAL';
    PRINT 'Route [BillingServiceRoute] created in PatientDB.';
END
GO

USE BillingDB;
GO

IF NOT EXISTS (SELECT * FROM sys.routes WHERE name = 'PatientServiceRoute')
BEGIN
    CREATE ROUTE [PatientServiceRoute]
    WITH SERVICE_NAME = N'PatientEventSendService',
         ADDRESS = N'LOCAL';
    PRINT 'Route [PatientServiceRoute] created in BillingDB.';
END
GO

PRINT '========================================';
PRINT 'Service Broker setup complete.';
PRINT '========================================';
GO
