/**
 * @File Name : RetailerAccountController.cls
 * @Description :
 * @Author :
 * @Last Modified By :
 * @Last Modified On : May 9, 2025
 * @Modification Log :
 *==============================================================================
 * Ver | Date | Author | Modification
 *==============================================================================
 * 1.0 | May 9, 2025 |   | Initial Version
 **/

// RetailerAccountController.cls
public without sharing class RetailerAccountController {

    @AuraEnabled(cacheable=true)
    public static List<Beat__c> getBeatsForCurrentUser() {
        Set<Id> userIds = GetSubOrinates.getSubOrinatesUserIds();
        
        String query = 'SELECT Id, Name, Territory__c, Employee_Name__c FROM Beat__c WHERE Employee_Name__c IN :userIds';
        List<Beat__c> beats = Database.query(query);
        return beats;
    }

  @AuraEnabled
  public static String uploadFile(
    Id parentId,
    String fileName,
    String base64Data,
    String contentType
  ) {
    ContentVersion cv = new ContentVersion(
      VersionData = EncodingUtil.base64Decode(base64Data),
      Title = fileName,
      PathOnClient = fileName,
      FirstPublishLocationId = parentId
    );
    insert cv;

    cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    return cv.Id;
  }

  @AuraEnabled
  public static String createContentDistribution(String contentVersionId) {
    ContentDistribution cd = new ContentDistribution(
      Name = 'Public_Image_Link',
      ContentVersionId = contentVersionId,
      PreferencesAllowViewInBrowser = true,
      PreferencesLinkLatestVersion = true,
      PreferencesNotifyOnVisit = false,
      PreferencesPasswordRequired = false,
      PreferencesAllowOriginalDownload = true
    );
    insert cd;

    cd = [
      SELECT DistributionPublicUrl
      FROM ContentDistribution
      WHERE Id = :cd.Id
    ];
    return cd.DistributionPublicUrl;
  }

  @AuraEnabled
  public static void uploadSelfie(Id latestAccountId, String base64Image) {
    try {
      if (String.isEmpty(base64Image) || latestAccountId == null) {
        throw new AuraHandledException('Invalid data for selfie upload.');
      }

      // Convert base64 to Blob
      Blob fileBody = EncodingUtil.base64Decode(base64Image);

      // Create ContentVersion directly linked to Account
      ContentVersion cv = new ContentVersion(
        Title = 'Outlet_Image_' + Datetime.now().format('yyyy-MM-dd_HHmmss'),
        PathOnClient = 'outlet-image.jpg',
        VersionData = fileBody,
        FirstPublishLocationId = latestAccountId // Auto-creates ContentDocumentLink
      );
      insert cv;

      // Create authenticated preview URL
      String authUrl =
        URL.getOrgDomainUrl().toExternalForm() +
        '/sfc/servlet.shepherd/version/download/' +
        cv.id;

      // Update Account with authenticated URL
      update new Account(Id = latestAccountId, Outlet_Image__c = authUrl);
    } catch (Exception e) {
      System.debug('Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
      throw new AuraHandledException('Image upload failed: ' + e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<String> getStatePicklistValues() {
    try {
      String statesLabel = System.Label.State_Values;
      return statesLabel.split(',');
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving state values: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getPicklistValues() {
    List<Map<String, String>> options = new List<Map<String, String>>();

    Schema.DescribeFieldResult fieldResult = Account.Outlets_Type__c.getDescribe();
    List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();

    for (Schema.PicklistEntry entry : ple) {
      if (entry.isActive()) {
        options.add(
          new Map<String, String>{
            'label' => entry.getLabel(),
            'value' => entry.getValue()
          }
        );
      }
    }
    return options;
  }
  @AuraEnabled
  public static Id getRecordTypeId() {
    return [
      SELECT Id
      FROM RecordType
      WHERE Name = 'Retailer' AND SObjectType = 'Account'
    ]
    .Id;
  }

  @AuraEnabled
  public static Boolean checkDuplicateOwnerNumber(String ownerNumber) {
    return [
        SELECT COUNT()
        FROM Account
        WHERE RecordType.Name = 'Retailer' AND Owners_Number__c = :ownerNumber
      ] > 0;
  }

 @AuraEnabled
public static Id createAccount(Map<String, Object> accountData) {
    
    // Initialize Account object
    Account acc = new Account();
    acc.Name = (String) accountData.get('Name');
    acc.Owners_Name__c = (String) accountData.get('Owners_Name__c');
    acc.Owners_Number__c = (String) accountData.get('Owners_Number__c');
    acc.Outlets_Type__c = (String) accountData.get('Outlets_Type__c');
    acc.Outlets_Channel__c = (String) accountData.get('Outlets_Channel__c');
    acc.GSTIN__c = (String) accountData.get('GSTIN__c');
    acc.BillingStreet = (String) accountData.get('BillingStreet');
    acc.Onboard_Date__c = System.Today();    

    // Latitude and Longitude
    Object latitudeObj = accountData.get('Latitude__c');
    if (latitudeObj != null) {
        acc.Latitude__c = String.valueOf(latitudeObj);
        acc.BillingLatitude = (Decimal) latitudeObj;
    }

    Object longitudeObj = accountData.get('Longitude__c');
    if (longitudeObj != null) {
        acc.Longitude__c = String.valueOf(longitudeObj);
        acc.BillingLongitude = (Decimal) longitudeObj;
    }
    
    Object accuracyObj = accountData.get('Capture_Accuracy__c');
    if (accuracyObj != null) {
        acc.Capture_Accuracy__c = String.valueOf(accuracyObj);
    }

    acc.BillingCity = (String) accountData.get('BillingCity');
    //acc.Primary_City__c = acc.BillingCity;
    acc.BillingCountry = (String) accountData.get('BillingCountry');
    acc.BillingPostalCode = (String) accountData.get('BillingPostalCode');

    // Convert postal code to decimal if valid
    String postalCode = acc.BillingPostalCode;
    if (postalCode != null) {
        Pattern decimalPattern = Pattern.compile('^\\d*\\.\\d+$');
        Matcher matcher = decimalPattern.matcher(postalCode);
        if (matcher.matches()) {
            acc.Primary_PINCode__c = Decimal.valueOf(postalCode);
        }
    }

    acc.BillingState = (String) accountData.get('BillingState');
    acc.Primary_Address_1__c = (String) accountData.get('Primary_Address_1__c');
    acc.PAN_Number__c = (String) accountData.get('PAN_Number__c');
    acc.FSSAI__c = (String) accountData.get('FSSAI__c');
    acc.RecordTypeId = (Id) accountData.get('RecordTypeId');
    acc.Is_Active__c = true;
    
    //Handle Shipping Address only if checkbox is true
    Boolean hasShipping = (Boolean) accountData.get('Has_Shipping_Address__c');
    if (hasShipping == true) {
        acc.ShippingStreet     = (String) accountData.get('ShippingStreet');
        acc.ShippingCity       = (String) accountData.get('ShippingCity');
        acc.ShippingState      = (String) accountData.get('ShippingState');
        acc.ShippingPostalCode = (String) accountData.get('ShippingPostalCode');
        acc.ShippingCountry    = (String) accountData.get('ShippingCountry');
        acc.Primary_Address_2__c = (String) accountData.get('Primary_Address_2__c');
    }

    // Handle beat and fetch Distributor__c
    String beatId = (String) accountData.get('Beats_Name__c');
    if (beatId != null) {
        acc.Beats_Name__c = beatId;

        try {
            Beat__c beatRecord = [
                SELECT Id, Distributor_Name__c,Employee_Name__c , Distributor_Name__r.Hub__c , Distributor_Name__r.Primary_State__c
                FROM Beat__c
                WHERE Id = :beatId
                LIMIT 1
            ];
            acc.Distributor__c = beatRecord.Distributor_Name__c;
            acc.OwnerId = beatRecord.Employee_Name__c;
            acc.Primary_State__c = beatRecord.Distributor_Name__r.Primary_State__c;
            acc.Hub__c = beatRecord.Distributor_Name__r.Hub__c;
        } catch (Exception e) {
            throw new AuraHandledException('Invalid Beat ID or Distributor not found: ' + e.getMessage());
        }
    } else {
        // Fall back to passed distributor if beat is not given
        acc.Distributor__c = (Id) accountData.get('Distributor__c');
    }

    insert acc;
    return acc.Id;
}


  @AuraEnabled
  public static Id getDistributorFromVisitTask(Id visitTaskId) {
    return [SELECT Distributor__c FROM Visit_Task__c WHERE Id = :visitTaskId]
    .Distributor__c;
  }
}