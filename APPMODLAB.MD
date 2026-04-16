---
title: "SQL Server to Azure SQL MI"
description: "Migrate on-premises SQL Server databases to Azure SQL Managed Instance with minimal downtime using Azure DMS"
authors: ["marconsilva"]
category: "Data Modernization"
industry: "Healthcare & Life Sciences"
services: ["Azure SQL Managed Instance", "Azure Database Migration Service"]
languages: ["SQL", "T-SQL", "C#"]
frameworks: [".NET"]
modernizationTools: ["Azure Migrate", "Data Migration Assistant"]
agenticTools: []
tags: ["sql-server", "managed-instance", "database-migration", "dms", "clr", "service-broker"]
extensions: ["github.copilot"]
thumbnail: "assets/screenshots/00-lab-architecture-overview.html"
video: ""
version: "1.0.0"
---

## Lab Architecture

The architecture overview shows the 4-database Lakeview Medical system with 30 tables, migration blockers, and MI compatibility assessment.

[View: Architecture Overview](assets/screenshots/00-lab-architecture-overview.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Legacy Database Analysis

### Patient Tables Schema

The PatientDB contains 16 tables with legacy patterns including TEXT columns, unencrypted SSN fields, and denormalized addresses — all requiring remediation before migration to Managed Instance.

[View: PatientDB Tables Schema](assets/screenshots/01-patient-tables-schema.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

### Cross-Database Stored Procedures

BillingDB stored procedures execute cross-database queries to PatientDB using three-part names. This is a key migration blocker since Azure SQL MI does not support cross-database queries.

[View: Cross-Database Stored Procedures](assets/screenshots/02-cross-database-stored-procs.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

### CLR Assembly — Medical Calculations

The system uses C# .NET CLR functions for drug interaction checks, GFR calculations, and HL7 message parsing. CLR assemblies are supported on MI but require `PERMISSION_SET` adjustments.

[View: CLR Assembly Medical Calculations](assets/screenshots/03-clr-assembly-medical-calcs.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Migration Blockers

### Linked Servers Configuration

Four linked servers connect to external Pharmacy, Insurance, Lab, and Radiology PACS systems. Linked servers are not supported on Azure SQL MI and must be replaced with alternative connectivity patterns.

[View: Linked Servers Configuration](assets/screenshots/04-linked-servers-config.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

### Service Broker Messaging

Asynchronous messaging between PatientDB and BillingDB uses Service Broker with activation procedures. Service Broker is supported on MI within a single instance, but cross-instance messaging requires redesign.

[View: Service Broker Messaging](assets/screenshots/05-service-broker-messaging.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

### SQL Agent Jobs

Seven automated jobs handle billing cycles, claims processing, data archival, and backups, plus 4 monitoring alerts. SQL Agent is supported on MI with minor syntax differences.

[View: SQL Agent Jobs](assets/screenshots/06-sql-agent-jobs.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Lab Environment

### Docker Compose Setup

The lab runs in a 3-container Docker environment: a main SQL Server instance plus simulated pharmacy and insurance external systems for linked server testing.

[View: Docker Compose Environment](assets/screenshots/07-docker-compose-environment.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Screenshots

Visual walkthroughs of the lab's key database objects and migration challenges. Open the HTML files in a browser for syntax-highlighted, screenshot-ready views.

| # | Screenshot | Description |
|---|-----------|-------------|
| 0 | [Architecture Overview](assets/screenshots/00-lab-architecture-overview.html) | Dashboard showing 4 databases, 30 tables, migration blockers, and MI compatibility |
| 1 | [PatientDB Tables](assets/screenshots/01-patient-tables-schema.html) | 16-table schema with legacy patterns highlighted (TEXT columns, unencrypted SSN, denormalized addresses) |
| 2 | [Cross-Database Stored Procs](assets/screenshots/02-cross-database-stored-procs.html) | BillingDB procedures with cross-database queries to PatientDB — migration blocker |
| 3 | [CLR Assembly](assets/screenshots/03-clr-assembly-medical-calcs.html) | C# .NET CLR functions: drug interactions, GFR calculation, HL7 parser |
| 4 | [Linked Servers](assets/screenshots/04-linked-servers-config.html) | 4 linked servers (Pharmacy, Insurance, Lab, Radiology PACS) — not supported on MI |
| 5 | [Service Broker](assets/screenshots/05-service-broker-messaging.html) | Async messaging between PatientDB and BillingDB with activation procedures |
| 6 | [SQL Agent Jobs](assets/screenshots/06-sql-agent-jobs.html) | 7 automated jobs (billing, claims, archival, backups) + 4 monitoring alerts |
| 7 | [Docker Compose](assets/screenshots/07-docker-compose-environment.html) | 3-container lab environment: main SQL Server + pharmacy + insurance systems |
