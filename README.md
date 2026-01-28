# Salesforce Email Forwarder LWC

A Lightning Web Component (LWC) solution for Salesforce that allows users to select and forward emails from any Salesforce object record as `.eml` file attachments.

![Salesforce](https://img.shields.io/badge/Salesforce-00A1E0?style=for-the-badge&logo=salesforce&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 📋 Overview

This feature provides a user-friendly modal interface that displays all emails associated with a Salesforce record. Users can select one or multiple emails using checkboxes and forward them to any email address as `.eml` attachments, preserving the original email format.

## ✨ Features

- **Universal Compatibility** - Works with any Salesforce object that has associated EmailMessage records (Cases, Opportunities, Accounts, etc.)
- **Interactive Data Table** - Lightning Datatable with sortable columns and row-level checkboxes for email selection
- **Bulk Selection** - Select multiple emails at once using the header checkbox
- **EML Format** - Emails are forwarded as `.eml` files that can be opened in any email client
- **Download as ZIP** - Download all selected emails as a single ZIP file containing individual `.eml` files (no external libraries required)
- **Configurable Recipient** - Enter any email address as the forwarding destination
- **Modern UI** - Clean, responsive design with SLDS styling and custom blue header
- **Error Handling** - Comprehensive error messages and validation
- **AppExchange Ready** - Follows Salesforce security best practices including CRUD/FLS enforcement and `with sharing` keyword

## 🏗️ Components

### Apex Classes

| Class | Description |
|-------|-------------|
| `EmailForwarder.cls` | Main controller class with methods for retrieving emails and forwarding them as EML attachments |
| `EmailForwarderTest.cls` | Comprehensive test class with 22+ test methods for security and functionality coverage |

### Lightning Web Components

| Component | Description |
|-----------|-------------|
| `emailForwarderModal` | Modal component with datatable for selecting and forwarding emails |

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

## ⚙️ Configuration

### Create a Quick Action

1. Go to **Setup → Object Manager → [Your Object] → Buttons, Links, and Actions**
2. Click **New Action**
3. Configure:
   - Action Type: **Lightning Web Component**
   - Lightning Web Component: **c:emailForwarderModal**
   - Label: **Forward Emails**
   - Name: **Forward_Emails**
4. Click **Save**
5. Add the action to your page layout

### Email Deliverability

Ensure your org's email deliverability is configured:

1. Go to **Setup → Email → Deliverability**
2. Set **Access level** to **All Email**

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
        └── lwc/
            └── emailForwarderModal/
                ├── emailForwarderModal.html
                ├── emailForwarderModal.js
                ├── emailForwarderModal.css
                └── emailForwarderModal.js-meta.xml
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
