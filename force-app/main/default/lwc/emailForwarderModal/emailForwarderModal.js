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
    @api recordId;
    
    @track emails = [];
    @track selectedEmailIds = [];
    @track isLoading = true;
    @track error = undefined;
    @track sortedBy = 'formattedDate';
    @track sortedDirection = 'desc';
    @track isSending = false;
    @track isDownloading = false;
    
    // Flag to prevent duplicate loading
    isInitialized = false;
    
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

    // Lifecycle hook - called when component is inserted into the DOM
    connectedCallback() {
        // Prevent duplicate loading if already initialized
        if (!this.isInitialized) {
            this.isInitialized = true;
            this.loadEmails();
        }
    }

    // Imperative call to fetch fresh emails from server
    loadEmails() {
        this.isLoading = true;
        this.error = undefined;
        // Clear existing emails to prevent duplicates
        this.emails = [];
        this.selectedEmailIds = [];
        
        getEmailsByRecordId({ recordId: this.recordId })
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

    // Handle the Download button click
    async handleDownload() {
        if (!this.hasSelectedEmails) {
            this.showToast('Warning', 'Please select at least one email to download.', 'warning');
            return;
        }

        this.isDownloading = true;

        try {
            // Get email contents from Apex
            const emailContents = await getEmailsForDownload({ emailIds: this.selectedEmailIds });
            
            // Create ZIP file using pure JavaScript
            const zipBlob = this.createZipFile(emailContents);
            
            // Create download link
            const downloadLink = document.createElement('a');
            downloadLink.href = URL.createObjectURL(zipBlob);
            downloadLink.download = 'emails_' + new Date().getTime() + '.zip';
            document.body.appendChild(downloadLink);
            downloadLink.click();
            document.body.removeChild(downloadLink);
            URL.revokeObjectURL(downloadLink.href);
            
            this.showToast('Success', `${this.selectedCount} email(s) downloaded successfully.`, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isDownloading = false;
        }
    }

    /**
     * Creates a ZIP file from an array of files using pure JavaScript
     * ZIP format specification: https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
     * @param {Array} files - Array of {fileName, content} objects
     * @returns {Blob} - ZIP file as a Blob
     */
    createZipFile(files) {
        const encoder = new TextEncoder();
        const centralDirectory = [];
        const fileDataParts = [];
        let offset = 0;

        for (const file of files) {
            const fileName = file.fileName;
            const fileContent = file.content;
            const fileNameBytes = encoder.encode(fileName);
            const fileContentBytes = encoder.encode(fileContent);
            
            // Calculate CRC32
            const crc = this.crc32(fileContentBytes);
            
            // Local file header (30 bytes + fileName length)
            const localHeader = new Uint8Array(30 + fileNameBytes.length);
            const localView = new DataView(localHeader.buffer);
            
            localView.setUint32(0, 0x04034b50, true);  // Local file header signature
            localView.setUint16(4, 20, true);          // Version needed to extract (2.0)
            localView.setUint16(6, 0, true);           // General purpose bit flag
            localView.setUint16(8, 0, true);           // Compression method (0 = stored)
            localView.setUint16(10, 0, true);          // File last modification time
            localView.setUint16(12, 0, true);          // File last modification date
            localView.setUint32(14, crc, true);        // CRC-32
            localView.setUint32(18, fileContentBytes.length, true);  // Compressed size
            localView.setUint32(22, fileContentBytes.length, true);  // Uncompressed size
            localView.setUint16(26, fileNameBytes.length, true);     // File name length
            localView.setUint16(28, 0, true);          // Extra field length
            
            // Add file name to local header
            localHeader.set(fileNameBytes, 30);
            
            // Store local header offset for central directory
            const localHeaderOffset = offset;
            
            // Add local header and file content to file data
            fileDataParts.push(localHeader);
            fileDataParts.push(fileContentBytes);
            offset += localHeader.length + fileContentBytes.length;
            
            // Central directory file header (46 bytes + fileName length)
            const centralHeader = new Uint8Array(46 + fileNameBytes.length);
            const centralView = new DataView(centralHeader.buffer);
            
            centralView.setUint32(0, 0x02014b50, true);   // Central directory signature
            centralView.setUint16(4, 20, true);            // Version made by
            centralView.setUint16(6, 20, true);            // Version needed to extract
            centralView.setUint16(8, 0, true);             // General purpose bit flag
            centralView.setUint16(10, 0, true);            // Compression method
            centralView.setUint16(12, 0, true);            // File last modification time
            centralView.setUint16(14, 0, true);            // File last modification date
            centralView.setUint32(16, crc, true);          // CRC-32
            centralView.setUint32(20, fileContentBytes.length, true);  // Compressed size
            centralView.setUint32(24, fileContentBytes.length, true);  // Uncompressed size
            centralView.setUint16(28, fileNameBytes.length, true);     // File name length
            centralView.setUint16(30, 0, true);            // Extra field length
            centralView.setUint16(32, 0, true);            // File comment length
            centralView.setUint16(34, 0, true);            // Disk number start
            centralView.setUint16(36, 0, true);            // Internal file attributes
            centralView.setUint32(38, 0, true);            // External file attributes
            centralView.setUint32(42, localHeaderOffset, true);  // Relative offset of local header
            
            // Add file name to central header
            centralHeader.set(fileNameBytes, 46);
            centralDirectory.push(centralHeader);
        }
        
        // Calculate central directory size
        const centralDirectoryOffset = offset;
        let centralDirectorySize = 0;
        for (const header of centralDirectory) {
            centralDirectorySize += header.length;
        }
        
        // End of central directory record (22 bytes)
        const endOfCentralDir = new Uint8Array(22);
        const endView = new DataView(endOfCentralDir.buffer);
        
        endView.setUint32(0, 0x06054b50, true);           // End of central directory signature
        endView.setUint16(4, 0, true);                     // Number of this disk
        endView.setUint16(6, 0, true);                     // Disk where central directory starts
        endView.setUint16(8, files.length, true);          // Number of central directory records on this disk
        endView.setUint16(10, files.length, true);         // Total number of central directory records
        endView.setUint32(12, centralDirectorySize, true); // Size of central directory
        endView.setUint32(16, centralDirectoryOffset, true); // Offset of start of central directory
        endView.setUint16(20, 0, true);                    // Comment length
        
        // Combine all parts into final ZIP blob
        const allParts = [...fileDataParts, ...centralDirectory, endOfCentralDir];
        return new Blob(allParts, { type: 'application/zip' });
    }

    /**
     * Calculate CRC32 checksum for data integrity
     * @param {Uint8Array} data - The data to calculate CRC32 for
     * @returns {number} - CRC32 value
     */
    crc32(data) {
        // CRC32 lookup table
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
        
        let crc = 0xFFFFFFFF;
        for (let i = 0; i < data.length; i++) {
            crc = this._crc32Table[(crc ^ data[i]) & 0xFF] ^ (crc >>> 8);
        }
        return (crc ^ 0xFFFFFFFF) >>> 0;
    }

    // Handle the Close button click
    handleClose() {
        // Dispatch close event for action screen
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // Show toast notification
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
                mode: 'dismissable'
            })
        );
    }

    // Reduce errors to a readable string
    reduceErrors(errors) {
        if (!Array.isArray(errors)) {
            errors = [errors];
        }

        return errors
            .filter(error => !!error)
            .map(error => {
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
                return JSON.stringify(error);
            })
            .join(', ');
    }
}
