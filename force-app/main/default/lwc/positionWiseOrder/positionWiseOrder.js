import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPositionWiseOrders from '@salesforce/apex/HangyoDashboardController.getPositionWiseOrders';
import getUserKPIAndSubordinates from '@salesforce/apex/HangyoDashboardController.getUserKPIAndSubordinates';
import getMySelfOnlyMTD from '@salesforce/apex/HangyoDashboardController.getMySelfOnlyMTD';

export default class PositionWiseOrder extends NavigationMixin(LightningElement) {

    month = new Date().getMonth() + 1;
    year = new Date().getFullYear();

    @track positions = [];
    @track loadingPositions = true;
    @track noData = false;

    // KPI values
    userActual = 0;
    userTarget = 0;
    userSecondary = 0;
    subordinatesActual = 0;
    subordinatesTarget = 0;
    mySelfOnlyActual = 0;

    connectedCallback() {
        this.loadData();
    }

    /*formatCurrency(v) {
        const num = Number(v || 0);
        return '₹' + num.toLocaleString('en-IN', { maximumFractionDigits: 2 });
    }*/

        formatCurrency(v) {
    const num = Number(v || 0);

    if (num >= 10000000) {          // 1 Crore
        return '₹' + (num / 10000000).toFixed(1).replace(/\.0$/, '') + 'Cr';
    }
    if (num >= 100000) {            // 1 Lakh
        return '₹' + (num / 100000).toFixed(1).replace(/\.0$/, '') + 'L';
    }
    if (num >= 1000) {              // 1 Thousand
        return '₹' + (num / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
    }

    // Below 1000 → normal ₹ currency
    return '₹' + num.toLocaleString('en-IN', { maximumFractionDigits: 2 });
}


    async loadData() {
        this.loadingPositions = true;
        this.noData = false;

        try {
            const posList = await getPositionWiseOrders({ monthNum: this.month, yearNum: this.year });

            if (!posList || posList.length === 0) {
                this.positions = [];
                this.noData = true;
            } else {
                let maxActual = Math.max(...posList.map(p => p.actualAmount || 0), 1);

                this.positions = posList.map(p => {
                    const actual = p.actualAmount || 0;
                    const target = p.targetAmount || 0;
                    const actualPct = Math.min(100, (actual / maxActual) * 100);
                    const targetPct = Math.min(100, (target / maxActual) * 100);
                    

                    return {
                        key: p.ownerId,
                        ownerId: p.ownerId,
                        positionName: p.positionName,
                        rank: p.rank,

                        actualAmount: actual,
                        targetAmount: target,

                        actualFormatted: this.formatCurrency(actual),
                        targetFormatted: this.formatCurrency(target),

                        actualWidthStyle: `width:${actualPct}%;`,
                        targetMarkerStyle: `left:${targetPct}%; width:2px;`,

                        expanded: false,
                        teamMembers: null
                    };
                });
            }

            const kpi = await getUserKPIAndSubordinates({
                monthNum: this.month,
                yearNum: this.year
            });

            this.userActual = kpi.userActual || 0;
            this.userTarget = kpi.userTarget || 0;
            this.userSecondary = kpi.userSecondary || 0;
            this.subordinatesActual = kpi.subordinatesActual || 0;
            this.subordinatesTarget = kpi.subordinatesTarget || 0;

            const mySelfOnly = await getMySelfOnlyMTD({
                monthNum: this.month,
                yearNum: this.year
            });
        
            this.mySelfOnlyActual = this.formatCurrency(mySelfOnly || 0);

        } catch (err) {
            console.error(err);
            this.noData = true;
        }

        this.loadingPositions = false;
    }

    get userActualFormatted() { return this.formatCurrency(this.userActual); }
    get userTargetFormatted() { return this.formatCurrency(this.userTarget); }
    get userSecondaryFormatted() { return this.formatCurrency(this.userSecondary); }
    get subordinatesActualFormatted() { return this.formatCurrency(this.subordinatesActual); }
    get subordinatesTargetFormatted() { return this.formatCurrency(this.subordinatesTarget); }
    get mySelfOnlyFormatted() {return this.formatCurrency(this.mySelfOnlyActual);}


   handleSeeDetails() {
    this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: {
            apiName: 'Subordinate_Details'
        }
    });
}
}