FROM node:20-slim

# Install gosu for privilege dropping in entrypoint
RUN apt-get update && apt-get install -y --no-install-recommends gosu ca-certificates && rm -rf /var/lib/apt/lists/*

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Create a non-root user (required: Claude CLI refuses --dangerously-skip-permissions as root)
RUN groupadd -r paperclip && useradd -r -g paperclip -m -d /home/paperclip -s /bin/bash paperclip

# Create the paperclip home directory (Railway volume mount point)
RUN mkdir -p /paperclip && chown -R paperclip:paperclip /paperclip

WORKDIR /app

# Copy package files and install dependencies
COPY package.json ./
RUN npm install --omit=dev

RUN ln -sf /app/node_modules/.bin/gemini /usr/local/bin/gemini

# Copy application code
COPY . .

# Make Gemini native shim executable and create symlink as 'gemini'
RUN chmod +x scripts/gemini-shim.mjs && \
    ln -sf /app/scripts/gemini-shim.mjs /app/scripts/gemini && \
    chown -R paperclip:paperclip /app /home/paperclip

# Copy and set up entrypoint (fixes volume mount ownership at runtime)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Railway injects PORT at runtime (default 3100)
ENV PORT=3100
EXPOSE 3100

# Entrypoint runs as root to fix volume permissions, then drops to paperclip user
ENTRYPOINT ["/entrypoint.sh"]
CMD ["npm", "start"]
