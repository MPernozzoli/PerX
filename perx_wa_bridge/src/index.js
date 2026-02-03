/**
 * PerX WhatsApp Bridge
 * Bridge WhatsApp usando whatsapp-web.js
 * Comunica con PerX Hub via HTTP API
 */

require('dotenv').config();
const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const express = require('express');
const axios = require('axios');

// Puppeteer con plugin stealth per evitare rilevamento automazione
const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

// Configuration
const HUB_URL = process.env.HUB_URL || 'http://localhost:8080';
const PORT = process.env.PORT || 5002;  // Porta standard per WA Bridge
const SESSION_PATH = process.env.SESSION_PATH || './sessions';

// Express app per API
const app = express();
app.use(express.json({ limit: '50mb' }));

// WhatsApp clients (uno per account)
const clients = new Map();

// Retry state per riconnessione
const retryState = new Map();
const MAX_RETRIES = 5;
const BASE_RETRY_DELAY = 5000;

// Sanitizza accountId per LocalAuth (solo alphanumeric, underscore, hyphen)
function sanitizeClientId(accountId) {
    // Sostituisce punti e altri caratteri non validi con underscore
    return accountId.replace(/[^a-zA-Z0-9_-]/g, '_');
}

// Normalizza numero telefono
function normalizePhoneNumber(number) {
    if (!number) return number;
    // Rimuovi @c.us se presente
    let cleaned = number.replace('@c.us', '').replace('@g.us', '');
    // Rimuovi caratteri non numerici eccetto il +
    cleaned = cleaned.replace(/[^\d+]/g, '');
    // Rimuovi + iniziale
    cleaned = cleaned.replace(/^\+/, '');
    return `${cleaned}@c.us`;
}

