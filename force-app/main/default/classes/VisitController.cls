/**
* Class Name  : VisitController
* Test Class  : VisitControllerTest
* author      : Shyam
* CreatedDate : 5-12-24
* Description : Created for to send Visits retaled to login user, To create Visits and Etc, Used in 'visitAccountDetailComponent' Component
* */
public with sharing class VisitController {
    
    @AuraEnabled
    public static Boolean checkAllAssetsAudited(Id visitTaskId) {
        System.debug('visitTaskId:- ' + visitTaskId);
        // Step 1: Get the Account ID from the Visit Task
        Visit_Task__c visitTask;
        try {
            visitTask = [SELECT Retailer__c FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1];
        } catch (Exception e) {
            return null; // Handle gracefully or return a default response
        }
        
        
        Id accountId = visitTask.Retailer__c;
        
        // Step 2: Get all Assets related to this Account
        List<Asset__c> relatedAssets = [SELECT Id FROM Asset__c WHERE Retailer_Account__c = :accountId];
        
        if (relatedAssets.isEmpty()) {
            return true; // No assets to audit
        }
        
        // Step 3: Get all Asset Audits linked to these Assets and Visit Task
        Set<Id> auditedAssetIds = new Set<Id>();
        List<Asset_Issue__c> audits = [
            SELECT Asset__c FROM Asset_Issue__c 
            WHERE Asset__c IN :relatedAssets AND Visit_Task__c = :visitTaskId
        ];
        
        // Collect audited Asset IDs
        for (Asset_Issue__c audit : audits) {
            auditedAssetIds.add(audit.Asset__c);
        }
        
        // Step 4: Check if all Assets have an audit record
        for (Asset__c asset : relatedAssets) {
            if (!auditedAssetIds.contains(asset.Id)) {
                return false; // At least one asset is missing an audit
            }
        }
        
        return true; // All assets have been audited
    }
    //This method to retrive all orders related to visittask account
    @AuraEnabled
    // added by fuzail - Updated to handle both Retailer (Account__c) and Distributor (Distributor__c) visit tasks
    public static List<Order__c> getOrdersByAccountForVisitTask(Id visitTaskId) {
        
        Visit_Task__c visitTask = [SELECT Id, Account__c, Distributor__c FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1];
        // added by fuzail - Get account ID from either Account__c (Retailer) or Distributor__c (Distributor)
        Id accountId = visitTask.Account__c != null ? visitTask.Account__c : visitTask.Distributor__c;
        return [SELECT Id, Name, CreatedDate,Account__c,Total_Order_Value__c,RecordType.Name,Total_Quantity__c  FROM Order__c WHERE Account__c = :accountId AND RecordType.Name='Secondary Order' ORDER BY CreatedDate DESC ];
    }
    
    //This method to getAccountBillingAddressVisitTask
    // added by fuzail - Updated to handle both Retailer (Account__c) and Distributor (Distributor__c) visit tasks
    @AuraEnabled(cacheable=true)
    public static Account getAccountBillingAddressVisitTask(String accountId) {
        List<Map<String, Object>> mapMarkers = new List<Map<String, Object>>();
        Visit_Task__c visitTask = [SELECT Id, Account__c, Distributor__c FROM Visit_Task__c WHERE Id = :accountId LIMIT 1];
        // added by fuzail - Get account ID from either Account__c (Retailer) or Distributor__c (Distributor)
        Id accountIdToQuery = visitTask.Account__c != null ? visitTask.Account__c : visitTask.Distributor__c;
        Account account = [SELECT ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,Location__c	
                           FROM Account 
                           WHERE Id = :accountIdToQuery LIMIT 1];      
        return account;
    }
    
    //This method to getVisitTaskDetails   
    // added by fuzail - Updated to handle both Retailer (Account__c) and Distributor (Distributor__c) visit tasks
    @AuraEnabled(cacheable=false)
    public static Map<String, String> getVisitTaskDetails(Id visitTaskRecordId) {
        
        Visit_Task__c visitTask = [SELECT Id, Account__c, Distributor__c,Distributor__r.Number_of_Assets__c, Distributor__r.Owner.Name, Retailer__c, Retailers_Address__c, Checked_In_Location__c FROM Visit_Task__c WHERE Id = :visitTaskRecordId LIMIT 1];
        
        // added by fuzail - Get account ID from either Account__c (Retailer) or Distributor__c (Distributor)
        Id accountId = visitTask.Account__c != null ? visitTask.Account__c : visitTask.Distributor__c;
        
        Account acc = [SELECT Name,Owners_Number__c,Phone_1__c,Outlet_photo__c,Outlet_Image__c, Phone,ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,RecordType.Name,
                       Average_Order_Value__c,Monthly_Target__c,Retailer_Code__c,Code__c
                       FROM Account WHERE Id = :accountId  LIMIT 1];
        
        String shippingAddress = '';
        
        if (acc.ShippingStreet != null) {
            shippingAddress += acc.ShippingStreet + ', ';
        }
        if (acc.ShippingCity != null) {
            shippingAddress += acc.ShippingCity + ', ';
        }
        if (acc.ShippingState != null) {
            shippingAddress += acc.ShippingState + ', ';
        }
        if (acc.ShippingPostalCode != null) {
            shippingAddress += acc.ShippingPostalCode + ', ';
        }
        if (acc.ShippingCountry != null) {
            shippingAddress += acc.ShippingCountry;
        }
        shippingAddress = shippingAddress.trim();
        if (shippingAddress.endsWith(',')) {
            shippingAddress = shippingAddress.substring(0, shippingAddress.length() - 1);
        }
        
        Map<String, String> result = new Map<String, String>();
        result.put('accountIdMap', acc.Id);
result.put('distributorId', visitTask.Distributor__c);
        result.put('accountName', acc.Name);
        // added by Fuzail - Use Code__c for Distributor visits, Retailer_Code__c for Retailer visits
        String codeValue;
        if (visitTask.Distributor__c != null && visitTask.Account__c == null && visitTask.Retailer__c == null) {
            // Distributor visit - use Code__c
            codeValue = acc.Code__c;
        } else {
            // Retailer visit - use Retailer_Code__c
            codeValue = acc.Retailer_Code__c;
        }
        result.put('accountCode', codeValue);
        // added by Fuzail - Use Phone_1__c for Distributor visits, Owners_Number__c for Retailer visits
        String phoneValue;
        if (visitTask.Distributor__c != null && visitTask.Account__c == null && visitTask.Retailer__c == null) {
            // Distributor visit - use Phone_1__c, fallback to Owners_Number__c if Phone_1__c is null
            phoneValue = String.isNotBlank(acc.Phone_1__c) ? acc.Phone_1__c : acc.Owners_Number__c;
        } else {
            // Retailer visit - use Owners_Number__c
            phoneValue = acc.Owners_Number__c;
        }
        result.put('accountPhone', phoneValue);
        result.put('billingAddress', visitTask.Retailers_Address__c );
        result.put('recordTypeName', acc.RecordType.Name);
        result.put('latitude', String.valueOf(visitTask.Checked_In_Location__c));
        result.put('outletPhoto', acc.Outlet_photo__c);
        result.put('outletPhotoUrl', acc.Outlet_Image__c);
        //added by Fuzail 
        Decimal numAssets = visitTask.Distributor__r.Number_of_Assets__c;
        if (numAssets != null) {
        result.put('numberOfAssets', String.valueOf(numAssets));
        } 
        else 
        {
        result.put('numberOfAssets', '0');
        }
        String ownerName = visitTask.Distributor__r.Owner != null ? visitTask.Distributor__r.Owner.Name : '';
        result.put('accountOwnerName', ownerName);
        Decimal monthlyRetailerAvg = acc.Average_Order_Value__c;
        if (monthlyRetailerAvg != null) {
            
            result.put('monthlyRetailerAverage', String.valueOf(monthlyRetailerAvg.setScale(2, RoundingMode.HALF_UP)));
        }
        Decimal monthlytarVal = acc.Monthly_Target__c;
        
        if (monthlytarVal != null) {
            
            result.put('monthlyTargetValue', String.valueOf(monthlytarVal.setScale(2, RoundingMode.HALF_UP)));
            
        }
        return result;
    }
       
    //This method to savePurposeOfVisitData    
    @AuraEnabled
    public static void savePurposeOfVisitData(String visitTaskId,String reason,String userId,String latitude, String longitude, Decimal accuracy) {        
        try {
            Decimal visitLatitude = Decimal.valueOf(latitude);
            Decimal visitLongitude = Decimal.valueOf(longitude);           
            Visit_Task__c visitTask = new Visit_Task__c(Id=visitTaskId);
            visitTask.Purpose_of_Visit__c = reason;
            visitTask.User__c=userId;
            visitTask.Status__c = 'In-Progress';
            visitTask.Checked_In_Location__Latitude__s = visitLatitude;
            visitTask.Checked_In_Location__Longitude__s = visitLongitude;
            visitTask.Checked_In_Time__c = DateTime.now();
            visitTask.Check_in_Accuracy__c = String.valueOf(accuracy);
            update visitTask;         
        }catch (Exception ex) {           
            throw new AuraHandledException(ex.getMessage());
        }       
    }
    
    //This method to saveNoOrderData   
    @AuraEnabled
    public static void saveNoOrderData(String visitTaskId, String reason, String otherReason) {      
        try {
            Visit_Task__c visitTask = [
                SELECT Id, Unproductive_Reasons__c, Other_Reason__c, Distributor__c, Account__c, Retailer__c
                FROM Visit_Task__c
                WHERE Id = :visitTaskId
                LIMIT 1
            ];
            visitTask.Unproductive_Reasons__c = reason;
            // Save Other_Reason__c if "Other" is selected
            if (reason == 'Other' && String.isNotBlank(otherReason)) {
                visitTask.Other_Reason__c = otherReason;
            } else {
                visitTask.Other_Reason__c = null;
            }
            // Status will be updated only when user clicks Check-Out, not here
            update visitTask;          
        }catch (Exception ex) {
            
            throw new AuraHandledException(ex.getMessage());
        }        
    }
    
    //This method to update status to "Completed" when Transfer DF is completed for distributor visits
    // NOTE: Status is now updated only on Check-Out, not here
    @AuraEnabled
    public static void updateStatusForTransferDF(String visitTaskId) {
        try {
            // Status will be updated only when user clicks Check-Out, not here
            // This method is kept for future use if needed, but currently does not update status
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }
    
    //This method to save StartCall Location and Time   
    @AuraEnabled
    public static Boolean saveStartCallLocationTimeRecord(String visitId, Decimal latitude, Decimal longitude, Decimal accuracy) {       
        try {
            Visit_Task__c visitTask = new Visit_Task__c(Id=visitId);            
            visitTask.Start_Call_Location__Latitude__s = latitude;
            visitTask.Start_Call_Location__Longitude__s = longitude;
            visitTask.Start_Call_Time__c = DateTime.now();
            visitTask.Status__c = 'In-Progress';
            visitTask.Check_in_Accuracy__c = String.valueOf(accuracy);
            update visitTask;
            return true;
        }
        catch (DmlException e) {         
            return false; // Return false in case of a DML error
        } catch (Exception ex) {           
            return false; // Return false in case of a DML error
        }        
    }
    
    //This method to save CheckOut details    
    @AuraEnabled
    public static Boolean saveCheckOutRecord(String visitId, Decimal latitude, Decimal longitude , Decimal accuracy) {
        try {
            Visit_Task__c visitTaskRecord = [
                SELECT Id, Order_Placed__c, OrderCustom__c, Status__c, Distributor__c, Retailer__c, Account__c, Unproductive_Reasons__c
                FROM Visit_Task__c 
                WHERE Id =: visitId 
                LIMIT 1
            ];
            Visit_Task__c visitTask = new Visit_Task__c(Id=visitId);            
            visitTask.Checked_Out_Location__Latitude__s = latitude;
            visitTask.Checked_Out_Location__Longitude__s = longitude;
            visitTask.Checked_Out_Time__c = DateTime.now();
            visitTask.Check_in_Accuracy__c = String.valueOf(accuracy);
            System.debug('visitTaskRecord.Order_Placed__c:-' + visitTaskRecord.Order_Placed__c);
            System.debug('visitTaskRecord.OrderCustom__c:-' + visitTaskRecord.OrderCustom__c);
            // For distributor visits, always set status to "Completed"
            if (visitTaskRecord.Distributor__c != null && visitTaskRecord.Retailer__c == null && visitTaskRecord.Account__c == null) {
                visitTask.Status__c = 'Completed';
            } else if(visitTaskRecord.Order_Placed__c == true && visitTaskRecord.OrderCustom__c != null){
                visitTask.Status__c = 'Completed - Order';
            } else {
                visitTask.Status__c = 'Completed - No Order';
            }
            update visitTask;            
            return true;
        }
        catch (DmlException e) {
            return false; // Return false in case of a DML error
        } catch (Exception ex) {
            return false; // Return false in case of a DML error
        }        
    }
    
    //This method to save EndCall details    
    @AuraEnabled
    public static Boolean saveEndCallRecord(String visitId, Decimal latitude, Decimal longitude, Decimal accuracy) {       
        try {
            Visit_Task__c visitTaskRecord = [
                SELECT Id, Order_Placed__c, OrderCustom__c, Status__c, Distributor__c, Retailer__c, Account__c, Unproductive_Reasons__c
                FROM Visit_Task__c 
                WHERE Id =: visitId 
                LIMIT 1
            ];
            Visit_Task__c visitTask = new Visit_Task__c(Id=visitId);
            visitTask.End_Call_Location__Latitude__s = latitude;
            visitTask.End_Call_Location__Longitude__s = longitude;
            visitTask.End_Call_Time__c = DateTime.now();
            visitTask.Check_in_Accuracy__c = String.valueOf(accuracy);
            System.debug('visitTaskRecord.Order_Placed__c:-' + visitTaskRecord.Order_Placed__c);
            System.debug('visitTaskRecord.OrderCustom__c:-' + visitTaskRecord.OrderCustom__c);
            // For distributor visits, always set status to "Completed"
            if (visitTaskRecord.Distributor__c != null && visitTaskRecord.Retailer__c == null && visitTaskRecord.Account__c == null) {
                visitTask.Status__c = 'Completed';
            } else if(visitTaskRecord.Order_Placed__c == true && visitTaskRecord.OrderCustom__c != null){
                visitTask.Status__c = 'Completed - Order';
            } else {
                visitTask.Status__c = 'Completed - No Order';
            }
            update visitTask; 
            return true;
        }
        catch (Exception ex) {
            return false; // Return false in case of a DML error
        }        
    }
    
    //This method to save checkin details    
    @AuraEnabled
    public static String saveVisitTask(String visitId, String latitude, String longitude, Decimal accuracy) {
        try {
            Visit_Task__c visitTask = [
                SELECT Id, Checked_In_Location__Latitude__s, Checked_In_Location__Longitude__s, 
                Account__c, Distributor__c, Retailer__c, Status__c
                FROM Visit_Task__c
                WHERE Id = :visitId
                LIMIT 1
            ];
            
            Id accountId = null;
            if (visitTask.Account__c != null) {
                accountId = visitTask.Account__c;
            } else if (visitTask.Distributor__c != null) {
                accountId = visitTask.Distributor__c;
            } else {
                return Label.Account_Location_Unavailable;
            }
            
            Account accountRecord = [
                SELECT Id, Latitude__c, Longitude__c, Location__Latitude__s, Location__Longitude__s 
                FROM Account
                WHERE Id = :accountId LIMIT 1
            ];
            
            if (accountRecord == null || accountRecord.Latitude__c == null || accountRecord.Longitude__c == null) {
                return Label.Account_Location_Unavailable;
            }
            
            Decimal visitLatitude = Decimal.valueOf(latitude);
            Decimal visitLongitude = Decimal.valueOf(longitude);
            Decimal accountLatitude = Decimal.valueOf(accountRecord.Latitude__c);
            Decimal accountLongitude = Decimal.valueOf(accountRecord.Longitude__c);
            
            // Calculate the distance between visit and account locations
            Double distance = calculateDistanceInMeters(visitLatitude, visitLongitude, accountLatitude, accountLongitude);
            
            Double allowedRadius = Double.valueOf(Label.Check_in_Radius);
            
            if (distance <= allowedRadius) {
                if (accuracy != null) {
                    Visit_Task__c auditUpdate = new Visit_Task__c(Id = visitId);
                    auditUpdate.Check_in_Accuracy__c = String.valueOf(accuracy);
                    update auditUpdate;
                }
                return 'success';
    
            } else {
                Visit_Task__c failedUpdate = new Visit_Task__c(Id = visitId);
                failedUpdate.Failed_Check_in_Location__Latitude__s  = visitLatitude;
                failedUpdate.Failed_Check_in_Location__Longitude__s = visitLongitude;
                if (accuracy != null) {
                    failedUpdate.Check_in_Accuracy__c = String.valueOf(accuracy);
                }
                update failedUpdate;
                
                Boolean isDistributorVisit = (visitTask.Distributor__c != null && visitTask.Account__c == null && visitTask.Retailer__c == null);
                
                Account accountForUpdate = [
                    SELECT Id, Name, Beats_Name__c, Beats_Name__r.Retailer_Location_Update__c,Retailer_Location_Update__c 
                    FROM Account WHERE Id = :accountId LIMIT 1
                ];
                
                if (isDistributorVisit) {
                    if (accountForUpdate.Retailer_Location_Update__c == true) {
                        return Label.Retailer_Location_Update_Message + ' | retailerLocationUpdate=true';
                    } else {
                        return Label.Beyong_50;
                    }
                } else {
                    if (accountForUpdate.Retailer_Location_Update__c == true || 
                       (accountForUpdate.Beats_Name__r != null && 
                        accountForUpdate.Beats_Name__r.Retailer_Location_Update__c)) {
                        return Label.Retailer_Location_Update_Message + ' | retailerLocationUpdate=true';
                    } else {
                        return Label.Beyong_50;
                    }
                }
            }
    
        } catch (DmlException e) {
            return 'Error updating visit task record. Please try again.';
        } catch (Exception ex) {
            return 'An unexpected error occurred. Please contact support.';
        }
    }
    
    // Helper method to calculate distance using the Haversine formula
    public static Double calculateDistanceInMeters(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        
        Double r = 6371000; // Earth's radius in meters
        
        // Convert degrees to radians using a helper method
        Double dLat = degreesToRadians((lat2 - lat1).doubleValue());
        Double dLon = degreesToRadians((lon2 - lon1).doubleValue());
        Double rLat1 = degreesToRadians(lat1.doubleValue());
        Double rLat2 = degreesToRadians(lat2.doubleValue());
        
        // Haversine formula
        Double a = Math.pow(Math.sin(dLat / 2), 2) +
            Math.cos(rLat1) * Math.cos(rLat2) *
            Math.pow(Math.sin(dLon / 2), 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        
        // Distance in meters
        return r * c;
    }
    
    // Custom helper method to convert degrees to radians
    public static Double degreesToRadians(Double degrees) {
        
        
        return degrees * (Math.PI / 180);
    }
    
    @AuraEnabled
    public static string updateRetailerLocation(String visitId, String latitude, String longitude, Decimal accuracy) {
        try {
            if (accuracy == null || accuracy > 20) {
                return 'Error: GPS accuracy is too poor (' + (accuracy != null ? String.valueOf(Math.roundToLong(accuracy)) : 'null') + ' m). Move to an open area and try again.';
            }
    
            Visit_Task__c visitTask = [
                SELECT Id, Account__c, Distributor__c, Retailer__c FROM Visit_Task__c
                WHERE Id = :visitId LIMIT 1
            ];
    
            Id accountIdToUpdate = null;
            if (visitTask.Distributor__c != null && visitTask.Account__c == null && visitTask.Retailer__c == null) {
                accountIdToUpdate = visitTask.Distributor__c;
            } else if (visitTask.Account__c != null) {
                accountIdToUpdate = visitTask.Account__c;
            } else {
                return 'Error: Unable to determine account to update.';
            }
    
            Decimal newLatitude  = Decimal.valueOf(latitude);
            Decimal newLongitude = Decimal.valueOf(longitude);
    
            Account accountToUpdate = [
                SELECT Id, Name, Latitude__c, Longitude__c, BillingLatitude, BillingLongitude FROM Account
                WHERE Id = :accountIdToUpdate LIMIT 1
            ];
    
            accountToUpdate.Latitude__c  = String.valueOf(newLatitude);
            accountToUpdate.Longitude__c = String.valueOf(newLongitude);   
            accountToUpdate.BillingLatitude  = newLatitude;
            accountToUpdate.BillingLongitude = newLongitude;
            accountToUpdate.Capture_Accuracy__c = String.valueOf(accuracy);
    
            update accountToUpdate;
    
            return 'success';
        } catch (Exception ex) {
            return 'An unexpected error occurred. Please contact support.';
        }
    }
    
    //This method to saveSelifeData
    @AuraEnabled
    public static void saveSelifeData(String visitId, String base64Image) {
        try {
            
            
            // Retrieve the Visit record
            //Visit_Task__c visitTask = [SELECT Id,Status__c, Checked_In_Location__Latitude__s, Checked_In_Location__Longitude__s FROM Visit_Task__c WHERE Id = :visitId LIMIT 1];
            /*Visit_Task__c visitTask = new Visit_Task__c(Id=visitId);
            visitTask.Status__c = 'In-Progress';
            update visitTask;*/
            
            // Save the selfie as a File
            String fileName = 'Selfie_' + DateTime.now().format('yyyyMMddHHmmss') + '.jpg'; 
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Image.substring(base64Image.indexOf(',') + 1));
            insert cv;
            
            // Get the ContentDocumentId
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = [SELECT Id FROM ContentDocument WHERE Title = :fileName LIMIT 1].Id;
            cdl.LinkedEntityId = visitId;
            cdl.ShareType = 'V';
            insert cdl;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error saving visit data: ' + e.getMessage());
        }    
    }
    //This method for joint visit
    
   /*@AuraEnabled(cacheable=false)
    public static List<User> searchUser() {
        List<User> userList= new List<User>();
        
        
        userList=[SELECT Id, Name, Email FROM User];
        
        
        return userList;
        
    }*/
    
    @AuraEnabled(cacheable=false)
    public static List<User> searchUser() {
        User currentUser = [SELECT Id, UserRoleId, 	Division FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        
        if (currentUser.UserRoleId == null || currentUser.Division == null) {
            return new List<User>(); // Nothing to search without role or region
        }
        
        Set<Id> sameHierarchyRoleIds = getSameHierarchyRoleIds(currentUser.UserRoleId);
        
        //List<User> usersInSameRegionAndHierarchy = [SELECT Id, Name, Email, UserRoleId,Division FROM User WHERE UserRoleId IN :sameHierarchyRoleIds AND Division = :currentUser.Division  AND Id != :UserInfo.getUserId() AND isActive = true AND Profile.Name = 'SFA Profile'];
        List<User> usersInSameRegionAndHierarchy = [SELECT Id, Name, Email, UserRoleId,Division FROM User WHERE UserRoleId IN :sameHierarchyRoleIds AND Division = :currentUser.Division  AND Id != :UserInfo.getUserId() AND isActive = true AND Profile.Name IN ('SFA Profile','SFA Profile - Light')];
        return usersInSameRegionAndHierarchy;
    }
 
    // Helper method to get all related roles (upward and downward from current)
    private static Set<Id> getSameHierarchyRoleIds(Id userRoleId) {
        Set<Id> relatedRoleIds = new Set<Id>();
        
        // Load all roles once into a map
        Map<Id, UserRole> roleMap = new Map<Id, UserRole>(
            [SELECT Id, ParentRoleId FROM UserRole]
        );
        
        // ----- Traverse Upward -----
        Id currentId = userRoleId;
        while (currentId != null) {
            relatedRoleIds.add(currentId);
            UserRole currentRole = roleMap.get(currentId);
            currentId = currentRole != null ? currentRole.ParentRoleId : null;
        }
        
        // Build parent-to-children map
        Map<Id, List<Id>> parentToChildrenMap = new Map<Id, List<Id>>();
        for (UserRole role : roleMap.values()) {
            if (role.ParentRoleId != null) {
                List<Id> children = parentToChildrenMap.get(role.ParentRoleId);
                if (children == null) {
                    children = new List<Id>();
                    parentToChildrenMap.put(role.ParentRoleId, children);
                }
                children.add(role.Id);
            }
        }

        // Traverse downward using flat loop (index-based, no nested for)
        List<Id> flatQueue = new List<Id>{ userRoleId };
        Integer idx = 0;
        while (idx < flatQueue.size()) {
            Id currentRoleId = flatQueue[idx];
            idx++;

            List<Id> children = parentToChildrenMap.get(currentRoleId);
            if (children != null && !children.isEmpty()) {
                flatQueue.addAll(children);
                relatedRoleIds.addAll(children);
            }
        }
        return relatedRoleIds;
    }
    
    //This method to getVisitTaskRecord
    
    @AuraEnabled
    public static Boolean getVisitTaskRecord(Id visitTaskRecordId) {
        
        Visit_Task__c visitTask = [
            SELECT Id,Purpose_of_Visit__c,Start_Call_Time__c
            FROM Visit_Task__c
            WHERE Id = :visitTaskRecordId
            LIMIT 1
        ];
        
        if((visitTask.Purpose_of_Visit__c!=null && visitTask.Purpose_of_Visit__c!='')|| visitTask.Start_Call_Time__c!=null){
            return true;
        }
        return false;
    }
    //This method to getVisitTaskOrderPlacedRecord
    
    @AuraEnabled
    public static Boolean getVisitTaskOrderPlacedRecord(Id visitTaskRecordId) {
        
        Visit_Task__c visitTask = [
            SELECT Id,Purpose_of_Visit__c,Start_Call_Time__c,Order_Placed__c
            FROM Visit_Task__c
            WHERE Id = :visitTaskRecordId
            LIMIT 1
        ];
        
        if(visitTask.Order_Placed__c==true ){
            return true;
        }
        return false;
    }
    //This method to getVisitTaskStartCallRecord
    
    @AuraEnabled
    public static Boolean getVisitTaskStartCallRecord(Id visitTaskRecordId) {
        
        Visit_Task__c visitTask = [
            SELECT Id,Purpose_of_Visit__c,Start_Call_Time__c
            FROM Visit_Task__c
            WHERE Id = :visitTaskRecordId
            LIMIT 1
        ];
        
        if(visitTask.Start_Call_Time__c!=null){
            return true;
        }
        return false;
    }
    //This method to getVisitTaskCompleteRecord
    
    @AuraEnabled
    public static Boolean getVisitTaskCompleteRecord(Id visitTaskRecordId) {
        
        Visit_Task__c visitTask = [
            SELECT Id,Purpose_of_Visit__c,Checked_Out_Time__c,End_Call_Time__c
            FROM Visit_Task__c
            WHERE Id = :visitTaskRecordId
            LIMIT 1
        ];
        
        if(visitTask.Checked_Out_Time__c!=null){
            return true;
        }
        else  if(visitTask.End_Call_Time__c!=null){
            return true;
        }
        return false;
    }
    //This method to getVisitTaskReson
    
    @AuraEnabled
    public static Boolean getVisitTaskReson(Id visitTaskRecordId) {
        
        Visit_Task__c visitTask = [
            SELECT Id,Purpose_of_Visit__c,Unproductive_Reasons__c
            FROM Visit_Task__c
            WHERE Id = :visitTaskRecordId
            LIMIT 1
        ];
        
        if(visitTask.Unproductive_Reasons__c!=null && visitTask.Unproductive_Reasons__c!=''){
            return true;
        }
        return false;
    }
    
    @AuraEnabled
    public static String checkTodayVisitTask() {
        List<Visit_Task__c> visitTaskList=new List<Visit_Task__c>();
        visitTaskList=[SELECT Id, CreatedDate,Retailer__r.Name,Retailer__r.Retailer_Code__c,Status__c,Task_Planned_Date__c,Visitor_Name__c FROM Visit_Task__c WHERE Task_Planned_Date__c = TODAY AND Visitor_Name__c = :UserInfo.getUserId() AND Checked_Out_Time__c = null AND End_Call_Time__c = null AND Status__c != 'Not Started' LIMIT 1];
        
        if (!visitTaskList.isEmpty()) {
            Visit_Task__c vt = visitTaskList[0];
            // Return JSON so JS can easily extract both fields
            return JSON.serialize(new Map<String, String>{
                'retailerName' => vt.Retailer__r.Name,
                'retailerCode' => vt.Retailer__r.Retailer_Code__c
            });
        }
        return null;
        //return !visitTaskList.isEmpty();        
    }

    @AuraEnabled
    public static Visit_Task__c getCurrentVisitRecord(Id visitTaskRecordId) {
        
        Visit_Task__c visitTask = [
                                    SELECT Id,Purpose_of_Visit__c,Start_Call_Time__c,Checked_Out_Time__c,
                                    End_Call_Time__c,Unproductive_Reasons__c,Order_Placed__c,Status__c,Checked_In_Time__c
                                    FROM Visit_Task__c
                                    WHERE Id = :visitTaskRecordId
                                    LIMIT 1
                                ];
        
        return visitTask;
    }
    
    //This method to removeCheckInDateTime    
    @AuraEnabled
    public static Boolean removeCheckInDateTime(Id visitTaskRecordId) {
        system.debug('visitTaskId**'+visitTaskRecordId);
        Visit_Task__c visitTask = [
            SELECT Id,Checked_In_Location__Latitude__s,Checked_In_Location__Longitude__s,Checked_In_Time__c
            FROM Visit_Task__c
            WHERE Id = :visitTaskRecordId
            LIMIT 1
        ];
        
        if(visitTask.Checked_In_Location__Latitude__s!=null && visitTask.Checked_In_Location__Longitude__s!=null && visitTask.Checked_In_Time__c!=null ){
            visitTask.Checked_In_Location__Latitude__s = null;
            visitTask.Checked_In_Location__Longitude__s = null;
            visitTask.Checked_In_Time__c = null;
            
            update visitTask;
            return true; // Indicate that the fields were cleared            
        }
        return false;
    }
    
    // added by fuzail - Invocable method to get filtered assets for Visit Tasks
    // Used by both Tagged_Assests and Transfer_Frezzer_Req Salesforce Flows
    // SIMPLE RULE: Only show assets where Distributor_Name__c is FILLED (not blank) for Distributor visits
    // Asset 1233 will NOT appear because its Distributor_Name__c is blank
    @InvocableMethod(label='Get Assets for Visit Task' description='Returns assets for Retailer or Distributor visit tasks. For Distributors, only assets with Distributor_Name__c filled and Retailer_Account__c blank are returned.')
    public static List<List<Asset__c>> getAssetsForVisitTask(List<Id> visitTaskIds) {
        List<Asset__c> assetsToReturn = new List<Asset__c>();
        
        System.debug('getAssetsForVisitTask called with visitTaskIds: ' + visitTaskIds);
        
        if (visitTaskIds == null || visitTaskIds.isEmpty()) {
            System.debug('visitTaskIds is null or empty, returning empty list');
            return new List<List<Asset__c>>{new List<Asset__c>()};
        }
        
        Id visitTaskId = visitTaskIds[0];
        System.debug('Processing visitTaskId: ' + visitTaskId);
        
        // Query Visit_Task__c to determine if it's a Retailer or Distributor visit
        Visit_Task__c visitTask = [
            SELECT Id, Account__c, Distributor__c
            FROM Visit_Task__c
            WHERE Id = :visitTaskId
            LIMIT 1
        ];
        
        System.debug('Visit Task - Account__c: ' + visitTask.Account__c + ', Distributor__c: ' + visitTask.Distributor__c);
        
        if (visitTask.Account__c != null) {
            // This is a Retailer visit - query assets using Retailer_Account__c
            System.debug('This is a Retailer visit');
            assetsToReturn = [
                SELECT Id, Name, Asset_Code__c, Model_Name__c, Installed_Date__c, Product__c,
                       Distributor_Name__c, Retailer_Account__c
                FROM Asset__c
                WHERE Retailer_Account__c = :visitTask.Account__c
            ];
            System.debug('Found ' + assetsToReturn.size() + ' assets for Retailer');
        } else if (visitTask.Distributor__c != null) {
            // This is a Distributor visit - SIMPLE RULE: Only show assets where Distributor_Name__c is FILLED (not blank)
            System.debug('This is a Distributor visit, Distributor__c: ' + visitTask.Distributor__c);
            assetsToReturn = [
                SELECT Id, Name, Asset_Code__c, Model_Name__c, Installed_Date__c, Product__c,
                       Distributor_Name__c, Retailer_Account__c
                FROM Asset__c
                WHERE Distributor_Name__c = :visitTask.Distributor__c
                AND Distributor_Name__c != null
                AND Retailer_Account__c = null
            ];
            System.debug('Found ' + assetsToReturn.size() + ' assets for Distributor');
            for (Asset__c asset : assetsToReturn) {
                System.debug('Asset: ' + asset.Asset_Code__c + ' (Name: ' + asset.Name + '), Distributor_Name__c: ' + asset.Distributor_Name__c + ', Retailer_Account__c: ' + asset.Retailer_Account__c);
            }
        } else {
            System.debug('Visit Task has neither Account__c nor Distributor__c');
        }
        
        return new List<List<Asset__c>>{assetsToReturn};
    }
}