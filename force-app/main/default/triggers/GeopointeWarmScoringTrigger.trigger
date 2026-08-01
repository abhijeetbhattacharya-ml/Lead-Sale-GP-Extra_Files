trigger GeopointeWarmScoringTrigger on Lead(after update) {
    new GeopointeWarmScoringTriggerHandler().run();
}
