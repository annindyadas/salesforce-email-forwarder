/**
 * Utility module for email-related operations
 * Provides common functionality for email downloading and error handling
 * 
 * @author Annindya Das
 * @version 1.0
 */

/**
 * CRC-32 table (lazy initialized)
 */
let crc32Table = null;

/**
 * Get or initialize the CRC-32 lookup table
 * @returns {Uint32Array} The CRC-32 lookup table
 */
function getCrc32Table() {
    if (!crc32Table) {
        crc32Table = new Uint32Array(256);
        for (let i = 0; i < 256; i++) {
            let c = i;
            for (let j = 0; j < 8; j++) {
                c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
            }
            crc32Table[i] = c;
        }
    }
    return crc32Table;
}

/**
 * Calculate CRC-32 checksum for data
 * @param {Uint8Array} data - The data to calculate CRC for
 * @returns {number} The CRC-32 checksum
 */
export function crc32(data) {
    let crc = 0xFFFFFFFF;
    const table = getCrc32Table();
    
    for (let i = 0; i < data.length; i++) {
        crc = (crc >>> 8) ^ table[(crc ^ data[i]) & 0xFF];
    }
    
    return (crc ^ 0xFFFFFFFF) >>> 0;
}

/**
 * Create a ZIP file from email contents (pure JavaScript, no external libraries)
 * @param {Array} emailContents - Array of objects with fileName and content properties
 * @returns {Promise<Blob>} A promise that resolves to a ZIP file Blob
 */
export async function createZipFile(emailContents) {
    const files = emailContents.map(email => ({
        name: email.fileName,
        content: email.content
    }));

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
        view.setUint32(14, crc32(fileData), true); // CRC-32
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
        centralView.setUint32(16, crc32(fileData), true); // CRC-32
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

/**
 * Download a single EML file (LWS-compliant using base64 data URL)
 * @param {string} content - The EML file content
 * @param {string} fileName - The filename for the download
 */
export function downloadEmlFile(content, fileName) {
    // Use base64 data URL for LWS compliance
    const base64Content = btoa(unescape(encodeURIComponent(content)));
    const dataUrl = `data:application/octet-stream;base64,${base64Content}`;
    triggerDownload(dataUrl, fileName);
}

/**
 * Download a ZIP file containing emails (LWS-compliant)
 * @param {Blob} zipBlob - The ZIP file blob
 * @param {string} fileName - The filename for the download (optional)
 */
export async function downloadZipFile(zipBlob, fileName) {
    const defaultFileName = `emails_${new Date().toISOString().slice(0, 10)}.zip`;
    const base64Content = await blobToBase64(zipBlob);
    const dataUrl = `data:application/octet-stream;base64,${base64Content}`;
    triggerDownload(dataUrl, fileName || defaultFileName);
}

/**
 * Convert Blob to base64 string
 * @param {Blob} blob - The blob to convert
 * @returns {Promise<string>} Base64 encoded string
 */
function blobToBase64(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onloadend = () => {
            // Remove the data URL prefix to get just the base64 string
            const base64 = reader.result.split(',')[1];
            resolve(base64);
        };
        reader.onerror = reject;
        reader.readAsDataURL(blob);
    });
}

/**
 * Trigger file download using data URL (LWS-compliant)
 * @param {string} dataUrl - The data URL
 * @param {string} fileName - The filename for the download
 */
function triggerDownload(dataUrl, fileName) {
    const downloadLink = document.createElement('a');
    downloadLink.href = dataUrl;
    downloadLink.download = fileName;
    downloadLink.style.display = 'none';
    document.body.appendChild(downloadLink);
    downloadLink.click();
    document.body.removeChild(downloadLink);
}

/**
 * Generic blob download helper (LWS-compliant)
 * @param {Blob} blob - The blob to download
 * @param {string} fileName - The filename for the download
 */
export async function downloadBlob(blob, fileName) {
    const base64Content = await blobToBase64(blob);
    const dataUrl = `data:application/octet-stream;base64,${base64Content}`;
    triggerDownload(dataUrl, fileName);
}

/**
 * Reduce errors from Apex calls to a readable string
 * @param {Error|Object|string} error - The error object to reduce
 * @returns {string} A human-readable error message
 */
export function reduceErrors(error) {
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
