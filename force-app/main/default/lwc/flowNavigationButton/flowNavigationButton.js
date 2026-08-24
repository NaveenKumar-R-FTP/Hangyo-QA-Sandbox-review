//This Js is created by Ajay and is used to show customised buttons in any Salesforce flows
import { LightningElement, api } from 'lwc';
import { FlowNavigationNextEvent, FlowNavigationBackEvent,FlowNavigationFinishEvent} from 'lightning/flowSupport';





export default class FlowNavigationButton extends LightningElement {
    @api buttonLabel = 'Next'; // Default label
    @api actionType = 'Next'; // Accepts 'Next', 'Previous', 'Finish'
    @api position = 'right'; // 'left' or 'right'

    get buttonClass() {
        return this.position === 'left' ? 'pink-button left' : 'pink-button right';
    }

    handleClick() {
        if (this.actionType === 'Next') {
            this.dispatchEvent(new FlowNavigationNextEvent());
        } else if (this.actionType === 'PREVIOUS') {
            this.dispatchEvent(new FlowNavigationBackEvent());
        } else if (this.actionType === 'FINISHED') {
            this.dispatchEvent(new FlowNavigationFinishEvent());
        }
         
    }
}