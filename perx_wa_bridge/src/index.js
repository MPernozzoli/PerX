/**
 * PerX WhatsApp Bridge
 * Bridge WhatsApp basato su OpenWA, compatibile con Render.
 */

require('dotenv').config();

const fs = require('fs');
const path = require('path');
const express = require('express');
const axios = require('axios');
const qrcode = require('qrcode-terminal');
const { create, ev, STATE } = require('@open-wa/wa-automate');

const HUB_URL = process.env.HUB_URL || 'http://localhost:8080';
const PORT = Number(process.env.PORT || 5002);
const SESSION_PATH = process.env.SESSION_PATH || path.join(process.cwd(), 'sessions');
const CHROME_EXECUTABLE_PATH = process.env.CHROME_EXECUTABLE_PATH || process.env.PUPPETEER_EXECUTABLE_PATH || null;
const SCHEDULED_CHECK_INTERVAL = Number(process.env.SCHEDULED_CHECK_INTERVAL_MS || 30 * 1000);
const INTERNAL_TOKEN = process.env.WA_BRIDGE_INTERNAL_TOKEN || null;

fs.mkdirSync(SESSION_PATH, { recursive: true });

const app = express();
app.use(express.json({ limit: '50mb' }));

const clients = new Map();
const qrListeners = new Map();
const retryState = new Map();
const MAX_RETRIES = Number(process.env.WA_MAX_RETRIES || 5);
const BASE_RETRY_DELAY = Number(process.env.WA_BASE_RETRY_DELAY_MS || 5000);

function sanitizeClientId(accountId) {
    return accountId.replace(/[^a-zA-Z0-9_-]/g, '_');
}

function normalizePhoneNumber(number) {
    if (!number) return number;

    if (number.includes('@g.us')) return number;

    let cleaned = number.replace('@c.us', '');
    cleaned = cleaned.replace(/[^\d+]/g, '');
    cleaned = cleaned.replace(/^\+/, '');

    return `${cleaned}@c.us`;
}

function setClientStatus(accountId, status, patch = {}) {
    const clientInfo = clients.get(accountId);
    if (clientInfo) {
        Object.assign(clientInfo, { status }, patch);
    }
}

async function notifyHub(pathname, payload) {
    try {
        await axios.post(`${HUB_URL}${pathname}`, payload, {
            timeout: 15000,
            headers: internalHeaders()
        });
    } catch (err) {
        console.error(`[WA Bridge] Failed to notify Hub ${pathname}:`, err.message);
    }
}

function internalHeaders() {
    return INTERNAL_TOKEN ? { 'X-PerX-WA-Bridge-Token': INTERNAL_TOKEN } : {};
}

function registerQrListener(accountId, safeClientId) {
    if (qrListeners.has(accountId)) return;

    const eventName = `qr.${safeClientId}`;
    const listener = (qr) => {
        console.log(`[WA Bridge] QR Code for ${accountId}:`);
        qrcode.generate(qr, { small: true });
        setClientStatus(accountId, 'waitingQR');
        notifyHub(`/internal/whatsapp/${accountId}/qr`, { qr });
    };

    ev.on(eventName, listener);
    qrListeners.set(accountId, { eventName, listener });
}

function unregisterQrListener(accountId) {
    const listenerInfo = qrListeners.get(accountId);
    if (!listenerInfo) return;

    ev.off(listenerInfo.eventName, listenerInfo.listener);
    qrListeners.delete(accountId);
}

