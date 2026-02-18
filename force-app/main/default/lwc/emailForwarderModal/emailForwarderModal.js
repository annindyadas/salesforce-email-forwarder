import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEmailsByRecordId from '@salesforce/apex/EmailForwarder.getEmailsByRecordId';
import forwardSelectedEmails from '@salesforce/apex/EmailForwarder.forwardSelectedEmails';
import getEmailsForDownload from '@salesforce/apex/EmailForwarder.getEmailsForDownload';
import { createZipFile, downloadZipFile, reduceErrors } from 'c/emailUtils';

const COLUMNS = [
    { 
        label: 'Subject', 
        fieldName: 'subject', 
        type: 'text', 
        sortable: true,
        wrapText: true,
        initialWidth: 280
    },
    { 
        label: 'From', 
        fieldName: 'fromAddress', 
        type: 'text', 
        sortable: true,
        initialWidth: 180
    },
    { 
        label: 'To', 
        fieldName: 'toAddress', 
        type: 'text', 
        sortable: true,
        initialWidth: 180
    },
    { 
        label: 'Date', 
        fieldName: 'formattedDate', 
        type: 'text', 
        sortable: true,
        initialWidth: 150
    },
    { 
        label: 'Direction', 
        fieldName: 'direction', 
        type: 'text', 
        sortable: true,
        initialWidth: 90
    },
    { 
        label: 'Attachments', 
        fieldName: 'attachmentCount', 
        type: 'number', 
        sortable: true,
        initialWidth: 100,
        cellAttributes: { alignment: 'center' }
    }
];

export default class EmailForwarderModal extends LightningElement {
    _recordId;
    
    // Use setter to trigger data load when recordId is set by the framework
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value && value !== this._recordId) {
            this._recordId = value;
            this.loadEmails();
        }
    }
    
    @track emails = [];
    @track selectedEmailIds = [];
    @track isLoading = true;
    @track error = undefined;
    @track sortedBy = 'formattedDate';
    @track sortedDirection = 'desc';
    @track isSending = false;
    @track isDownloading = false;
    
    // Recipient email - user must enter this
    @track recipientEmail = '';
    
    columns = COLUMNS;
    
    // Computed property to show content (not loading and no error)
    get showContent() {
        return !this.isLoading && !this.error;
    }

    get hasEmails() {
        return this.emails && this.emails.length > 0;
    }

    get noEmails() {
        return !this.hasEmails;
    }
    
    get hasSelectedEmails() {
        return this.selectedEmailIds && this.selectedEmailIds.length > 0;
    }
    
    get selectedCount() {
        return this.selectedEmailIds.length;
    }
    
    get totalCount() {
        return this.emails.length;
    }
    
    get sendButtonLabel() {
        if (this.isSending) {
            return 'Sending...';
        }
        return this.selectedCount > 0 
            ? `Send ${this.selectedCount} Email(s)` 
            : 'Send';
    }
    
    get isSendDisabled() {
        return !this.hasSelectedEmails || this.isSending || !this.recipientEmail;
    }

    get downloadButtonLabel() {
        if (this.isDownloading) {
            return 'Downloading...';
        }
        return this.selectedCount > 0 
            ? `Download ${this.selectedCount} Email(s)` 
            : 'Download';
    }

    get isDownloadDisabled() {
        return !this.hasSelectedEmails || this.isDownloading;
    }

    get modalTitle() {
        return `Forward Emails (${this.totalCount} available)`;
    }

    // Imperative call to fetch fresh emails from server
    loadEmails() {
        this.isLoading = true;
        this.error = undefined;
        // Clear existing emails to prevent duplicates
        this.emails = [];
        this.selectedEmailIds = [];
        
        getEmailsByRecordId({ recordId: this._recordId })
            .then(data => {
                this.emails = data ? [...data] : [];
                this.error = undefined;
                // Apply initial sorting
                this.sortData(this.sortedBy, this.sortedDirection);
            })
            .catch(error => {
                this.error = reduceErrors(error);
                this.emails = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Handle row selection in the datatable
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedEmailIds = selectedRows.map(row => row.id);
    }

    // Handle column sorting
    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
        this.sortData(fieldName, sortDirection);
    }

    // Sort the data based on field and direction
    sortData(fieldName, direction) {
        const parseData = JSON.parse(JSON.stringify(this.emails));
        
        const keyValue = (a) => {
            return a[fieldName] ? String(a[fieldName]).toLowerCase() : '';
        };
        
        const isReverse = direction === 'asc' ? 1 : -1;
        
        parseData.sort((x, y) => {
            x = keyValue(x);
            y = keyValue(y);
            return isReverse * ((x > y) - (y > x));
        });
        
        this.emails = parseData;
    }

    // Handle recipient email input change
    handleRecipientChange(event) {
        this.recipientEmail = event.target.value;
    }

    // Handle the Send button click
    async handleSend() {
        if (!this.hasSelectedEmails) {
            this.showToast('Warning', 'Please select at least one email to forward.', 'warning');
            return;
        }

        if (!this.recipientEmail) {
            this.showToast('Warning', 'Please enter a recipient email address.', 'warning');
            return;
        }

        this.isSending = true;

        try {
            const result = await forwardSelectedEmails({ 
                emailIds: this.selectedEmailIds, 
                recipientEmail: this.recipientEmail 
            });
            
            this.showToast('Success', result, 'success');
            this.handleClose();
        } catch (error) {
            this.showToast('Error', reduceErrors(error), 'error');
        } finally {
            this.isSending = false;
        }
    }

    // Handle the Download button click - downloads selected emails as ZIP
    async handleDownload() {
        if (!this.hasSelectedEmails) {
            this.showToast('Warning', 'Please select at least one email to download.', 'warning');
            return;
        }

        this.isDownloading = true;

        try {
            // Get email contents from server
            const emailContents = await getEmailsForDownload({ 
                emailIds: this.selectedEmailIds 
            });
            
            if (!emailContents || emailContents.length === 0) {
                this.showToast('Warning', 'No email content available for download.', 'warning');
                return;
            }

            // Create ZIP file using utility
            const zipBlob = await createZipFile(emailContents);
            
            // Download the ZIP file using utility
            downloadZipFile(zipBlob);
            
            this.showToast('Success', `Downloaded ${emailContents.length} email(s) as ZIP`, 'success');
        } catch (error) {
            this.showToast('Error', reduceErrors(error), 'error');
        } finally {
            this.isDownloading = false;
        }
    }

    // Handle the Close button click
    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // Show toast message
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}
