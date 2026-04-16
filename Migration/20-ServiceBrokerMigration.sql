-- ============================================
-- 20 - Service Broker Migration to Azure SQL MI
-- Lakeview Medical Center
-- Recreates Service Broker configuration on MI
-- for PatientDB <-> BillingDB messaging
-- ============================================
-- PREREQUISITES:
--   - PatientDB and BillingDB migrated to the MI instance
--   - sysadmin or db_owner on both databases
--
-- MI SERVICE BROKER CONSIDERATIONS:
--   - Azure SQL MI fully supports Service Broker
--   - Cross-database messaging within the same MI is supported
--   - Cross-instance messaging requires additional configuration
--   - Service Broker is enabled by default on MI databases
--   - Routes using ADDRESS = 'LOCAL' work for same-instance DBs
-- ============================================

PRINT '============================================';
PRINT ' Service Broker Migration to Azure SQL MI';
PRINT ' Started: ' + CONVERT(VARCHAR(30), GETDATE(), 121);
PRINT '============================================';
GO

-- ============================================
-- PART 1: Enable Service Broker on both databases
-- ============================================
PRINT '';
PRINT '>> Part 1: Enabling Service Broker on databases...';
GO

-- Enable on PatientDB
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'PatientDB' AND is_broker_enabled = 1)
BEGIN
    ALTER DATABASE PatientDB SET ENABLE_BROKER WITH NO_WAIT;
    PRINT '   Service Broker ENABLED on PatientDB.';
END
ELSE
    PRINT '   Service Broker already enabled on PatientDB.';
GO

-- Enable on BillingDB
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'BillingDB' AND is_broker_enabled = 1)
BEGIN
    ALTER DATABASE BillingDB SET ENABLE_BROKER WITH NO_WAIT;
    PRINT '   Service Broker ENABLED on BillingDB.';
END
ELSE
    PRINT '   Service Broker already enabled on BillingDB.';
GO

-- Verify broker status
SELECT name AS DatabaseName,
       is_broker_enabled AS BrokerEnabled,
       service_broker_guid AS BrokerGUID
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB');
GO

-- ============================================
-- PART 2: PatientDB Service Broker Objects
-- ============================================
PRINT '';
PRINT '>> Part 2: Creating PatientDB Service Broker objects...';
GO

USE PatientDB;
GO

-- ============================================
-- 2a: Message Types
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = 'PatientEncounterMessage')
BEGIN
    CREATE MESSAGE TYPE [PatientEncounterMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT '   Created message type: PatientEncounterMessage';
END
ELSE PRINT '   Message type PatientEncounterMessage already exists.';
GO

IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = 'PatientDischargeMessage')
BEGIN
    CREATE MESSAGE TYPE [PatientDischargeMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT '   Created message type: PatientDischargeMessage';
END
ELSE PRINT '   Message type PatientDischargeMessage already exists.';
GO

IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = 'BillingResponseMessage')
BEGIN
    CREATE MESSAGE TYPE [BillingResponseMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT '   Created message type: BillingResponseMessage';
END
ELSE PRINT '   Message type BillingResponseMessage already exists.';
GO

IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = 'LabResultNotificationMessage')
BEGIN
    CREATE MESSAGE TYPE [LabResultNotificationMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT '   Created message type: LabResultNotificationMessage';
END
ELSE PRINT '   Message type LabResultNotificationMessage already exists.';
GO

-- ============================================
-- 2b: Contracts
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.service_contracts WHERE name = 'PatientBillingContract')
BEGIN
    CREATE CONTRACT [PatientBillingContract]
    (
        [PatientEncounterMessage] SENT BY INITIATOR,
        [PatientDischargeMessage] SENT BY INITIATOR,
        [BillingResponseMessage]  SENT BY TARGET
    );
    PRINT '   Created contract: PatientBillingContract';
END
ELSE PRINT '   Contract PatientBillingContract already exists.';
GO

IF NOT EXISTS (SELECT 1 FROM sys.service_contracts WHERE name = 'LabNotificationContract')
BEGIN
    CREATE CONTRACT [LabNotificationContract]
    (
        [LabResultNotificationMessage] SENT BY INITIATOR
    );
    PRINT '   Created contract: LabNotificationContract';