function buildOpenWaConfig(accountId, safeClientId) {
    const chromiumArgs = [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--disable-extensions',
        '--disable-background-networking',
        '--disable-sync',
        '--disable-default-apps',
        '--disable-blink-features=AutomationControlled',
        '--window-size=1920,1080'
    ];

    const config = {
        sessionId: safeClientId,
        sessionDataPath: SESSION_PATH,
        multiDevice: true,
        headless: true,
        qrTimeout: 0,
        authTimeout: 0,
        cacheEnabled: false,
        blockCrashLogs: true,
        disableSpins: true,
        logConsole: false,
        popup: false,
        qrLogSkip: true,
        useStealth: true,
        inDocker: process.env.RENDER === 'true' || process.env.NODE_ENV === 'production',
        chromiumArgs,
        restartOnCrash: () => {
            console.error(`[WA Bridge] OpenWA page crashed for ${accountId}; restarting client`);
            restartClient(accountId).catch((err) => {
                console.error(`[WA Bridge] Restart after crash failed for ${accountId}:`, err.message);
            });
        }
    };

    if (CHROME_EXECUTABLE_PATH) {
        config.executablePath = CHROME_EXECUTABLE_PATH;
    } else {
        config.useChrome = true;
    }

    return config;
}

async function initClient(accountId, phoneNumber) {
    console.log(`[WA Bridge] Initializing OpenWA client for ${accountId}`);

    const safeClientId = sanitizeClientId(accountId);
    retryState.set(accountId, { count: 0, lastAttempt: null });
    clients.set(accountId, {
        client: null,
        phoneNumber,
        safeClientId,
        status: 'initializing',
        error: null
    });

    registerQrListener(accountId, safeClientId);

    try {
        const client = await create(buildOpenWaConfig(accountId, safeClientId));
        clients.set(accountId, {
            client,
            phoneNumber,
            safeClientId,
            status: 'ready',
            error: null
        });

        unregisterQrListener(accountId);
        retryState.set(accountId, { count: 0, lastAttempt: null });
        await attachClientHandlers(accountId, client);
        await notifyHub(`/internal/whatsapp/${accountId}/status`, { status: 'ready' });
        console.log(`[WA Bridge] Client ${accountId} ready`);
        return client;
    } catch (err) {
        console.error(`[WA Bridge] Failed to initialize client ${accountId}:`, err);
        setClientStatus(accountId, 'error', { error: err.message });
        await notifyHub(`/internal/whatsapp/${accountId}/status`, {
            status: 'error',
            reason: err.message
        });
        throw err;
    }
}

async function attachClientHandlers(accountId, client) {
    await client.onAnyMessage(async (msg) => {
        try {
            const isOutgoing = msg.fromMe || msg.self === 'out';
            await handleMessage(accountId, client, msg, isOutgoing);
        } catch (err) {
            console.error(`[WA Bridge] Error handling message for ${accountId}:`, err);
        }
    });

    await client.onAck(async (msg) => {
        const ack = typeof msg.ack === 'number' ? msg.ack : 0;
        const ackNames = { '-1': 'error', 0: 'pending', 1: 'sent', 2: 'delivered', 3: 'read', 4: 'played' };
        const ackName = ackNames[ack] || `unknown(${ack})`;

        try {
            await axios.post(`${HUB_URL}/internal/whatsapp/message-ack`, {
                accountId,
                messageId: getMessageId(msg),
                ack,
                ackName,
                timestamp: Date.now() / 1000
            }, { timeout: 10000, headers: internalHeaders() });
        } catch (_) {
            // Gli ACK sono frequenti; non rendiamo rumorosi i log se l'Hub non risponde.
        }
    });

    await client.onStateChanged(async (state) => {
        console.log(`[WA Bridge] State ${accountId}: ${state}`);

        if (state === STATE.CONNECTED) {
            setClientStatus(accountId, 'ready', { error: null });
            retryState.set(accountId, { count: 0, lastAttempt: null });
            await notifyHub(`/internal/whatsapp/${accountId}/status`, { status: 'ready' });
            return;
        }

        if ([STATE.UNPAIRED, STATE.UNPAIRED_IDLE].includes(state)) {
            setClientStatus(accountId, 'waitingQR');
            await notifyHub(`/internal/whatsapp/${accountId}/status`, { status: 'waitingQR', reason: state });
            return;
        }

        if ([STATE.DISCONNECTED, STATE.CONFLICT, STATE.UNLAUNCHED, STATE.TIMEOUT].includes(state)) {
            setClientStatus(accountId, 'disconnected');
            await notifyHub(`/internal/whatsapp/${accountId}/status`, { status: 'disconnected', reason: state });
            scheduleReconnect(accountId, state);
        }
    });
}

