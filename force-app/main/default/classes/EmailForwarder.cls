public class EmailForwarder {

    /**
     * Invocable method for Flow/Process Builder integration
     */
    @InvocableMethod(label='Forward Emails as EML Attachments' category='Email')
    public static void forwardEmails(List<List<Id>> emailIdBatches) {
        Set<Id> allEmailIds = new Set<Id>();
        for (List<Id> batch : emailIdBatches) {
            allEmailIds.addAll(batch);
        }

        if (allEmailIds.isEmpty()) return;

        // Default recipient - can be configured
        String recipientEmail = '';
        forwardEmailsToRecipient(new List<Id>(allEmailIds), recipientEmail);
    }

    /**
     * AuraEnabled method for LWC integration
     * Forwards selected emails to the specified recipient
     */
    @AuraEnabled
    public static String forwardSelectedEmails(List<Id> emailIds, String recipientEmail) {
        try {
            if (emailIds == null || emailIds.isEmpty()) {
                throw new AuraHandledException('No emails selected for forwarding.');
            }
            if (String.isBlank(recipientEmail)) {
                throw new AuraHandledException('Recipient email address is required.');
            }
            
            String result = forwardEmailsToRecipient(emailIds, recipientEmail);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error forwarding emails: ' + e.getMessage() + ' | Line: ' + e.getLineNumber());
        }
    }

    /**
     * Retrieves all EmailMessages related to a specific record
     */
    @AuraEnabled(cacheable=true)
    public static List<EmailMessageWrapper> getEmailsByRecordId(Id recordId) {
        try {
            List<EmailMessageWrapper> wrapperList = new List<EmailMessageWrapper>();
            
            // Query EmailMessages where the RelatedToId matches the record
            List<EmailMessage> emails = [
                SELECT Id, Subject, FromAddress, ToAddress, MessageDate, Status, Incoming
                FROM EmailMessage 
                WHERE RelatedToId = :recordId
                ORDER BY MessageDate DESC
            ];
            
            for (EmailMessage em : emails) {
                wrapperList.add(new EmailMessageWrapper(em));
            }
            
            return wrapperList;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving emails: ' + e.getMessage());
        }
    }

    /**
     * AuraEnabled method for LWC integration
     * Returns selected emails as EML content for client-side ZIP creation
     */
    @AuraEnabled
    public static List<EmailContentWrapper> getEmailsForDownload(List<Id> emailIds) {
        try {
            if (emailIds == null || emailIds.isEmpty()) {
                throw new AuraHandledException('No emails selected for download.');
            }

            Map<Id, EmailMessage> emailMap = new Map<Id, EmailMessage>([
                SELECT Subject, HtmlBody, TextBody, FromAddress, ToAddress, MessageDate 
                FROM EmailMessage 
                WHERE Id IN :emailIds
            ]);

            if (emailMap.isEmpty()) {
                throw new AuraHandledException('No email messages found for the provided IDs.');
            }

            List<EmailContentWrapper> emailContents = new List<EmailContentWrapper>();
            
            for (Id emailId : emailIds) {
                EmailMessage em = emailMap.get(emailId);
                if (em == null) continue;

                String fromAddr = em.FromAddress != null ? em.FromAddress : '';
                String toAddr = em.ToAddress != null ? em.ToAddress : '';
                String subject = em.Subject != null ? em.Subject : '(No Subject)';
                String dateStr = em.MessageDate != null ? em.MessageDate.formatGmt('EEE, d MMM yyyy HH:mm:ss Z') : '';
                String body = em.HtmlBody != null ? em.HtmlBody : (em.TextBody != null ? em.TextBody : '');

                String emlContent = 'From: ' + fromAddr + '\r\n' +
                                    'To: ' + toAddr + '\r\n' +
                                    'Date: ' + dateStr + '\r\n' +
                                    'Subject: ' + subject + '\r\n' +
                                    'MIME-Version: 1.0\r\n' +
                                    'Content-Type: text/html; charset=UTF-8\r\n\r\n' + 
                                    body;
                
                String safeSubject = subject.replaceAll('[^a-zA-Z0-9]', '_');
                if (String.isBlank(safeSubject)) {
                    safeSubject = 'Email_' + emailId;
                }
                
                emailContents.add(new EmailContentWrapper(safeSubject + '.eml', emlContent));
            }
            
            return emailContents;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error preparing emails for download: ' + e.getMessage());
        }
    }

    /**
     * Wrapper class for email content to be used in client-side ZIP creation
     */
    public class EmailContentWrapper {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String content { get; set; }
        
        public EmailContentWrapper(String fileName, String content) {
            this.fileName = fileName;
            this.content = content;
        }
    }

    /**
     * Core method to forward emails to a recipient
     * Returns a status message
     */
    private static String forwardEmailsToRecipient(List<Id> emailIds, String recipientEmail) {
        if (emailIds == null || emailIds.isEmpty() || String.isBlank(recipientEmail)) {
            throw new AuraHandledException('Invalid parameters: emailIds or recipientEmail is empty.');
        }

        Map<Id, EmailMessage> emailMap = new Map<Id, EmailMessage>([
            SELECT Subject, HtmlBody, TextBody, FromAddress, ToAddress, MessageDate, Parent.Contact.Email 
            FROM EmailMessage 
            WHERE Id IN :emailIds
        ]);

        if (emailMap.isEmpty()) {
            throw new AuraHandledException('No email messages found for the provided IDs.');
        }

        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

        for (Id emailId : emailIds) {
            EmailMessage em = emailMap.get(emailId);
            if (em == null) continue;

            // Safe null handling for all fields
            String fromAddr = em.FromAddress != null ? em.FromAddress : '';
            String toAddr = em.ToAddress != null ? em.ToAddress : '';
            String subject = em.Subject != null ? em.Subject : '(No Subject)';
            String dateStr = em.MessageDate != null ? em.MessageDate.formatGmt('EEE, d MMM yyyy HH:mm:ss Z') : '';
            String body = em.HtmlBody != null ? em.HtmlBody : (em.TextBody != null ? em.TextBody : '');

            // Build EML (MIME) Format
            String emlContent = 'From: ' + fromAddr + '\r\n' +
                                'To: ' + toAddr + '\r\n' +
                                'Date: ' + dateStr + '\r\n' +
                                'Subject: ' + subject + '\r\n' +
                                'MIME-Version: 1.0\r\n' +
                                'Content-Type: text/html; charset=UTF-8\r\n\r\n' + 
                                body;
            
            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            // Use .eml extension so it opens as an email record
            String safeSubject = subject.replaceAll('[^a-zA-Z0-9]', '_');
            if (String.isBlank(safeSubject)) {
                safeSubject = 'Email_' + emailId;
            }
            efa.setFileName(safeSubject + '.eml');
            efa.setBody(Blob.valueOf(emlContent));
            efa.setContentType('message/rfc822'); // Correct MIME type for email files
            attachments.add(efa);
        }

        if (attachments.isEmpty()) {
            throw new AuraHandledException('No attachments were created from the selected emails.');
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { recipientEmail });
        mail.setSubject('Fwd: Original Email Records');
        mail.setPlainTextBody('Attached are the original email messages in .eml format.\n\nTotal emails attached: ' + attachments.size());
        mail.setFileAttachments(attachments);
        
        // Set saveAsActivity to false to avoid issues
        mail.setSaveAsActivity(false);
        
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        
        // Check if email was sent successfully
        for (Messaging.SendEmailResult result : results) {
            if (!result.isSuccess()) {
                String errorMsg = '';
                for (Messaging.SendEmailError error : result.getErrors()) {
                    errorMsg += error.getMessage() + ' (Code: ' + error.getStatusCode() + ') ';
                }
                throw new AuraHandledException('Failed to send email: ' + errorMsg);
            }
        }
        
        return 'Success: ' + attachments.size() + ' email(s) forwarded to ' + recipientEmail;
    }

    /**
     * Wrapper class for EmailMessage to expose to LWC
     */
    public class EmailMessageWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String fromAddress { get; set; }
        @AuraEnabled public String toAddress { get; set; }
        @AuraEnabled public Datetime messageDate { get; set; }
        @AuraEnabled public String formattedDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean incoming { get; set; }
        @AuraEnabled public String direction { get; set; }
        
        public EmailMessageWrapper(EmailMessage em) {
            this.id = em.Id;
            this.subject = em.Subject != null ? em.Subject : '(No Subject)';
            this.fromAddress = em.FromAddress;
            this.toAddress = em.ToAddress;
            this.messageDate = em.MessageDate;
            this.formattedDate = em.MessageDate != null ? em.MessageDate.format('MM/dd/yyyy hh:mm a') : '';
            this.status = em.Status;
            this.incoming = em.Incoming;
            this.direction = em.Incoming ? 'Incoming' : 'Outgoing';
        }
    }
}
