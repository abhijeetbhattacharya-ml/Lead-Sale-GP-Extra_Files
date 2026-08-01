@isTest
public class GeopointeWarmScoringSchedulerTest {
    @TestSetup
    static void setup() {
        TriggerHandler.disableAllGPTriggers = true;
        insert new Lead(FirstName = 'Scheduler', LastName = 'Test', Company = 'Scheduler Co', Status = 'Open - Not Contacted');
    }

    @isTest
    static void testExecuteEnqueuesWarmScoringJob() {
        TriggerHandler.disableAllGPTriggers = true;
        Lead lead = [SELECT Id FROM Lead LIMIT 1];
        Set<Id> leadIds = new Set<Id>{ lead.Id };

        // Mock so the enqueued GeopointeWarmScoringJob's callout doesn't fail
        Test.setMock(
            HttpCalloutMock.class,
            new MockHttpResponse(
                200, 'OK', new Map<String, String>(),
                JSON.serialize(new Map<String, Object>{
                    'warm_score' => 60,
                    'profile_found' => true,
                    'model_version' => 'v1.0',
                    'scoring_timestamp' => '2024-01-01T00:00:00.000Z'
                })
            )
        );

        Test.startTest();
        String cronExpr = '0 0 0 1 1 ? 2099';
        System.schedule('GP_SchedulerTest_' + System.currentTimeMillis(), cronExpr, new GeopointeWarmScoringScheduler(leadIds));
        Test.stopTest();

        // After stopTest the scheduler's execute() ran, which enqueued GeopointeWarmScoringJob.
        // The enqueued job also ran in the same stopTest (one level of chained async is processed).
        List<AsyncApexJob> jobs = [
            SELECT Id, ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'GeopointeWarmScoringJob'
        ];
        System.assert(jobs.size() >= 1, 'GeopointeWarmScoringJob should have been enqueued');
    }
}