function getMessageId(msg) {
    if (!msg) return null;
    if (typeof msg.id === 'string') return msg.id;
    if (msg.id?._serialized) return msg.id._serialized;
    if (msg.id?.id) return msg.id.id;
    if (msg.mId) return msg.mId;
    return String(msg.id || '');
}

function getMessageBody(msg) {
    return msg.body || msg.caption || msg.text || msg.content || '';
}

async function handleMessage(accountId, client, msg, isOutgoing = false) {
    const body = getMessageBody(msg);
    const bodyPreview = body ? body.substring(0, 50) : '[media/no text]';
    const direction = isOutgoing ? 'OUT' : 'IN';
    console.log(`[WA Bridge] ${direction} | ${msg.from} -> ${msg.to}: ${bodyPreview}...`);

    const messageData = {
        accountId,
        messageId: getMessageId(msg),
        from: msg.from,
        to: msg.to,
        body,
        timestamp: msg.timestamp || msg.t,
        type: msg.type,
        hasMedia: Boolean(msg.isMedia || msg.isMMS || msg.mimetype),
        isGroup: Boolean(msg.isGroupMsg || String(msg.from || '').endsWith('@g.us')),
        author: msg.author || null,
        isOutgoing
    };

    if (messageData.hasMedia) {
        try {
            const dataUrl = await client.decryptMedia(msg);
            const media = parseDataUrl(dataUrl, msg);
            if (media) {
                messageData.media = media;
                console.log(`[WA Bridge] Media downloaded: ${media.mimetype}, ${Math.round(media.data.length * 0.75 / 1024)}KB`);
            }
        } catch (err) {
            console.error('[WA Bridge] Failed to download media:', err.message);
        }
    }

    try {
        await axios.post(`${HUB_URL}/internal/whatsapp/message`, messageData, {
            timeout: 30000,
            headers: internalHeaders()
        });
        console.log('[WA Bridge] Message sent to Hub');
    } catch (err) {
        console.error('[WA Bridge] Failed to send message to Hub:', err.message);
        if (err.response) {
            console.error('[WA Bridge] Hub response:', err.response.status, err.response.data);
        }
    }
}

function parseDataUrl(dataUrl, msg) {
    if (!dataUrl || typeof dataUrl !== 'string') return null;

    const match = dataUrl.match(/^data:([^;]+);base64,(.*)$/);
    if (!match) {
        return {
            mimetype: msg.mimetype || 'application/octet-stream',
            data: dataUrl,
            filename: msg.filename || defaultFilename(msg.mimetype)
        };
    }

    return {
        mimetype: match[1],
        data: match[2],
        filename: msg.filename || defaultFilename(match[1])
    };
}

function defaultFilename(mimetype = 'application/octet-stream') {
    const extension = mimetype.split('/')[1] || 'bin';
    return `attachment.${extension.split(';')[0]}`;
}

async function restartClient(accountId) {
    const clientInfo = clients.get(accountId);
    if (!clientInfo) return;

    try {
        if (clientInfo.client) {
            await clientInfo.client.kill('restart');
        }
    } catch (err) {
        console.error(`[WA Bridge] Kill before restart failed for ${accountId}:`, err.message);
    }

    await initClient(accountId, clientInfo.phoneNumber);
}

function scheduleReconnect(accountId, reason) {
    const state = retryState.get(accountId) || { count: 0, lastAttempt: null };

    if (state.count >= MAX_RETRIES) {
        console.error(`[WA Bridge] Max retries reached for ${accountId}`);
        notifyHub(`/internal/whatsapp/${accountId}/status`, {
            status: 'max_retries',
            reason: `Maximum reconnection attempts reached after ${reason}`
        });
        return;
    }

    const delay = BASE_RETRY_DELAY * Math.pow(2, state.count);
    retryState.set(accountId, { count: state.count + 1, lastAttempt: Date.now() });
    console.log(`[WA Bridge] Reconnecting ${accountId} in ${delay / 1000}s (${state.count + 1}/${MAX_RETRIES})`);

    setTimeout(() => {
        restartClient(accountId).catch((err) => {
            console.error(`[WA Bridge] Reconnect failed for ${accountId}:`, err.message);
        });
    }, delay);
}

