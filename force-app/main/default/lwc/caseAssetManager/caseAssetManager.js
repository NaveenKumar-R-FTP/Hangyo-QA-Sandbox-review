import { LightningElement, track, api } from 'lwc';

export default class CaseAssetManager extends LightningElement {
    @api isCheckInDone;
    @api isenableMappedAsset;
    @api isrecordComplete;

      @track isHome = true;
    @track isCase = false;
    @track isAsset = false;

    handleClick(event) {
    const type = event.currentTarget.dataset.type;

    this.isHome = false; //  IMPORTANT

    this.isCase = type === 'case';
    this.isAsset = type === 'asset';
}

    // BACK HANDLER
   goBack() {
    this.isHome = true;
    this.isCase = false;
    this.isAsset = false;
}

handleClick(event) {
    const type = event.currentTarget.dataset.type;

    this.dispatchEvent(new CustomEvent('open', {
        detail: type
    }));
}


get isAssetDisabled() {

    console.log('this.isCheckInDone; : ',this.isCheckInDone);
    console.log('this.isenableMappedAsset; : ',this.isenableMappedAsset);
    console.log('isAssetDisabled; : ',(!this.isCheckInDone || !this.isenableMappedAsset));
    return !(this.isCheckInDone || this.isenableMappedAsset || this.isrecordComplete);
}

}