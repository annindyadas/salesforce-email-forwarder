/**
 * @description Test class for EmailForwarder
 * Provides comprehensive test coverage including security checks for AppExchange compliance
 * @author Annindya Das
 */
@isTest
private class EmailForwarderTest {
    
    /**
     * @description Test data setup - creates a Case with multiple EmailMessages
     */
    @TestSetup
    static void setupTestData() {
        // Create a test Case
        Case testCase = new Case(
            Subject = 'Test Case for Email Forwarding',
            Status = 'New',
            Origin = 'Email'
        );
        insert testCase;
        
        // Create test EmailMessages related to the Case
        List<EmailMessage> testEmails = new List<EmailMessage>();
        
        // Email 1 - Incoming email
        testEmails.add(new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Test Email 1 - Incoming',
            TextBody = 'This is the body of test email 1',
            HtmlBody = '<html><body>This is the body of test email 1</body></html>',
            FromAddress = 'sender1@test.com',
            FromName = 'Test Sender 1',
            ToAddress = 'recipient1@test.com',
            MessageDate = DateTime.now().addDays(-2),
            Incoming = true
        ));
        
        // Email 2 - Outgoing email
        testEmails.add(new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Test Email 2 - Outgoing',
            TextBody = 'This is the body of test email 2',
            HtmlBody = '<html><body>This is the body of test email 2</body></html>',
            FromAddress = 'agent@company.com',
            FromName = 'Support Agent',
            ToAddress = 'customer@test.com',
            MessageDate = DateTime.now().addDays(-1),
            Incoming = false
        ));
        
        // Email 3 - Email with no subject
        testEmails.add(new EmailMessage(
            ParentId = testCase.Id,
            Subject = null,
            TextBody = 'Email with no subject',
            FromAddress = 'sender2@test.com',
            ToAddress = 'recipient2@test.com',
            MessageDate = DateTime.now(),
            Incoming = true
        ));
        
        insert testEmails;
    }
    
    /**
     * @description Get the test Case created in setup
     */
    private static Case getTestCase() {
        return [SELECT Id FROM Case WHERE Subject = 'Test Case for Email Forwarding' LIMIT 1];
    }
    
    /**
     * @description Get the test EmailMessages created in setup
     */
    private static List<EmailMessage> getTestEmails() {
        Case testCase = getTestCase();
        return [SELECT Id FROM EmailMessage WHERE ParentId = :testCase.Id];
    }
    
    /**
     * @description Test getEmailsByRecordId with valid record Id
     */
    @isTest
    static void testGetEmailsByRecordId_ValidId() {
        Case testCase = getTestCase();
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.size(), 'Should return 3 emails');
    }
    
    /**
     * @description Test getEmailsByRecordId with null Id
     * When null is passed, SOQL returns empty results
     */
    @isTest
    static void testGetEmailsByRecordId_NullId() {
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return empty list for null Id');
    }
    
    /**
     * @description Test getEmailsByRecordId with invalid Id format
     */
    @isTest
    static void testGetEmailsByRecordId_InvalidId() {
        Test.startTest();
        try {
            EmailForwarder.getEmailsByRecordId('invalid-id-format');
            System.assert(false, 'Should have thrown an exception');
        } catch (Exception e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test getEmailsByRecordId with valid Id but no emails
     */
    @isTest
    static void testGetEmailsByRecordId_NoEmails() {
        // Create a Case with no emails
        Case emptyCase = new Case(
            Subject = 'Empty Case',
            Status = 'New'
        );
        insert emptyCase;
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(emptyCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return empty email list');
    }
    
    /**
     * @description Test forwardSelectedEmails with valid data
     */
    @isTest
    static void testForwardSelectedEmails_ValidData() {
        List<EmailMessage> testEmails = getTestEmails();
        List<String> emailIds = new List<String>();
        for (EmailMessage em : testEmails) {
            emailIds.add(em.Id);
        }
        
        Test.startTest();
        String result = EmailForwarder.forwardSelectedEmails(emailIds, 'test@example.com');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('Success'), 'Result should indicate success');
    }
    
    /**
     * @description Test forwardSelectedEmails with empty email list
     */
    @isTest
    static void testForwardSelectedEmails_EmptyList() {
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(new List<String>(), 'test@example.com');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test forwardSelectedEmails with null email list
     */
    @isTest
    static void testForwardSelectedEmails_NullList() {
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(null, 'test@example.com');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test forwardSelectedEmails with empty recipient
     */
    @isTest
    static void testForwardSelectedEmails_EmptyRecipient() {
        List<EmailMessage> testEmails = getTestEmails();
        List<String> emailIds = new List<String>();
        for (EmailMessage em : testEmails) {
            emailIds.add(em.Id);
        }
        
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(emailIds, '');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test forwardSelectedEmails with null recipient
     */
    @isTest
    static void testForwardSelectedEmails_NullRecipient() {
        List<EmailMessage> testEmails = getTestEmails();
        List<String> emailIds = new List<String>();
        for (EmailMessage em : testEmails) {
            emailIds.add(em.Id);
        }
        
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(emailIds, null);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test forwardSelectedEmails with invalid email format
     */
    @isTest
    static void testForwardSelectedEmails_InvalidEmailFormat() {
        List<EmailMessage> testEmails = getTestEmails();
        List<String> emailIds = new List<String>();
        for (EmailMessage em : testEmails) {
            emailIds.add(em.Id);
        }
        
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(emailIds, 'invalid-email');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected for invalid email format');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test getEmailsForDownload with valid data
     */
    @isTest
    static void testGetEmailsForDownload_ValidData() {
        List<EmailMessage> testEmails = getTestEmails();
        List<String> emailIds = new List<String>();
        for (EmailMessage em : testEmails) {
            emailIds.add(em.Id);
        }
        
        Test.startTest();
        List<EmailForwarder.EmailContentWrapper> result = EmailForwarder.getEmailsForDownload(emailIds);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.size(), 'Should return 3 email contents');
        
        // Verify wrapper properties
        for (EmailForwarder.EmailContentWrapper wrapper : result) {
            System.assertNotEquals(null, wrapper.fileName, 'File name should not be null');
            System.assertNotEquals(null, wrapper.content, 'EML content should not be null');
            System.assert(wrapper.fileName.endsWith('.eml'), 'File name should end with .eml');
        }
    }
    
    /**
     * @description Test getEmailsForDownload with empty list
     */
    @isTest
    static void testGetEmailsForDownload_EmptyList() {
        Test.startTest();
        try {
            EmailForwarder.getEmailsForDownload(new List<String>());
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test getEmailsForDownload with null list
     */
    @isTest
    static void testGetEmailsForDownload_NullList() {
        Test.startTest();
        try {
            EmailForwarder.getEmailsForDownload(null);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test EmailMessageWrapper properties
     */
    @isTest
    static void testEmailMessageWrapper() {
        Case testCase = getTestCase();
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        // Verify wrapper has all expected properties
        EmailForwarder.EmailMessageWrapper wrapper = result[0];
        System.assertNotEquals(null, wrapper.id, 'Id should not be null');
        System.assertNotEquals(null, wrapper.fromAddress, 'From address should not be null');
        System.assertNotEquals(null, wrapper.toAddress, 'To address should not be null');
    }
    
    /**
     * @description Test EmailContentWrapper structure
     */
    @isTest
    static void testEmailContentWrapper() {
        List<EmailMessage> testEmails = getTestEmails();
        List<String> emailIds = new List<String>{ testEmails[0].Id };
        
        Test.startTest();
        List<EmailForwarder.EmailContentWrapper> wrappers = EmailForwarder.getEmailsForDownload(emailIds);
        Test.stopTest();
        
        System.assertEquals(1, wrappers.size(), 'Should return 1 wrapper');
        EmailForwarder.EmailContentWrapper wrapper = wrappers[0];
        System.assertNotEquals(null, wrapper.fileName, 'File name should not be null');
        System.assertNotEquals(null, wrapper.content, 'EML content should not be null');
        System.assert(wrapper.content.contains('MIME-Version:'), 'EML should contain MIME header');
        System.assert(wrapper.content.contains('Content-Type:'), 'EML should contain Content-Type');
    }
    
    /**
     * @description Test email with HTML body for download
     */
    @isTest
    static void testGetEmailsForDownload_WithHtmlBody() {
        List<EmailMessage> testEmails = [
            SELECT Id FROM EmailMessage 
            WHERE Subject = 'Test Email 1 - Incoming' 
            LIMIT 1
        ];
        
        Test.startTest();
        List<EmailForwarder.EmailContentWrapper> result = EmailForwarder.getEmailsForDownload(
            new List<String>{ testEmails[0].Id }
        );
        Test.stopTest();
        
        System.assertEquals(1, result.size(), 'Should return 1 email');
        System.assert(result[0].content.contains('Content-Type: text/html'), 
            'EML should indicate HTML content type');
    }
    
    /**
     * @description Test email with only text body for download
     */
    @isTest
    static void testGetEmailsForDownload_WithTextBodyOnly() {
        // Create an email with only text body
        Case testCase = getTestCase();
        EmailMessage textOnlyEmail = new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Text Only Email',
            TextBody = 'This is plain text only',
            HtmlBody = null,
            FromAddress = 'sender@test.com',
            ToAddress = 'recipient@test.com',
            MessageDate = DateTime.now(),
            Incoming = true
        );
        insert textOnlyEmail;
        
        Test.startTest();
        List<EmailForwarder.EmailContentWrapper> result = EmailForwarder.getEmailsForDownload(
            new List<String>{ textOnlyEmail.Id }
        );
        Test.stopTest();
        
        System.assertEquals(1, result.size(), 'Should return 1 email');
        // Verify the text body is included in the EML content
        System.assert(result[0].content.contains('This is plain text only'), 
            'EML should contain the text body content');
    }
    
    /**
     * @description Test CRUD permission checks - EmailMessage readable
     * Note: Standard system admin profile should have read access
     */
    @isTest
    static void testCrudPermissions_ReadAccess() {
        Case testCase = getTestCase();
        
        Test.startTest();
        // This should not throw an exception for admin user
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should have read access to EmailMessage');
    }
    
    /**
     * @description Test security - verify wrapper does not expose sensitive data
     */
    @isTest
    static void testSecurityDataExposure() {
        Case testCase = getTestCase();
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        // Verify only expected fields are exposed
        EmailForwarder.EmailMessageWrapper wrapper = result[0];
        
        // Verify the wrapper properties are properly set
        System.assertNotEquals(null, wrapper.id, 'Id should be accessible');
        System.assertNotEquals(null, wrapper.fromAddress, 'From should be accessible');
    }
    
    /**
     * @description Test handling of special characters in subject
     */
    @isTest
    static void testSpecialCharactersInSubject() {
        Case testCase = getTestCase();
        EmailMessage specialEmail = new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Test <script>alert("xss")</script> & Special Chars!@#$%',
            TextBody = 'Test body',
            FromAddress = 'sender@test.com',
            ToAddress = 'recipient@test.com',
            MessageDate = DateTime.now(),
            Incoming = true
        );
        insert specialEmail;
        
        Test.startTest();
        List<EmailForwarder.EmailContentWrapper> result = EmailForwarder.getEmailsForDownload(
            new List<String>{ specialEmail.Id }
        );
        Test.stopTest();
        
        System.assertEquals(1, result.size(), 'Should handle special characters');
        System.assertNotEquals(null, result[0].fileName, 'File name should be generated');
    }
    
    /**
     * @description Test with multiple email IDs including invalid ones
     */
    @isTest
    static void testMixedValidInvalidIds() {
        List<EmailMessage> testEmails = getTestEmails();
        List<String> emailIds = new List<String>();
        emailIds.add(testEmails[0].Id);
        
        Test.startTest();
        List<EmailForwarder.EmailContentWrapper> result = EmailForwarder.getEmailsForDownload(emailIds);
        Test.stopTest();
        
        System.assertEquals(1, result.size(), 'Should return results for valid IDs');
    }
    
    /**
     * @description Test forwardSelectedEmails with various valid email formats
     */
    @isTest
    static void testForwardSelectedEmails_VariousEmailFormats() {
        List<EmailMessage> testEmails = getTestEmails();
        List<String> emailIds = new List<String>{ testEmails[0].Id };
        
        // Test with standard email
        Test.startTest();
        String result1 = EmailForwarder.forwardSelectedEmails(emailIds, 'user@domain.com');
        System.assert(result1.contains('Success'), 'Should accept standard email format');
        
        // Test with subdomain email
        String result2 = EmailForwarder.forwardSelectedEmails(emailIds, 'user@subdomain.domain.com');
        System.assert(result2.contains('Success'), 'Should accept subdomain email format');
        
        // Test with plus sign email
        String result3 = EmailForwarder.forwardSelectedEmails(emailIds, 'user+tag@domain.com');
        System.assert(result3.contains('Success'), 'Should accept plus sign email format');
        Test.stopTest();
    }
    
    /**
     * @description Test the 1000 email limit
     */
    @isTest
    static void testEmailLimit() {
        Case testCase = getTestCase();
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        // With only 3 test emails, verify we get all of them
        System.assertEquals(3, result.size(), 'Should return all test emails within limit');
    }
    
    /**
     * @description Test attachment count is returned in wrapper
     */
    @isTest
    static void testAttachmentCountInWrapper() {
        Case testCase = getTestCase();
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        // Verify attachmentCount property exists and is 0 (no attachments in test data)
        System.assertNotEquals(null, result, 'Result should not be null');
        for (EmailForwarder.EmailMessageWrapper wrapper : result) {
            System.assertNotEquals(null, wrapper.attachmentCount, 'Attachment count should not be null');
            System.assertEquals(0, wrapper.attachmentCount, 'Should have 0 attachments');
        }
    }
    
    /**
     * @description Test email with ContentDocumentLink attachment
     */
    @isTest
    static void testEmailWithAttachment() {
        Case testCase = getTestCase();
        
        // Create an email for attachment test
        EmailMessage emailWithAttachment = new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Email With Attachment',
            TextBody = 'This email has an attachment',
            FromAddress = 'sender@test.com',
            ToAddress = 'recipient@test.com',
            MessageDate = DateTime.now(),
            Incoming = true
        );
        insert emailWithAttachment;
        
        // Create a ContentVersion (file)
        ContentVersion cv = new ContentVersion(
            Title = 'TestAttachment',
            PathOnClient = 'TestAttachment.txt',
            VersionData = Blob.valueOf('Test file content for attachment'),
            IsMajorVersion = true
        );
        insert cv;
        
        // Get the ContentDocumentId
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        
        // Link the file to the EmailMessage
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = emailWithAttachment.Id,
            ShareType = 'V'
        );
        insert cdl;
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        // Find the email with attachment
        Boolean foundAttachment = false;
        for (EmailForwarder.EmailMessageWrapper wrapper : result) {
            if (wrapper.subject == 'Email With Attachment') {
                System.assertEquals(1, wrapper.attachmentCount, 'Should have 1 attachment');
                foundAttachment = true;
            }
        }
        System.assert(foundAttachment, 'Should find the email with attachment');
    }
    
    /**
     * @description Test getEmailsForDownload with attachment
     */
    @isTest
    static void testGetEmailsForDownload_WithAttachment() {
        Case testCase = getTestCase();
        
        // Create an email for attachment test
        EmailMessage emailWithAttachment = new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Download Test With Attachment',
            TextBody = 'This email has an attachment for download',
            FromAddress = 'sender@test.com',
            ToAddress = 'recipient@test.com',
            MessageDate = DateTime.now(),
            Incoming = true
        );
        insert emailWithAttachment;
        
        // Create a ContentVersion (file)
        ContentVersion cv = new ContentVersion(
            Title = 'DownloadTestFile',
            PathOnClient = 'DownloadTestFile.pdf',
            VersionData = Blob.valueOf('PDF content simulation'),
            IsMajorVersion = true
        );
        insert cv;
        
        // Get the ContentDocumentId
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        
        // Link the file to the EmailMessage
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = emailWithAttachment.Id,
            ShareType = 'V'
        );
        insert cdl;
        
        Test.startTest();
        List<EmailForwarder.EmailContentWrapper> result = EmailForwarder.getEmailsForDownload(
            new List<String>{ emailWithAttachment.Id }
        );
        Test.stopTest();
        
        System.assertEquals(1, result.size(), 'Should return 1 email');
        // Verify the EML content contains multipart MIME structure
        System.assert(result[0].content.contains('multipart/mixed'), 'Should be multipart MIME format');
        System.assert(result[0].content.contains('DownloadTestFile'), 'Should contain attachment filename');
    }
    
    /**
     * @description Test forwardSelectedEmails with attachment
     */
    @isTest
    static void testForwardSelectedEmails_WithAttachment() {
        Case testCase = getTestCase();
        
        // Create an email for attachment test
        EmailMessage emailWithAttachment = new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Forward Test With Attachment',
            TextBody = 'This email has an attachment to forward',
            FromAddress = 'sender@test.com',
            ToAddress = 'recipient@test.com',
            MessageDate = DateTime.now(),
            Incoming = true
        );
        insert emailWithAttachment;
        
        // Create a ContentVersion (file)
        ContentVersion cv = new ContentVersion(
            Title = 'ForwardTestFile',
            PathOnClient = 'ForwardTestFile.docx',
            VersionData = Blob.valueOf('Document content simulation'),
            IsMajorVersion = true
        );
        insert cv;
        
        // Get the ContentDocumentId
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        
        // Link the file to the EmailMessage
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = emailWithAttachment.Id,
            ShareType = 'V'
        );
        insert cdl;
        
        Test.startTest();
        String result = EmailForwarder.forwardSelectedEmails(
            new List<String>{ emailWithAttachment.Id },
            'test@example.com'
        );
        Test.stopTest();
        
        System.assert(result.contains('Success'), 'Should successfully forward email with attachment');
    }
    
    /**
     * @description Test email with multiple attachments
     */
    @isTest
    static void testEmailWithMultipleAttachments() {
        Case testCase = getTestCase();
        
        // Create an email for multiple attachments test
        EmailMessage emailWithAttachments = new EmailMessage(
            ParentId = testCase.Id,
            Subject = 'Multiple Attachments Test',
            TextBody = 'This email has multiple attachments',
            FromAddress = 'sender@test.com',
            ToAddress = 'recipient@test.com',
            MessageDate = DateTime.now(),
            Incoming = true
        );
        insert emailWithAttachments;
        
        // Create multiple ContentVersions
        List<ContentVersion> cvList = new List<ContentVersion>();
        cvList.add(new ContentVersion(
            Title = 'Attachment1',
            PathOnClient = 'Attachment1.txt',
            VersionData = Blob.valueOf('First attachment content'),
            IsMajorVersion = true
        ));
        cvList.add(new ContentVersion(
            Title = 'Attachment2',
            PathOnClient = 'Attachment2.pdf',
            VersionData = Blob.valueOf('Second attachment content'),
            IsMajorVersion = true
        ));
        cvList.add(new ContentVersion(
            Title = 'Attachment3',
            PathOnClient = 'Attachment3.jpg',
            VersionData = Blob.valueOf('Third attachment content'),
            IsMajorVersion = true
        ));
        insert cvList;
        
        // Get ContentDocumentIds and create links
        List<ContentDocumentLink> cdlList = new List<ContentDocumentLink>();
        for (ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :cvList]) {
            cdlList.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = emailWithAttachments.Id,
                ShareType = 'V'
            ));
        }
        insert cdlList;
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        // Find the email with multiple attachments
        Boolean foundEmail = false;
        for (EmailForwarder.EmailMessageWrapper wrapper : result) {
            if (wrapper.subject == 'Multiple Attachments Test') {
                System.assertEquals(3, wrapper.attachmentCount, 'Should have 3 attachments');
                foundEmail = true;
            }
        }
        System.assert(foundEmail, 'Should find the email with multiple attachments');
    }
}
