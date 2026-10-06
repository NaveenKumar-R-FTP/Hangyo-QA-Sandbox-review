global class UpdateAccountAssetCountScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new UpdateAccountAssetCountBatch(), 50);
    }
}