// Initialize client for an account
function initClient(accountId, phoneNumber) {
    console.log(`[WA Bridge] Initializing client for ${accountId}`);
    
    // Sanitizza clientId per LocalAuth (che non accetta punti)
    const safeClientId = sanitizeClientId(accountId);
    console.log(`[WA Bridge] Using clientId: ${safeClientId}`);
    
    // Reset retry state
    retryState.set(accountId, { count: 0, lastAttempt: null });
    
    // Cerca Chrome installato
    const chromePaths = [
        '/Users/mpernozzoli/.cache/puppeteer/chrome/mac_arm-144.0.7559.96/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/opt/homebrew/bin/chromium'
    ];
    
    const fs = require('fs');
    let executablePath = null;
    for (const p of chromePaths) {
        if (fs.existsSync(p)) {
            executablePath = p;
            break;
        }
    }
    
    console.log(`[WA Bridge] Using Chrome at: ${executablePath || 'default'}`);
    
    const puppeteerOptions = {
        headless: 'new',  // Nuova modalità headless (meno rilevabile)
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--disable-blink-features=AutomationControlled',  // Anti-detection
            '--disable-infobars',
            '--window-size=1920,1080'
        ]
    };
    
    if (executablePath) {
        puppeteerOptions.executablePath = executablePath;
    }
    
    const client = new Client({
        authStrategy: new LocalAuth({
            clientId: safeClientId,
            dataPath: SESSION_PATH
        }),
        puppeteer: puppeteerOptions,
        webVersionCache: {
            type: 'remote',
            remotePath: 'https://raw.githubusercontent.com/nicebots-xyz/nicebots/main/nicebots/'
        }
    });
    
    // QR Code
    client.on('qr', (qr) => {
        console.log(`[WA Bridge] QR Code for ${accountId}:`);
        qrcode.generate(qr, { small: true });
        
        // Aggiorna stato client
        const clientInfo = clients.get(accountId);
        if (clientInfo) clientInfo.status = 'waitingQR';
        
        // Invia QR all'Hub per UI
        axios.post(`${HUB_URL}/internal/whatsapp/${accountId}/qr`, { qr })
            .catch(err => console.error('Failed to send QR to Hub:', err.message));
    });
    
    // Authenticated (QR scansionato con successo)
    client.on('authenticated', () => {
        console.log(`[WA Bridge] Client ${accountId} authenticated!`);
        const clientInfo = clients.get(accountId);
        if (clientInfo) clientInfo.status = 'authenticated';
        
        // Reset retry count on successful auth
        retryState.set(accountId, { count: 0, lastAttempt: null });
    });
    
    // Auth failure
    client.on('auth_failure', (msg) => {
        console.error(`[WA Bridge] Auth failed for ${accountId}:`, msg);
        const clientInfo = clients.get(accountId);
        if (clientInfo) clientInfo.status = 'auth_failed';
        
        axios.post(`${HUB_URL}/internal/whatsapp/${accountId}/status`, { 
            status: 'auth_failed',
            reason: String(msg)
        }).catch(err => console.error('Failed to notify Hub:', err.message));
    });
    
    // Ready
    client.on('ready', () => {
        console.log(`[WA Bridge] Client ${accountId} ready!`);
        
        // Aggiorna stato client
        const clientInfo = clients.get(accountId);
        if (clientInfo) clientInfo.status = 'ready';
        
        // Reset retry count
        retryState.set(accountId, { count: 0, lastAttempt: null });
        
        axios.post(`${HUB_URL}/internal/whatsapp/${accountId}/status`, { status: 'ready' })
            .catch(err => console.error('Failed to notify Hub:', err.message));
    });
    
    // Message received (incoming)
    client.on('message', async (msg) => {
        try {
            console.log(`[WA Bridge] 📨 Incoming message from ${msg.from}`);
            await handleIncomingMessage(accountId, msg, false);
        } catch (err) {
            console.error(`[WA Bridge] Error handling incoming message:`, err);
        }
    });
    
    // Message created (outgoing - sent by us)
    client.on('message_create', async (msg) => {
        // Solo messaggi inviati da noi
        if (msg.fromMe) {
            try {
                console.log(`[WA Bridge] 📤 Outgoing message to ${msg.to}`);
                await handleIncomingMessage(accountId, msg, true);
            } catch (err) {
                console.error(`[WA Bridge] Error handling outgoing message:`, err);
            }
        }
    });
    
    // Disconnected con riconnessione automatica
    client.on('disconnected', (reason) => {
        console.log(`[WA Bridge] Client ${accountId} disconnected:`, reason);
        
        // Aggiorna stato
        const clientInfo = clients.get(accountId);
        if (clientInfo) clientInfo.status = 'disconnected';
        
        axios.post(`${HUB_URL}/internal/whatsapp/${accountId}/status`, { 
            status: 'disconnected',
            reason 
        }).catch(err => console.error('Failed to notify Hub:', err.message));
        
        // Riconnessione automatica con backoff esponenziale
        const state = retryState.get(accountId) || { count: 0, lastAttempt: null };
        
        if (state.count < MAX_RETRIES) {
            const delay = BASE_RETRY_DELAY * Math.pow(2, state.count);
            console.log(`[WA Bridge] Tentativo riconnessione ${accountId} in ${delay/1000}s (attempt ${state.count + 1}/${MAX_RETRIES})`);
            
            retryState.set(accountId, { count: state.count + 1, lastAttempt: Date.now() });
            
            setTimeout(async () => {
                try {
                    console.log(`[WA Bridge] Riconnessione ${accountId}...`);
                    if (clientInfo) clientInfo.status = 'reconnecting';
                    await client.initialize();
                } catch (err) {
                    console.error(`[WA Bridge] Riconnessione fallita per ${accountId}:`, err.message);
                }
            }, delay);
        } else {
            console.error(`[WA Bridge] Max retries raggiunto per ${accountId}, richiesta riconnessione manuale`);
            axios.post(`${HUB_URL}/internal/whatsapp/${accountId}/status`, { 
                status: 'max_retries',
                reason: 'Maximum reconnection attempts reached'
            }).catch(err => console.error('Failed to notify Hub:', err.message));
        }
    });
    
    // Loading screen (durante l'avvio)
    client.on('loading_screen', (percent, message) => {
        console.log(`[WA Bridge] Loading ${accountId}: ${percent}% - ${message}`);
        const clientInfo = clients.get(accountId);
        if (clientInfo) clientInfo.status = 'loading';
    });
    
    // Gestione errori generici
    client.on('error', (error) => {
        console.error(`[WA Bridge] Client error for ${accountId}:`, error);
    });
    
    // Read receipts (spunte blu)
    // ack: -1 = ERROR, 0 = PENDING, 1 = SERVER, 2 = DEVICE, 3 = READ, 4 = PLAYED
    client.on('message_ack', async (msg, ack) => {
        const ackNames = { '-1': 'error', '0': 'pending', '1': 'sent', '2': 'delivered', '3': 'read', '4': 'played' };
        const ackName = ackNames[ack.toString()] || `unknown(${ack})`;
        console.log(`[WA Bridge] 📬 ACK ${ackName} for message ${msg.id.id}`);
        
        try {
            await axios.post(`${HUB_URL}/internal/whatsapp/message-ack`, {
                accountId,
                messageId: msg.id.id,
                ack: ack,
                ackName: ackName,
                timestamp: Date.now() / 1000
            });
        } catch (err) {
            // Non loggare errori per ogni ACK, troppo verbose
        }
    });
    
    // Salva il client PRIMA di initialize
    clients.set(accountId, { client, phoneNumber, status: 'initializing' });
    
    // Inizializza con gestione errori
    client.initialize().catch(err => {
        console.error(`[WA Bridge] Failed to initialize client ${accountId}:`, err);
        const clientInfo = clients.get(accountId);
        if (clientInfo) {
            clientInfo.status = 'error';
            clientInfo.error = err.message;
        }
    });
    
    return client;
}