END
ELSE PRINT '   Contract LabNotificationContract already exists.';
GO

-- ============================================
-- 2c: Queues
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.service_queues WHERE name = 'PatientEventSendQueue')
BEGIN
    CREATE QUEUE dbo.PatientEventSendQueue
    WITH
        STATUS = ON,
        RETENTION = OFF,
        POISON_MESSAGE_HANDLING (STATUS = ON);
    PRINT '   Created queue: PatientEventSendQueue';
END
ELSE PRINT '   Queue PatientEventSendQueue already exists.';
GO

IF NOT EXISTS (SELECT 1 FROM sys.service_queues WHERE name = 'LabNotificationQueue')
BEGIN
    CREATE QUEUE dbo.LabNotificationQueue
    WITH
        STATUS = ON,
        RETENTION = OFF,
        POISON_MESSAGE_HANDLING (STATUS = ON);
    PRINT '   Created queue: LabNotificationQueue';
END
ELSE PRINT '   Queue LabNotificationQueue already exists.';
GO

-- ============================================
-- 2d: Services
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.services WHERE name = 'PatientEventSendService')
BEGIN
    CREATE SERVICE [PatientEventSendService]
    ON QUEUE dbo.PatientEventSendQueue
    (
        [PatientBillingContract]
    );
    PRINT '   Created service: PatientEventSendService';
END
ELSE PRINT '   Service PatientEventSendService already exists.';
GO

IF NOT EXISTS (SELECT 1 FROM sys.services WHERE name = 'LabNotificationService')
BEGIN
    CREATE SERVICE [LabNotificationService]
    ON QUEUE dbo.LabNotificationQueue
    (
        [LabNotificationContract]
    );
    PRINT '   Created service: LabNotificationService';
END
ELSE PRINT '   Service LabNotificationService already exists.';
GO

-- ============================================
-- 2e: Lab Notification Activation Procedure
-- ============================================
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_ProcessLabNotifications')
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
                DECLARE @PatientID INT = @MessageBody.value('(/LabNotification/PatientID)[1]', 'INT');
                DECLARE @TestName NVARCHAR(200) = @MessageBody.value('(/LabNotification/TestName)[1]', 'NVARCHAR(200)');
                DECLARE @CriticalFlag BIT = @MessageBody.value('(/LabNotification/CriticalFlag)[1]', 'BIT');

                IF @CriticalFlag = 1
                BEGIN
                    INSERT INTO dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
                    VALUES ('LabResults', @PatientID, 'CRITICAL_LAB_NOTIFICATION',
                            'Critical lab result notification processed: ' + @TestName,
                            'ServiceBroker');
                END

                END CONVERSATION @ConversationHandle;
            END
            ELSE IF @MessageTypeName = N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
                END CONVERSATION @ConversationHandle;
            ELSE IF @MessageTypeName = N'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
                END CONVERSATION @ConversationHandle;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            INSERT INTO dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
            VALUES ('ServiceBroker', 0, 'ACTIVATION_ERROR', ERROR_MESSAGE(), 'ServiceBroker');

            BREAK;
        END CATCH
    END
END
GO

PRINT '   Created activation procedure: usp_ProcessLabNotifications';
GO

-- Enable activation on the lab notification queue
ALTER QUEUE dbo.LabNotificationQueue
WITH ACTIVATION (
    STATUS = ON,
    PROCEDURE_NAME = dbo.usp_ProcessLabNotifications,
    MAX_QUEUE_READERS = 2,
    EXECUTE AS SELF
);
GO
PRINT '   Activation enabled on LabNotificationQueue.';
GO

PRINT '   PatientDB Service Broker objects complete.';
GO

-- ============================================
-- PART 3: BillingDB Service Broker Objects
-- ============================================
PRINT '';
PRINT '>> Part 3: Creating BillingDB Service Broker objects...';
GO

USE BillingDB;
GO

-- ============================================
-- 3a: Message Types (must match PatientDB)
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = 'PatientEncounterMessage')
BEGIN
    CREATE MESSAGE TYPE [PatientEncounterMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT '   Created message type: PatientEncounterMessage (BillingDB)';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = 'PatientDischargeMessage')
