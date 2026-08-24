//TEST 1
import { LightningElement, track, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import USER_ID from '@salesforce/user/Id';
import getUserRolledUpMetrics from '@salesforce/apex/AssetSummaryController.getUserRolledUpMetrics';

export default class AssetSummary extends NavigationMixin(LightningElement) {
    @api parentUserId; // Accept parent user ID from parent component

    @track totalDF = 0;
    @track billedDF = 0;
    @track zeroBillingDF = 0;
    @track throughput = 0;
    @track loading = false;
    @track showZeroBilling = true;

    currentUserId;
    currentUserRole = '';

    get effectiveUserId() {
        return this.parentUserId || USER_ID;
    }

    // Format number with abbreviations (k for thousands, Cr for crores)
    formatNumber(num) {
        if (!num && num !== 0) return '0';
        
        const value = parseFloat(num);
        
        if (value === 0) return '0';
        
        // For values >= 10,000,000 (1 Crore)
        if (Math.abs(value) >= 10000000) {
            const inCrores = value / 10000000;
            // If it's a whole number in crores, show without decimal
            if (inCrores % 1 === 0) {
                return `${inCrores}Cr`;
            }
            // Otherwise show with 2 decimal places
            return `${inCrores.toFixed(2)}Cr`;
        }
        
        // For values >= 1,000 (1 Thousand)
        if (Math.abs(value) >= 1000) {
            const inThousands = value / 1000;
            // If it's a whole number in thousands, show without decimal
            if (inThousands % 1 === 0) {
                return `${inThousands}k`;
            }
            // Otherwise show with 2 decimal places
            return `${inThousands.toFixed(2)}k`;
        }
        
        // For values less than 1000
        // If it's a whole number, show without decimal
        if (value % 1 === 0) {
            return `${value}`;
        }
        // Otherwise show with 2 decimal places
        return `${value.toFixed(2)}`;
    }

    get formattedThroughput() {
        if (this.throughput === 0 || !this.throughput) {
            return '0';
        }
        return this.formatNumber(this.throughput);
    }

    connectedCallback() {
        this.currentUserId = this.effectiveUserId;
        this.loadSummary();
    }

    renderedCallback() {
        if (this.parentUserId && this.currentUserId !== this.parentUserId) {
            this.currentUserId = this.parentUserId;
            this.loadSummary();
        }
    }

    async loadSummary() {
        this.loading = true;
        try {
            // Get ROLLED-UP metrics for this user and all their subordinates
            const result = await getUserRolledUpMetrics({ userId: this.currentUserId });

            if (result) {
                this.totalDF = result.totalDF || 0;
                this.billedDF = result.billedDF || 0;
                this.zeroBillingDF = result.zeroBillingDF || 0;
                this.throughput = result.throughput || 0;
                this.currentUserRole = result.role || '';
            } else {
                this.totalDF = 0;
                this.billedDF = 0;
                this.zeroBillingDF = 0;
                this.throughput = 0;
            }
        } catch (error) {
            console.error('Error loading summary:', error);
            this.totalDF = 0;
            this.billedDF = 0;
            this.zeroBillingDF = 0;
            this.throughput = 0;
        } finally {
            this.loading = false;
        }
    }

    handleSeeDetails(event) {
        event.preventDefault();

        const targetId = this.effectiveUserId;

        try {
            const navResult = this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'Asset_Summary_Details'
                },
                state: {
                    c__uid: targetId
                }
            });

            // Only attach catch if navResult is actually a Promise
            if (navResult && typeof navResult.then === 'function') {
                navResult.catch(error => {
                    console.error('Navigation error:', error);
                });
            }
        } catch (error) {
            console.error('Navigation execution error:', error);
        }
    }

   /* get donutChartData() {
        const totalDF = this.totalDF || 0;
        const billedDF = this.billedDF || 0;
        const throughput = this.throughput || 0;

        const circumference = 2 * Math.PI * 50; // r = 50 like your SVG

        // Case: everything zero → 3 equal slices
        if (totalDF === 0 && billedDF === 0 && throughput === 0) {
            const part = circumference / 3;
            return {
                segment1: { length: part, offset: 0 },
                segment2: { length: part, offset: -part },
                segment3: { length: part, offset: -2 * part }
            };
        }

        const total = totalDF + billedDF + throughput;

        const seg1 = (totalDF / total) * circumference;
        const seg2 = (billedDF / total) * circumference;
        const seg3 = (throughput / total) * circumference;

        return {
            segment1: { length: seg1, offset: 0 },
            segment2: { length: seg2, offset: -seg1 },
            segment3: { length: seg3, offset: -(seg1 + seg2) }
        };
    }

    get donutSegment1() {
        return `${this.donutChartData.segment1.length} ${314.16 - this.donutChartData.segment1.length}`;
    }

    get donutSegment2() {
        return `${this.donutChartData.segment2.length} ${314.16 - this.donutChartData.segment2.length}`;
    }

    get donutSegment3() {
        return `${this.donutChartData.segment3.length} ${314.16 - this.donutChartData.segment3.length}`;
    }

    get donutOffset2() {
        return this.donutChartData.segment2.offset;
    }

    get donutOffset3() {
        return this.donutChartData.segment3.offset;
    }*/
}