# Hörbuchwunsch – Server-Dienst für Ohrregal
FROM python:3.13-slim

# curl (mit HTTP/2) und openssl für Apple Push; mehr braucht der Dienst nicht
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd -g 1000 medien && useradd -u 1000 -g 1000 -M -d /data -s /usr/sbin/nologin medien \
 && install -d -o 1000 -g 1000 /data

COPY hoerbuch_wunsch.py /app/hoerbuch_wunsch.py

ENV WUNSCH_BIND=0.0.0.0 \
    WUNSCH_PORT=8097 \
    WUNSCH_DATENBANK=/data/wunsch.sqlite \
    WUNSCH_TOKENS=/data/tokens.json \
    PYTHONUNBUFFERED=1

USER 1000:1000
VOLUME /data
EXPOSE 8097
HEALTHCHECK --interval=60s --timeout=5s --start-period=20s \
  CMD curl -fsS http://127.0.0.1:8097/status || exit 1
ENTRYPOINT ["python3", "/app/hoerbuch_wunsch.py"]
CMD ["dienst"]
