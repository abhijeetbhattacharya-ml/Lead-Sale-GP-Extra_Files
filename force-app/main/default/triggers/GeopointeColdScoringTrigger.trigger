trigger GeopointeColdScoringTrigger on Lead(after insert) {
    new GeopointeColdScoringTriggerHandler().run();
}
