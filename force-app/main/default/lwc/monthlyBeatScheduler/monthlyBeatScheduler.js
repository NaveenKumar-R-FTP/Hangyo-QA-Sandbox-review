import { LightningElement, track } from 'lwc';
import getBeatsByUser from '@salesforce/apex/MonthlyBeatSchedulerController.getBeatsByUser';
import saveMonthlyBeatPlans from '@salesforce/apex/MonthlyBeatSchedulerController.saveMonthlyBeatPlans';
import YEAR_LIMIT from '@salesforce/label/c.Year';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class MonthlyBeatScheduler extends LightningElement {

    /* ---------------- State ---------------- */
    selectedUserId;
    selectedMonth;
    selectedYear;

    @track beatOptions = [];
    @track calendarWeeks = [];

    beatSelections = {};     // { 'YYYY-MM-DD': beatId }
    beatsCache = {};

    weekDays = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];

    /* ---------------- Init ---------------- */
    connectedCallback() {
        const today = new Date();
        this.selectedMonth = today.getMonth();
        this.selectedYear = today.getFullYear().toString();
        this.generateCalendar();
    }

    /* ---------------- User Change ---------------- */
    handleUserChange(event) {
        this.selectedUserId = event.detail.recordId;
        this.loadBeatsForUser();
    }

    /* ---------------- Fetch Beats ---------------- */
    loadBeatsForUser() {
        if (!this.selectedUserId) {
            this.resetSelections();
            return;
        }

        getBeatsByUser({
            userId: this.selectedUserId,
            month: this.selectedMonth,
            year: this.selectedYear
        })
        .then(result => {

            // ✅ Add "None" option
            const noneOption = { label: 'None', value: 'NONE' };

            this.beatsCache[this.selectedUserId] = [
                noneOption,
                ...result.beats.map(b => ({
                    label: b.Name,
                    value: b.Id
                }))
            ];

            this.beatOptions = this.beatsCache[this.selectedUserId];

            // Existing selections
            this.beatSelections = { ...result.existingPlans };

            this.generateCalendar();
        })
        .catch(error => {
            console.error(error);
            this.resetSelections();
        });
    }

    /* ---------------- Month / Year ---------------- */
    get monthOptions() {
        return [
            { label: 'January', value: 0 },
            { label: 'February', value: 1 },
            { label: 'March', value: 2 },
            { label: 'April', value: 3 },
            { label: 'May', value: 4 },
            { label: 'June', value: 5 },
            { label: 'July', value: 6 },
            { label: 'August', value: 7 },
            { label: 'September', value: 8 },
            { label: 'October', value: 9 },
            { label: 'November', value: 10 },
            { label: 'December', value: 11 }
        ];
    }

    get yearOptions() {
        const years = [];
        const startYear = 2025;
        const endYear = parseInt(YEAR_LIMIT, 10);

        for (let i = startYear; i <= endYear; i++) {
            years.push({
                label: i.toString(),
                value: i.toString()
            });
        }
        return years;
    }

    handleMonthChange(event) {
        this.selectedMonth = Number(event.detail.value);
        this.loadBeatsForUser();
    }

    handleYearChange(event) {
        this.selectedYear = event.detail.value;
        this.loadBeatsForUser();
    }

    /* ---------------- Calendar ---------------- */
    generateCalendar() {
        const firstDay = new Date(this.selectedYear, this.selectedMonth, 1);
        const daysInMonth = new Date(this.selectedYear, this.selectedMonth + 1, 0).getDate();

        let weeks = [];
        let week = [];
        let id = 0;

        for (let i = 0; i < firstDay.getDay(); i++) {
            week.push({ key: `empty-${i}` });
        }

        for (let day = 1; day <= daysInMonth; day++) {
            const monthStr = String(this.selectedMonth + 1).padStart(2, '0');
            const dayStr = String(day).padStart(2, '0');
            const date = `${this.selectedYear}-${monthStr}-${dayStr}`;

            const today = new Date();
            today.setHours(0,0,0,0);

            const currentDate = new Date(this.selectedYear, this.selectedMonth, day);
            currentDate.setHours(0,0,0,0);

            const isPast = currentDate < today;

            week.push({
                key: date,
                date,
                dayNumber: day,
                selectedBeat: this.beatSelections[date] || null, // 👈 null = show placeholder
                isPast
            });

            if (week.length === 7) {
                weeks.push({ id: id++, days: week });
                week = [];
            }
        }

        if (week.length) {
            while (week.length < 7) {
                week.push({ key: `empty-end-${week.length}` });
            }
            weeks.push({ id: id++, days: week });
        }

        this.calendarWeeks = weeks;
    }

    /* ---------------- Beat Change ---------------- */
    handleBeatChange(event) {
        const date = event.target.dataset.date;
        const value = event.detail.value;

        // ✅ NONE = clear beat
        if (value === 'NONE') {
            const updated = { ...this.beatSelections };
            delete updated[date];
            this.beatSelections = updated;
        } else {
            this.beatSelections = {
                ...this.beatSelections,
                [date]: value
            };
        }

        this.generateCalendar();
    }

    handleBeatDropdownClick(event) {
        if (!this.selectedUserId) {
            event.preventDefault();
            event.stopPropagation();
            this.showToast(
                'Select User First',
                'Please select a user before selecting beats.',
                'warning'
            );
        }
    }

    /* ---------------- Save ---------------- */
    handleSave() {
        if (!this.selectedUserId || Object.keys(this.beatSelections).length === 0) {
            this.showToast('Error', 'Please select user and beats', 'error');
            return;
        }

        saveMonthlyBeatPlans({
            userId: this.selectedUserId,
            month: this.selectedMonth,
            year: this.selectedYear,
            beatSelections: this.beatSelections
        })
        .then(() => {
            this.showToast('Success', 'Monthly Beat Plan created successfully', 'success');
            this.resetAll();
        })
        .catch(error => {
            console.error(error);
            this.showToast('Error', error.body?.message || 'Something went wrong', 'error');
        });
    }

    /* ---------------- Reset ---------------- */
    resetSelections() {
        this.beatOptions = [];
        this.beatSelections = {};
        this.calendarWeeks = [];
        this.generateCalendar();
    }

    resetAll() {
        this.selectedUserId = null;
        this.beatOptions = [];
        this.beatSelections = {};
        this.beatsCache = {};
        this.generateCalendar();

        const picker = this.template.querySelector('lightning-record-picker');
        if (picker) picker.value = null;
    }

    /* ---------------- Toast ---------------- */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}