// Handle message (incoming or outgoing)
async function handleIncomingMessage(accountId, msg, isOutgoing = false) {
    const bodyPreview = msg.body ? msg.body.substring(0, 50) : '[media/no text]';
    const direction = isOutgoing ? '📤 OUT' : '📨 IN';
    console.log(`[WA Bridge] ${direction} | ${msg.from} → ${msg.to}: ${bodyPreview}...`);
    
    const messageData = {
        accountId,
        messageId: msg.id.id,
        from: msg.from,
        to: msg.to,
        body: msg.body,
        timestamp: msg.timestamp,
        type: msg.type,
        hasMedia: msg.hasMedia,
        isGroup: msg.isGroup,
        author: msg.author || null,
        isOutgoing: isOutgoing
    };
    
    // Download media if present
    if (msg.hasMedia) {
        console.log(`[WA Bridge] 📎 Downloading media (type: ${msg.type})...`);
        try {
            const media = await msg.downloadMedia();
            if (media) {
                const sizeKB = Math.round((media.data?.length || 0) * 0.75 / 1024);
                console.log(`[WA Bridge] 📎 Media downloaded: ${media.mimetype}, ${sizeKB}KB`);
                messageData.media = {
                    mimetype: media.mimetype,
                    data: media.data,
                    filename: media.filename || `attachment.${media.mimetype.split('/')[1] || 'bin'}`
                };
            } else {
                console.log(`[WA Bridge] ⚠️ Media download returned null`);
            }
        } catch (err) {
            console.error('[WA Bridge] ❌ Failed to download media:', err.message);
        }
    }
    
    // Send to Hub
    try {
        await axios.post(`${HUB_URL}/internal/whatsapp/message`, messageData);
        console.log(`[WA Bridge] ✅ Message sent to Hub`);
    } catch (err) {
        console.error('[WA Bridge] ❌ Failed to send message to Hub:', err.message);
        if (err.response) {
            console.error('[WA Bridge] Hub response:', err.response.status, err.response.data);
        }
    }
}

// API Endpoints

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        clients: Array.from(clients.entries()).map(([id, c]) => ({
            accountId: id,
            status: c.status
        }))
    });
});

