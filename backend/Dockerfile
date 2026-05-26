FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    nodejs \
    npm \
    chromium \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnss3 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy WhatsApp bridge and install Node dependencies
COPY perx_wa_bridge ./perx_wa_bridge
RUN cd perx_wa_bridge && npm install --omit=dev

# Copy application code
COPY backend/app ./app
COPY backend/migrations ./migrations
COPY backend/scripts/start-render.sh ./scripts/start-render.sh
RUN chmod +x ./scripts/start-render.sh

# Environment variables
ENV PORT=8080
ENV PYTHONUNBUFFERED=1
ENV PERX_WA_BRIDGE_URL=http://127.0.0.1:5002
ENV WA_BRIDGE_PORT=5002
ENV CHROME_EXECUTABLE_PATH=/usr/bin/chromium
ENV SESSION_PATH=/var/data/openwa-sessions

# Run the application
CMD ["./scripts/start-render.sh"]
