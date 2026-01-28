@isTest
private class EmailForwarderTest {
    
    /**
     * Test data setup - creates Case and EmailMessage records
     */
    @TestSetup
    static void setupTestData() {
        // Create a test Case (used as a parent record for EmailMessages)
        Case testCase = new Case(
            Subject = 'Test Record for Email Forwarding',
            Status = 'New',
            Origin = 'Email'
        );
        insert testCase;
        
        // Create test EmailMessages related to the Case
        List<EmailMessage> testEmails = new List<EmailMessage>();
        
        // Email 1 - Incoming with HTML body
        EmailMessage email1 = new EmailMessage(
            RelatedToId = testCase.Id,
            Subject = 'Test Email 1',
            FromAddress = 'sender1@example.com',
            ToAddress = 'recipient1@example.com',
            HtmlBody = '<html><body><p>This is test email 1 body</p></body></html>',
            TextBody = 'This is test email 1 body',
            MessageDate = Datetime.now().addDays(-1),
            Status = '0',
            Incoming = true
        );
        testEmails.add(email1);
        
        // Email 2 - Outgoing with Text body only
        EmailMessage email2 = new EmailMessage(
            RelatedToId = testCase.Id,
            Subject = 'Test Email 2',
            FromAddress = 'sender2@example.com',
            ToAddress = 'recipient2@example.com',
            TextBody = 'This is test email 2 body - text only',
            MessageDate = Datetime.now().addDays(-2),
            Status = '3',
            Incoming = false
        );
        testEmails.add(email2);
        
        // Email 3 - No subject, no body (edge case)
        EmailMessage email3 = new EmailMessage(
            RelatedToId = testCase.Id,
            FromAddress = 'sender3@example.com',
            ToAddress = 'recipient3@example.com',
            MessageDate = Datetime.now(),
            Status = '0',
            Incoming = true
        );
        testEmails.add(email3);
        
        insert testEmails;
    }
    
    /**
     * Helper method to get test Case
     */
    private static Case getTestCase() {
        return [SELECT Id FROM Case WHERE Subject = 'Test Record for Email Forwarding' LIMIT 1];
    }
    
    /**
     * Helper method to get test EmailMessages
     */
    private static List<EmailMessage> getTestEmails() {
        return [SELECT Id, Subject, FromAddress, ToAddress, HtmlBody, TextBody, MessageDate, Status, Incoming 
                FROM EmailMessage 
                WHERE RelatedToId = :getTestCase().Id];
    }
    
    /**
     * Test getEmailsByRecordId - Success scenario
     */
    @isTest
    static void testGetEmailsByRecordId_Success() {
        Case testCase = getTestCase();
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(testCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.size(), 'Should return 3 email messages');
        
        // Verify wrapper properties are populated
        for (EmailForwarder.EmailMessageWrapper wrapper : result) {
            System.assertNotEquals(null, wrapper.id, 'Id should not be null');
            System.assertNotEquals(null, wrapper.subject, 'Subject should not be null');
            System.assertNotEquals(null, wrapper.direction, 'Direction should not be null');
        }
    }
    
    /**
     * Test getEmailsByRecordId - No emails found
     */
    @isTest
    static void testGetEmailsByRecordId_NoEmails() {
        // Create a Case with no emails
        Case emptyCase = new Case(Subject = 'Empty Case', Status = 'New');
        insert emptyCase;
        
        Test.startTest();
        List<EmailForwarder.EmailMessageWrapper> result = EmailForwarder.getEmailsByRecordId(emptyCase.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return 0 email messages');
    }
    
    /**
     * Test getEmailsForDownload - Success scenario
     */
    @isTest
    static void testGetEmailsForDownload_Success() {
        List<EmailMessage> testEmails = getTestEmails();
        List<Id> emailIds = new List<Id>();
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
            System.assertNotEquals(null, wrapper.fileName, 'FileName should not be null');
            System.assert(wrapper.fileName.endsWith('.eml'), 'FileName should end with .eml');
            System.assertNotEquals(null, wrapper.content, 'Content should not be null');
            System.assert(wrapper.content.contains('MIME-Version: 1.0'), 'Content should contain MIME header');
        }
    }
    
