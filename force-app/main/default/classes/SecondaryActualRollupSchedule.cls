/**
 * SecondaryActualRollupSchedule
 * ---------------------------------------------------------------------------
 * Schedulable wrapper so the secondary-actual rollup can run nightly.
 * Schedule (Execute Anonymous, e.g. daily 01:00):
 *   System.schedule('Secondary Actual Rollup - Nightly',
 *                   '0 0 1 * * ?', new SecondaryActualRollupSchedule());
 */
public class SecondaryActualRollupSchedule implements Schedulable {
    public void execute(SchedulableContext sc) {
        SecondaryActualRollup.run();
    }
}