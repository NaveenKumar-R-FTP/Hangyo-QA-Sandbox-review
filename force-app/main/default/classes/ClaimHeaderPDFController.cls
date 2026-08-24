public without sharing class ClaimHeaderPDFController {

    public ClaimHeaderWrapper claimWrapper { get; set; }

    public class ClaimHeaderWrapper {
        public Claim_Header__c claimHeader { get; set; }
        public List<AggregatedLineItem> aggregatedLineItems { get; set; }
        public String claimHeaderDate { get; set; }
        public String soapprovadate { get; set; }
        public String rsmapprovadate { get; set; }
        public String asmapprovadate { get; set; }
        public string misapprovedate { get; set; }
        public string finapprovedate { get; set; }
        public string headapprovedate { get; set; }
        public String startDateFormatted { get; set; }
        public String endDateFormatted { get; set; }
        public Date startDate { get; set; }
        public Date endDate { get; set; }
        public String monthName { get; set; }
        public String zsmFirstName { get; set; }
        public String zsmLastName { get; set; }
        public String headFirstName { get; set; }
        public String headLastName { get; set; }
        public Decimal totalApprovedAmount { get; set; }
       
        

        public ClaimHeaderWrapper() {
            aggregatedLineItems = new List<AggregatedLineItem>();
        }
    }

    public class AggregatedLineItem implements Comparable {
        public String typeName { get; set; }
        public Decimal total { get; set; }
        public String remark { get; set; }
        public Integer sequence { get; set; } 
        public Decimal approvedTotal { get; set; }

        public AggregatedLineItem(String typeName, Decimal total, String remark ,Integer sequence, Decimal approvedTotal) {
            this.typeName = typeName;
            this.total = total;
            this.remark = remark;
            this.sequence = sequence;
            this.approvedTotal = approvedTotal;
        }

        public Integer compareTo(Object other) {
            AggregatedLineItem o = (AggregatedLineItem) other;
            return this.sequence - o.sequence;
        }
    }
    
        public String companyName { get; set; }
        public String companyState { get; set; }

    public ClaimHeaderPDFController() {
       
        String claimId = ApexPages.currentPage().getParameters().get('Id');
        system.debug('claimId: ' + claimId);
        
         Organization__c org = Organization__c.getInstance('Hangyo');
        
    
    if (org != null) {
        companyName = org.Company_Name__c;
        companyState = org.State__c;
         system.debug('companyName: ' + companyName);
         system.debug('companyState: ' + companyState);
    }

        claimWrapper = new ClaimHeaderWrapper();
        claimWrapper.totalApprovedAmount = 0;

        if (claimId == null) return;

        claimWrapper.claimHeader = [
            SELECT Id, Name, Status__c,
                   Finance_Approved_Date__c,Distributor__r.Code__c,
                   Distributor__r.Name,RSM__r.FirstName,RSM__r.LastName,MIS_User__r.firstName,MIS_User__r.LastName,
                   ASM__r.FirstName,ASM__r.LastName,SO__r.FirstName,MIS_Approved_Date__c,Finance_User__r.FirstName,Finance_User__r.LastName,
                   SO__r.LastName,Month__c,SO_Approved_Date__c,RSM_Approved_Date__c,ASM_Approved_Date__c, Year__c,
                   Distributor__r.BillingCity, 
                   Distributor__r.BillingState,
                    Distributor__r.BillingCountry,
                    Distributor__r.BillingPostalCode,
                    Distributor__r.BillingStreet,
                   Submitted_Amount__c,Submitted_date__c,ZSM_User__c, ZSM_User__r.FirstName,ZSM_User__r.LastName,ZSM_Approved_Date__c,Head_User__c, Head_User__r.FirstName,Head_User__r.LastName, Head_Approved_Date__c
            FROM Claim_Header__c
            WHERE Id = :claimId
            LIMIT 1
        ];
        
        system.debug('claimWrapper.claimHeader'+claimWrapper.claimHeader);
         system.debug('claimWrapper.claimHeaderASM__r.LastName'+claimWrapper.claimHeader.ASM__r.LastName);
        
        claimWrapper.zsmFirstName = claimWrapper.claimHeader.ZSM_User__r.FirstName;
        claimWrapper.zsmLastName = claimWrapper.claimHeader.ZSM_User__r.LastName;
        claimWrapper.headFirstName = claimWrapper.claimHeader.Head_User__r.FirstName;
        claimWrapper.headLastName = claimWrapper.claimHeader.Head_User__r.LastName;
        
        system.debug('claimWrapper.claimHeader   :    ' + claimWrapper.claimHeader);
        System.debug('ZSM_User__r: ' + claimWrapper.claimHeader.ZSM_User__r.LastName);
System.debug('Head_User__r ' + claimWrapper.claimHeader.Head_User__r.LastName);

        if (claimWrapper.claimHeader.Submitted_date__c != null) {
            claimWrapper.claimHeaderDate = formatDate(claimWrapper.claimHeader.Submitted_date__c);
            claimWrapper.soapprovadate = formatDate(claimWrapper.claimHeader.SO_Approved_Date__c);
            claimWrapper.rsmapprovadate = formatDate(claimWrapper.claimHeader.RSM_Approved_Date__c);
            claimWrapper.asmapprovadate = formatDate(claimWrapper.claimHeader.ASM_Approved_Date__c);
            claimWrapper.misapprovedate = formatDate(claimWrapper.claimHeader.MIS_Approved_Date__c);
            claimWrapper.finapprovedate  = formatDate(claimWrapper.claimHeader.ZSM_Approved_Date__c);
            claimWrapper.headapprovedate  = formatDate(claimWrapper.claimHeader.Head_Approved_Date__c);
        }
        system.debug('claimWrapper.asmapprovadate'+claimWrapper.asmapprovadate);

        Id recordTypeId = Schema.SObjectType.Case_Type__c.getRecordTypeInfosByDeveloperName()
            .get('Claim').getRecordTypeId();

        List<Case_Type__c> claimTypeList = [
            SELECT Id, Name,sequence__c
            FROM Case_Type__c
            WHERE RecordTypeId = :recordTypeId ORDER by sequence__c ASC
        ];

        List<Claim_Line_Item__c> claimLineItems = [
            SELECT Case_Type__r.Name,
                   Amount__c,
                   Remark__c,
                   Claim_Date__c, Approved_Amount__c
            FROM Claim_Line_Item__c
            WHERE Claim__c = :claimId
                  AND Case_Type__c != NULL
            ORDER BY Case_Type__r.sequence__c ASC
        ];

        if (!claimLineItems.isEmpty()) {
            Date claimDate = claimLineItems[0].Claim_Date__c;

            Date monthStartDate = Date.newInstance(
                claimDate.year(),
                claimDate.month(),
                1
            );

            Date monthEndDate = monthStartDate.addMonths(1).addDays(-1);

            claimWrapper.startDate = monthStartDate;
            claimWrapper.endDate = monthEndDate;

            claimWrapper.startDateFormatted = formatDate(monthStartDate);
            claimWrapper.endDateFormatted   = formatDate(monthEndDate);
        }

        Map<String, Decimal> claimTypeToTotal = new Map<String, Decimal>();
        Map<String, Decimal> claimTypeToApprovedTotal = new Map<String, Decimal>();
        Map<String, String> claimTypeToRemark = new Map<String, String>();

        for (Claim_Line_Item__c item : claimLineItems) {
            String typeKey = item.Case_Type__r != null
                ? item.Case_Type__r.Name
                : 'Unknown';

            Decimal existing = claimTypeToTotal.containsKey(typeKey)
                ? claimTypeToTotal.get(typeKey)
                : 0;

            Decimal newTotal = existing + (item.Amount__c != null ? item.Amount__c : 0);
            claimTypeToTotal.put(typeKey, newTotal.setScale(2, RoundingMode.HALF_UP));
            
            Decimal existingApproved = claimTypeToApprovedTotal.containsKey(typeKey)
                ? claimTypeToApprovedTotal.get(typeKey)
                : 0;
            
            Decimal newApproved = existingApproved + 
                (item.Approved_Amount__c != null ? item.Approved_Amount__c : 0);
            
            claimTypeToApprovedTotal.put(typeKey, newApproved.setScale(2, RoundingMode.HALF_UP));

            if (!claimTypeToRemark.containsKey(typeKey) && item.Remark__c != null) {
                claimTypeToRemark.put(typeKey, item.Remark__c);
            }
        }

        for (Case_Type__c ct : claimTypeList) {
            String typeName = ct.Name;
            Integer seq = (ct.Sequence__c == null) 
                ? 0 
                : Integer.valueOf(ct.Sequence__c);

            Decimal total = claimTypeToTotal.containsKey(typeName) 
                ? claimTypeToTotal.get(typeName).setScale(2, RoundingMode.HALF_UP) 
                : 0;
            
             Decimal approvedTotal = claimTypeToApprovedTotal.containsKey(typeName)
        ? claimTypeToApprovedTotal.get(typeName).setScale(2, RoundingMode.HALF_UP)
        : 0;
            
            claimWrapper.totalApprovedAmount += approvedTotal;

            String remark = claimTypeToRemark.containsKey(typeName) ? claimTypeToRemark.get(typeName) : '';

            claimWrapper.aggregatedLineItems.add(
                new AggregatedLineItem(typeName, total, remark,seq, approvedTotal)
            );
        }

        claimWrapper.aggregatedLineItems.sort();
    }

    private static String formatDate(Date inputDate) {
        if (inputDate == null) return '';
        return (inputDate.day() < 10 ? '0' + inputDate.day() : String.valueOf(inputDate.day())) + '/' +
               (inputDate.month() < 10 ? '0' + inputDate.month() : String.valueOf(inputDate.month())) + '/' +
               String.valueOf(inputDate.year());
    }

    @AuraEnabled(cacheable=true)
    public static String getInvoicePdfUrl() {
        try {
            Visualforce_PDF__c cfg = Visualforce_PDF__c.getInstance('claimheaderpdf');
            system.debug('cfg   :  '+cfg);
            return cfg == null ? null : cfg.PDF_Url__c;
        } catch (Exception ex) {
            throw new AuraHandledException('Error fetching PDF URL: ' + ex.getMessage());
        }
    }
}