// Initialize client
app.post('/clients/:accountId/init', (req, res) => {
    const { accountId } = req.params;
    const { phoneNumber } = req.body;
    
    // Se il client esiste già, restituisce lo status attuale
    if (clients.has(accountId)) {
        const clientInfo = clients.get(accountId);
        return res.json({ 
            status: clientInfo.status,
            phoneNumber: clientInfo.phoneNumber,
            message: 'Client already initialized'
        });
    }
    
    try {
        initClient(accountId, phoneNumber);
        res.json({ status: 'initializing' });
    } catch (error) {
        console.error(`[WA Bridge] Error initializing client ${accountId}:`, error);
        res.status(500).json({ error: error.message || 'Failed to initialize client' });
    }
});

// Get client status
app.get('/clients/:accountId/status', (req, res) => {
    const { accountId } = req.params;
    const clientInfo = clients.get(accountId);
    
    if (!clientInfo) {
        return res.status(404).json({ error: 'Client not found' });
    }
    
    res.json({
        accountId,
        status: clientInfo.status,
        phoneNumber: clientInfo.phoneNumber,
        error: clientInfo.error || null
    });
});

// Check if number is registered on WhatsApp
app.post('/clients/:accountId/check-number', async (req, res) => {
    const { accountId } = req.params;
    const { phoneNumber } = req.body;
    
    const clientInfo = clients.get(accountId);
    if (!clientInfo) {
        return res.status(404).json({ error: 'Client not found' });
    }
    
    if (clientInfo.status !== 'ready') {
        return res.status(400).json({ error: 'Client not ready' });
    }
    
    if (!phoneNumber) {
        return res.status(400).json({ error: 'Phone number is required' });
    }
    
    try {
        // Normalizza il numero
        const normalized = normalizePhoneNumber(phoneNumber);
        
        // getNumberId ritorna null se il numero non è su WhatsApp
        const numberId = await clientInfo.client.getNumberId(normalized);
        
        if (numberId) {
            // Prova a ottenere anche la foto profilo
            let profilePicUrl = null;
            try {
                profilePicUrl = await clientInfo.client.getProfilePicUrl(numberId._serialized);
            } catch (picErr) {
                // Foto profilo non disponibile (privacy)
            }
            
            res.json({
                isRegistered: true,
                numberId: numberId._serialized,
                profilePicUrl: profilePicUrl
            });
        } else {
            res.json({
                isRegistered: false,
                numberId: null
            });
        }
    } catch (err) {
        console.error('[WA Bridge] Check number failed:', err);
        res.status(500).json({ error: err.message });
    }
});

// Get profile picture URL
app.get('/clients/:accountId/profile-pic/:contactId', async (req, res) => {
    const { accountId, contactId } = req.params;
    
    const clientInfo = clients.get(accountId);
    if (!clientInfo) {
        return res.status(404).json({ error: 'Client not found' });
    }
    
    if (clientInfo.status !== 'ready') {
        return res.status(400).json({ error: 'Client not ready' });
    }
    
    try {
        // contactId può essere numero o chatId (es. 393401234567@c.us)
        let chatId = contactId;
        if (!contactId.includes('@')) {
            chatId = normalizePhoneNumber(contactId);
        }
        
        const profilePicUrl = await clientInfo.client.getProfilePicUrl(chatId);
        
        res.json({
            contactId: chatId,
            profilePicUrl: profilePicUrl || null
        });
    } catch (err) {
        // Privacy settings may prevent getting profile pic
        res.json({
            contactId: contactId,
            profilePicUrl: null,
            error: 'Profile picture not available'
        });
    }
});

// Send message
app.post('/clients/:accountId/send', async (req, res) => {
    const { accountId } = req.params;
    const { to, body, media } = req.body;
    
    const clientInfo = clients.get(accountId);
    if (!clientInfo) {
        return res.status(404).json({ error: 'Client not found' });
    }
    
    try {
        let message;
        
        if (media) {
            // Send with media
            const mediaObj = new MessageMedia(media.mimetype, media.data, media.filename);
            message = await clientInfo.client.sendMessage(to, mediaObj, { caption: body });
        } else {
            // Send text only
            message = await clientInfo.client.sendMessage(to, body);
        }
        
        res.json({
            success: true,
            messageId: message.id.id
        });
        
    } catch (err) {
        console.error('[WA Bridge] Send failed:', err);
        res.status(500).json({ error: err.message });
    }
});

