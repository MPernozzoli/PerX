/**
 * PerX WhatsApp Bridge
 * Bridge per gestione WhatsApp tramite whatsapp-web.js
 * Comunica con l'Hub Swift via HTTP
 */

const express = require('express');
const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode');
const axios = require('axios');
const fs = require('fs');
const path = require('path');

const VERSION = '1.0.0';
const START_TIME = Date.now();

// Configuration
const config = {
    port: process.env.PORT || 5002,
    hubUrl: process.env.HUB_URL || 'http://localhost:8080',
    dataDir: process.env.DATA_DIR || './wa_data',
    pollInterval: parseInt(process.env.POLL_INTERVAL) || 30000
};

// Express app
const app = express();
app.use(express.json());

// State
let clients = {};
let qrCodes = {};
let lastError = null;

// Health endpoint
app.get('/health', (req, res) => {
    const uptime = (Date.now() - START_TIME) / 1000;
    const connectedAccounts = Object.keys(clients).filter(k => clients[k]?.info).length;
    
    res.json({
        status: 'ok',
        version: VERSION,
        uptime: uptime,
        connected_accounts: connectedAccounts,
        hub_url: config.hubUrl,
        last_error: lastError
    });
});

// Get QR code for account
app.get('/qr/:accountId', async (req, res) => {
    const { accountId } = req.params;
    
    if (qrCodes[accountId]) {
        const qrImage = await qrcode.toDataURL(qrCodes[accountId]);
        res.json({ qr: qrImage });
    } else if (clients[accountId]?.info) {
        res.json({ status: 'connected', phone: clients[accountId].info.wid.user });
    } else {
        res.status(404).json({ error: 'No QR code available' });
    }
});

// Initialize client for account
app.post('/init/:accountId', async (req, res) => {
    const { accountId } = req.params;
    
    try {
        if (clients[accountId]) {
            return res.json({ status: 'already_initialized' });
        }
        
        await initClient(accountId);
        res.json({ status: 'initializing' });
    } catch (error) {
        lastError = error.message;
        res.status(500).json({ error: error.message });
    }
});

// Send message
app.post('/send', async (req, res) => {
    const { accountId, to, message } = req.body;
    
    if (!clients[accountId]?.info) {
        return res.status(400).json({ error: 'Account not connected' });
    }
    
    try {
        const chatId = to.includes('@') ? to : `${to}@c.us`;
        const result = await clients[accountId].sendMessage(chatId, message);
        
        res.json({
            success: true,
            messageId: result.id.id,
            timestamp: result.timestamp
        });
    } catch (error) {
        lastError = error.message;
        res.status(500).json({ error: error.message });
    }
});

// Get status for account
app.get('/status/:accountId', (req, res) => {
    const { accountId } = req.params;
    const client = clients[accountId];
    
    if (!client) {
        res.json({ status: 'not_initialized' });
    } else if (client.info) {
        res.json({
            status: 'connected',
            phone: client.info.wid.user,
            name: client.info.pushname
        });
    } else if (qrCodes[accountId]) {
        res.json({ status: 'waiting_qr' });
    } else {
        res.json({ status: 'connecting' });
    }
});

// Disconnect account
app.post('/disconnect/:accountId', async (req, res) => {
    const { accountId } = req.params;
    
    if (clients[accountId]) {
        await clients[accountId].destroy();
        delete clients[accountId];
        delete qrCodes[accountId];
    }
    
    res.json({ status: 'disconnected' });
});

// Restart endpoint
app.post('/restart', (req, res) => {
    res.json({ status: 'restarting' });
    setTimeout(() => process.exit(0), 1000);
});

// Initialize WhatsApp client
async function initClient(accountId) {
    const authPath = path.join(config.dataDir, accountId);
    fs.mkdirSync(authPath, { recursive: true });
    
    const client = new Client({
        authStrategy: new LocalAuth({ dataPath: authPath }),
        puppeteer: {
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        }
    });
    
    client.on('qr', (qr) => {
        console.log(`[WA-${accountId}] QR received`);
        qrCodes[accountId] = qr;
        
        // Notify Hub
        notifyHub('qr_received', { accountId, qr });
    });
    
    client.on('ready', () => {
        console.log(`[WA-${accountId}] Connected: ${client.info.wid.user}`);
        delete qrCodes[accountId];
        
        // Notify Hub
        notifyHub('connected', {
            accountId,
            phone: client.info.wid.user,
            name: client.info.pushname
        });
    });
    
    client.on('message', async (msg) => {
        // Forward message to Hub
        try {
            await sendMessageToHub(accountId, msg);
        } catch (error) {
            console.error(`[WA-${accountId}] Failed to forward message:`, error);
            lastError = error.message;
        }
    });
    
    client.on('disconnected', (reason) => {
        console.log(`[WA-${accountId}] Disconnected: ${reason}`);
        delete clients[accountId];
        
        // Notify Hub
        notifyHub('disconnected', { accountId, reason });
    });
    
    client.on('auth_failure', (error) => {
        console.error(`[WA-${accountId}] Auth failed:`, error);
        lastError = `Auth failed for ${accountId}`;
        delete clients[accountId];
    });
    
    clients[accountId] = client;
    await client.initialize();
}

// Send message to Hub
async function sendMessageToHub(accountId, msg) {
    const messageData = {
        account_id: accountId,
        message_id: msg.id.id,
        from: msg.from,
        to: msg.to,
        body: msg.body,
        timestamp: msg.timestamp,
        has_media: msg.hasMedia,
        type: msg.type
    };
    
    try {
        await axios.post(`${config.hubUrl}/internal/whatsapp/received`, messageData, {
            timeout: 10000
        });
    } catch (error) {
        throw error;
    }
}

// Notify Hub of events
async function notifyHub(event, data) {
    try {
        await axios.post(`${config.hubUrl}/internal/whatsapp/event`, {
            event,
            ...data
        }, { timeout: 5000 });
    } catch (error) {
        console.error(`[WA] Failed to notify Hub:`, error.message);
    }
}

// Start server
app.listen(config.port, () => {
    console.log(`WhatsApp Bridge running on port ${config.port}`);
    console.log(`Hub URL: ${config.hubUrl}`);
});
