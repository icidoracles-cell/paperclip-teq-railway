FROM node:20-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gosu ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @google/gemini-cli

RUN groupadd -r paperclip && useradd -r -g paperclip -m -d /home/paperclip -s /bin/bash paperclip
RUN mkdir -p /paperclip && chown -R paperclip:paperclip /paperclip

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY . .
RUN chown -R paperclip:paperclip /app /home/paperclip

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN gemini --version || echo "WARNING: gemini not found on PATH"

ENV PORT=3100
EXPOSE 3100
ENTRYPOINT ["/entrypoint.sh"]
CMD ["npm", "start"]