BEGIN
    CREATE MESSAGE TYPE [PatientDischargeMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT '   Created message type: PatientDischargeMessage (BillingDB)';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = 'BillingResponseMessage')
BEGIN
    CREATE MESSAGE TYPE [BillingResponseMessage]
    VALIDATION = WELL_FORMED_XML;
    PRINT '   Created message type: BillingResponseMessage (BillingDB)';
END
GO

-- ============================================
-- 3b: Contract
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.service_contracts WHERE name = 'PatientBillingContract')
BEGIN
    CREATE CONTRACT [PatientBillingContract]
    (
        [PatientEncounterMessage] SENT BY INITIATOR,
        [PatientDischargeMessage] SENT BY INITIATOR,
        [BillingResponseMessage]  SENT BY TARGET
    );
    PRINT '   Created contract: PatientBillingContract (BillingDB)';
END
GO

-- ============================================
-- 3c: Queue
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.service_queues WHERE name = 'BillingEventReceiveQueue')
BEGIN
    CREATE QUEUE dbo.BillingEventReceiveQueue
    WITH
        STATUS = ON,
        RETENTION = OFF,
        POISON_MESSAGE_HANDLING (STATUS = ON);
    PRINT '   Created queue: BillingEventReceiveQueue';
END
GO

-- ============================================
-- 3d: Service
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.services WHERE name = 'BillingEventReceiveService')
BEGIN
    CREATE SERVICE [BillingEventReceiveService]
    ON QUEUE dbo.BillingEventReceiveQueue
    (
        [PatientBillingContract]
    );
    PRINT '   Created service: BillingEventReceiveService';
END
GO

-- ============================================
-- 3e: Billing Event Activation Procedure
-- ============================================
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_ProcessBillingEvents')
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
                DECLARE @EncounterID INT = @MessageBody.value('(/NewEncounter/EncounterID)[1]', 'INT');
                DECLARE @PatientID INT = @MessageBody.value('(/NewEncounter/PatientID)[1]', 'INT');
                DECLARE @EncounterType NVARCHAR(20) = @MessageBody.value('(/NewEncounter/EncounterType)[1]', 'NVARCHAR(20)');

                INSERT INTO dbo.BillingAudit (TableName, RecordID, Action, NewValues, ChangedBy)
                VALUES ('Encounters', @EncounterID, 'NEW_ENCOUNTER_RECEIVED',
                        'Encounter notification received via Service Broker. Patient: ' + CAST(@PatientID AS VARCHAR) +
                        ', Type: ' + @EncounterType,
                        'ServiceBroker');

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
                DECLARE @DischargeEncounterID INT = @MessageBody.value('(/PatientDischarge/EncounterID)[1]', 'INT');

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
                END CONVERSATION @ConversationHandle;
            ELSE IF @MessageTypeName = N'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
                END CONVERSATION @ConversationHandle;

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

PRINT '   Created activation procedure: usp_ProcessBillingEvents';
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
PRINT '   Activation enabled on BillingEventReceiveQueue.';
GO

PRINT '   BillingDB Service Broker objects complete.';
GO

-- ============================================
-- PART 4: Cross-Database Routes
-- Routes enable PatientDB and BillingDB to
-- communicate within the same MI instance.
-- ADDRESS = 'LOCAL' is used for same-instance routing.
-- ============================================
PRINT '';
PRINT '>> Part 4: Configuring cross-database routes...';
GO

USE PatientDB;
GO

IF NOT EXISTS (SELECT 1 FROM sys.routes WHERE name = 'BillingServiceRoute')
BEGIN
    CREATE ROUTE [BillingServiceRoute]
    WITH SERVICE_NAME = N'BillingEventReceiveService',
         ADDRESS = N'LOCAL';
    PRINT '   Created route: BillingServiceRoute (PatientDB -> BillingDB)';
END
ELSE PRINT '   Route BillingServiceRoute already exists.';
GO

USE BillingDB;
GO

