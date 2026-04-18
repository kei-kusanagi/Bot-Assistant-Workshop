# syntax=docker/dockerfile:1
# Compila el ejecutable Dart. En runtime debes montar la librería Neonize (.so) y NEONIZE_PATH.
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/whatsapp_qr_pairing.dart -o /app/whatsapp_qr_pairing

FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/whatsapp_qr_pairing /usr/local/bin/whatsapp_qr_pairing
RUN mkdir -p /app/data
WORKDIR /app
ENV NEONIZE_PATH=/neonize/libneonize.so
ENTRYPOINT ["/usr/local/bin/whatsapp_qr_pairing"]
