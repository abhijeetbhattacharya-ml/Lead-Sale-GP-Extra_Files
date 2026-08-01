public class GeopointeColdScoringJob implements Queueable, Database.AllowsCallouts {
    private Set<Id> leadIds;

    public GeopointeColdScoringJob(Set<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public void execute(QueueableContext ctx) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        Id leadId = (new List<Id>(leadIds))[0];
        leadIds.remove(leadId);

        try {
            Lead lead = [
                SELECT
                    Id, CreatedDate, LeadSource, Industry, Country, State,
                    AnnualRevenue, NumberOfEmployees, Salesforce_Edition__c,
                    Salesforce_Seats__c, Employee_Range__c, Job_Function__c,
                    Job_Level__c, Role_Formula__c, Lead_Category__c
                FROM Lead
                WHERE Id = :leadId
            ];

            Map<String, Object> leadMap = new Map<String, Object>{
                'Id' => String.valueOf(lead.Id),
                'CreatedDate' => lead.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
                'LeadSource' => lead.LeadSource,
                'Industry' => lead.Industry,
                'Country' => lead.Country,
                'State' => lead.State,
                'AnnualRevenue' => lead.AnnualRevenue,
                'NumberOfEmployees' => lead.NumberOfEmployees,
                'Salesforce_Edition__c' => lead.Salesforce_Edition__c,
                'Salesforce_Seats__c' => lead.Salesforce_Seats__c,
                'Employee_Range__c' => lead.Employee_Range__c,
                'Job_Function__c' => lead.Job_Function__c,
                'Job_Level__c' => lead.Job_Level__c,
                'Role_Formula__c' => lead.Role_Formula__c,
                'Lead_Category__c' => lead.Lead_Category__c
            };

            String requestBody = JSON.serialize(new Map<String, Object>{ 'lead' => leadMap });

            // HTTP callout delegated to PredictionAPIService which handles
            // endpoint URL (environment-aware via Utils.PREDICTION_API_URL_*),
            // authentication (x-ascent-cloud-api-token via Utils.platformToken()),
            // and Content-Type header. See PredictionAPIService.cls.
            HttpResponse res = PredictionAPIService.scoreCold(requestBody, 30000);

            if (res.getStatusCode() == 200) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Integer coldScore = Integer.valueOf(String.valueOf(parsed.get('cold_score')));
                update new Lead(
                    Id = leadId,
                    GP_Cold_Score__c = coldScore,
                    GP_Cold_Score_Date__c = DateTime.now()
                );
            } else {
                logError(leadId, null, 'Model1', 'HTTP ' + res.getStatusCode() + ': ' + res.getBody());
            }
        } catch (Exception e) {
            logError(leadId, null, 'Model1', e.getMessage());
        }

        chainIfNeeded();
    }

    private void chainIfNeeded() {
        // In test context, Salesforce disallows Queueable chaining beyond
        // one level inside Test.startTest()/stopTest(). Guard prevents
        // AsyncException: Maximum stack depth in tests. Production behavior
        // is unchanged — chaining works normally across async boundaries.
        if (!leadIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new GeopointeColdScoringJob(leadIds));
        }
    }

    private static void logError(Id leadId, Id accountId, String model, String message) {
        try {
            insert new GP_Scoring_Error__c(
                Lead_ID__c = String.valueOf(leadId),
                Account_ID__c = accountId != null ? String.valueOf(accountId) : null,
                Model__c = model,
                Error_Message__c = message,
                Error_Timestamp__c = DateTime.now()
            );
        } catch (Exception e) {
            // Swallow — error logging must never affect the Lead record
        }
    }
}
