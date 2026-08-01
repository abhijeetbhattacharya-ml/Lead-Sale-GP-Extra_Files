# Geopointe ML Lead Scoring — Salesforce Integration

**Author:** Abhijeet Bhattacharya  
**Role:** Data Science Intern, Ascent Cloud  
**Mentor:** Mazen Mirza  
**Period:** Summer 2026  
**Repository context:** Geopointe is a Salesforce ISV field sales mapping tool built by Ascent Cloud

---

## What this is

This repository contains the Salesforce Apex integration 
for an end-to-end ML lead scoring system built for Geopointe. 
Two XGBoost models deployed on AWS ECS score Geopointe leads 
automatically — no manual action required from sales reps.

---

## How it works

```
New Lead created in Salesforce
        ↓
GeopointeColdScoringTrigger (after insert)
        ↓
GeopointeColdScoringJob (Queueable)
        ↓
Ascent Gateway → AWS ECS /v1/score/cold
        ↓
GP_Cold_Score__c written to Lead  ← within seconds
```
Lead converted to Account
↓
GeopointeWarmScoringTrigger (after update)
↓
GeopointeWarmScoringScheduler (12hr CRON delay)
↓
GeopointeWarmScoringJob (Queueable)
↓
Ascent Gateway → AWS ECS /v1/score/warm
↓
GP_Warm_Score__c written to Lead AND Account

---

## Files in this repo

### Apex Classes (9)

| File | Type | Purpose |
|------|------|---------|
| `GeopointeColdScoringJob.cls` | Queueable | Calls /v1/score/cold, writes cold score to Lead |
| `GeopointeColdScoringJobTest.cls` | Test | 4 tests: happy path, HTTP error, exception, bulk chaining |
| `GeopointeColdScoringTriggerHandler.cls` | TriggerHandler | Collects Lead IDs on insert, enqueues cold job |
| `GeopointeWarmScoringJob.cls` | Queueable | Queries Lead+Account+Opps, calls /v1/score/warm, writes to both |
| `GeopointeWarmScoringJobTest.cls` | Test | 4 tests: happy path, HTTP error, exception, null account guard |
| `GeopointeWarmScoringTriggerHandler.cls` | TriggerHandler | Detects IsConverted flip, schedules warm job |
| `GeopointeWarmScoringScheduler.cls` | Schedulable | 12-hour delay bridge before warm job executes |
| `GeopointeWarmScoringSchedulerTest.cls` | Test | 1 test: verifies scheduler enqueues the warm job |
| `GeopointeWarmScoringTriggerTest.cls` | Test | 1 test: verifies conversion triggers the scheduler |

**Total: 10 test methods · 100% mock-based callouts**

### Apex Triggers (2)

| File | Event | Notes |
|------|-------|-------|
| `GeopointeColdScoringTrigger.trigger` | Lead after insert | Thin trigger — zero business logic |
| `GeopointeWarmScoringTrigger.trigger` | Lead after update | Thin trigger — zero business logic |

### Custom Object

**`GP_Scoring_Error__c`** — Logs all failed scoring callouts

| Field | Type | Purpose |
|-------|------|---------|
| `Lead_ID__c` | Text(255) | Salesforce ID of the lead |
| `Account_ID__c` | Text(255) | Salesforce ID of the account |
| `Model__c` | Text(255) | "Model1" (cold) or "Model2" (warm) |
| `Error_Message__c` | LongTextArea | Full error message |
| `Error_Timestamp__c` | DateTime | When the error occurred |

### Custom Fields

**Lead (4 new fields):**
- `GP_Cold_Score__c` — Number(3,0) — cold score 0-100
- `GP_Warm_Score__c` — Number(3,0) — warm score 0-100
- `GP_Cold_Score_Date__c` — DateTime — when cold score was written
- `GP_Warm_Score_Date__c` — DateTime — when warm score was written

**Account (2 new fields):**
- `GP_Warm_Score__c` — Number(3,0) — warm score 0-100
- `GP_Warm_Score_Date__c` — DateTime — when warm score was written

### Scratch Org Stub Fields (19 files)

These 19 field files exist ONLY to allow Apex to compile 
in a fresh scratch org. The fields they define already exist 
in the Geopointe corporate org with production-quality definitions.

**Do NOT deploy these to the corporate org** — they are excluded 
via `.forceignore`. Deploying them would overwrite production 
field definitions.

- Lead stubs (7): Salesforce_Edition__c, Salesforce_Seats__c, 
  Employee_Range__c, Job_Function__c, Job_Level__c, 
  Role_Formula__c, Lead_Category__c
- Account stubs (12): Status__c, Employee_Range__c, 
  Secondary_Industry__c, Sales_Team_Size__c, Current_ARR__c, 
  Total_GeoPointe_ARR__c, ARR_GP__c, ARR_L11__c, 
  Licensed_Users_GP__c, Licensed_Areas__c, 
  NAICS_Code__c, Zoom_Clean_Technology_Products__c

---

## ML Model results (prediction-api repo)

| Metric | Cold Score (Model 1) | Warm Score (Model 2) |
|--------|---------------------|---------------------|
| Features | 30 (lead-level only) | 137 (lead + account + opps + profile) |
| ROC-AUC | 0.8276 | 0.9660 |
| PR-AUC | 0.5015 | 0.8901 |
| Top 10% precision | 57.8% | 94.5% |
| Lift at top 10% | 2.68× | 3.71× |
| Live cold score | 67 ✅ | — |
| Live warm score | — | 73 ✅ |

---

## Architecture dependencies

This Apex code depends on infrastructure added in PR #3892 
by Mazen Mirza:

- `PredictionAPIService.cls` — centralized HTTP client 
  (all callouts go through this)
- `Utils.platformToken()` — reads auth token from 
  `Geopointe_Setting__mdt.PLATFORM_DEV`
- `Utils.PREDICTION_API_URL_*` — environment-aware 
  endpoint URLs (Dev/Test/Staging/Production)

---

## Auth flow

Token is stored in `Geopointe_Setting__mdt.PLATFORM_DEV` 
(pre-existing Geopointe infrastructure). 
`PredictionAPIService` reads it via `Utils.platformToken()` 
and injects it as the `x-ascent-cloud-api-token` header 
on every callout. No Named Credential is required.

---

## Key design decisions

**Thin trigger pattern** — All Geopointe triggers contain 
zero business logic. One line calls the handler class.

**Queueable with chaining** — HTTP callouts must be async. 
Queueable supports chaining for bulk lead scoring. 
Chaining is guarded with `Test.isRunningTest()` to 
prevent `AsyncException` in test context.

**12-hour warm score delay** — `GeopointeWarmScoringScheduler` 
uses `System.schedule()` with a CRON expression. 
Queueable has no built-in delay mechanism.

**Historical leads unaffected** — Cold trigger is 
`after insert` only. Warm trigger requires 
`IsConverted` to flip from false→true. 
Neither fires retroactively on existing records.

---

## Related repositories

- `ascentcloud/prediction-api` — FastAPI service on AWS ECS 
  (the ML endpoint this Apex calls)
- `abhijeetbhattacharya-ml/Lead-Sale-Prob-GP-main` — 
  SageMaker training pipeline (XGBoost, feature engineering, 
  AppFlow data ingestion)

---

*Built during Data Science internship at Ascent Cloud, 
Summer 2026. Mentor: Mazen Mirza.*