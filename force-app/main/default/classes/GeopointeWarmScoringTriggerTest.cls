@isTest
public class GeopointeWarmScoringTriggerTest {
    @TestSetup
    static void setup() {
        TriggerHandler.disableAllGPTriggers = true;
        insert new Lead(FirstName = 'Trigger', LastName = 'Warm', Company = 'Trigger Corp', Status = 'Open - Not Contacted');
    }

    private static String getConvertedStatus() {
        for (LeadStatus ls : [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1]) {
            return ls.MasterLabel;
        }
        return 'Closed - Converted';
    }

    @isTest
    static void testConversionSchedulesWarmScoringJob() {
        // Disable the geocoding trigger but allow the scoring trigger to fire.
        // We selectively re-enable by not disabling the GP triggers flag here.
        Lead lead = [SELECT Id FROM Lead LIMIT 1];

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead.Id);
        lc.setConvertedStatus(getConvertedStatus());
        lc.setDoNotCreateOpportunity(true);

        Test.startTest();
        // Temporarily enable triggers so GeopointeWarmScoringTrigger fires
        TriggerHandler.disableAllGPTriggers = false;
        Database.convertLead(lc);
        TriggerHandler.disableAllGPTriggers = true;
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :('GP_WarmScore_' + lead.Id + '%')
        ];

        System.assertEquals(1, jobs.size(), 'Exactly one warm scoring job should be scheduled for the converted lead');

        DateTime expectedFireTime = DateTime.now().addHours(12);
        Long diffMs = Math.abs(jobs[0].NextFireTime.getTime() - expectedFireTime.getTime());
        System.assert(
            diffMs < 60000,
            'NextFireTime should be within 60 seconds of 12 hours from now, but was ' + diffMs + 'ms off'
        );
    }
}
