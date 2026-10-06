import { LightningElement, track } from 'lwc';
import uploadTargets from '@salesforce/apex/TargetUploadController.uploadTargets';

const TEMPLATE_CSV = 'Employee Code,Month,Year,Secondary Target\r\n11795,8,2026,160000\r\n';

const COLUMNS = [
    { label: 'Row', fieldName: 'rowNumber', type: 'number', initialWidth: 70 },
    { label: 'Employee Code', fieldName: 'employeeCode' },
    { label: 'Status', fieldName: 'status', initialWidth: 100 },
    { label: 'Message', fieldName: 'message' }
];

export default class TargetUpload extends LightningElement {
    @track result;
    @track fileName;
    @track loading = false;
    csvData;
    columns = COLUMNS;

    // A real, user-clicked <a download> link — reliable under Lightning Web Security.
    get templateHref() {
        return 'data:text/csv;charset=utf-8,' + encodeURIComponent(TEMPLATE_CSV);
    }

    handleFile(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;
        this.fileName = file.name;
        this.result = undefined;
        const reader = new FileReader();
        reader.onload = () => { this.csvData = reader.result; };
        reader.readAsText(file);
    }

    handleUpload() {
        if (!this.csvData) return;
        this.loading = true;
        this.result = undefined;
        uploadTargets({ csvData: this.csvData })
            .then((res) => { this.result = res; })
            .catch((e) => {
                this.result = {
                    total: 0, success: 0, failed: 0,
                    rows: [{ rowNumber: 0, employeeCode: '', status: 'Error',
                             message: (e && e.body && e.body.message) || 'Upload failed' }]
                };
            })
            .finally(() => { this.loading = false; });
    }

    get hasResult() { return this.result != null; }
    get uploadDisabled() { return this.loading || !this.csvData; }
}