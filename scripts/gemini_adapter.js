/**
 * Starcaller Native Gemini Adapter for Paperclip
 * Calls Google Gemini REST API directly — no CLI, no npm runtime installs.
 *
 * Drop into Paperclip's adapter system or use standalone.
 * Replaces @google/gemini-cli for stable production use.
 */

const https = require("https");
const http = require("http");

const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com";

class GeminiNativeAdapter {
  constructor(config = {}) {
    this.apiKey = config.apiKey || process.env.GEMINI_API_KEY || "";
    this.model = config.model || "gemma-4-31b-it";
    this.baseUrl = config.baseUrl || GEMINI_BASE_URL;
    this.maxTokens = config.maxTokens || 8192;
    this.temperature = config.temperature || 0.7;
    this.timeout = config.timeout || 120000;
  }

  async generate(prompt, options = {}) {
    const model = options.model || this.model;
    const url = `${this.baseUrl}/v1beta/models/${model}:generateContent?key=${this.apiKey}`;

    const body = JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [{ text: prompt }],
        },
      ],
      generationConfig: {
        temperature: options.temperature ?? this.temperature,
        maxOutputTokens: options.maxTokens ?? this.maxTokens,
        topP: 0.95,
        topK: 40,
      },
    });

    return this._request(url, body, options.systemInstruction);
  }

  async chat(messages, options = {}) {
    const model = options.model || this.model;
    const url = `${this.baseUrl}/v1beta/models/${model}:generateContent?key=${this.apiKey}`;

    const contents = messages
      .filter((m) => m.role !== "system")
      .map((m) => ({
        role: m.role === "assistant" ? "model" : "user",
        parts: [{ text: m.content }],
      }));

    const systemInstruction =
      messages.find((m) => m.role === "system")?.content || null;

    const body = JSON.stringify({
      contents,
      generationConfig: {
        temperature: options.temperature ?? this.temperature,
        maxOutputTokens: options.maxTokens ?? this.maxTokens,
        topP: 0.95,
        topK: 40,
      },
      ...(systemInstruction
        ? {
            systemInstruction: {
              parts: [{ text: systemInstruction }],
            },
          }
        : {}),
    });

    return this._request(url, body);
  }

  async _request(url, body, systemInstruction) {
    return new Promise((resolve, reject) => {
      const urlObj = new URL(url);
      const isHttps = urlObj.protocol === "https:";
      const lib = isHttps ? https : http;

      const req = lib.request(
        {
          hostname: urlObj.hostname,
          port: urlObj.port || (isHttps ? 443 : 80),
          path: urlObj.pathname + urlObj.search,
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(body),
          },
          timeout: this.timeout,
        },
        (res) => {
          let data = "";
          res.on("data", (chunk) => (data += chunk));
          res.on("end", () => {
            try {
              const parsed = JSON.parse(data);

              if (res.statusCode !== 200) {
                const errMsg =
                  parsed.error?.message || `HTTP ${res.statusCode}`;
                reject(new Error(`Gemini API error: ${errMsg}`));
                return;
              }

              const text =
                parsed.candidates?.[0]?.content?.parts?.[0]?.text || "";
              const finishReason =
                parsed.candidates?.[0]?.finishReason || "unknown";
              const usage = {
                promptTokens: parsed.usageMetadata?.promptTokenCount || 0,
                completionTokens:
                  parsed.usageMetadata?.candidatesTokenCount || 0,
                totalTokens: parsed.usageMetadata?.totalTokenCount || 0,
              };

              resolve({
                text,
                finishReason,
                usage,
                model: parsed.modelVersion || this.model,
                raw: parsed,
              });
            } catch (e) {
              reject(new Error(`Failed to parse Gemini response: ${e.message}`));
            }
          });
        }
      );

      req.on("error", (e) => reject(new Error(`Gemini request failed: ${e.message}`)));
      req.on("timeout", () => {
        req.destroy();
        reject(new Error(`Gemini request timed out after ${this.timeout}ms`));
      });

      req.write(body);
      req.end();
    });
  }

  async healthCheck() {
    try {
      const result = await this.generate("ping", { maxTokens: 10 });
      return { healthy: true, model: this.model };
    } catch (e) {
      return { healthy: false, error: e.message, model: this.model };
    }
  }
}

module.exports = GeminiNativeAdapter;
