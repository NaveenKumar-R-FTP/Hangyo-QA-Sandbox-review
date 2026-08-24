import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMultiplePicklistValues from '@salesforce/apex/ClaimHeaderController.getMultiplePicklistValues';
import getAccountsAndCaseTypesMap from '@salesforce/apex/ClaimHeaderController.getAccountsAndCaseTypesMap';
import createClaimWithAttachment from '@salesforce/apex/ClaimHeaderController.createClaimWithAttachment';
import isClaimHeaderApproved from '@salesforce/apex/ClaimHeaderController.isClaimHeaderApproved';

export default class ClaimScreen extends LightningElement {
    @track statusOptions = [];
    @track yearOptions = [];
    @track monthOptions = [];
    @track accountOptions = [];
    @track claimTypeOptions = [];
    @track distributordisable = false;
    @track loader = false;
    @track disableyear = false;
    @track disablesavebutton = false;
    lastValidFilesMap = {};
    isAddDisabled = false;
    @track selectedAccount;
    @track selectedMonth;
    @track selectedYear;
    @track selectedStatus = 'Draft';
    @track submittedDate;
    @track claimDescription;
    @track claimRows = [];
    connectedCallback() {
        this.submittedDate = new Date().toISOString().split('T')[0];
        this.addRow();
    }
    addRow() {
        this.claimRows = [...this.claimRows, this.createNewRow()];
    }
    createNewRow() {
        const now = new Date();
        const uniqueKey = now.getFullYear().toString() + (now.getMonth() + 1).toString().padStart(2, '0') + now.getDate().toString().padStart(2, '0') + now.getHours().toString().padStart(2, '0') + now.getMinutes().toString().padStart(2, '0') + now.getSeconds().toString().padStart(2, '0') + now.getMilliseconds().toString().padStart(3, '0');
        return {
            id: `row-${uniqueKey}`,
            caseTypeId: null,
            amount: '',
            date: '',
            remarks: '',
            files: []
        };
    }
    removeRow(event) {
        if (this.claimRows.length <= 1) {
            this.showToast('Warning', 'At least one claim Line Item is required', 'warning');
            return;
        }
        this.isAddDisabled = false;
        const rowId = event.target.dataset.id;
        this.claimRows = this.claimRows.filter(row => row.id != rowId);
    }
    monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    get minClaimDate() {
        if (this.selectedMonth && this.selectedYear) {
            const monthIndex = this.monthNames.indexOf(this.selectedMonth);
            const firstDay = new Date(this.selectedYear, monthIndex, 1);
            const year = firstDay.getFullYear();
            const month = String(firstDay.getMonth() + 1).padStart(2, '0');
            const day = String(firstDay.getDate()).padStart(2, '0');
            return `${year}-${month}-${day}`;
        }
        return null;
    }
    get maxClaimDate() {
        if (this.selectedMonth && this.selectedYear) {
            const monthIndex = this.monthNames.indexOf(this.selectedMonth);
            const lastDay = new Date(this.selectedYear, monthIndex + 1, 0);
            const year = lastDay.getFullYear();
            const month = String(lastDay.getMonth() + 1).padStart(2, '0');
            const day = String(lastDay.getDate()).padStart(2, '0');
            return `${year}-${month}-${day}`;
        }
        return null;
    }
    handleFieldChange(event) {
        const rowId = event.target.closest('tr').dataset.key;
        const fieldName = this.getFieldName(event.target);
        console.log('OUTPUT : ', fieldName);
        if (!fieldName) return;
        if (event.target.type === 'file' && event.target.files.length === 0) {
            return;
        }
        if (event.target.type === 'file' && event.target.files.length > 0) {
            const allowedTypes = ['image/jpeg', 'image/png', 'application/pdf', 'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'];
            const allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf', 'xls', 'xlsx'];
            const newFiles = Array.from(event.target.files);
            const rowId = event.target.closest('tr').dataset.key;
            const maxFilesPerRow = 3;
            const maxOverallSize = 3 * 1024 * 1024; // 3 MB overall
            const existingRow = this.claimRows.find(row => row.id == rowId);
            console.log('existingRow : ', JSON.stringify(existingRow));
            const existingFiles = existingRow?.files || [];
            // ------------------------------
            //  CHECK PER ROW MAX FILE COUNT
            // ------------------------------
            const totalFilesCount = existingFiles.length + newFiles.length;
            if (totalFilesCount > maxFilesPerRow) {
                this.showToast('Warning', `You can upload only ${maxFilesPerRow} files per line item.`, 'warning');
                event.target.value = null;
                if (this.lastValidFilesMap[rowId]) {
                    try {
                        // event.target.files = this.lastValidFilesMap[rowId];
                    } catch (e) {
                        // fallback (browser restriction)
                        event.target.value = null;
                    }
                }
                return;
            }
            // ---------------------------------------------------
            //  CHECK TOTAL UPLOADED FILE SIZE ACROSS ALL ROWS
            // ---------------------------------------------------
            let overallSize = 0;
            this.claimRows.forEach(row => {
                (row.files || []).forEach(file => {
                    overallSize += file.size || 0;
                });
            });
            for (let file of newFiles) {
                const fileExt = file.name.split('.').pop().toLowerCase();
                if (!allowedTypes.includes(file.type) || !allowedExtensions.includes(fileExt)) {
                    this.showToast('Warning', 'Only JPG, PNG, PDF, Excel files are allowed', 'warning');
                    if (this.lastValidFilesMap[rowId]) {}
                    return;
                }
            }
            newFiles.forEach(file => {
                overallSize += file.size;
            });
            if (overallSize > maxOverallSize) {
                this.showToast('Warning', `Total uploaded file size across all rows cannot exceed 3 MB.`, 'warning');
                this.claimRows = this.claimRows.filter(row => row.files && row.files.length > 0);
                this.isAddDisabled = true;
                event.target.value = '';
                return;
            }
            this.lastValidFilesMap[rowId] = event.target.files;
            // --------------------------------
            //  PROCEED TO ADD NEW FILES
            // --------------------------------
            newFiles.forEach(file => {
                const reader = new FileReader();
                reader.onload = (() => {
                    const base64 = reader.result.split(',')[1];
                    if (!base64) return;
                    this.claimRows = this.claimRows.map(row => {
                        if (row.id == rowId) {
                            return {
                                ...row,
                                files: [...(row.files || []), {
                                    base64: base64,
                                    name: file.name,
                                    type: file.type,
                                    size: file.size
                                }]
                            };
                        }
                        return row;
                    });
                    this.isAddDisabled = false;
                });
                reader.readAsDataURL(file);
            });
        } else {
            if (fieldName === 'amount') {
                let value = event.target.value;
                value = value.replace(/[, ]/g, '');
                if (!/^\d*\.?\d*$/.test(value)) {
                    this.showToast('Warning', 'Only numeric values are allowed', 'warning');
                    event.target.value = '';
                    return;
                }
                const parts = value.split('.');
                const integerPart = parts[0];
                const decimalPart = parts[1] || '';
                if (integerPart.length > 12) {
                    this.showToast('Warning', 'Amount cannot exceed 12 digits in total', 'warning');
                    event.target.value = integerPart.slice(0, 12);
                    return;
                }
                const totalDigits = integerPart.length + decimalPart.length;
                if (totalDigits > 12) {
                    this.showToast('Warning', 'Total amount length (excluding decimal) cannot exceed 12 digits', 'warning');
                    event.target.value = value.slice(0, value.length - 1);
                    return;
                }
                if (decimalPart.length > 2) {
                    this.showToast('Warning', 'Only up to 2 digits are allowed after decimal', 'warning');
                    event.target.value = integerPart + '.' + decimalPart.slice(0, 2);
                    return;
                }
                event.target.value = value;
            }
            if (fieldName === 'date') {
                const value = event.target.value;
                if (!value) return;
                if (!this.selectedMonth || !this.selectedYear) {
                    this.showToast('warning', 'Please select Month and Year first', 'warning');
                    event.target.value = '';
                    return;
                }
                const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
                const monthIndex = monthNames.indexOf(this.selectedMonth); // 0-based
                if (monthIndex === -1) return;
                const [yearStr, monthStr, dayStr] = value.split('-');
                const selectedYear = parseInt(yearStr, 10);
                const selectedMonth = parseInt(monthStr, 10); // 1-based
                const selectedDay = parseInt(dayStr, 10);
                if (selectedYear !== this.selectedYear && selectedMonth !== monthIndex + 1) {
                    this.showToast('warning', 'Please select a date within the selected Month and Year', 'warning');
                    event.target.value = '';
                    this.selectedDate = null;
                    return;
                }
                const daysInMonth = new Date(this.selectedYear, monthIndex + 1, 0).getDate();
                if (selectedDay < 1 || selectedDay > daysInMonth) {
                    this.showToast('warning', 'Invalid day for selected month', 'warning');
                    event.target.value = '';
                    this.selectedDate = null;
                    return;
                }
                const selectedDateObj = new Date(selectedYear, selectedMonth - 1, selectedDay);
                const today = new Date();
                selectedDateObj.setHours(0, 0, 0, 0);
                today.setHours(0, 0, 0, 0);
                if (selectedDateObj.getTime() > today.getTime()) {
                    this.showToast('warning', 'Future Date Not Allowed', 'warning');
                    event.target.value = '';
                    this.selectedDate = null;
                    return;
                }
                this.selectedDate = value;
            }
            const value = event.target.value;
            this.claimRows = this.claimRows.map(row => row.id == rowId ? {
                ...row,
                [fieldName]: value
            } : row);
        }
    }
    getFieldName(target) {
        if (target.tagName === 'LIGHTNING-COMBOBOX') return 'caseTypeId';
        if (target.type === 'text' && target.placeholder === 'Amount') return 'amount';
        if (target.type === 'date') return 'date';
        if (target.type === 'text' && target.placeholder === 'Remarks') return 'remarks';
        if (target.type === 'file') return 'files';
        return null;
    }
    @wire(getMultiplePicklistValues)
    wiredPicklists({
        error,
        data
    }) {
        if (data) {
            const today = new Date();
            const currentMonthIndex = today.getMonth();
            const currentYear = today.getFullYear();
            const allMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
            const monthOptions = [];
            const yearSet = new Set();
            for (let i = 2; i >= 0; i--) {
                let monthIndex = currentMonthIndex - i;
                console.log('currentMonthIndex => ', JSON.stringify(currentMonthIndex));
                console.log('Month monthIndex => ', JSON.stringify(monthIndex));
                let year = currentYear;
                if (monthIndex < 0) {
                    monthIndex += 12; // wrap around if negative
                    year -= 1;
                }
                monthOptions.push({
                    label: allMonths[monthIndex],
                    value: allMonths[monthIndex]
                });
                yearSet.add(year);
            }
            this.monthOptions = monthOptions;
            this.yearOptions = (data.yearoption || []).filter(year => yearSet.has(parseInt(year.value)));
            console.log('this.yearOptions : ', this.yearOptions);
            console.log('Month Options => ', JSON.stringify(this.monthOptions));
            console.log('Year Options => ', JSON.stringify(this.yearOptions));
            if (this.yearOptions.length === 1) {
                this.selectedYear = this.yearOptions[0].value;
                this.disableyear = true;
            } else {
                this.selectedYear = null;
            }
            this.statusOptions = data.statusoption || [];
        } else if (error) {
            console.error('Error fetching picklist values:', error);
        }
    }
    @wire(getAccountsAndCaseTypesMap)
    wiredData({
        error,
        data
    }) {
        if (data) {
            if (data.accounts) {
                console.log('data--273 : ', JSON.stringify(data));
                this.accountOptions = data.accounts.map(acc => ({
                    label: acc.Name,
                    value: acc.Id
                }));
                if (this.accountOptions.length === 1) {
                    this.selectedAccount = this.accountOptions[0].value;
                    this.distributordisable = true;
                }
            }
            if (data.caseTypes) {
                this.claimTypeOptions = data.caseTypes.map(ct => ({
                    label: ct.Name,
                    value: ct.Id
                }));
            }
        } else if (error) {
            console.error('Error fetching accounts/case types:', error);
        }
    }
    handleAccountChange(event) {
        this.selectedAccount = event.detail.value;
    }
    handleMonthChange(event) {
        const newMonth = event.detail.value;
        this.selectedMonth = newMonth;
        if (!this.selectedAccount || !this.selectedYear) {
            return;
        }
        isClaimHeaderApproved({
            distributorId: this.selectedAccount,
            month: this.selectedMonth,
            year: this.selectedYear
        }).then(isApproved => {
            if (isApproved) {
                this.showToast('Error', this.selectedMonth + ' ' + 'month claim has already been approved. Please add claim for next month .', 'error');
                this.selectedMonth = null;
            } else {
                this.claimRows = this.claimRows.map(row => {
                    return {
                        ...row,
                        date: ''
                    };
                });
            }
        }).catch(error => {
            console.error('Error:', error);
        });
    }
    handleYearChange(event) {
        this.selectedYear = event.detail.value;
    }
    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }
    handleDateChange(event) {
        this.submittedDate = event.target.value;
    }
    handleDescriptionChange(event) {
        this.claimDescription = event.target.value;
    }
    handleSubmit() {
        if (this.selectedAccount == '' || this.selectedAccount == undefined) {
            this.showToast('warning', 'Please select Distributor', 'warning');
            return;
        }
        if (this.selectedMonth == '' || this.selectedMonth == undefined) {
            this.showToast('warning', 'Please select Month', 'warning');
            return;
        }
        for (let i = 0; i < this.claimRows.length; i++) {
            const row = this.claimRows[i];
            if (!row.caseTypeId) {
                this.showToast('warning', `Row ${i + 1}: Please select Claim Type`, 'warning');
                return;
            }
            console.log('row---->', JSON.stringify(row));
            if (!row.amount) {
                this.showToast('warning', `Row ${i + 1}: Please enter Amount`, 'warning');
                return;
            }
            if (!row.date) {
                this.showToast('warning', `Row ${i + 1}: Please select date`, 'warning');
                return;
            }
            if (!row.files || row.files.length === 0) {
                this.showToast('warning', `Row ${i + 1}: Please upload at least one file`, 'warning');
                return;
            }
        }
        this.disablesavebuttonn = true;
        const claimHeader = {
            distributorId: this.selectedAccount,
            claimMonth: this.selectedMonth,
            claimYear: this.selectedYear,
            submittedDate: this.submittedDate,
            claimStatus: this.selectedStatus,
            claimDescription: this.claimDescription
        };
        const claimLines = this.claimRows.map(row => ({
            lineId: row.id,
            caseTypeId: row.caseTypeId,
            amount: row.amount,
            date: row.date,
            remarks: row.remarks,
            files: row.files
        }));
        const payload = {
            header: claimHeader,
            lines: claimLines
        };
        this.loader = true;
        createClaimWithAttachment({
            requestData: JSON.stringify(payload)
        }).then(result => {
            this.disablesavebuttonn = false;
            if (result.status === 'SUCCESS') {
                this.showToast('Success', 'Claim created successfully.', 'success');
                setTimeout(() => {
                    this.loader = false;
                    window.location.reload();
                }, 1000);
            } else if (result.status === 'ERROR') {
                this.loader = false;
                this.disablesavebuttonn = false;
                const message = result.message || 'An unknown error occurred while creating the claim.';
                this.showToast('warning', message, 'warning');
            } else {
                this.loader = false;
                this.disablesavebuttonn = false;
                this.showToast('Error', JSON.stringify(result), 'error');
            }
        }).catch(error => {
            this.loader = false;
            this.disablesavebuttonn = false;
            let message = JSON.stringify(error);
            this.showToast('Error', message, 'error');
            console.log('createClaimWithAttachment error:', JSON.stringify(error));
        });
    }
    handlecancel() {
        this.loader = true;
        window.location.reload();
    }
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }
    removeFile(event) {
        const rowId = event.target.dataset.id;
        const fileIndex = event.target.dataset.index;
        this.claimRows = this.claimRows.map(row => {
            if (row.id == rowId) {
                let updatedFiles = [...(row.files || [])];
                updatedFiles.splice(fileIndex, 1);
                if (updatedFiles.length === 0) {
                    this.showToast('Warning', 'At least one file is required', 'warning');
                }
                return {
                    ...row,
                    files: updatedFiles
                };
            }
            return row;
        });
    }
    previewFile(event) {
        const rowId = event.currentTarget.dataset.id;
        const index = event.currentTarget.dataset.index;
        const row = this.claimRows.find(r => r.id == rowId);
        const file = row?.files?.[index];
        if (!file) return;
        const byteCharacters = atob(file.base64);
        const byteNumbers = new Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
            byteNumbers[i] = byteCharacters.charCodeAt(i);
        }
        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], {
            type: file.type
        });
        const blobUrl = URL.createObjectURL(blob);
        window.open(blobUrl, '_blank');
    }
}