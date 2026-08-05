public class GeopointeWarmScoringJob implements Queueable, Database.AllowsCallouts {
    private Set<Id> leadIds;

    public GeopointeWarmScoringJob(Set<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public void execute(QueueableContext ctx) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        Id leadId = (new List<Id>(leadIds))[0];
        leadIds.remove(leadId);

        Id convertedAccountId;
        try {
            Lead lead = [
                SELECT
                    Id, CreatedDate, ConvertedDate, ConvertedAccountId,
                    LeadSource, Industry, Country, State, AnnualRevenue,
                    NumberOfEmployees, Salesforce_Edition__c, Salesforce_Seats__c,
                    Employee_Range__c, Job_Function__c, Job_Level__c,
                    Role_Formula__c, Lead_Category__c
                FROM Lead
                WHERE Id = :leadId
            ];

            if (lead.ConvertedAccountId == null) {
                logError(leadId, null, 'Model2', 'ConvertedAccountId null on Lead: ' + leadId);
                chainIfNeeded();
                return;
            }

            convertedAccountId = lead.ConvertedAccountId;

            // FIELD NAME ADAPTER: queries real Salesforce production
            // field names; sends them to the API under the contract
            // names that schemas.py and account_features.py expect.
            // Verified against account_cleaned.parquet (AppFlow
            // extract from production org, 73,971 accounts):
            //   Number_of_Sales_Employees__c ✓ (Sales_Team_Size__c absent)
            //   Total_ARR_Geopointe__c ✓ (Total_GeoPointe_ARR__c absent)
            //   ARR_Geopointe__c ✓ (ARR_GP__c absent)
            //   ARR_LevelEleven__c ✓ (ARR_L11__c absent)
            //   ARR_Licensed_Users_Geopointe__c ✓ (Licensed_Users_GP__c absent)
            //   ARR_Licensed_Assignment_Areas__c ✓ (Licensed_Areas__c absent)
            //   Zoom_Clean_SIC_Codes__c preferred (Sic: 68.7% null in prod)
            //   Zoom_Clean_NAICS_Codes__c preferred (NAICS_Code__c: 77.5% null)
            Account acct = [
                SELECT
                    Id, Status__c, Type, BillingCountry, BillingState, Industry,
                    AnnualRevenue, NumberOfEmployees, Employee_Range__c,
                    Secondary_Industry__c, AccountSource, Number_of_Sales_Employees__c,
                    Current_ARR__c, Total_ARR_Geopointe__c, ARR_Geopointe__c, ARR_LevelEleven__c,
                    ARR_Licensed_Users_Geopointe__c, ARR_Licensed_Assignment_Areas__c, Zoom_Clean_SIC_Codes__c, Zoom_Clean_NAICS_Codes__c,
                    CreatedDate, LastActivityDate, Zoom_Clean_Technology_Products__c
                FROM Account
                WHERE Id = :convertedAccountId
            ];

            List<Opportunity> opps = [
                SELECT Id, IsWon, IsClosed, CloseDate, Amount
                FROM Opportunity
                WHERE AccountId = :convertedAccountId
            ];

            String leadCreatedDate = lead.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            String leadConvertedDate = lead.ConvertedDate != null ? String.valueOf(lead.ConvertedDate) : null;
            String acctCreatedDate = acct.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            String acctLastActivityDate = acct.LastActivityDate != null ? String.valueOf(acct.LastActivityDate) : null;

            Map<String, Object> leadMap = new Map<String, Object>{
                'Id' => String.valueOf(lead.Id),
                'CreatedDate' => leadCreatedDate,
                'ConvertedDate' => leadConvertedDate,
                'ConvertedAccountId' => String.valueOf(lead.ConvertedAccountId),
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

            Map<String, Object> acctMap = new Map<String, Object>{
                'Id' => String.valueOf(acct.Id),
                'Status__c' => acct.Status__c,
                'Type' => acct.Type,
                'BillingCountry' => acct.BillingCountry,
                'BillingState' => acct.BillingState,
                'Industry' => acct.Industry,
                'AnnualRevenue' => acct.AnnualRevenue,
                'NumberOfEmployees' => acct.NumberOfEmployees,
                'Employee_Range__c' => acct.Employee_Range__c,
                'Secondary_Industry__c' => acct.Secondary_Industry__c,
                'AccountSource' => acct.AccountSource,
                'Sales_Team_Size__c' => acct.Number_of_Sales_Employees__c,
                'Current_ARR__c' => acct.Current_ARR__c,
                'Total_GeoPointe_ARR__c' => acct.Total_ARR_Geopointe__c,
                'ARR_GP__c' => acct.ARR_Geopointe__c,
                'ARR_L11__c' => acct.ARR_LevelEleven__c,
                'Licensed_Users_GP__c' => acct.ARR_Licensed_Users_Geopointe__c,
                'Licensed_Areas__c' => acct.ARR_Licensed_Assignment_Areas__c,
                'Sic' => acct.Zoom_Clean_SIC_Codes__c,
                'NAICS_Code__c' => acct.Zoom_Clean_NAICS_Codes__c,
                'CreatedDate' => acctCreatedDate,
                'LastActivityDate' => acctLastActivityDate,
                'Zoom_Clean_Technology_Products__c' => acct.Zoom_Clean_Technology_Products__c
            };

            List<Map<String, Object>> oppsList = new List<Map<String, Object>>();
            for (Opportunity opp : opps) {
                oppsList.add(new Map<String, Object>{
                    'Id' => String.valueOf(opp.Id),
                    'IsWon' => opp.IsWon,
                    'IsClosed' => opp.IsClosed,
                    'CloseDate' => opp.CloseDate != null ? String.valueOf(opp.CloseDate) : null,
                    'Amount' => opp.Amount
                });
            }

            String requestBody = JSON.serialize(new Map<String, Object>{
                'lead' => leadMap,
                'account' => acctMap,
                'opportunities' => oppsList
            });

            // HTTP callout delegated to PredictionAPIService which handles
            // endpoint URL (environment-aware via Utils.PREDICTION_API_URL_*),
            // authentication (x-ascent-cloud-api-token via Utils.platformToken()),
            // and Content-Type header. See PredictionAPIService.cls.
            HttpResponse res = PredictionAPIService.scoreWarm(requestBody, 30000);

            if (res.getStatusCode() == 200) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Integer warmScore = Integer.valueOf(String.valueOf(parsed.get('warm_score')));
                DateTime scoredAt = DateTime.now();

                update new Lead(
                    Id = leadId,
                    GP_Warm_Score__c = warmScore,
                    GP_Warm_Score_Date__c = scoredAt
                );

                update new Account(
                    Id = convertedAccountId,
                    GP_Warm_Score__c = warmScore,
                    GP_Warm_Score_Date__c = scoredAt
                );
            } else {
                logError(leadId, convertedAccountId, 'Model2', 'HTTP ' + res.getStatusCode() + ': ' + res.getBody());
            }
        } catch (Exception e) {
            logError(leadId, convertedAccountId, 'Model2', e.getMessage());
        }

        chainIfNeeded();
    }

    private void chainIfNeeded() {
        // In test context, Salesforce disallows Queueable chaining beyond
        // one level inside Test.startTest()/stopTest(). Guard prevents
        // AsyncException: Maximum stack depth in tests. Production behavior
        // is unchanged — chaining works normally across async boundaries.
        if (!leadIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new GeopointeWarmScoringJob(leadIds));
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
            // Swallow — error logging must never affect the Lead or Account record
        }
    }
}
