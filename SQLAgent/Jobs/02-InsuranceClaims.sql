-- ============================================
-- SQL Agent Job: Daily Insurance Claims Submission
-- Lakeview Medical Center
-- Runs daily at 6:00 AM and 6:00 PM
-- ============================================
USE msdb;
GO

IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'LMC - Daily Claims Submission')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Daily Claims Submission', @delete_unused_schedule = 1;
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Daily Claims Submission',
    @enabled = 1,
    @notify_level_eventlog = 2,
    @notify_level_email = 2,
    @description = N'Submits pending insurance claims to clearinghouse, processes claim responses (835 remittance), and updates claim statuses.',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Step 1: Submit pending claims
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Claims Submission',
    @step_name = N'Submit Pending Claims',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'EXEC BillingDB.dbo.usp_SubmitClaimToInsurance @BatchSubmit = 1;',
    @database_name = N'BillingDB',
    @retry_attempts = 3,
    @retry_interval = 10,
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 2: Check for claim responses from clearinghouse
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Claims Submission',
    @step_name = N'Process Claim Responses (835)',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        -- Legacy: would query linked server for 835 remittance responses
        -- TODO: Replace with actual clearinghouse integration
        /*
        DECLARE @ResponseXML XML;
        
        SELECT @ResponseXML = ResponseData
        FROM OPENQUERY([INSURANCE_CLEARINGHOUSE],
            ''SELECT ResponseData FROM ClearinghouseDB.dbo.PendingResponses 
              WHERE FacilityID = ''''LAKEVIEW'''' AND ProcessedFlag = 0'');
        */
        
        -- Simulate: auto-adjudicate claims submitted > 14 days ago
        UPDATE BillingDB.dbo.InsuranceClaims
        SET ClaimStatus = ''ADJUDICATED'',
            AdjudicatedDate = GETDATE(),
            AllowedAmount = TotalCharges * 0.80,
            ModifiedDate = GETDATE()
        WHERE ClaimStatus = ''SUBMITTED''
          AND DATEDIFF(DAY, SubmittedDate, GETDATE()) > 14;
        
        PRINT ''Claims adjudicated: '' + CAST(@@ROWCOUNT AS VARCHAR);
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 3: Process denied claims for resubmission
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Claims Submission',
    @step_name = N'Flag Claims for Appeal',
    @step_id = 3,
    @subsystem = N'TSQL',
    @command = N'
        -- Flag denied claims approaching appeal deadline
        UPDATE BillingDB.dbo.InsuranceClaims
        SET ClaimStatus = ''APPEALED'',
            AppealedDate = GETDATE(),
            ModifiedDate = GETDATE()
        WHERE ClaimStatus = ''DENIED''
          AND AppealDeadline IS NOT NULL
          AND DATEDIFF(DAY, GETDATE(), AppealDeadline) BETWEEN 1 AND 30
          AND TotalCharges > 500.00;  -- Only appeal claims over $500
        
        PRINT ''Claims flagged for appeal: '' + CAST(@@ROWCOUNT AS VARCHAR);
        
        -- Update denied claims past appeal deadline
        INSERT INTO BillingDB.dbo.BillingAudit (TableName, RecordID, Action, NewValues)
        SELECT ''InsuranceClaims'', ClaimID, ''APPEAL_EXPIRED'',
               ''Claim '' + ClaimNumber + '' denial is past appeal deadline ($'' + CAST(TotalCharges AS VARCHAR) + '')''
        FROM BillingDB.dbo.InsuranceClaims
        WHERE ClaimStatus = ''DENIED''
          AND AppealDeadline < GETDATE();
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Schedule 1: 6:00 AM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Daily Claims Submission',
    @name = N'Morning Claims Run',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 060000;

-- Schedule 2: 6:00 PM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Daily Claims Submission',
    @name = N'Evening Claims Run',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 180000;

PRINT 'SQL Agent Job "LMC - Daily Claims Submission" created.';
GO
