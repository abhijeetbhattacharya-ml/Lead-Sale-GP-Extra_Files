public class GeopointeWarmScoringTriggerHandler extends TriggerHandler {
    protected override void afterUpdate(
        List<SObject> oldList,
        List<SObject> newList,
        Map<ID, SObject> newMap,
        Map<ID, SObject> oldMap
    ) {
        for (SObject newRecord : newList) {
            Lead newLead = (Lead) newRecord;
            Lead oldLead = (Lead) oldMap.get(newLead.Id);
            if (!oldLead.IsConverted && newLead.IsConverted) {
                DateTime schedTime = DateTime.now().addHours(12);
                String cronExpr =
                    schedTime.second() + ' ' +
                    schedTime.minute() + ' ' +
                    schedTime.hour() + ' ' +
                    schedTime.day() + ' ' +
                    schedTime.month() + ' ? ' +
                    schedTime.year();
                String jobName = 'GP_WarmScore_' + newLead.Id + '_' + System.currentTimeMillis();
                System.schedule(jobName, cronExpr, new GeopointeWarmScoringScheduler(new Set<Id>{ newLead.Id }));
            }
        }
    }
}
