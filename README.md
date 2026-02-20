# Email Forward & Download for Salesforce

## ⚠️ Prerequisites

To ensure full functionality, especially for attachment handling, please review these prerequisites before installing:

- **Save Email-to-Case attachments as Salesforce files** must be enabled in Email-to-Case settings. This ensures email attachments are stored as ContentDocument files and are accessible to the app.
   - Go to **Setup → Email-to-Case**
   - Enable **Save Email-to-Case attachments as Salesforce files**
   - Click **Save**
- Salesforce org must have **EmailMessage** object enabled (standard in most orgs).
- Assign the provided permission sets to users as needed (see below).

Failure to enable the above setting may result in missing attachments when forwarding or downloading emails.

A Lightning Web Component (LWC) solution for Salesforce that allows users to select, download, and forward emails from any Salesforce object record as `.eml` file attachments.

![Salesforce](https://img.shields.io/badge/Salesforce-00A1E0?style=for-the-badge&logo=salesforce&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 📋 Overview

Email Forward & Download provides a user-friendly modal interface that displays all emails associated with a Salesforce record. Users can select one or multiple emails using checkboxes, download them as `.eml` files, or forward them to any email address as `.eml` attachments, preserving the original email format.

## ✨ Features

- **Universal Compatibility** - Works with any Salesforce object that has associated EmailMessage records (Cases, Opportunities, Accounts, etc.)
- **Interactive Data Table** - Lightning Datatable with sortable columns and row-level checkboxes for email selection
- **Bulk Selection** - Select multiple emails at once using the header checkbox
- **EML Format** - Emails are forwarded or downloaded as `.eml` files that can be opened in any email client
- **Download as ZIP** - Download all selected emails as a single ZIP file containing individual `.eml` files (no external libraries required)
- **Configurable Recipient** - Enter any email address as the forwarding destination
- **Modern UI** - Clean, responsive design with SLDS styling and custom blue header
- **Error Handling** - Comprehensive error messages and validation
- **AppExchange Ready** - Follows Salesforce security best practices including CRUD/FLS enforcement and `with sharing` keyword

### 📎 Attachment Support

- **Forward with Attachments** – All original email attachments (ContentDocumentLinks and Attachments) are automatically included when forwarding emails
- **Download with Attachments** - When downloading emails as a ZIP file, all attachments are bundled together with the `.eml` files
- **Preserved File Names** - Original attachment filenames are preserved for easy identification
- **Multiple Attachment Types** - Supports all file types including documents, images, PDFs, and more

## 🏗️ Components

### Apex Classes

| Class | Description |
|-------|-------------|
| `EmailForwarder.cls` | Main controller class with methods for retrieving, downloading, and forwarding emails as EML attachments |
| `EmailForwarderTest.cls` | Comprehensive test class with 22+ test methods for security and functionality coverage |

### Lightning Web Components

| Component | Description |
|-----------|-------------|
| `emailForwarderModal` | Modal component with datatable for selecting and forwarding emails from any object |
| `emailDownloader` | Component for downloading a single email as EML file from EmailMessage record |
| `emailUtils` | Shared utility module for ZIP creation, file downloads, and error handling |

### Flows

| Flow | Description |
|------|-------------|
| `Download_Email` | Screen Flow that wraps emailDownloader LWC for EmailMessage quick action |

### Quick Actions

| Action | Object | Description |
|--------|--------|-------------|
| `Download` | EmailMessage | Downloads the email as an EML file |

### Custom Permissions

| Custom Permission | Description |
|-------------------|-------------|
| `Allow_Email_Forwarding` | Enables the email forwarding feature |
| `Allow_Email_Download` | Enables the email download feature |

### Permission Sets

| Permission Set | Custom Permissions | Description |
|----------------|-------------------|-------------|
| `Email_Forwarder_Full_Access` | Forward + Download | Full access - for Sys Admins and power users |
| `Email_Forwarder_Download_Only` | Download only | Limited access - for standard users |


## ⚠️ Installation Best Practice

**For security, always install the package using "For Admins Only".**

This ensures that only administrators have access to package features by default. You can then assign the provided permission sets to users who need access. If you install "For All Users", all users will automatically get access to the custom permissions and Apex classes, which may defeat the purpose of permission set-based security.

**Recommended steps:**
- Install the package "For Admins Only"
- Assign the appropriate permission set(s) to users who need access (see below)

---

## 📦 Installation

### Option 1: Deploy using Salesforce CLI

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/salesforce-email-forwarder.git

# Navigate to the project directory
cd salesforce-email-forwarder

# Authenticate with your Salesforce org
sf org login web -a MyOrg

# Deploy to your org
sf project deploy start -o MyOrg
```

### Option 2: Deploy using VS Code

1. Clone this repository
2. Open in VS Code with Salesforce Extension Pack installed
3. Authorize your Salesforce org
4. Right-click on the `force-app` folder and select **Deploy Source to Org**

## 📋 Post-Installation Setup

After installing the package, complete the following steps:

### 1. Assign Permission Set

Assign the appropriate permission set based on user needs:

| User Type | Permission Set | Capabilities |
|-----------|----------------|--------------|
| Sys Admins / Power Users | **Email Forwarder Full Access** | Forward + Download |
| Standard Users | **Email Forwarder Download Only** | Download only |

**Steps:**
1. Go to **Setup → Permission Sets**
2. Click the appropriate permission set
3. Click **Manage Assignments** → **Add Assignment**
4. Select users who need access to the feature
5. Click **Assign**

### 2. Configure Email Deliverability (Required for Send Feature)

1. Go to **Setup → Email → Deliverability**
2. Set **Access level** to **All Email**

### 3. Add "Download" Action to EmailMessage Page Layout

The Quick Action is included in the package but must be added to the page layout manually.

1. Go to **Setup → Object Manager → Email Message → Page Layouts**
2. Edit the **Email Message Layout**
3. Scroll to **Salesforce Mobile and Lightning Experience Actions** section
4. Click the wrench icon to override predefined actions (if needed)
5. Drag **Download** from available actions to the action bar
6. Click **Save**

### 4. Setup "Forward Emails" Action (Per Object)

This action needs to be created manually on each object where you want the forward emails feature (e.g., Case, Contact, Account, Opportunity).

#### Create Quick Action:

1. Go to **Setup → Object Manager → [Your Object]** (e.g., Case)
2. Click **Buttons, Links, and Actions** → **New Action**
3. Configure:
   | Field | Value |
   |-------|-------|
   | Action Type | Lightning Web Component |
   | Lightning Web Component | `c:emailForwarderModal` |
   | Label | Forward Emails |
   | Name | Forward_Emails |
4. Click **Save**

#### Add to Page Layout:

1. Go to **[Object] → Page Layouts** → Edit your layout
2. Scroll to **Salesforce Mobile and Lightning Experience Actions**
3. Click the wrench icon to override predefined actions (if needed)
4. Drag **Forward Emails** to the action bar
5. Click **Save**

#### For Dynamic Actions (Lightning App Builder):

If your org uses Dynamic Actions on Lightning Record Pages:

1. Go to **Setup → Lightning App Builder**
2. Edit the Record Page for your object
3. Select the **Highlights Panel** component
4. In properties, find **Actions** section
5. Click **Add Action** → Select **Forward Emails**
6. Save and Activate the page

### ✅ Setup Checklist

| Step | Task | Included in Package | Manual Action |
|------|------|:-------------------:|:-------------:|
| 1 | Permission Sets | ✅ | Assign to users based on role |
| 2 | Email Deliverability | — | Configure in Setup (for Send) |
| 3 | Download Action (EmailMessage) | ✅ | Add to page layout |
| 4 | Forward Emails Action (Other Objects) | — | Create action & add to layout |

> **Note:** The feature automatically shows/hides Forward and Download buttons based on the user's assigned custom permissions. Users with only the "Download Only" permission set will only see the Download button.

## 🖥️ Usage

1. Navigate to any record that has associated emails (e.g., a Case)
2. Click the **Forward Emails** action button
3. The modal will display all emails associated with the record
4. Select the emails you want using the checkboxes
5. Choose your action:
   - **Send**: Enter the recipient email address and click **Send** to forward the selected emails as `.eml` attachments
   - **Download**: Click **Download** to download all selected emails as a single ZIP file containing individual `.eml` files

## 📁 Project Structure

```
force-app/
└── main/
    └── default/
        ├── classes/
        │   ├── EmailForwarder.cls
        │   ├── EmailForwarder.cls-meta.xml
        │   ├── EmailForwarderTest.cls
        │   └── EmailForwarderTest.cls-meta.xml
        ├── customPermissions/
        │   ├── Allow_Email_Download.customPermission-meta.xml
        │   └── Allow_Email_Forwarding.customPermission-meta.xml
        ├── flows/
        │   └── Download_Email.flow-meta.xml
        ├── lwc/
        │   ├── emailDownloader/
        │   ├── emailForwarderModal/
        │   └── emailUtils/
        ├── permissionsets/
        │   ├── Email_Forwarder_Download_Only.permissionset-meta.xml
        │   └── Email_Forwarder_Full_Access.permissionset-meta.xml
        └── quickActions/
            └── EmailMessage.Download.quickAction-meta.xml
```

## 🔧 Technical Details

### EmailMessage Query

The component queries EmailMessage records using the `RelatedToId` field, which links emails to their parent record.

### EML Format

Emails are converted to RFC 822 compliant `.eml` format with the following headers:
- From
- To
- Date
- Subject
- MIME-Version
- Content-Type

### Supported Data Table Columns

| Column | Field | Sortable |
|--------|-------|----------|
| Subject | subject | ✅ |
| From | fromAddress | ✅ |
| To | toAddress | ✅ |
| Date | formattedDate | ✅ |
| Direction | direction | ✅ |

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Salesforce Lightning Web Components](https://developer.salesforce.com/docs/component-library/documentation/en/lwc)
- Styled with [Salesforce Lightning Design System (SLDS)](https://www.lightningdesignsystem.com/)

## 📞 Support

If you encounter any issues or have questions, please open an issue on GitHub.

---

**Made with ❤️ for the Salesforce community**
