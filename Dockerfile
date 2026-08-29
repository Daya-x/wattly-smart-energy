FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

COPY ai_training/requirements.txt /app/ai_training/requirements.txt
RUN pip install --no-cache-dir -r /app/ai_training/requirements.txt

COPY ai_training/src /app/ai_training/src
COPY ai_training/models /app/ai_training/models
COPY ai_training/reports /app/ai_training/reports
COPY ai_training/tariffs /app/ai_training/tariffs
COPY ai_training/datasets/forecasting /app/ai_training/datasets/forecasting
COPY ai_training/datasets/anomalies /app/ai_training/datasets/anomalies
COPY ai_training/datasets/safety /app/ai_training/datasets/safety
COPY ai_training/datasets/appliance_window_features.csv /app/ai_training/datasets/appliance_window_features.csv

CMD ["sh", "-c", "python -m uvicorn api:app --app-dir ai_training/src --host 0.0.0.0 --port ${PORT}"]
