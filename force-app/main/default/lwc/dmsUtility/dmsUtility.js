import {ShowToastEvent} from 'lightning/platformShowToastEvent';

export function isNullEmptyUndefined(v) {
    if (v === "" || v === null || v === undefined || v === " ") {
      return true;
    } else {
      return false;
    }
}

export function isNullEmptyUndefinedObject(v) {
    if (v === "" || v === null || v === undefined) {
      return true;
    } else if (typeof v === "object") {
      if (Array.isArray(v)) {
        return v.length == 0;
      }
      return Object.keys(v).length === 0;
    } else {
      return false;
    }
  }

export function showToast(toastTitle, toastMessage, toastMessageData, toastVariant, toastMode) {
    const event = new ShowToastEvent({
        title: toastTitle,
        message: toastMessage,
        messageData: isNullEmptyUndefined(toastMessageData) ? [] : toastMessageData,
        variant: toastVariant,
        mode: isNullEmptyUndefined(toastMode) ? 'dismissible' : toastMode
    });
    return event;     
}