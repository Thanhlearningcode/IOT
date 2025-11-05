FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt ./requirements.txt
COPY .wheelhouse /tmp/wheelhouse
RUN pip install --no-cache-dir --no-index --find-links=/tmp/wheelhouse -r requirements.txt
COPY . /app
ENV PYTHONPATH=/app