IF NOT EXISTS (SELECT 1 FROM sys.routes WHERE name = 'PatientServiceRoute')
BEGIN
    CREATE ROUTE [PatientServiceRoute]
    WITH SERVICE_NAME = N'PatientEventSendService',
         ADDRESS = N'LOCAL';
    PRINT '   Created route: PatientServiceRoute (BillingDB -> PatientDB)';
END
ELSE PRINT '   Route PatientServiceRoute already exists.';
GO

-- ============================================
-- PART 5: Smoke test - send a test message
-- Verifies the cross-database path works on MI
-- ============================================
PRINT '';
PRINT '>> Part 5: Smoke test - sending a test message...';
GO

USE PatientDB;
GO

DECLARE @ConvHandle UNIQUEIDENTIFIER;
DECLARE @TestMessage XML = N'<NewEncounter>
    <EncounterID>99999</EncounterID>
    <PatientID>10001</PatientID>
    <EncounterType>TEST</EncounterType>
    <AdmitDate>2026-04-16T00:00:00</AdmitDate>
</NewEncounter>';

BEGIN TRY
    BEGIN DIALOG CONVERSATION @ConvHandle
        FROM SERVICE [PatientEventSendService]
        TO SERVICE N'BillingEventReceiveService'
        ON CONTRACT [PatientBillingContract]
        WITH ENCRYPTION = OFF;

    SEND ON CONVERSATION @ConvHandle
        MESSAGE TYPE [PatientEncounterMessage] (@TestMessage);

    PRINT '   Test message sent on conversation: ' + CAST(@ConvHandle AS NVARCHAR(50));
    PRINT '   Check BillingDB.dbo.BillingEventReceiveQueue for message arrival.';
END TRY
BEGIN CATCH
    PRINT '   WARNING: Smoke test failed: ' + ERROR_MESSAGE();
    PRINT '   This may be expected if Service Broker was just enabled.';
    PRINT '   Retry after the broker is fully initialized.';
END CATCH
GO

-- Verify the message was sent
SELECT 'PatientDB Send Queue' AS QueueName,
       COUNT(*) AS MessageCount
FROM dbo.PatientEventSendQueue WITH (NOLOCK);
GO

-- Check if message arrived in BillingDB
USE BillingDB;
GO

WAITFOR DELAY '00:00:02';

SELECT 'BillingDB Receive Queue' AS QueueName,
       COUNT(*) AS MessageCount
FROM dbo.BillingEventReceiveQueue WITH (NOLOCK);
GO

-- ============================================
-- PART 6: Document Service Broker configuration
-- ============================================
PRINT '';
PRINT '>> Part 6: Service Broker configuration summary...';
GO

USE PatientDB;
GO

PRINT '--- PatientDB Objects ---';
SELECT 'Message Types' AS ObjectType, name AS ObjectName
FROM sys.service_message_types WHERE is_default = 0
UNION ALL
SELECT 'Contracts', name
FROM sys.service_contracts WHERE is_default = 0
UNION ALL
SELECT 'Queues', name
FROM sys.service_queues WHERE is_ms_shipped = 0
UNION ALL
SELECT 'Services', name
FROM sys.services WHERE is_ms_shipped = 0
UNION ALL
SELECT 'Routes', name
FROM sys.routes WHERE name <> 'AutoCreatedLocal'
ORDER BY ObjectType, ObjectName;
GO

USE BillingDB;
GO

PRINT '--- BillingDB Objects ---';
SELECT 'Message Types' AS ObjectType, name AS ObjectName
FROM sys.service_message_types WHERE is_default = 0
UNION ALL
SELECT 'Contracts', name
FROM sys.service_contracts WHERE is_default = 0
UNION ALL
SELECT 'Queues', name
FROM sys.service_queues WHERE is_ms_shipped = 0
UNION ALL
SELECT 'Services', name
FROM sys.services WHERE is_ms_shipped = 0
UNION ALL
SELECT 'Routes', name
FROM sys.routes WHERE name <> 'AutoCreatedLocal'
ORDER BY ObjectType, ObjectName;
GO

PRINT '';
PRINT '============================================';
PRINT ' Service Broker Migration Complete';
PRINT ' Finished: ' + CONVERT(VARCHAR(30), GETDATE(), 121);
PRINT '============================================';
GO
