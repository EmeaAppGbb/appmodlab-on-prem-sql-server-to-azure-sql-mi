-- ============================================
-- SQL Agent Job: Nightly Billing Batch
-- Lakeview Medical Center
-- Runs nightly at 2:00 AM
-- ============================================
USE msdb;
GO

-- Delete existing job
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'LMC - Nightly Billing Batch')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Nightly Billing Batch', @delete_unused_schedule = 1;
END
GO

-- Create job
DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Nightly Billing Batch',
    @enabled = 1,
    @notify_level_eventlog = 2,
    @notify_level_email = 2,
    @notify_level_page = 0,
    @delete_level = 0,
    @description = N'Processes nightly billing batch: posts room charges, creates insurance claims for discharged encounters, submits pending claims, and generates patient invoices.',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Step 1: Post daily room charges and process encounter charges
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Nightly Billing Batch',
    @step_name = N'Execute Nightly Billing Batch',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'EXEC BillingDB.dbo.usp_BatchNightlyBilling;',
    @database_name = N'BillingDB',
    @retry_attempts = 2,
    @retry_interval = 5,
    @on_success_action = 2,  -- Go to next step
    @on_fail_action = 2;     -- Go to next step (log error but continue)

-- Step 2: Update encounter totals in PatientDB
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Nightly Billing Batch',
    @step_name = N'Reconcile Encounter Totals',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        -- Reconcile total charges between BillingDB and PatientDB
        UPDATE e
        SET e.TotalCharges = ISNULL(bc.TotalCharges, 0),
            e.TotalPayments = ISNULL(py.TotalPayments, 0),
            e.PatientBalance = ISNULL(bc.TotalCharges, 0) - ISNULL(py.TotalPayments, 0),
            e.ModifiedDate = GETDATE()
        FROM PatientDB.dbo.Encounters e
        OUTER APPLY (
            SELECT SUM(ChargeAmount - AdjustmentAmount) AS TotalCharges
            FROM BillingDB.dbo.BillingCharges b
            WHERE b.EncounterID = e.EncounterID AND b.ChargeStatus <> ''VOIDED''
        ) bc
        OUTER APPLY (
            SELECT SUM(PaymentAmount) AS TotalPayments
            FROM BillingDB.dbo.Payments p
            WHERE p.EncounterID = e.EncounterID AND p.PaymentStatus <> ''VOIDED''
        ) py
        WHERE e.EncounterStatus IN (''ACTIVE'', ''DISCHARGED'')
          AND e.AdmitDate >= DATEADD(YEAR, -1, GETDATE());
        
        PRINT ''Encounter totals reconciled: '' + CAST(@@ROWCOUNT AS VARCHAR) + '' encounters updated.'';
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 3: Send payment plan reminders
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Nightly Billing Batch',
    @step_name = N'Process Payment Plan Reminders',
    @step_id = 3,
    @subsystem = N'TSQL',
    @command = N'
        -- Flag overdue payment plans
        UPDATE BillingDB.dbo.PaymentPlans
        SET PlanStatus = ''DEFAULTED'',
            DefaultedDate = GETDATE(),
            ModifiedDate = GETDATE()
        WHERE PlanStatus = ''ACTIVE''
          AND NextPaymentDate < DATEADD(DAY, -60, GETDATE());
        
        PRINT ''Defaulted payment plans: '' + CAST(@@ROWCOUNT AS VARCHAR);
        
        -- Send overdue invoices to collections (over 120 days)
        UPDATE BillingDB.dbo.Invoices
        SET InvoiceStatus = ''COLLECTIONS'',
            SentToCollections = 1,
            CollectionDate = GETDATE(),
            ModifiedDate = GETDATE()
        WHERE InvoiceStatus = ''OPEN''
          AND DATEDIFF(DAY, DueDate, GETDATE()) > 120
          AND TotalAmount - PaidAmount > 50.00;  -- Only if balance > $50
        
        PRINT ''Invoices sent to collections: '' + CAST(@@ROWCOUNT AS VARCHAR);
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 0,
    @retry_interval = 0,
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2;     -- Go to next step

-- Schedule: Every day at 2:00 AM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Nightly Billing Batch',
    @name = N'Nightly at 2AM',
    @enabled = 1,
    @freq_type = 4,          -- Daily
    @freq_interval = 1,
    @active_start_time = 020000;  -- 2:00 AM

PRINT 'SQL Agent Job "LMC - Nightly Billing Batch" created.';
GO
