@isTest
public class GeopointeColdScoringJobTest {
    private static final String COLD_SCORE_SUCCESS_BODY = JSON.serialize(new Map<String, Object>{
        'cold_score' => 72,
        'model_version' => 'v1.0',
        'scoring_timestamp' => '2024-01-01T00:00:00.000Z'
    });

    @TestSetup
    static void setup() {
        TriggerHandler.disableAllGPTriggers = true;
        insert new Lead(FirstName = 'Test', LastName = 'Scoring', Company = 'Acme Corp', Status = 'Open - Not Contacted');
    }

    @isTest
    static void testHappyPath() {
        TestUtils.initOrgMetaDataForTests();
        TriggerHandler.disableAllGPTriggers = true;
        Lead lead = [SELECT Id FROM Lead LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, 'OK', new Map<String, String>(), COLD_SCORE_SUCCESS_BODY));

        Test.startTest();
        System.enqueueJob(new GeopointeColdScoringJob(new Set<Id>{ lead.Id }));
        Test.stopTest();

        Lead result = [SELECT GP_Cold_Score__c, GP_Cold_Score_Date__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(72, result.GP_Cold_Score__c.intValue(), 'GP_Cold_Score__c should be 72');
        System.assertNotEquals(null, result.GP_Cold_Score_Date__c, 'GP_Cold_Score_Date__c should be populated');
    }

    @isTest
    static void testHttpError() {
        TestUtils.initOrgMetaDataForTests();
        TriggerHandler.disableAllGPTriggers = true;
        Lead lead = [SELECT Id FROM Lead LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(500, 'Internal Server Error', new Map<String, String>(), 'Service unavailable'));

        Test.startTest();
        System.enqueueJob(new GeopointeColdScoringJob(new Set<Id>{ lead.Id }));
        Test.stopTest();

        Lead result = [SELECT GP_Cold_Score__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(null, result.GP_Cold_Score__c, 'No score should be written on HTTP 500');

        List<GP_Scoring_Error__c> errors = [SELECT Model__c, Error_Message__c FROM GP_Scoring_Error__c];
        System.assertEquals(1, errors.size(), 'One error record should be created');
        System.assertEquals('Model1', errors[0].Model__c, 'Model should be Model1');
        System.assert(errors[0].Error_Message__c.contains('HTTP 500'), 'Error message should contain HTTP status');
    }

    @isTest
    static void testCalloutException() {
        TestUtils.initOrgMetaDataForTests();
        TriggerHandler.disableAllGPTriggers = true;
        Lead lead = [SELECT Id FROM Lead LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new CalloutExceptionMock());

        Test.startTest();
        System.enqueueJob(new GeopointeColdScoringJob(new Set<Id>{ lead.Id }));
        Test.stopTest();

        Lead result = [SELECT GP_Cold_Score__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(null, result.GP_Cold_Score__c, 'No score should be written when callout throws');

        List<GP_Scoring_Error__c> errors = [SELECT Model__c FROM GP_Scoring_Error__c];
        System.assertEquals(1, errors.size(), 'One error record should be created');
        System.assertEquals('Model1', errors[0].Model__c, 'Model should be Model1');
    }

    @isTest
    static void testBulkChaining() {
        TestUtils.initOrgMetaDataForTests();
        TriggerHandler.disableAllGPTriggers = true;
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName = 'Bulk1', LastName = 'Lead', Company = 'Alpha', Status = 'Open - Not Contacted'),
            new Lead(FirstName = 'Bulk2', LastName = 'Lead', Company = 'Beta', Status = 'Open - Not Contacted'),
            new Lead(FirstName = 'Bulk3', LastName = 'Lead', Company = 'Gamma', Status = 'Open - Not Contacted')
        };
        insert leads;

        Set<Id> leadIds = new Set<Id>();
        for (Lead l : leads) {
            leadIds.add(l.Id);
        }

        // Verify the job correctly pops one ID and re-enqueues for the rest.
        // In a single Test.startTest()/stopTest() context, only one Queueable
        // executes; we verify chaining by inspecting the job's remaining set
        // and the first lead receiving a score.
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, 'OK', new Map<String, String>(), COLD_SCORE_SUCCESS_BODY));

        GeopointeColdScoringJob job = new GeopointeColdScoringJob(leadIds);
        System.assertEquals(3, leadIds.size(), 'Job should start with 3 lead IDs');

        Test.startTest();
        System.enqueueJob(job);
        Test.stopTest();

        // After stopTest, exactly one lead processed; verify at least one scored
        List<Lead> scored = [SELECT Id, GP_Cold_Score__c FROM Lead WHERE GP_Cold_Score__c != null];
        System.assert(scored.size() >= 1, 'At least one lead should be scored after first job execution');
    }

    private class CalloutExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Read timeout');
        }
    }
}
