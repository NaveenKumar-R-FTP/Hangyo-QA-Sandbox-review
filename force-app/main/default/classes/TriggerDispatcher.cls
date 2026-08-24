public class TriggerDispatcher {
    
    public static void run(ITriggerHandler handler, string triggerName){
        
        if (handler.IsDisabled()){
            System.debug('Trigger is disabled');
            return;
        }
        
        
        Trigger_Setting__c setting = Trigger_Setting__c.getInstance(triggerName);
        if(setting != Null){
            if(setting.IsActive__c){
                System.debug('trigger called');
                switch on Trigger.operationType {
                    when BEFORE_INSERT {
                        handler.BeforeInsert(trigger.new);
                    }
                    when AFTER_INSERT {handler.AfterInsert(trigger.new, trigger.newMap);}
                    
                    when BEFORE_UPDATE {handler.BeforeUpdate(trigger.new, trigger.newMap, trigger.old, trigger.oldMap);}
                    when AFTER_UPDATE { handler.AfterUpdate(trigger.new, trigger.newMap, trigger.old, trigger.oldMap); }  when BEFORE_DELETE { handler.BeforeDelete(trigger.old, trigger.oldMap); } when AFTER_DELETE { handler.AfterDelete(trigger.old, trigger.oldMap); }  when AFTER_UNDELETE { handler.AfterUnDelete(trigger.new, trigger.newMap);
                   
                    
                   
                                        }
                }
            }   
        }   
    }
}