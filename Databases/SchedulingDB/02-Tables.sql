-- ============================================
-- SchedulingDB Tables
-- Lakeview Medical Center
-- Legacy: cross-database references to PatientDB
-- ============================================
USE SchedulingDB;
GO

-- ============================================
-- Rooms
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Rooms') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Rooms (
        RoomID              INT IDENTITY(1,1) NOT NULL,
        RoomNumber          VARCHAR(10) NOT NULL,
        FloorNumber         INT NOT NULL,
        RoomType            VARCHAR(30) NOT NULL,               -- EXAM, OR, PROCEDURE, IMAGING, CONFERENCE, OFFICE
        DepartmentCode      VARCHAR(10) NULL,                   -- References PatientDB department
        Capacity            INT NOT NULL DEFAULT 1,
        HasOxygen           BIT NOT NULL DEFAULT 0,
        HasSuction          BIT NOT NULL DEFAULT 0,
        HasMonitoring       BIT NOT NULL DEFAULT 0,
        IsActive            BIT NOT NULL DEFAULT 1,
        Notes               NVARCHAR(500) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Rooms PRIMARY KEY CLUSTERED (RoomID),
        CONSTRAINT UQ_Rooms_Number UNIQUE (RoomNumber),
        CONSTRAINT CK_Rooms_Type CHECK (RoomType IN ('EXAM', 'OR', 'PROCEDURE', 'IMAGING', 'CONFERENCE', 'OFFICE', 'ICU', 'NICU', 'ED_BAY'))
    );
    PRINT 'Table dbo.Rooms created.';
END
GO