    /**
     * Test getEmailsForDownload - Empty list throws exception
     */
    @isTest
    static void testGetEmailsForDownload_EmptyList() {
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            EmailForwarder.getEmailsForDownload(new List<Id>());
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected AuraHandledException for empty list');
    }
    
    /**
     * Test getEmailsForDownload - Null list throws exception
     */
    @isTest
    static void testGetEmailsForDownload_NullList() {
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            EmailForwarder.getEmailsForDownload(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected AuraHandledException for null list');
    }
    
    /**
     * Test getEmailsForDownload - Invalid IDs (no matching records)
     */
    @isTest
    static void testGetEmailsForDownload_InvalidIds() {
        // Use a fake ID that doesn't exist
        Id fakeId = '02s000000000001AAA'; // EmailMessage fake ID
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            EmailForwarder.getEmailsForDownload(new List<Id>{ fakeId });
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected AuraHandledException for invalid IDs');
    }
    
    /**
     * Test forwardSelectedEmails - Success scenario
     */
    @isTest
    static void testForwardSelectedEmails_Success() {
        List<EmailMessage> testEmails = getTestEmails();
        List<Id> emailIds = new List<Id>();
        for (EmailMessage em : testEmails) {
            emailIds.add(em.Id);
        }
        
        Test.startTest();
        String result = EmailForwarder.forwardSelectedEmails(emailIds, 'test@example.com');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('Success'), 'Result should contain Success');
        System.assert(result.contains('3'), 'Result should mention 3 emails');
    }
    
    /**
     * Test forwardSelectedEmails - Empty email list throws exception
     */
    @isTest
    static void testForwardSelectedEmails_EmptyList() {
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(new List<Id>(), 'test@example.com');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected AuraHandledException for empty list');
    }
    
    /**
     * Test forwardSelectedEmails - Null email list throws exception
     */
    @isTest
    static void testForwardSelectedEmails_NullList() {
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(null, 'test@example.com');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected AuraHandledException for null list');
    }
    
    /**
     * Test forwardSelectedEmails - Blank recipient throws exception
     */
    @isTest
    static void testForwardSelectedEmails_BlankRecipient() {
        List<EmailMessage> testEmails = getTestEmails();
        List<Id> emailIds = new List<Id>{ testEmails[0].Id };
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(emailIds, '');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected AuraHandledException for blank recipient');
    }
    
