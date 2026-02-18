import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEmailsForDownload from '@salesforce/apex/EmailForwarder.getEmailsForDownload';
import { downloadEmlFile, reduceErrors } from 'c/emailUtils';

/**
 * Email Downloader Component (Screen Action / Flow Screen)
 * Downloads a single email message as an EML file from the EmailMessage record page
 * 
 * @author Annindya Das
 * @version 1.0
 */
export default class EmailDownloader extends LightningElement {
    _recordId;
    _isDownloading = false;
    
    // Flow support - available actions
    @api availableActions = [];
    
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value && value !== this._recordId) {
            this._recordId = value;
            // Auto-trigger download when recordId is set
            this.downloadEmail();
        }
    }
    
    /**
     * Download the email as EML file
     */
    async downloadEmail() {
        if (this._isDownloading || !this._recordId) {
            return;
        }
        this._isDownloading = true;
        
        try {
            // Get email content as EML
            const emailContents = await getEmailsForDownload({ 
                emailIds: [this._recordId] 
            });
            
            if (!emailContents || emailContents.length === 0) {
                this.showToast('Warning', 'No email content available for download.', 'warning');
                this.closeAction();
                return;
            }
            
            // Download as single EML file
            const email = emailContents[0];
            downloadEmlFile(email.content, email.fileName);
            
            this.showToast('Success', 'Email downloaded successfully', 'success');
        } catch (error) {
            this.showToast('Error', reduceErrors(error), 'error');
        } finally {
            // Small delay to ensure download starts before closing
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.closeAction();
            }, 500);
        }
    }
    
    /**
     * Close the action screen or finish the flow
     */
    closeAction() {
        // Try to finish Flow first (if running in Flow context)
        if (this.availableActions && this.availableActions.includes('FINISH')) {
            this.dispatchEvent(new FlowNavigationFinishEvent());
        } else {
            // Fall back to CloseActionScreenEvent for Quick Actions
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }
    
    /**
     * Show toast notification
     */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
