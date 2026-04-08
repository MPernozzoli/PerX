FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app ./app
COPY migrations ./migrations

# Environment variables
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Run the application
CMD ["sh", "-c", "alembic -c migrations/alembic.ini upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8080"]
