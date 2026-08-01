global without sharing class GeopointeWarmScoringScheduler implements Schedulable {
    private Set<Id> leadIds;

    global GeopointeWarmScoringScheduler(Set<Id> leadIds) {
        this.leadIds = leadIds;
    }

    global void execute(SchedulableContext sc) {
        System.enqueueJob(new GeopointeWarmScoringJob(leadIds));
    }
}
