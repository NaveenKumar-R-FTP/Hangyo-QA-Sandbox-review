public interface ITriggerHandler {
    
    void BeforeInsert(List<sObject> newList);
    void AfterInsert(List<sObject> newList, Map<Id, sObject> newMap);
    void BeforeUpdate(List<sObject> newList, Map<Id, sObject> newMap,  List<sObject> oldList, Map<Id, sObject> oldMap);
    void AfterUpdate(List<sObject> newList, Map<Id, sObject> newMap,  List<sObject> oldList, Map<Id, sObject> oldMap);
    void BeforeDelete(List<sObject> oldList , Map<Id, sObject> oldMap);
    void AfterDelete(List<sObject> oldList , Map<Id, sObject> oldMap);
    void AfterUnDelete(List<sObject> newList, Map<Id, sObject> newMap);
    Boolean isDisabled();
}