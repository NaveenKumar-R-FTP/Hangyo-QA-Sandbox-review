/**
 * PerformanceDashboardController
 * Entry point for the performanceDashboard LWC. Three live (non-cacheable) calls loaded in parallel.
 * Access: only designations in Performance_Dashboard_Access__mdt (VP, ZSM, RSM).
 * New class - Performance Dashboard project.
 */
public with sharing class PerformanceDashboardController {

    /** Cards 1-4, 6, 8, 9. mode = 'MTD' or 'YTD'. */
    @AuraEnabled
    public static PerformanceDashboardDTO.Summary getSummary(String mode) {
        try {
            PerformanceDashboardDTO.Summary s = new PerformanceDashboardDTO.Summary();
            s.mode = PerformanceDataService.normaliseMode(mode);
            s.asOf = System.now();
            User me = PerformanceDataService.currentUser();
            if (!PerformanceDataService.hasAccess(me)) { s.accessDenied = true; return s; }

            PerformanceDataService.Window w = PerformanceDataService.window(s.mode, Date.today());
            s.periodStart = w.startDate;
            s.periodEnd = w.endDate;
            s.header = PerformanceDataService.buildHeader(me);
            Set<Id> teamIds = PerformanceDataService.selfAndReports(me.Id);
            s.target = PerformanceDataService.buildTarget(me.Id, teamIds, w);
            s.growth = PerformanceDataService.buildGrowth(teamIds, w, s.target.achievement);
            s.calls = PerformanceDataService.buildCalls(teamIds, w);
            s.primary = PerformanceDataService.buildPrimary(PerformanceDataService.teamDivisions(teamIds), w);
            if (s.mode == PerformanceDataService.MODE_MTD) {
                // Cards 6 and 9 show today's data and are hidden in YTD.
                s.attendance = PerformanceDataService.buildAttendance(me.Id, teamIds, w.today);
                s.today = PerformanceDataService.buildToday(teamIds, w.today);
            }
            return s;
        } catch (Exception e) {
            throw new AuraHandledException('Performance Dashboard could not load: ' + e.getMessage());
        }
    }

    /** Card 5 (loaded separately - heaviest query). */
    @AuraEnabled
    public static PerformanceDashboardDTO.FreezerDTO getFreezer(String mode) {
        try {
            PerformanceDashboardDTO.FreezerDTO f = new PerformanceDashboardDTO.FreezerDTO();
            User me = PerformanceDataService.currentUser();
            if (!PerformanceDataService.hasAccess(me)) { f.accessDenied = true; return f; }
            PerformanceDataService.Window w = PerformanceDataService.window(mode, Date.today());
            return PerformanceDataService.buildFreezer(PerformanceDataService.selfAndReports(me.Id), w);
        } catch (Exception e) {
            throw new AuraHandledException('Freezer card could not load: ' + e.getMessage());
        }
    }

    /** Card 7 (loaded separately). */
    @AuraEnabled
    public static PerformanceDashboardDTO.RegionDTO getRegion(String mode) {
        try {
            PerformanceDashboardDTO.RegionDTO r = new PerformanceDashboardDTO.RegionDTO();
            User me = PerformanceDataService.currentUser();
            if (!PerformanceDataService.hasAccess(me)) { r.accessDenied = true; return r; }
            PerformanceDataService.Window w = PerformanceDataService.window(mode, Date.today());
            return PerformanceDataService.buildRegion(me.Id, PerformanceDataService.selfAndReports(me.Id), w);
        } catch (Exception e) {
            throw new AuraHandledException('Region card could not load: ' + e.getMessage());
        }
    }
}