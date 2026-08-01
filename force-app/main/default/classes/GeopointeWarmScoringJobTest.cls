@isTest
public class GeopointeWarmScoringJobTest {
    private static final String WARM_SCORE_SUCCESS_BODY = JSON.serialize(new Map<String, Object>{
        'warm_score' => 85,
        'profile_found' => true,
        'model_version' => 'v1.0',
        'scoring_timestamp' => '2024-01-01T00:00:00.000Z'
    });

    @TestSetup
    static void setup() {
        TriggerHandler.disableAllGPTriggers = true;
        insert new Lead(FirstName = 'Warm', LastName = 'Scoring', Company = 'Acme Corp', Status = 'Open - Not Contacted');
    }

    private static Lead getConvertedLead() {
        TriggerHandler.disableAllGPTriggers = true;
        Lead lead = [SELECT Id FROM Lead LIMIT 1];
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead.Id);
        lc.setConvertedStatus(getConvertedStatus());
        lc.setDoNotCreateOpportunity(false);
        Database.convertLead(lc);
        return [SELECT Id, ConvertedAccountId FROM Lead WHERE Id = :lead.Id];
    }

    private static String getConvertedStatus() {
        for (LeadStatus ls : [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1]) {
            return ls.MasterLabel;
        }
        return 'Closed - Converted';
    }

    @isTest
    static void testHappyPath() {
        TestUtils.initOrgMetaDataForTests();
        TriggerHandler.disableAllGPTriggers = true;
        Lead converted = getConvertedLead();
        System.assertNotEquals(null, converted.ConvertedAccountId, 'Lead should have a ConvertedAccountId');

        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, 'OK', new Map<String, String>(), WARM_SCORE_SUCCESS_BODY));

        Test.startTest();
        System.enqueueJob(new GeopointeWarmScoringJob(new Set<Id>{ converted.Id }));
        Test.stopTest();

        Lead resultLead = [SELECT GP_Warm_Score__c, GP_Warm_Score_Date__c FROM Lead WHERE Id = :converted.Id];
        System.assertEquals(85, resultLead.GP_Warm_Score__c.intValue(), 'Lead GP_Warm_Score__c should be 85');
        System.assertNotEquals(null, resultLead.GP_Warm_Score_Date__c, 'Lead GP_Warm_Score_Date__c should be populated');

        Account resultAcct = [SELECT GP_Warm_Score__c, GP_Warm_Score_Date__c FROM Account WHERE Id = :converted.ConvertedAccountId];
        System.assertEquals(85, resultAcct.GP_Warm_Score__c.intValue(), 'Account GP_Warm_Score__c should be 85');
        System.assertNotEquals(null, resultAcct.GP_Warm_Score_Date__c, 'Account GP_Warm_Score_Date__c should be populated');
    }

    @isTest
    static void testHttpError() {
        TestUtils.initOrgMetaDataForTests();
        TriggerHandler.disableAllGPTriggers = true;
        Lead converted = getConvertedLead();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(500, 'Internal Server Error', new Map<String, String>(), 'Service unavailable'));

        Test.startTest();
        System.enqueueJob(new GeopointeWarmScoringJob(new Set<Id>{ converted.Id }));
        Test.stopTest();

        Lead resultLead = [SELECT GP_Warm_Score__c FROM Lead WHERE Id = :converted.Id];
        System.assertEquals(null, resultLead.GP_Warm_Score__c, 'No score should be written on HTTP 500');

        List<GP_Scoring_Error__c> errors = [SELECT Model__c, Error_Message__c FROM GP_Scoring_Error__c];
        System.assertEquals(1, errors.size(), 'One error record should be created');
        System.assertEquals('Model2', errors[0].Model__c, 'Model should be Model2');
        System.assert(errors[0].Error_Message__c.contains('HTTP 500'), 'Error message should contain HTTP status');
    }

    @isTest
    static void testCalloutException() {
        TestUtils.initOrgMetaDataForTests();
        TriggerHandler.disableAllGPTriggers = true;
        Lead converted = getConvertedLead();
        Test.setMock(HttpCalloutMock.class, new CalloutExceptionMock());

        Test.startTest();
        System.enqueueJob(new GeopointeWarmScoringJob(new Set<Id>{ converted.Id }));
        Test.stopTest();

        Lead resultLead = [SELECT GP_Warm_Score__c FROM Lead WHERE Id = :converted.Id];
        System.assertEquals(null, resultLead.GP_Warm_Score__c, 'No score should be written when callout throws');

        List<GP_Scoring_Error__c> errors = [SELECT Model__c FROM GP_Scoring_Error__c];
        System.assertEquals(1, errors.size(), 'One error record should be created');
        System.assertEquals('Model2', errors[0].Model__c, 'Model should be Model2');
    }

    @isTest
    static void testNullConvertedAccountId() {
        TestUtils.initOrgMetaDataForTests();
        TriggerHandler.disableAllGPTriggers = true;
        // Insert a fresh unconverted lead and use its Id directly —
        // we cannot set ConvertedAccountId manually, but the job guards against null.
        Lead raw = new Lead(FirstName = 'Null', LastName = 'Account', Company = 'Ghost Co', Status = 'Open - Not Contacted');
        insert raw;

        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, 'OK', new Map<String, String>(), WARM_SCORE_SUCCESS_BODY));

        Test.startTest();
        System.enqueueJob(new GeopointeWarmScoringJob(new Set<Id>{ raw.Id }));
        Test.stopTest();

        List<GP_Scoring_Error__c> errors = [SELECT Model__c, Error_Message__c FROM GP_Scoring_Error__c];
        System.assertEquals(1, errors.size(), 'One error record should be created for null ConvertedAccountId');
        System.assertEquals('Model2', errors[0].Model__c, 'Model should be Model2');
        System.assert(
            errors[0].Error_Message__c.contains('ConvertedAccountId null'),
            'Error message should mention ConvertedAccountId null'
        );
    }

    private class CalloutExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Connection refused');
        }
    }
}