app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        engine: 'openwa',
        hubUrl: HUB_URL,
        sessionPath: SESSION_PATH,
        clients: Array.from(clients.entries()).map(([id, c]) => ({
            accountId: id,
            status: c.status,
            error: c.error || null
        }))
    });
});

app.post('/clients/:accountId/init', (req, res) => {
    const { accountId } = req.params;
    const { phoneNumber } = req.body || {};

    if (clients.has(accountId)) {
        const clientInfo = clients.get(accountId);
        return res.json({
            status: clientInfo.status,
            phoneNumber: clientInfo.phoneNumber,
            message: 'Client already initialized'
        });
    }

    initClient(accountId, phoneNumber).catch(() => {
        // Lo stato di errore viene esposto da /status e notificato all'Hub.
    });

    res.json({ status: 'initializing' });
});

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

app.post('/clients/:accountId/check-number', async (req, res) => {
    const { accountId } = req.params;
    const { phoneNumber } = req.body || {};
    const clientInfo = clients.get(accountId);

    if (!clientInfo) return res.status(404).json({ error: 'Client not found' });
    if (clientInfo.status !== 'ready' || !clientInfo.client) return res.status(400).json({ error: 'Client not ready' });
    if (!phoneNumber) return res.status(400).json({ error: 'Phone number is required' });

    try {
        const normalized = normalizePhoneNumber(phoneNumber);
        const numberStatus = await clientInfo.client.checkNumberStatus(normalized);
        let profilePicUrl = null;

        if (numberStatus?.numberExists || numberStatus?.canReceiveMessage) {
            try {
                profilePicUrl = await clientInfo.client.getProfilePicFromServer(normalized);
            } catch (_) {
                profilePicUrl = null;
            }
        }

        res.json({
            isRegistered: Boolean(numberStatus?.numberExists || numberStatus?.canReceiveMessage),
            numberId: numberStatus?.id?._serialized || numberStatus?.id?.user || normalized,
            profilePicUrl
        });
    } catch (err) {
        console.error('[WA Bridge] Check number failed:', err);
        res.status(500).json({ error: err.message });
    }
});

app.get('/clients/:accountId/profile-pic/:contactId', async (req, res) => {
    const { accountId, contactId } = req.params;
    const clientInfo = clients.get(accountId);

    if (!clientInfo) return res.status(404).json({ error: 'Client not found' });
    if (clientInfo.status !== 'ready' || !clientInfo.client) return res.status(400).json({ error: 'Client not ready' });

    try {
        const chatId = contactId.includes('@') ? contactId : normalizePhoneNumber(contactId);
        const profilePicUrl = await clientInfo.client.getProfilePicFromServer(chatId);
        res.json({ contactId: chatId, profilePicUrl: profilePicUrl || null });
    } catch (_) {
        res.json({ contactId, profilePicUrl: null, error: 'Profile picture not available' });
    }
});

app.post('/clients/:accountId/send', async (req, res) => {
    const { accountId } = req.params;
    const { to, body, media } = req.body || {};
    const clientInfo = clients.get(accountId);

    if (!clientInfo) return res.status(404).json({ error: 'Client not found' });
    if (clientInfo.status !== 'ready' || !clientInfo.client) return res.status(400).json({ error: 'Client not ready' });

    try {
        const chatId = normalizePhoneNumber(to);
        let messageId;

        if (media) {
            const file = media.data?.startsWith('data:')
                ? media.data
                : `data:${media.mimetype || 'application/octet-stream'};base64,${media.data}`;
            messageId = await clientInfo.client.sendFile(
                chatId,
                file,
                media.filename || defaultFilename(media.mimetype),
                body || '',
                undefined,
                true
            );
        } else {
            messageId = await clientInfo.client.sendText(chatId, body || '');
        }

        res.json({ success: true, messageId: String(messageId) });
    } catch (err) {
        console.error('[WA Bridge] Send failed:', err);
        res.status(500).json({ error: err.message });
    }
});

