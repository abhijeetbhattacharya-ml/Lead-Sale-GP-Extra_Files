public class GeopointeColdScoringTriggerHandler extends TriggerHandler {
    protected override void afterInsert(List<SObject> newList) {
        Set<Id> leadIds = new Set<Id>();
        for (SObject record : newList) {
            leadIds.add(record.Id);
        }
        System.enqueueJob(new GeopointeColdScoringJob(leadIds));
    }
}