// Disconnect client
app.post('/clients/:accountId/disconnect', async (req, res) => {
    const { accountId } = req.params;
    const clientInfo = clients.get(accountId);
    
    if (!clientInfo) {
        return res.status(404).json({ error: 'Client not found' });
    }
    
    try {
        await clientInfo.client.destroy();
        clients.delete(accountId);
        res.json({ status: 'disconnected' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ========== Scheduled Messages ==========

// Intervallo di check per messaggi programmati (30 secondi)
const SCHEDULED_CHECK_INTERVAL = 30 * 1000;

async function checkScheduledMessages() {
    try {
        const response = await axios.get(`${HUB_URL}/internal/whatsapp/scheduled/pending`);
        const scheduled = response.data;
        
        if (scheduled && scheduled.length > 0) {
            console.log(`[WA Bridge] Found ${scheduled.length} scheduled messages to send`);
            
            for (const msg of scheduled) {
                await sendScheduledMessage(msg);
            }
        }
    } catch (err) {
        // Non loggare errore se è solo 404 (endpoint non ancora attivo)
        if (err.response?.status !== 404) {
            console.error('[WA Bridge] Error checking scheduled messages:', err.message);
        }
    }
}

async function sendScheduledMessage(scheduled) {
    const { id, accountId, phoneNumber, body, mediaData, mediaType, mediaFilename } = scheduled;
    
    // Normalizza numero telefono
    const normalizedNumber = normalizePhoneNumber(phoneNumber);
    console.log(`[WA Bridge] Sending scheduled message ${id} to ${normalizedNumber}`);
    
    const clientInfo = clients.get(accountId);
    if (!clientInfo) {
        console.error(`[WA Bridge] Client not found for scheduled message: ${accountId}`);
        await markScheduledFailed(id, `Client not found: ${accountId}`);
        return;
    }
    
    // Verifica che il client sia ready
    if (clientInfo.status !== 'ready') {
        console.error(`[WA Bridge] Client ${accountId} not ready (status: ${clientInfo.status})`);
        await markScheduledFailed(id, `Client not ready: ${clientInfo.status}`);
        return;
    }
    
    try {
        let message;
        
        if (mediaData && mediaType) {
            // Invia con media
            const media = new MessageMedia(mediaType, mediaData, mediaFilename || 'file');
            message = await clientInfo.client.sendMessage(normalizedNumber, media, { caption: body });
        } else {
            // Invia solo testo
            message = await clientInfo.client.sendMessage(normalizedNumber, body);
        }
        
        console.log(`[WA Bridge] ✅ Scheduled message ${id} sent: ${message.id.id}`);
        await markScheduledSent(id, message.id.id);
        
    } catch (err) {
        console.error(`[WA Bridge] ❌ Scheduled message ${id} failed:`, err.message);
        await markScheduledFailed(id, err.message);
    }
}

async function markScheduledSent(scheduledId, messageId) {
    try {
        await axios.post(`${HUB_URL}/internal/whatsapp/scheduled/${scheduledId}/sent`, {
            messageId: messageId
        });
    } catch (err) {
        console.error('[WA Bridge] Failed to mark scheduled as sent:', err.message);
    }
}

async function markScheduledFailed(scheduledId, error) {
    try {
        await axios.post(`${HUB_URL}/internal/whatsapp/scheduled/${scheduledId}/failed`, {
            error: error
        });
    } catch (err) {
        console.error('[WA Bridge] Failed to mark scheduled as failed:', err.message);
    }
}

// Avvia polling per messaggi programmati
setInterval(checkScheduledMessages, SCHEDULED_CHECK_INTERVAL);

// Check iniziale dopo 5 secondi
setTimeout(checkScheduledMessages, 5000);

// Start server
app.listen(PORT, () => {
    console.log(`[WA Bridge] Server running on port ${PORT}`);
    console.log(`[WA Bridge] Hub URL: ${HUB_URL}`);
    console.log(`[WA Bridge] Scheduled message check interval: ${SCHEDULED_CHECK_INTERVAL/1000}s`);
});
