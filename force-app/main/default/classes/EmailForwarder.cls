/**
 * EmailForwarder - Apex controller for Email Forwarder LWC
 * Handles retrieving and forwarding emails as EML attachments
 * Supports email attachments through ContentDocumentLink
 * 
 * Security: Uses 'with sharing' to enforce record-level security
 * All SOQL queries check CRUD/FLS permissions before execution
 * 
 * @author Annindya Das
 * @version 2.0 - Added attachment support
 */
public with sharing class EmailForwarder {

    // Maximum number of emails to query/process
    private static final Integer MAX_EMAILS = 1000;
    
    // Maximum attachment size in bytes (10MB per attachment)
    private static final Integer MAX_ATTACHMENT_SIZE = 10485760;
    
    // Maximum total attachments size (25MB for email)
    private static final Integer MAX_TOTAL_ATTACHMENT_SIZE = 26214400;
    
    // MIME boundary for multipart messages
    private static final String BOUNDARY = '----=_Part_' + String.valueOf(DateTime.now().getTime());

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
     * Get details for a single EmailMessage
     * Used by the EmailDownloader LWC component
     * Returns subject and attachment count for display
     */
    @AuraEnabled
    public static EmailDetailWrapper getEmailDetails(Id emailId) {
        try {
            if (emailId == null) {
                throw new AuraHandledException('Email ID is required.');
            }
            
            // Check object-level access
            if (!Schema.sObjectType.EmailMessage.isAccessible()) {
                throw new AuraHandledException('You do not have permission to view email messages.');
            }
            
            List<EmailMessage> emails = [
                SELECT Id, Subject
                FROM EmailMessage 
                WHERE Id = :emailId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            if (emails.isEmpty()) {
                throw new AuraHandledException('Email message not found.');
            }
            
            EmailMessage em = emails[0];
            
            // Get attachment count
            Set<Id> emailIds = new Set<Id>{ emailId };
            Map<Id, Integer> attachmentCounts = getAttachmentCounts(emailIds);
            
            EmailDetailWrapper wrapper = new EmailDetailWrapper();
            wrapper.subject = String.isNotBlank(em.Subject) ? em.Subject : '(No Subject)';
            wrapper.attachmentCount = attachmentCounts.containsKey(emailId) ? attachmentCounts.get(emailId) : 0;
            
            return wrapper;
            
        } catch (System.QueryException qe) {
            throw new AuraHandledException('You do not have permission to access one or more email fields.');
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving email details: ' + e.getMessage());
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
            
            // Get attachment counts for each email
            Set<Id> emailIds = new Set<Id>();
            for (EmailMessage em : emails) {
                emailIds.add(em.Id);
            }
            
            Map<Id, Integer> attachmentCounts = getAttachmentCounts(emailIds);
            
            for (EmailMessage em : emails) {
                EmailMessageWrapper wrapper = new EmailMessageWrapper(em);
                wrapper.attachmentCount = attachmentCounts.containsKey(em.Id) ? attachmentCounts.get(em.Id) : 0;
                wrapperList.add(wrapper);
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
     * Get attachment counts for a set of email IDs
     */
    private static Map<Id, Integer> getAttachmentCounts(Set<Id> emailIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        
        if (emailIds.isEmpty()) {
            return counts;
        }
        
        // Check if user has access to ContentDocumentLink
        if (!Schema.sObjectType.ContentDocumentLink.isAccessible()) {
            return counts;
        }
        
        // Query ContentDocumentLinks for email attachments
        List<ContentDocumentLink> cdls = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :emailIds
            WITH SECURITY_ENFORCED
        ];
        
        for (ContentDocumentLink cdl : cdls) {
            Integer currentCount = counts.containsKey(cdl.LinkedEntityId) ? counts.get(cdl.LinkedEntityId) : 0;
            counts.put(cdl.LinkedEntityId, currentCount + 1);
        }
        
        return counts;
    }
    
    /**
     * Get attachments for a set of email IDs
     * Returns a map of EmailMessage Id to list of AttachmentWrapper
     */
    private static Map<Id, List<AttachmentWrapper>> getEmailAttachments(Set<Id> emailIds) {
        Map<Id, List<AttachmentWrapper>> attachmentMap = new Map<Id, List<AttachmentWrapper>>();
        
        if (emailIds.isEmpty()) {
            return attachmentMap;
        }
        
        // Initialize map with empty lists
        for (Id emailId : emailIds) {
            attachmentMap.put(emailId, new List<AttachmentWrapper>());
        }
        
        // Check if user has access to ContentDocumentLink and ContentVersion
        if (!Schema.sObjectType.ContentDocumentLink.isAccessible() ||
            !Schema.sObjectType.ContentVersion.isAccessible()) {
            return attachmentMap;
        }
        
        // Query ContentDocumentLinks for email attachments
        List<ContentDocumentLink> cdls = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :emailIds
            WITH SECURITY_ENFORCED
        ];
        
        if (cdls.isEmpty()) {
            return attachmentMap;
        }
        
        // Get Content Document IDs
        Set<Id> contentDocIds = new Set<Id>();
        Map<Id, Id> docToEmailMap = new Map<Id, Id>();
        
        for (ContentDocumentLink cdl : cdls) {
            contentDocIds.add(cdl.ContentDocumentId);
            docToEmailMap.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }
        
        // Query ContentVersion for file content
        List<ContentVersion> versions = [
            SELECT ContentDocumentId, Title, FileExtension, VersionData, ContentSize, FileType
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds
            AND IsLatest = true
            WITH SECURITY_ENFORCED
        ];
        
        // Build attachment wrappers
        for (ContentVersion cv : versions) {
            Id emailId = docToEmailMap.get(cv.ContentDocumentId);
            
            if (emailId != null && cv.ContentSize <= MAX_ATTACHMENT_SIZE) {
                AttachmentWrapper aw = new AttachmentWrapper();
                aw.fileName = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
                aw.contentType = getMimeType(cv.FileType, cv.FileExtension);
                aw.size = cv.ContentSize;
                aw.base64Content = EncodingUtil.base64Encode(cv.VersionData);
                
                attachmentMap.get(emailId).add(aw);
            }
        }
        
        return attachmentMap;
    }
    
    /**
     * Get MIME type based on file type and extension
     */
    private static String getMimeType(String fileType, String extension) {
        if (String.isBlank(fileType) && String.isBlank(extension)) {
            return 'application/octet-stream';
        }
        
        String ext = String.isNotBlank(extension) ? extension.toLowerCase() : '';
        
        Map<String, String> mimeTypes = new Map<String, String>{
            'pdf' => 'application/pdf',
            'doc' => 'application/msword',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls' => 'application/vnd.ms-excel',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'ppt' => 'application/vnd.ms-powerpoint',
            'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'txt' => 'text/plain',
            'csv' => 'text/csv',
            'html' => 'text/html',
            'htm' => 'text/html',
            'xml' => 'application/xml',
            'json' => 'application/json',
            'zip' => 'application/zip',
            'rar' => 'application/x-rar-compressed',
            'jpg' => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png' => 'image/png',
            'gif' => 'image/gif',
            'bmp' => 'image/bmp',
            'svg' => 'image/svg+xml',
            'ico' => 'image/x-icon',
            'mp3' => 'audio/mpeg',
            'wav' => 'audio/wav',
            'mp4' => 'video/mp4',
            'avi' => 'video/x-msvideo',
            'mov' => 'video/quicktime'
        };
        
        return mimeTypes.containsKey(ext) ? mimeTypes.get(ext) : 'application/octet-stream';
    }

    /**
     * AuraEnabled method for LWC integration
     * Returns selected emails as EML content for client-side ZIP creation
     * Includes attachments in MIME multipart format
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
            
            // Get attachments for all emails
            Map<Id, List<AttachmentWrapper>> attachmentMap = getEmailAttachments(emailMap.keySet());

            List<EmailContentWrapper> emailContents = new List<EmailContentWrapper>();
            
            for (Id emailId : emailIds) {
                EmailMessage em = emailMap.get(emailId);
                if (em == null) continue;

                String emlContent = buildEmlContent(em, attachmentMap.get(emailId));
                
                String subject = String.isNotBlank(em.Subject) ? em.Subject : '(No Subject)';
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
     * Build EML content with proper MIME format including attachments
     */
    private static String buildEmlContent(EmailMessage em, List<AttachmentWrapper> attachments) {
        String fromAddr = String.isNotBlank(em.FromAddress) ? em.FromAddress : '';
        String toAddr = String.isNotBlank(em.ToAddress) ? em.ToAddress : '';
        String subject = String.isNotBlank(em.Subject) ? em.Subject : '(No Subject)';
        String dateStr = em.MessageDate != null ? em.MessageDate.formatGmt('EEE, d MMM yyyy HH:mm:ss Z') : '';
        String body = String.isNotBlank(em.HtmlBody) ? em.HtmlBody : (String.isNotBlank(em.TextBody) ? em.TextBody : '');
        Boolean isHtml = String.isNotBlank(em.HtmlBody);
        
        // Check if we have attachments
        Boolean hasAttachments = attachments != null && !attachments.isEmpty();
        
        String emlContent = '';
        
        // Common headers
        emlContent += 'From: ' + fromAddr + '\r\n';
        emlContent += 'To: ' + toAddr + '\r\n';
        emlContent += 'Date: ' + dateStr + '\r\n';
        emlContent += 'Subject: ' + subject + '\r\n';
        emlContent += 'MIME-Version: 1.0\r\n';
        
        if (hasAttachments) {
            // Multipart message with attachments
            emlContent += 'Content-Type: multipart/mixed; boundary="' + BOUNDARY + '"\r\n';
            emlContent += '\r\n';
            emlContent += 'This is a multi-part message in MIME format.\r\n';
            emlContent += '\r\n';
            
            // Body part
            emlContent += '--' + BOUNDARY + '\r\n';
            emlContent += 'Content-Type: ' + (isHtml ? 'text/html' : 'text/plain') + '; charset=UTF-8\r\n';
            emlContent += 'Content-Transfer-Encoding: quoted-printable\r\n';
            emlContent += '\r\n';
            emlContent += body + '\r\n';
            emlContent += '\r\n';
            
            // Attachment parts
            for (AttachmentWrapper att : attachments) {
                emlContent += '--' + BOUNDARY + '\r\n';
                emlContent += 'Content-Type: ' + att.contentType + '; name="' + att.fileName + '"\r\n';
                emlContent += 'Content-Disposition: attachment; filename="' + att.fileName + '"\r\n';
                emlContent += 'Content-Transfer-Encoding: base64\r\n';
                emlContent += '\r\n';
                
                // Add base64 content with line breaks every 76 characters (RFC 2045)
                String base64 = att.base64Content;
                Integer lineLength = 76;
                for (Integer i = 0; i < base64.length(); i += lineLength) {
                    Integer endIdx = Math.min(i + lineLength, base64.length());
                    emlContent += base64.substring(i, endIdx) + '\r\n';
                }
                emlContent += '\r\n';
            }
            
            // End boundary
            emlContent += '--' + BOUNDARY + '--\r\n';
        } else {
            // Simple message without attachments
            emlContent += 'Content-Type: ' + (isHtml ? 'text/html' : 'text/plain') + '; charset=UTF-8\r\n';
            emlContent += '\r\n';
            emlContent += body;
        }
        
        return emlContent;
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
     * Wrapper class for attachment data
     */
    private class AttachmentWrapper {
        public String fileName { get; set; }
        public String contentType { get; set; }
        public Integer size { get; set; }
        public String base64Content { get; set; }
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
        
        // Get attachments for all emails
        Map<Id, List<AttachmentWrapper>> attachmentMap = getEmailAttachments(emailMap.keySet());

        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        Integer totalAttachmentSize = 0;

        for (Id emailId : emailIds) {
            EmailMessage em = emailMap.get(emailId);
            if (em == null) continue;

            // Build EML content with attachments
            String emlContent = buildEmlContent(em, attachmentMap.get(emailId));
            
            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            // Use .eml extension so it opens as an email record
            String subject = String.isNotBlank(em.Subject) ? em.Subject : '(No Subject)';
            String safeSubject = subject.replaceAll('[^a-zA-Z0-9]', '_');
            if (String.isBlank(safeSubject)) {
                safeSubject = 'Email_' + String.valueOf(emailId).left(15);
            }
            // Limit filename length
            if (safeSubject.length() > 50) {
                safeSubject = safeSubject.left(50);
            }
            efa.setFileName(safeSubject + '.eml');
            
            Blob emlBlob = Blob.valueOf(emlContent);
            totalAttachmentSize += emlBlob.size();
            
            // Check total size limit
            if (totalAttachmentSize > MAX_TOTAL_ATTACHMENT_SIZE) {
                throw new AuraHandledException('Total attachment size exceeds 25MB limit. Please select fewer emails or emails with smaller attachments.');
            }
            
            efa.setBody(emlBlob);
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
        @AuraEnabled public Integer attachmentCount { get; set; }
        
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
            this.attachmentCount = 0;
        }
    }
    
    /**
     * Wrapper class for email details (used by EmailDownloader component)
     */
    public class EmailDetailWrapper {
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Integer attachmentCount { get; set; }
    }
}