-- ============================================
-- Appointments
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Appointments') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Appointments (
        AppointmentID       INT IDENTITY(1,1) NOT NULL,
        PatientID           INT NOT NULL,                       -- References PatientDB.dbo.Patients (no FK cross-db)
        PhysicianID         INT NOT NULL,                       -- References PatientDB.dbo.Physicians
        AppointmentDate     DATE NOT NULL,
        StartTime           TIME NOT NULL,
        EndTime             TIME NOT NULL,
        Duration            INT NOT NULL DEFAULT 30,            -- minutes
        AppointmentType     VARCHAR(30) NOT NULL,               -- NEW_PATIENT, FOLLOW_UP, PROCEDURE, CONSULT, URGENT
        RoomID              INT NULL,
        DepartmentCode      VARCHAR(10) NULL,
        ReasonForVisit      NVARCHAR(500) NULL,
        -- Legacy: patient demographics cached locally (denormalized)
        PatientName         NVARCHAR(150) NULL,
        PatientPhone        VARCHAR(20) NULL,
        PatientDOB          DATE NULL,
        InsuranceVerified   BIT NOT NULL DEFAULT 0,
        PreAuthRequired     BIT NOT NULL DEFAULT 0,
        PreAuthNumber       VARCHAR(50) NULL,
        -- Status tracking
        AppointmentStatus   VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED',
        CheckedInDate       DATETIME NULL,
        CheckedInBy         NVARCHAR(100) NULL,
        RoomedDate          DATETIME NULL,
        SeenByProviderDate  DATETIME NULL,
        CheckedOutDate      DATETIME NULL,
        CancelledDate       DATETIME NULL,
        CancelledReason     NVARCHAR(500) NULL,
        NoShowIndicator     BIT NOT NULL DEFAULT 0,
        -- Recurrence (legacy: self-referencing for series)
        RecurrenceParentID  INT NULL,
        RecurrencePattern   VARCHAR(20) NULL,                   -- DAILY, WEEKLY, BIWEEKLY, MONTHLY
        RecurrenceEndDate   DATE NULL,
        -- Reminders
        ReminderSent        BIT NOT NULL DEFAULT 0,
        ReminderSentDate    DATETIME NULL,
        ConfirmedDate       DATETIME NULL,
        Comments            NVARCHAR(MAX) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        CreatedBy           NVARCHAR(100) NOT NULL DEFAULT SUSER_SNAME(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_Appointments PRIMARY KEY CLUSTERED (AppointmentID),
        CONSTRAINT FK_Appointments_Room FOREIGN KEY (RoomID) REFERENCES dbo.Rooms(RoomID),
        CONSTRAINT FK_Appointments_Recurrence FOREIGN KEY (RecurrenceParentID) REFERENCES dbo.Appointments(AppointmentID),
        CONSTRAINT CK_Appointments_Type CHECK (AppointmentType IN ('NEW_PATIENT', 'FOLLOW_UP', 'PROCEDURE', 'CONSULT', 'URGENT', 'TELEHEALTH', 'LAB', 'IMAGING')),
        CONSTRAINT CK_Appointments_Status CHECK (AppointmentStatus IN ('SCHEDULED', 'CONFIRMED', 'CHECKED_IN', 'ROOMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'NO_SHOW', 'RESCHEDULED'))
    );

    CREATE NONCLUSTERED INDEX IX_Appointments_Patient ON dbo.Appointments (PatientID, AppointmentDate);
    CREATE NONCLUSTERED INDEX IX_Appointments_Physician ON dbo.Appointments (PhysicianID, AppointmentDate, StartTime);
    CREATE NONCLUSTERED INDEX IX_Appointments_Date ON dbo.Appointments (AppointmentDate, AppointmentStatus) INCLUDE (PatientID, PhysicianID, StartTime, EndTime);
    CREATE NONCLUSTERED INDEX IX_Appointments_Room ON dbo.Appointments (RoomID, AppointmentDate, StartTime) WHERE RoomID IS NOT NULL;
    CREATE NONCLUSTERED INDEX IX_Appointments_Status ON dbo.Appointments (AppointmentStatus) INCLUDE (AppointmentDate, PatientID);

    PRINT 'Table dbo.Appointments created.';
END
GO

-- ============================================
-- RoomAssignments (inpatient room tracking)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.RoomAssignments') AND type = 'U')
BEGIN
    CREATE TABLE dbo.RoomAssignments (
        AssignmentID        INT IDENTITY(1,1) NOT NULL,
        EncounterID         INT NOT NULL,                       -- References PatientDB.dbo.Encounters
        PatientID           INT NOT NULL,
        RoomID              INT NOT NULL,
        BedNumber           VARCHAR(5) NULL,
        AssignedDate        DATETIME NOT NULL DEFAULT GETDATE(),
        ReleasedDate        DATETIME NULL,
        AssignmentStatus    VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        TransferReason      NVARCHAR(500) NULL,
        AssignedBy          NVARCHAR(100) NOT NULL DEFAULT SUSER_SNAME(),
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_RoomAssignments PRIMARY KEY CLUSTERED (AssignmentID),
        CONSTRAINT FK_RoomAssignments_Room FOREIGN KEY (RoomID) REFERENCES dbo.Rooms(RoomID),
        CONSTRAINT CK_RoomAssignments_Status CHECK (AssignmentStatus IN ('ACTIVE', 'TRANSFERRED', 'DISCHARGED', 'CANCELLED'))
    );

    CREATE NONCLUSTERED INDEX IX_RoomAssignments_Room ON dbo.RoomAssignments (RoomID, AssignmentStatus);
    CREATE NONCLUSTERED INDEX IX_RoomAssignments_Encounter ON dbo.RoomAssignments (EncounterID);

    PRINT 'Table dbo.RoomAssignments created.';
END
GO

-- ============================================
-- StaffSchedules
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.StaffSchedules') AND type = 'U')
BEGIN
    CREATE TABLE dbo.StaffSchedules (
        ScheduleID          INT IDENTITY(1,1) NOT NULL,
        StaffID             INT NOT NULL,                       -- References physician or nurse (cross-db to PatientDB)
        StaffType           VARCHAR(20) NOT NULL,               -- PHYSICIAN, NURSE, TECH, ADMIN
        ScheduleDate        DATE NOT NULL,
        ShiftStart          TIME NOT NULL,
        ShiftEnd            TIME NOT NULL,
        ShiftType           VARCHAR(20) NOT NULL,               -- DAY, EVENING, NIGHT, ON_CALL
        DepartmentCode      VARCHAR(10) NULL,
        IsOnCall            BIT NOT NULL DEFAULT 0,
        IsOvertime          BIT NOT NULL DEFAULT 0,
        ScheduleStatus      VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED',
        SwapRequestedWith   INT NULL,
        Comments            NVARCHAR(500) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        ModifiedDate        DATETIME NULL,
        CONSTRAINT PK_StaffSchedules PRIMARY KEY CLUSTERED (ScheduleID),
        CONSTRAINT CK_StaffSchedules_ShiftType CHECK (ShiftType IN ('DAY', 'EVENING', 'NIGHT', 'ON_CALL', 'SPLIT')),
        CONSTRAINT CK_StaffSchedules_Status CHECK (ScheduleStatus IN ('SCHEDULED', 'CONFIRMED', 'CANCELLED', 'CALLED_OFF', 'SWAPPED'))
    );

    CREATE NONCLUSTERED INDEX IX_StaffSchedules_Staff ON dbo.StaffSchedules (StaffID, ScheduleDate);
    CREATE NONCLUSTERED INDEX IX_StaffSchedules_Date ON dbo.StaffSchedules (ScheduleDate, DepartmentCode) INCLUDE (StaffID, ShiftStart, ShiftEnd);

    PRINT 'Table dbo.StaffSchedules created.';
END
GO

-- ============================================
-- WaitingList
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.WaitingList') AND type = 'U')
BEGIN
    CREATE TABLE dbo.WaitingList (
        WaitListID          INT IDENTITY(1,1) NOT NULL,
        PatientID           INT NOT NULL,
        PhysicianID         INT NULL,
        RequestedDate       DATE NULL,
        PreferredTimeSlot   VARCHAR(20) NULL,                   -- MORNING, AFTERNOON, ANY
        AppointmentType     VARCHAR(30) NOT NULL,
        Priority            INT NOT NULL DEFAULT 5,             -- 1=highest, 10=lowest
        ReasonForVisit      NVARCHAR(500) NULL,
        WaitListStatus      VARCHAR(20) NOT NULL DEFAULT 'WAITING',
        AddedDate           DATETIME NOT NULL DEFAULT GETDATE(),
        NotifiedDate        DATETIME NULL,
        ScheduledAppointmentID INT NULL,
        Comments            NVARCHAR(500) NULL,
        CreatedDate         DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_WaitingList PRIMARY KEY CLUSTERED (WaitListID),
        CONSTRAINT FK_WaitingList_Appointment FOREIGN KEY (ScheduledAppointmentID) REFERENCES dbo.Appointments(AppointmentID),
        CONSTRAINT CK_WaitingList_Status CHECK (WaitListStatus IN ('WAITING', 'NOTIFIED', 'SCHEDULED', 'CANCELLED', 'EXPIRED'))
    );

    CREATE NONCLUSTERED INDEX IX_WaitingList_Patient ON dbo.WaitingList (PatientID, WaitListStatus);
    CREATE NONCLUSTERED INDEX IX_WaitingList_Status ON dbo.WaitingList (WaitListStatus, Priority, AddedDate);

    PRINT 'Table dbo.WaitingList created.';
END
GO

PRINT '========================================';
PRINT 'All SchedulingDB tables created.';
PRINT '========================================';
GO
