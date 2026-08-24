import { LightningElement, track, api, wire } from 'lwc';
import getVisitRecordsByDate from '@salesforce/apex/VisitTaskController.getVisitRecordsByDate';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import checkAnyVisitTaskInprogress from '@salesforce/apex/VisitTaskController.checkAnyVisitTaskInprogress';
import getVisitRecordsByDateTest from '@salesforce/apex/VisitTaskController.getVisitRecordsByDateTest'; 

import { CurrentPageReference } from 'lightning/navigation';

export default class visitListView1 extends NavigationMixin(LightningElement) {
    @track visitTasks = [];
    @track selectedDayKey = null;
    @track days = [];
    @track selectedDate = '';
    @track visitRecords = [];
    // Status tracking
    @track notStarted = [];
    @track inProgress = [];
    @track completedOrderReceived = [];
    @track completedDistributor = [];
    @track completedUnproductive = [];
    @track cancelled = [];
    @track remainingVisits = [];

    @track isJourneyScreen = true;
    @track isLoading = false;
    @track errorMessage = '';

    @track visitRecord = { Account__c: '', Task_planned_date__c: '', RecordType: '' };
    @track showModal = false;

    @track searchKey = '';

    @track showChildComponent = false;
    @track selectedVisit = null;
    // added by fuzail - Track if selected visit is a Distributor
    @track isDistributorVisit = false;

    //added by Fuzail - Tab selection tracking
    @track selectedTab = 'all';

    @track visit;
    @track formattedAverageOrderValue;
    isDataRefreshed = false;
    wiredVisitResult;
    isManualRefresh = false; // Flag to prevent wired result from overriding manual refresh