    /**
     * Test forwardSelectedEmails - Null recipient throws exception
     */
    @isTest
    static void testForwardSelectedEmails_NullRecipient() {
        List<EmailMessage> testEmails = getTestEmails();
        List<Id> emailIds = new List<Id>{ testEmails[0].Id };
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            EmailForwarder.forwardSelectedEmails(emailIds, null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected AuraHandledException for null recipient');
    }
    
    /**
     * Test forwardEmails (Invocable) - Success scenario
     */
    @isTest
    static void testForwardEmails_Invocable_EmptyBatch() {
        // Test with empty batch - should return without error
        List<List<Id>> emptyBatches = new List<List<Id>>();
        emptyBatches.add(new List<Id>());
        
        Test.startTest();
        // This should not throw an exception, just return early
        EmailForwarder.forwardEmails(emptyBatches);
        Test.stopTest();
        
        // If we get here without exception, test passes
        System.assert(true, 'Empty batch should not throw exception');
    }
    
    /**
     * Test EmailMessageWrapper - Verify all properties
     */
    @isTest
    static void testEmailMessageWrapper_Properties() {
        List<EmailMessage> testEmails = getTestEmails();
        EmailMessage incomingEmail = null;
        EmailMessage outgoingEmail = null;
        
        for (EmailMessage em : testEmails) {
            if (em.Incoming == true && em.Subject != null) {
                incomingEmail = em;
            } else if (em.Incoming == false) {
                outgoingEmail = em;
            }
        }
        
        Test.startTest();
        
        // Test incoming email wrapper
        EmailForwarder.EmailMessageWrapper incomingWrapper = new EmailForwarder.EmailMessageWrapper(incomingEmail);
        System.assertEquals(incomingEmail.Id, incomingWrapper.id, 'Id should match');
        System.assertEquals('Test Email 1', incomingWrapper.subject, 'Subject should match');
        System.assertEquals('sender1@example.com', incomingWrapper.fromAddress, 'From address should match');
        System.assertEquals('recipient1@example.com', incomingWrapper.toAddress, 'To address should match');
        System.assertEquals(true, incomingWrapper.incoming, 'Incoming should be true');
        System.assertEquals('Incoming', incomingWrapper.direction, 'Direction should be Incoming');
        
        // Test outgoing email wrapper
        EmailForwarder.EmailMessageWrapper outgoingWrapper = new EmailForwarder.EmailMessageWrapper(outgoingEmail);
        System.assertEquals(false, outgoingWrapper.incoming, 'Incoming should be false');
        System.assertEquals('Outgoing', outgoingWrapper.direction, 'Direction should be Outgoing');
        
        Test.stopTest();
    }
    
    /**
     * Test EmailMessageWrapper - Null subject handling
     */
    @isTest
    static void testEmailMessageWrapper_NullSubject() {
        List<EmailMessage> testEmails = getTestEmails();
        EmailMessage nullSubjectEmail = null;
        
        for (EmailMessage em : testEmails) {
            if (em.Subject == null) {
                nullSubjectEmail = em;
                break;
            }
        }
        
        Test.startTest();
        EmailForwarder.EmailMessageWrapper wrapper = new EmailForwarder.EmailMessageWrapper(nullSubjectEmail);
        Test.stopTest();
        
        System.assertEquals('(No Subject)', wrapper.subject, 'Null subject should be replaced with (No Subject)');
    }
    
    /**
     * Test EmailContentWrapper - Constructor
     */
    @isTest
    static void testEmailContentWrapper_Constructor() {
        Test.startTest();
        EmailForwarder.EmailContentWrapper wrapper = new EmailForwarder.EmailContentWrapper('test.eml', 'Test content');
        Test.stopTest();
        
        System.assertEquals('test.eml', wrapper.fileName, 'FileName should match');
        System.assertEquals('Test content', wrapper.content, 'Content should match');
    }
    
    /**
     * Test forwardSelectedEmails - Single email forward
     */
    @isTest
    static void testForwardSelectedEmails_SingleEmail() {
        List<EmailMessage> testEmails = getTestEmails();
        List<Id> emailIds = new List<Id>{ testEmails[0].Id };
        
        Test.startTest();
        String result = EmailForwarder.forwardSelectedEmails(emailIds, 'single@example.com');
        Test.stopTest();
        
        System.assert(result.contains('1 email(s) forwarded'), 'Result should mention 1 email forwarded');
    }
    
    /**
     * Test getEmailsForDownload - Verifies EML content format
     */
    @isTest
    static void testGetEmailsForDownload_EmlFormat() {
        List<EmailMessage> testEmails = getTestEmails();
        // Get the email with HTML body
        EmailMessage htmlEmail = null;
        for (EmailMessage em : testEmails) {
            if (em.HtmlBody != null) {
                htmlEmail = em;
                break;
            }
        }
        
        Test.startTest();
        List<EmailForwarder.EmailContentWrapper> result = EmailForwarder.getEmailsForDownload(new List<Id>{ htmlEmail.Id });
        Test.stopTest();
        
        System.assertEquals(1, result.size(), 'Should return 1 email content');
        
        String emlContent = result[0].content;
        System.assert(emlContent.contains('From: sender1@example.com'), 'EML should contain From header');
        System.assert(emlContent.contains('To: recipient1@example.com'), 'EML should contain To header');
        System.assert(emlContent.contains('Subject: Test Email 1'), 'EML should contain Subject header');
        System.assert(emlContent.contains('MIME-Version: 1.0'), 'EML should contain MIME version');
        System.assert(emlContent.contains('Content-Type: text/html'), 'EML should contain Content-Type');
    }
}
