import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEmailsByRecordId from '@salesforce/apex/EmailForwarder.getEmailsByRecordId';
import forwardSelectedEmails from '@salesforce/apex/EmailForwarder.forwardSelectedEmails';
import getEmailsForDownload from '@salesforce/apex/EmailForwarder.getEmailsForDownload';

const COLUMNS = [
    { 
        label: 'Subject', 
        fieldName: 'subject', 
        type: 'text', 
        sortable: true,
        wrapText: true,
        initialWidth: 300
    },
    { 
        label: 'From', 
        fieldName: 'fromAddress', 
        type: 'text', 
        sortable: true,
        initialWidth: 200
    },
    { 
        label: 'To', 
        fieldName: 'toAddress', 
        type: 'text', 
        sortable: true,
        initialWidth: 200
    },
    { 
        label: 'Date', 
        fieldName: 'formattedDate', 
        type: 'text', 
        sortable: true,
        initialWidth: 160
    },
    { 
        label: 'Direction', 
        fieldName: 'direction', 
        type: 'text', 
        sortable: true,
        initialWidth: 100
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
                this.error = this.reduceErrors(error);
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
            this.showToast('Error', this.reduceErrors(error), 'error');
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

            // Create ZIP file
            const zipBlob = await this.createZipFile(emailContents);
            
            // Download the ZIP file
            const downloadLink = document.createElement('a');
            downloadLink.href = URL.createObjectURL(zipBlob);
            downloadLink.download = `emails_${new Date().toISOString().slice(0,10)}.zip`;
            document.body.appendChild(downloadLink);
            downloadLink.click();
            document.body.removeChild(downloadLink);
            URL.revokeObjectURL(downloadLink.href);
            
            this.showToast('Success', `Downloaded ${emailContents.length} email(s) as ZIP`, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isDownloading = false;
        }
    }

    // Create a ZIP file from email contents (pure JavaScript, no external libraries)
    async createZipFile(emailContents) {
        const files = emailContents.map(email => ({
            name: email.fileName,
            content: email.content
        }));

        // Simple ZIP file creation
        const zipParts = [];
        const centralDirectory = [];
        let offset = 0;

        for (const file of files) {
            const encoder = new TextEncoder();
            const fileData = encoder.encode(file.content);
            const fileName = encoder.encode(file.name);
            
            // Local file header
            const localHeader = new Uint8Array(30 + fileName.length);
            const view = new DataView(localHeader.buffer);
            
            view.setUint32(0, 0x04034b50, true); // Local file header signature
            view.setUint16(4, 20, true); // Version needed
            view.setUint16(6, 0, true); // General purpose bit flag
            view.setUint16(8, 0, true); // Compression method (store)
            view.setUint16(10, 0, true); // File last mod time
            view.setUint16(12, 0, true); // File last mod date
            view.setUint32(14, this.crc32(fileData), true); // CRC-32
            view.setUint32(18, fileData.length, true); // Compressed size
            view.setUint32(22, fileData.length, true); // Uncompressed size
            view.setUint16(26, fileName.length, true); // File name length
            view.setUint16(28, 0, true); // Extra field length
            localHeader.set(fileName, 30);
            
            zipParts.push(localHeader);
            zipParts.push(fileData);
            
            // Central directory entry
            const centralEntry = new Uint8Array(46 + fileName.length);
            const centralView = new DataView(centralEntry.buffer);
            
            centralView.setUint32(0, 0x02014b50, true); // Central directory signature
            centralView.setUint16(4, 20, true); // Version made by
            centralView.setUint16(6, 20, true); // Version needed
            centralView.setUint16(8, 0, true); // General purpose bit flag
            centralView.setUint16(10, 0, true); // Compression method
            centralView.setUint16(12, 0, true); // File last mod time
            centralView.setUint16(14, 0, true); // File last mod date
            centralView.setUint32(16, this.crc32(fileData), true); // CRC-32
            centralView.setUint32(20, fileData.length, true); // Compressed size
            centralView.setUint32(24, fileData.length, true); // Uncompressed size
            centralView.setUint16(28, fileName.length, true); // File name length
            centralView.setUint16(30, 0, true); // Extra field length
            centralView.setUint16(32, 0, true); // File comment length
            centralView.setUint16(34, 0, true); // Disk number start
            centralView.setUint16(36, 0, true); // Internal file attributes
            centralView.setUint32(38, 0, true); // External file attributes
            centralView.setUint32(42, offset, true); // Relative offset of local header
            centralEntry.set(fileName, 46);
            
            centralDirectory.push(centralEntry);
            offset += localHeader.length + fileData.length;
        }

        // Calculate central directory size
        let centralDirSize = 0;
        for (const entry of centralDirectory) {
            centralDirSize += entry.length;
        }

        // End of central directory
        const endOfCentralDir = new Uint8Array(22);
        const endView = new DataView(endOfCentralDir.buffer);
        
        endView.setUint32(0, 0x06054b50, true); // End of central directory signature
        endView.setUint16(4, 0, true); // Number of this disk
        endView.setUint16(6, 0, true); // Disk where central directory starts
        endView.setUint16(8, files.length, true); // Number of central directory records on this disk
        endView.setUint16(10, files.length, true); // Total number of central directory records
        endView.setUint32(12, centralDirSize, true); // Size of central directory
        endView.setUint32(16, offset, true); // Offset of start of central directory
        endView.setUint16(20, 0, true); // Comment length

        // Combine all parts
        const allParts = [...zipParts, ...centralDirectory, endOfCentralDir];
        const totalLength = allParts.reduce((sum, part) => sum + part.length, 0);
        const zipData = new Uint8Array(totalLength);
        
        let position = 0;
        for (const part of allParts) {
            zipData.set(part, position);
            position += part.length;
        }

        return new Blob([zipData], { type: 'application/zip' });
    }

    // CRC-32 calculation for ZIP file
    crc32(data) {
        let crc = 0xFFFFFFFF;
        const table = this.getCrc32Table();
        
        for (let i = 0; i < data.length; i++) {
            crc = (crc >>> 8) ^ table[(crc ^ data[i]) & 0xFF];
        }
        
        return (crc ^ 0xFFFFFFFF) >>> 0;
    }

    getCrc32Table() {
        if (!this._crc32Table) {
            this._crc32Table = new Uint32Array(256);
            for (let i = 0; i < 256; i++) {
                let c = i;
                for (let j = 0; j < 8; j++) {
                    c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
                }
                this._crc32Table[i] = c;
            }
        }
        return this._crc32Table;
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

    // Reduce errors to a readable string
    reduceErrors(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error.body) {
            if (typeof error.body.message === 'string') {
                return error.body.message;
            }
            if (error.body.fieldErrors) {
                return Object.values(error.body.fieldErrors)
                    .flat()
                    .map(e => e.message)
                    .join(', ');
            }
        }
        if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}