    //This method calling from visitAccountDetailComponent child component on handleBack() Method
    @api
    callMeFromParent() {
        const formattedDate = this.selectedDate; // assuming it's already 'YYYY-MM-DD'

        getVisitRecordsByDateTest({ selectedDate: formattedDate })
            .then(result => {
                // added by fuzail - Normalize visit records to handle both Retailer (Account__r) and Distributor (Distributor__r)
                const records = Array.isArray(result) ? result : [];
                const normalizedResult = this.normalizeVisitRecords(records);
                
                this.notStarted = this.categorizeVisits(normalizedResult, 'Not Started');
                this.inProgress = this.categorizeVisits(normalizedResult, 'In-Progress');
                this.completedOrderReceived = this.categorizeVisits(normalizedResult, 'Completed - Order');
                this.cancelled = this.categorizeVisits(normalizedResult, 'Cancelled');
                // Separate Distributor "Completed" tasks from "Completed - No Order"
                // Distributor visits with status "Completed" go to completedDistributor
                this.completedDistributor = normalizedResult
                    .filter(record => 
                        record.Status__c === 'Completed' && 
                        record.Distributor__c != null && 
                        record.Account__c == null
                    )
                    .map(record => ({
                        ...record,
                        Task_planned_date__c: this.formatDate(record.Task_planned_date__c)
                    }));
                // Only "Completed - No Order" status goes to completedUnproductive (no Distributor "Completed")
                this.completedUnproductive = this.categorizeVisits(normalizedResult, 'Completed - No Order');
                this.remainingVisits = this.categorizeVisits(normalizedResult, null);
                this.visitRecords = normalizedResult;
                this.isLoading = false;
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error?.body?.message || error.message || 'Error fetching visit data.',
                        variant: 'error'
                    })
                );
            });
    }

    // Fetching Visit Task Data
    fetchVisitData() {
        getVisitRecordsByDate()
            .then(result => {
                console.log('result999', result);
                this.visit = result;
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error?.body?.message || error.message || 'Error fetching visit data.',
                        variant: 'error'
                    })
                );
            });
    }

    @wire(CurrentPageReference) pageRef;

    // Fetch Visit Records using @wire
    @wire(getVisitRecordsByDate)
    wiredVisit(result) {
        this.wiredVisitResult = result; // Store the wired response for refresh
        
        // Don't process wired result if we're doing a manual refresh
        // This prevents stale data from overriding fresh data
        if (this.isManualRefresh) {
            return;
        }
        
        // added for code optimization
        this.visit = result;

        if (result.data) {
            this.visit = result.data;
        } else if (result.error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message:
                        result.error?.body?.message ||
                        result.error.message ||
                        'Error fetching visit data.',
                    variant: 'error'
                })
            );
        }
    }

    connectedCallback() {
        this.generateWeekdays();
        
        // Check if we need to restore a selected date after reload
        const restoreDate = sessionStorage.getItem('restoreSelectedDate');
        const restoreDateFormatted = sessionStorage.getItem('restoreSelectedDateFormatted');
        
        if (restoreDate && restoreDateFormatted) {
            // Restore the selected date
            sessionStorage.removeItem('restoreSelectedDate');
            sessionStorage.removeItem('restoreSelectedDateFormatted');
            
            this.selectedDayKey = restoreDate;
            this.selectedDate = restoreDateFormatted;
            
            // Update button classes to highlight the selected date
            this.days = this.days.map(day => ({
                ...day,
                buttonClass: day.key === restoreDate ? 'day-button-orange' : 'day-button-green'
            }));
            
            // Fetch records for the restored date
            const selectedDateObj = new Date(restoreDate);
            this.isLoading = true;
            this.fetchVisitRecords(selectedDateObj);
        } else {
            // Normal flow - select today and fetch records
            this.selectTodayAndFetchRecords();
        }
        
        // Only restore if showChildComponent flag is set (meaning we should show it)
        const shouldShowChild = localStorage.getItem('showChildComponent') === 'true' || sessionStorage.getItem('showChildComponent') === 'true';
        if (shouldShowChild) {
            this.selectedVisit = window.sessionStorage.getItem('visitId') || localStorage.getItem('visitId');
            if (this.selectedVisit) {
                this.showChildComponent = true;
                // Restore isDistributorVisit flag from localStorage
                const storedFlag = localStorage.getItem('isDistributorVisit');
                if (storedFlag !== null) {
                    this.isDistributorVisit = storedFlag === 'true';
                }
            }
        }

        // Handle if it's the Salesforce Mobile SDK and enable refresh
        if (navigator.userAgent.includes('SalesforceMobileSDK') && !this.isDataRefreshed) {
            this.isDataRefreshed = true; // Set flag to prevent multiple refresh calls
            this.handleRefresh();
        }

        // ✅ Check if we should refresh on load (after navigation)
        const shouldRefresh = window.sessionStorage.getItem('shouldRefreshVisitData');
        if (shouldRefresh === 'true') {
            window.sessionStorage.removeItem('shouldRefreshVisitData');
            this.handleRefresh(); // Custom method to refresh wired data
        }
    }

    renderedCallback() {
        // this.handleRefresh();
    }

    //  Handle Refresh for Pull-to-Refresh in Mobile
    async handleRefresh() {
        try {
            await refreshApex(this.wiredVisitResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || error.message || 'Error refreshing data.',
                    variant: 'error'
                })
            );
        }
    }

    // Handles the search input to be filter out
    handleSearchChange(event) {
        this.searchKey = event.target.value.trim();
        this.fetchVisitRecords(new Date(this.selectedDayKey));
        this.handleRefresh();
    }

    // Create the Week days with date Dynamically
    generateWeekdays() {
        const today = new Date();
        const daysOfWeek = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const daysArray = [];

        for (let i = 0; i < 7; i++) {
            const date = new Date(today);
            date.setDate(today.getDate() - today.getDay() + i);
            daysArray.push({
                label: daysOfWeek[date.getDay()],
                date: date.getDate(),
                fullDate: date,
                key: date.toISOString(),
                buttonClass:
                    date.toDateString() === today.toDateString()
                        ? 'day-button-orange'
                        : 'day-button-green'
            });
        }

        this.days = daysArray;
    }

    // Select dynamically today & fetch record for same
    selectTodayAndFetchRecords() {
        const todayKey = this.days.find(day => day.buttonClass === 'day-button-orange').key;
        const todayDate = new Date(todayKey);
        this.selectedDate = todayDate.toISOString().split('T')[0];
        this.selectedDayKey = todayKey;

        this.isLoading = true;
        this.errorMessage = '';
        this.fetchVisitRecords(todayDate);
    }

    // Handles the date clicked
    handleDateClick(event) {
        const selectedKey = event.currentTarget.dataset.key;
        const selectedDay = new Date(selectedKey);
        this.selectedDate = selectedDay.toISOString().split('T')[0];

        this.days = this.days.map(day => ({
            ...day,
            buttonClass: 'day-button-green'
        }));

        this.days = this.days.map(day => {
            const isSelected = day.key === selectedKey;
            return {
                ...day,
                buttonClass: isSelected ? 'day-button-orange' : 'day-button-green'
            };
        });

        this.isLoading = true;
        this.errorMessage = '';
        this.fetchVisitRecords(selectedDay);
        this.selectedDayKey = selectedKey;

        this.handleRefresh();
    }

    //added by Fuzail - Handle tab click for status filtering
    handleTabClick(event) {
        const tabValue = event.currentTarget.dataset.tab;
        this.selectedTab = tabValue;
    }

    //added by Fuzail - Computed properties for tab classes
    get tabAllClass() {
        return this.selectedTab === 'all' ? 'status-tab active-tab' : 'status-tab';
    }

    get tabInProgressClass() {
        return this.selectedTab === 'in-progress' ? 'status-tab active-tab' : 'status-tab';
    }

    get tabCompletedOrderClass() {
        return this.selectedTab === 'completed-order' ? 'status-tab active-tab' : 'status-tab';
    }

    get tabCompletedClass() {
        return this.selectedTab === 'completed' ? 'status-tab active-tab' : 'status-tab';
    }

    get tabCompletedNoOrderClass() {
        return this.selectedTab === 'completed-no-order' ? 'status-tab active-tab' : 'status-tab';
    }

    get tabStartedCancelledClass() {
        return this.selectedTab === 'started-cancelled' ? 'status-tab active-tab' : 'status-tab';
    }

    //added by Fuzail - Filtered visit arrays based on selected tab
    get filteredInProgress() {
        if (this.selectedTab === 'all' || this.selectedTab === 'in-progress') {
            return this.inProgress;
        }
        return [];
    }

    get filteredNotStarted() {
        if (this.selectedTab === 'all' || this.selectedTab === 'started-cancelled') {
            return this.notStarted;
        }
        return [];
    }

    get filteredCompletedOrderReceived() {
        if (this.selectedTab === 'all' || this.selectedTab === 'completed-order') {
            return this.completedOrderReceived;
        }
        return [];
    }

    get filteredCompletedDistributor() {
        if (this.selectedTab === 'all' || this.selectedTab === 'completed') {
            return this.completedDistributor;
        }
        return [];
    }

    get filteredCompletedUnproductive() {
        if (this.selectedTab === 'all' || this.selectedTab === 'completed-no-order') {
            return this.completedUnproductive;
        }
        return [];
    }

    get filteredCancelled() {
        if (this.selectedTab === 'all' || this.selectedTab === 'started-cancelled') {
            return this.cancelled;
        }
        return [];
    }

    get filteredRemainingVisits() {
        if (this.selectedTab === 'all') {
            return this.remainingVisits;
        }
        return [];
    }

    // Fetch Visit Task records for selected date
    fetchVisitRecords(date) {
        this.isLoading = true;
        const filters = {
            account: this.searchKey
        };
        const checkboxfilter = this.selectedStatusFilters;
        return getVisitRecordsByDate({
            selectedDate: this.selectedDate,
            filters: filters,
            checkboxfilter: []
        })
            .then(result => {
                // added by fuzail - Normalize visit records to handle both Retailer (Account__r) and Distributor (Distributor__r)
                // Ensure result is an array and normalize it
                const records = Array.isArray(result) ? result : [];
                const normalizedResult = this.normalizeVisitRecords(records);
                
                this.notStarted = this.categorizeVisits(normalizedResult, 'Not Started');
                this.inProgress = this.categorizeVisits(normalizedResult, 'In-Progress');
                this.completedOrderReceived = this.categorizeVisits(normalizedResult, 'Completed - Order');
                this.cancelled = this.categorizeVisits(normalizedResult, 'Cancelled');
                // Separate Distributor "Completed" tasks from "Completed - No Order"
                // Distributor visits with status "Completed" go to completedDistributor
                this.completedDistributor = normalizedResult
                    .filter(record => 
                        record.Status__c === 'Completed' && 
                        record.Distributor__c != null && 
                        record.Account__c == null
                    )
                    .map(record => ({
                        ...record,
                        Task_planned_date__c: this.formatDate(record.Task_planned_date__c)
                    }));
                // Only "Completed - No Order" status goes to completedUnproductive (no Distributor "Completed")
                this.completedUnproductive = this.categorizeVisits(normalizedResult, 'Completed - No Order');
                this.remainingVisits = this.categorizeVisits(normalizedResult, null);
                this.visitRecords = normalizedResult;
                
                // If we have a selectedVisit but isDistributorVisit wasn't set, determine it from the records
                if (this.selectedVisit && localStorage.getItem('isDistributorVisit') === null) {
                    const selectedRecord = this.visitRecords.find(record => record.Id === this.selectedVisit);
                    if (selectedRecord) {
                        this.isDistributorVisit = selectedRecord.Distributor__c && !selectedRecord.Account__c;
                        localStorage.setItem('isDistributorVisit', this.isDistributorVisit ? 'true' : 'false');
                    }
                }
                
                this.isLoading = false;
                return result; // Return result for promise chaining
            })
            .catch(error => {
                this.errorMessage =
                    'There was an error fetching visit records. Please try again later.';
                this.notStarted = [];
                this.inProgress = [];
                this.completedOrderReceived = [];
                this.completedUnproductive = [];
                this.remainingVisits = [];
                this.visitRecords = [];
                this.isLoading = false;
                throw error; // Re-throw for promise chaining
            });
    }

    // added by fuzail - Normalize visit records to use Account__r for both Retailer and Distributor
    // This allows the UI to use the same structure regardless of account type
    normalizeVisitRecords(records) {
        if (!records || !Array.isArray(records) || records.length === 0) {
            return [];
        }
        return records.map(record => {
            // Ensure Account__r is always defined to prevent undefined errors
            let accountData = {
                Name: '',
                Retailer_classification__c: '',
                Last_Ordered_Date__c: '',
                Last_Confirmed_Invoice_Date__c: '',
                Invoice_Amount__c: 0,
                Order_Frequency__c: '',
                Total_Order_Value__c: 0,
                Phone: '',
                Outlet_photo__c: ''
            };
            
            // If Distributor__c exists and Account__c doesn't, use Distributor__r
            if (record.Distributor__c && !record.Account__c) {
                if (record.Distributor__r) {
                    accountData = {
                        Name: record.Distributor__r.Name || '',
                        Retailer_classification__c: record.Distributor__r.Retailer_classification__c || '',
                        Last_Ordered_Date__c: record.Distributor__r.Last_Ordered_Date__c || '',
                        Last_Confirmed_Invoice_Date__c: record.Distributor__r.Last_Confirmed_Invoice_Date__c || '',
                        Invoice_Amount__c: record.Distributor__r.Invoice_Amount__c || 0,
                        Order_Frequency__c: record.Distributor__r.Order_Frequency__c || '',
                        Total_Order_Value__c: record.Distributor__r.Total_Order_Value__c || 0,
                        Phone: record.Distributor__r.Phone || '',
                        Outlet_photo__c: record.Distributor__r.Outlet_photo__c || ''
                    };
                }
            } 
            // Otherwise, use Account__r (for Retailers)
            else if (record.Account__c && record.Account__r) {
                accountData = {
                    Name: record.Account__r.Name || '',
                    Retailer_classification__c: record.Account__r.Retailer_classification__c || '',
                    Last_Ordered_Date__c: record.Account__r.Last_Ordered_Date__c || '',
                    Last_Confirmed_Invoice_Date__c: record.Account__r.Last_Confirmed_Invoice_Date__c || '',
                    Invoice_Amount__c: record.Account__r.Invoice_Amount__c || 0,
                    Order_Frequency__c: record.Account__r.Order_Frequency__c || '',
                    Total_Order_Value__c: record.Account__r.Total_Order_Value__c || 0,
                    Phone: record.Account__r.Phone || '',
                    Outlet_photo__c: record.Account__r.Outlet_photo__c || ''
                };
            }
            
            // Format status for distributor visits - always show "Completed" for distributor visits
            let displayStatus = record.Status__c || '';
            if (record.Distributor__c && !record.Account__c) {
                // For distributor visits, if status is "Completed - No Order" or "Completed - Order", display as "Completed"
                if (record.Status__c === 'Completed - No Order' || record.Status__c === 'Completed - Order' || record.Status__c === 'Completed') {
                    displayStatus = 'Completed';
                }
            }
            
            // Return normalized record with Account__r always set (never undefined or null)
            const normalizedRecord = {
                ...record,
                Account__r: accountData,
                DisplayStatus__c: displayStatus || record.Status__c || '' // Add formatted status for display, fallback to original status
            };
            
            // Final safety check - ensure Account__r is always an object with Name
            if (!normalizedRecord.Account__r || typeof normalizedRecord.Account__r !== 'object' || Array.isArray(normalizedRecord.Account__r)) {
                normalizedRecord.Account__r = {
                    Name: '',
                    Retailer_classification__c: '',
                    Last_Ordered_Date__c: '',
                    Last_Confirmed_Invoice_Date__c: '',
                    Invoice_Amount__c: 0,
                    Order_Frequency__c: '',
                    Total_Order_Value__c: 0,
                    Phone: '',
                    Outlet_photo__c: ''
                };
            }
            // Ensure Name property exists and is never null/undefined
            if (!normalizedRecord.Account__r.hasOwnProperty('Name') || normalizedRecord.Account__r.Name === null || normalizedRecord.Account__r.Name === undefined) {
                normalizedRecord.Account__r.Name = String(normalizedRecord.Account__r.Name || '');
            }
            // Ensure all other properties exist
            if (!normalizedRecord.Account__r.hasOwnProperty('Retailer_classification__c')) {
                normalizedRecord.Account__r.Retailer_classification__c = '';
            }
            if (!normalizedRecord.Account__r.hasOwnProperty('Last_Ordered_Date__c')) {
                normalizedRecord.Account__r.Last_Ordered_Date__c = '';
            }
            if (!normalizedRecord.Account__r.hasOwnProperty('Last_Confirmed_Invoice_Date__c')) {
                normalizedRecord.Account__r.Last_Confirmed_Invoice_Date__c = '';
            }
            if (!normalizedRecord.Account__r.hasOwnProperty('Invoice_Amount__c')) {
                normalizedRecord.Account__r.Invoice_Amount__c = 0;
            }
            if (!normalizedRecord.Account__r.hasOwnProperty('Order_Frequency__c')) {
                normalizedRecord.Account__r.Order_Frequency__c = '';
            }
            if (!normalizedRecord.Account__r.hasOwnProperty('Total_Order_Value__c')) {
                normalizedRecord.Account__r.Total_Order_Value__c = 0;
            }
            
            return normalizedRecord;
        });
    }

    // Visit Task Categories according to status
    categorizeVisits(records, status) {
        return records
            .filter(record =>
                status
                    ? record.Status__c === status
                    : ![
                          'Not Started',
                          'Unplanned',
                          'In-Progress',
                          'Completed - Order',
                          'Completed',
                          'Completed - No Order',
                          'Cancelled'
                      ].includes(record.Status__c)
            )
            .map(record => {
                return {
                    ...record,
                    Task_planned_date__c: this.formatDate(record.Task_planned_date__c)
                };
            });
    }

    // Calendar date formating
    formatDate(dateString) {
        if (!dateString) {
            return ''; // Return an empty string if dateString is null or undefined
        }
        const date = new Date(dateString);
        const day = ('0' + date.getDate()).slice(-2);
        const month = ('0' + (date.getMonth() + 1)).slice(-2);
        const year = date.getFullYear();
        return `${day}/${month}/${year}`;
    }

    //added by Fuzail - Updated to check filtered records
    //Checking records are there for Visit task
    get hasVisitRecords() {
        return (
            this.filteredNotStarted.length > 0 ||
            this.filteredInProgress.length > 0 ||
            this.filteredCompletedOrderReceived.length > 0 ||
            this.filteredCompletedDistributor.length > 0 ||
            this.filteredCompletedUnproductive.length > 0 ||
            this.filteredCancelled.length > 0 ||
            this.filteredRemainingVisits.length > 0
        );
    }

    //added by Fuzail - Updated to check filtered records
    //Checking records are not there for Visit task
    get hasNoVisitRecords() {
        return (
            !this.isLoading &&
            this.filteredNotStarted.length === 0 &&
            this.filteredInProgress.length === 0 &&
            this.filteredCompletedOrderReceived.length === 0 &&
            this.filteredCompletedDistributor.length === 0 &&
            this.filteredCompletedUnproductive.length === 0 &&
            this.filteredCancelled.length === 0 &&
            this.filteredRemainingVisits.length === 0
        );
    }

    //Handle the Visit task record onclick event
    handleVisitClick(event) {
        const todayDate = new Date().toISOString().split('T')[0]; // Get today's date in YYYY-MM-DD format
        const visitId = event.currentTarget.dataset.id;
        if (this.selectedDate !== todayDate) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'You can only proceed with today’s visits.',
                    variant: 'error'
                })
            );
            return;
        }
        if (visitId) {
            this.selectedVisit = visitId;
            // added by fuzail - Check if this is a Distributor visit task
            const selectedRecord = this.visitRecords.find(record => record.Id === visitId);
            this.isDistributorVisit = selectedRecord && selectedRecord.Distributor__c && !selectedRecord.Account__c;
            
            this.showChildComponent = true;
            //Added by Supriya
            sessionStorage.setItem('visitId', visitId);
            sessionStorage.setItem('showChildComponent', 'true');
            localStorage.setItem('visitId', visitId);
            localStorage.setItem('showChildComponent', 'true');
            // Store isDistributorVisit flag so it persists on refresh
            localStorage.setItem('isDistributorVisit', this.isDistributorVisit ? 'true' : 'false');
            const urlStr = `${window.location.origin}${window.location.pathname}?visitId=${this.selectedVisit}`;

            // Update the URL without reloading the page (using replaceState)
            window.history.replaceState({}, '', urlStr);
        }
    }

    // Handle back on child component
    // added by fuzail - Re-normalize visit records when coming back to ensure Account__r is always defined
    handleBack() {
        // Clear visitId from storage
        sessionStorage.removeItem('visitId');
        sessionStorage.removeItem('showChildComponent');
        localStorage.removeItem('visitId');
        localStorage.removeItem('showChildComponent');
        localStorage.removeItem('isDistributorVisit');
        
        // Store the selected date so we can restore it after reload
        if (this.selectedDayKey) {
            sessionStorage.setItem('restoreSelectedDate', this.selectedDayKey);
            sessionStorage.setItem('restoreSelectedDateFormatted', this.selectedDate);
        }
        
        // Remove visitId from URL
        const urlStr = `${window.location.origin}${window.location.pathname}`;
        window.history.replaceState({}, '', urlStr);
        
        // Hard refresh - reload entire page to guarantee fresh data
        // This ensures the status is updated correctly after completing a visit
        window.location.reload();
    }

    //Create_New_Visit onclick event
    handleCreateNewVisit() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Create_New_Visit'
            }
        });
    }

    //Visit_Summary onclick event
    generateVisitSummary() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Visit_Summary'
            }
        });
    }

    handleBeatChange() {
        checkAnyVisitTaskInprogress()
            .then(result => {
                if (result) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message:
                                'A Visit Task is currently in progress. Please complete it before changing the beat.',
                            variant: 'error'
                        })
                    );
                } else {
                    // No task in progress, proceed with navigation
                    this[NavigationMixin.Navigate]({
                        type: 'standard__navItemPage',
                        attributes: {
                            apiName: 'Beat_Change'
                        }
                    });
                }
            })
            .catch(error => {
                // Optional: show error if Apex call fails
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }
}