/**
 * PerformanceDashboardDTO
 * Data shapes returned to the performanceDashboard LWC. New class - Performance Dashboard project.
 */
public with sharing class PerformanceDashboardDTO {

    public class Summary {
        @AuraEnabled public Boolean accessDenied = false;
        @AuraEnabled public String mode;
        @AuraEnabled public Datetime asOf;
        @AuraEnabled public Date periodStart;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public HeaderDTO header;
        @AuraEnabled public TargetDTO target;
        @AuraEnabled public CallsDTO calls;
        @AuraEnabled public GrowthDTO growth;
        @AuraEnabled public AttendanceDTO attendance;
        @AuraEnabled public GrowthDTO primary;
        @AuraEnabled public TodayDTO today;
    }

    public class HeaderDTO {
        @AuraEnabled public String userName;
        @AuraEnabled public String division;
        @AuraEnabled public String designation;
        @AuraEnabled public Integer directReports = 0;
    }

    public class TargetDTO {
        @AuraEnabled public Decimal target = 0;          // MTD: month target | YTD: Apr..current month
        @AuraEnabled public Decimal periodTarget = 0;    // MTD: month target | YTD: full FY (Apr..Mar) - basis for balance and RRR
        @AuraEnabled public Decimal achievement = 0;
        @AuraEnabled public Decimal percent = 0;
        @AuraEnabled public Decimal balance = 0;
        @AuraEnabled public Integer remainingDays = 0;
        @AuraEnabled public Decimal rrr = 0;
    }

    public class CallsDTO {
        @AuraEnabled public Integer totalCalls = 0;
        @AuraEnabled public Integer productiveCalls = 0;
        @AuraEnabled public Decimal percent = 0;
    }

    /** Used for Card 4 (secondary growth) and Card 8 (primary). growthPercent = null when last year = 0. */
    public class GrowthDTO {
        @AuraEnabled public Decimal current = 0;
        @AuraEnabled public Decimal lastYear = 0;
        @AuraEnabled public Decimal growthPercent;
    }

    public class AttendanceDTO {
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Decimal present = 0;
        @AuraEnabled public Decimal leaveCount = 0;
        @AuraEnabled public Decimal absent = 0;
        @AuraEnabled public Integer notMarked = 0;
    }

    public class TodayDTO {
        @AuraEnabled public Decimal orderValue = 0;
        @AuraEnabled public Integer orderCount = 0;
        @AuraEnabled public Integer totalCalls = 0;
        @AuraEnabled public Integer productiveCalls = 0;
        @AuraEnabled public Decimal pcPercent = 0;
        @AuraEnabled public Decimal dfOrderValue = 0;
        @AuraEnabled public Integer dfOutletsOrdered = 0;
        @AuraEnabled public Decimal dfThroughPut = 0;
    }

    public class FreezerDTO {
        @AuraEnabled public Boolean accessDenied = false;
        @AuraEnabled public Integer activeFreezers = 0;
        @AuraEnabled public Integer billedFreezers = 0;
        @AuraEnabled public Decimal billedPercent = 0;
        @AuraEnabled public Decimal dfSale = 0;
        @AuraEnabled public Decimal perFreezer = 0;
    }

    public class RegionDTO {
        @AuraEnabled public Boolean accessDenied = false;
        @AuraEnabled public List<HubDTO> hubs = new List<HubDTO>();
    }

    public class HubDTO {
        @AuraEnabled public String hub;
        @AuraEnabled public String headName;
        @AuraEnabled public String headDesignation;
        @AuraEnabled public Decimal target = 0;
        @AuraEnabled public Decimal achievement = 0;
        @AuraEnabled public Decimal percent = 0;
        @AuraEnabled public Decimal primarySale = 0;
        @AuraEnabled public List<MemberDTO> members = new List<MemberDTO>();
    }

    public class MemberDTO {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String designation;
        @AuraEnabled public Decimal target = 0;
        @AuraEnabled public Decimal achievement = 0;
        @AuraEnabled public Decimal percent = 0;
    }
}