app.post('/clients/:accountId/disconnect', async (req, res) => {
    const { accountId } = req.params;
    const clientInfo = clients.get(accountId);

    if (!clientInfo) return res.status(404).json({ error: 'Client not found' });

    try {
        unregisterQrListener(accountId);
        if (clientInfo.client) await clientInfo.client.kill('manual disconnect');
        clients.delete(accountId);
        retryState.delete(accountId);
        res.json({ status: 'disconnected' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

async function checkScheduledMessages() {
    try {
        const response = await axios.get(`${HUB_URL}/internal/whatsapp/scheduled/pending`, {
            timeout: 15000,
            headers: internalHeaders()
        });
        const scheduled = response.data;

        if (scheduled && scheduled.length > 0) {
            console.log(`[WA Bridge] Found ${scheduled.length} scheduled messages to send`);
            for (const msg of scheduled) {
                await sendScheduledMessage(msg);
            }
        }
    } catch (err) {
        if (err.response?.status !== 404) {
            console.error('[WA Bridge] Error checking scheduled messages:', err.message);
        }
    }
}

async function sendScheduledMessage(scheduled) {
    const { id, accountId, phoneNumber, body, mediaData, mediaType, mediaFilename } = scheduled;
    const normalizedNumber = normalizePhoneNumber(phoneNumber);
    const clientInfo = clients.get(accountId);

    if (!clientInfo) {
        await markScheduledFailed(id, `Client not found: ${accountId}`);
        return;
    }

    if (clientInfo.status !== 'ready' || !clientInfo.client) {
        await markScheduledFailed(id, `Client not ready: ${clientInfo.status}`);
        return;
    }

    try {
        let messageId;

        if (mediaData && mediaType) {
            messageId = await clientInfo.client.sendFile(
                normalizedNumber,
                `data:${mediaType};base64,${mediaData}`,
                mediaFilename || defaultFilename(mediaType),
                body || '',
                undefined,
                true
            );
        } else {
            messageId = await clientInfo.client.sendText(normalizedNumber, body || '');
        }

        console.log(`[WA Bridge] Scheduled message ${id} sent: ${messageId}`);
        await markScheduledSent(id, String(messageId));
    } catch (err) {
        console.error(`[WA Bridge] Scheduled message ${id} failed:`, err.message);
        await markScheduledFailed(id, err.message);
    }
}

async function markScheduledSent(scheduledId, messageId) {
    await notifyHub(`/internal/whatsapp/scheduled/${scheduledId}/sent`, { messageId });
}

async function markScheduledFailed(scheduledId, error) {
    await notifyHub(`/internal/whatsapp/scheduled/${scheduledId}/failed`, { error });
}

setInterval(checkScheduledMessages, SCHEDULED_CHECK_INTERVAL);
setTimeout(checkScheduledMessages, 5000);

async function shutdown(signal) {
    console.log(`[WA Bridge] ${signal} received, shutting down`);

    for (const [accountId, clientInfo] of clients.entries()) {
        unregisterQrListener(accountId);
        if (clientInfo.client) {
            try {
                await clientInfo.client.kill(signal);
            } catch (err) {
                console.error(`[WA Bridge] Failed to stop ${accountId}:`, err.message);
            }
        }
    }

    process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

app.listen(PORT, '0.0.0.0', () => {
    console.log(`[WA Bridge] Server running on port ${PORT}`);
    console.log(`[WA Bridge] Engine: OpenWA`);
    console.log(`[WA Bridge] Hub URL: ${HUB_URL}`);
    console.log(`[WA Bridge] Session path: ${SESSION_PATH}`);
    console.log(`[WA Bridge] Chrome executable: ${CHROME_EXECUTABLE_PATH || 'auto'}`);
    console.log(`[WA Bridge] Scheduled message check interval: ${SCHEDULED_CHECK_INTERVAL / 1000}s`);
});
