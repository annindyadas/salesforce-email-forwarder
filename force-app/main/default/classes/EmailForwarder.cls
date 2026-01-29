/**
 * EmailForwarder - Apex controller for Email Forwarder LWC
 * Handles retrieving and forwarding emails as EML attachments
 * 
 * Security: Uses 'with sharing' to enforce record-level security
 * All SOQL queries check CRUD/FLS permissions before execution
 * 
 * @author Annindya Das
 * @version 1.0
 */
public with sharing class EmailForwarder {

    // Maximum number of emails to query/process
    private static final Integer MAX_EMAILS = 1000;

    /**
     * Forwards selected emails to the specified recipient
     * Called by the LWC when user clicks Send button
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
            
            // Validate email format
            if (!isValidEmail(recipientEmail)) {
                throw new AuraHandledException('Please enter a valid email address.');
            }
            
            String result = forwardEmailsToRecipient(emailIds, recipientEmail);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error forwarding emails: ' + e.getMessage());
        }
    }

    /**
     * Retrieves all EmailMessages related to a specific record
     * Enforces CRUD/FLS security checks
     * Note: Not cacheable to ensure fresh data on each call
     */
    @AuraEnabled
    public static List<EmailMessageWrapper> getEmailsByRecordId(Id recordId) {
        try {
            // Check if user has read access to EmailMessage object
            if (!Schema.sObjectType.EmailMessage.isAccessible()) {
                throw new AuraHandledException('You do not have permission to view email messages.');
            }
            
            // Check field-level security for each field we're querying
            checkFieldReadAccess();
            
            List<EmailMessageWrapper> wrapperList = new List<EmailMessageWrapper>();
            
            // Query EmailMessages where the RelatedToId matches the record
            List<EmailMessage> emails = [
                SELECT Id, Subject, FromAddress, ToAddress, MessageDate, Status, Incoming
                FROM EmailMessage 
                WHERE RelatedToId = :recordId
                WITH SECURITY_ENFORCED
                ORDER BY MessageDate DESC
                LIMIT :MAX_EMAILS
            ];
            
            for (EmailMessage em : emails) {
                wrapperList.add(new EmailMessageWrapper(em));
            }
            
            return wrapperList;
        } catch (System.QueryException qe) {
            // Handle SECURITY_ENFORCED exceptions
            throw new AuraHandledException('You do not have permission to access one or more email fields.');
        } catch (AuraHandledException e) {
            throw e;
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

            // Check object-level access
            if (!Schema.sObjectType.EmailMessage.isAccessible()) {
                throw new AuraHandledException('You do not have permission to view email messages.');
            }

            Map<Id, EmailMessage> emailMap = new Map<Id, EmailMessage>([
                SELECT Subject, HtmlBody, TextBody, FromAddress, ToAddress, MessageDate 
                FROM EmailMessage 
                WHERE Id IN :emailIds
                WITH SECURITY_ENFORCED
                LIMIT :MAX_EMAILS
            ]);

            if (emailMap.isEmpty()) {
                throw new AuraHandledException('No email messages found for the provided IDs.');
            }

            List<EmailContentWrapper> emailContents = new List<EmailContentWrapper>();
            
            for (Id emailId : emailIds) {
                EmailMessage em = emailMap.get(emailId);
                if (em == null) continue;

                String fromAddr = String.isNotBlank(em.FromAddress) ? em.FromAddress : '';
                String toAddr = String.isNotBlank(em.ToAddress) ? em.ToAddress : '';
                String subject = String.isNotBlank(em.Subject) ? em.Subject : '(No Subject)';
                String dateStr = em.MessageDate != null ? em.MessageDate.formatGmt('EEE, d MMM yyyy HH:mm:ss Z') : '';
                String body = String.isNotBlank(em.HtmlBody) ? em.HtmlBody : (String.isNotBlank(em.TextBody) ? em.TextBody : '');

                String emlContent = 'From: ' + fromAddr + '\r\n' +
                                    'To: ' + toAddr + '\r\n' +
                                    'Date: ' + dateStr + '\r\n' +
                                    'Subject: ' + subject + '\r\n' +
                                    'MIME-Version: 1.0\r\n' +
                                    'Content-Type: text/html; charset=UTF-8\r\n\r\n' + 
                                    body;
                
                String safeSubject = subject.replaceAll('[^a-zA-Z0-9]', '_');
                if (String.isBlank(safeSubject)) {
                    safeSubject = 'Email_' + String.valueOf(emailId).left(15);
                }
                // Limit filename length to prevent issues
                if (safeSubject.length() > 50) {
                    safeSubject = safeSubject.left(50);
                }
                
                emailContents.add(new EmailContentWrapper(safeSubject + '.eml', emlContent));
            }
            
            return emailContents;
            
        } catch (System.QueryException qe) {
            throw new AuraHandledException('You do not have permission to access one or more email fields.');
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

        // Validate email format
        if (!isValidEmail(recipientEmail)) {
            throw new AuraHandledException('Please enter a valid email address.');
        }

        // Check object-level access
        if (!Schema.sObjectType.EmailMessage.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view email messages.');
        }

        Map<Id, EmailMessage> emailMap = new Map<Id, EmailMessage>([
            SELECT Subject, HtmlBody, TextBody, FromAddress, ToAddress, MessageDate 
            FROM EmailMessage 
            WHERE Id IN :emailIds
            WITH SECURITY_ENFORCED
            LIMIT :MAX_EMAILS
        ]);

        if (emailMap.isEmpty()) {
            throw new AuraHandledException('No email messages found for the provided IDs.');
        }

        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

        for (Id emailId : emailIds) {
            EmailMessage em = emailMap.get(emailId);
            if (em == null) continue;

            // Safe null handling for all fields using String.isNotBlank
            String fromAddr = String.isNotBlank(em.FromAddress) ? em.FromAddress : '';
            String toAddr = String.isNotBlank(em.ToAddress) ? em.ToAddress : '';
            String subject = String.isNotBlank(em.Subject) ? em.Subject : '(No Subject)';
            String dateStr = em.MessageDate != null ? em.MessageDate.formatGmt('EEE, d MMM yyyy HH:mm:ss Z') : '';
            String body = String.isNotBlank(em.HtmlBody) ? em.HtmlBody : (String.isNotBlank(em.TextBody) ? em.TextBody : '');

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
                safeSubject = 'Email_' + String.valueOf(emailId).left(15);
            }
            // Limit filename length
            if (safeSubject.length() > 50) {
                safeSubject = safeSubject.left(50);
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
                    errorMsg += error.getMessage() + ' ';
                }
                throw new AuraHandledException('Failed to send email: ' + errorMsg.trim());
            }
        }
        
        return 'Success: ' + attachments.size() + ' email(s) forwarded to ' + recipientEmail;
    }

    /**
     * Check field-level read access for EmailMessage fields
     */
    private static void checkFieldReadAccess() {
        List<String> fieldsToCheck = new List<String>{
            'Subject', 'FromAddress', 'ToAddress', 'MessageDate', 'Status', 'Incoming', 'HtmlBody', 'TextBody'
        };
        
        Map<String, Schema.SObjectField> fieldMap = Schema.sObjectType.EmailMessage.fields.getMap();
        
        for (String fieldName : fieldsToCheck) {
            Schema.SObjectField field = fieldMap.get(fieldName);
            if (field != null && !field.getDescribe().isAccessible()) {
                throw new AuraHandledException('You do not have permission to access the ' + fieldName + ' field.');
            }
        }
    }

    /**
     * Validate email address format
     * @param email The email address to validate
     * @return Boolean indicating if email format is valid
     */
    private static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        // Simple email validation pattern
        String emailRegex = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher emailMatcher = emailPattern.matcher(email);
        return emailMatcher.matches();
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
            this.subject = String.isNotBlank(em.Subject) ? em.Subject : '(No Subject)';
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
