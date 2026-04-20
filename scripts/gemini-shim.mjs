#!/usr/bin/env node
/**
 * gemini-shim.mjs — Drop-in replacement for @google/gemini-cli
 *
 * Intercepts calls that paperclipai would make to the `gemini` CLI
 * and routes them through GeminiNativeAdapter (direct REST API).
 *
 * No npm runtime installs. No CLI dependency. Pure HTTP.
 *
 * Usage (same as gemini CLI):
 *   gemini-shim.mjs --model gemma-4-31b-it "prompt text"
 *   echo "prompt" | gemini-shim.mjs --model gemma-4-31b-it
 *   gemini-shim.mjs --sandbox "prompt text"
 */

import { createRequire } from "module";
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const require = createRequire(import.meta.url);
const GeminiNativeAdapter = require(join(__dirname, "gemini_adapter.js"));

const adapter = new GeminiNativeAdapter({
  apiKey: process.env.GEMINI_API_KEY,
  model: "gemma-4-31b-it",
});

function parseArgs(argv) {
  const args = argv.slice(2);
  let model = "gemma-4-31b-it";
  let prompt = [];
  let sandbox = false;
  let files = [];
  let i = 0;

  while (i < args.length) {
    switch (args[i]) {
      case "--model":
      case "-m":
        model = args[++i] || model;
        break;
      case "--sandbox":
      case "-s":
        sandbox = true;
        break;
      case "--file":
      case "-f":
        files.push(args[++i]);
        break;
      case "--help":
      case "-h":
        console.log("gemini-shim — Native Gemini REST adapter (replaces @google/gemini-cli)");
        console.log("Usage: gemini-shim [options] [prompt]");
        console.log("  --model, -m <model>   Model name (default: gemma-4-31b-it)");
        console.log("  --sandbox, -s         Sandbox mode (no-op, for compatibility)");
        console.log("  --file, -f <path>     Include file content in prompt");
        console.log("  --help, -h            Show this help");
        process.exit(0);
      default:
        if (!args[i].startsWith("-")) {
          prompt.push(args[i]);
        }
        break;
    }
    i++;
  }

  return { model, prompt: prompt.join(" "), sandbox, files };
}

async function readStdin() {
  return new Promise((resolve) => {
    if (process.stdin.isTTY) {
      resolve("");
      return;
    }
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => resolve(data.trim()));
    process.stdin.resume();
  });
}

async function main() {
  const { model, prompt, sandbox, files } = parseArgs(process.argv);

  let fullPrompt = prompt;

  const stdinData = await readStdin();
  if (stdinData) {
    fullPrompt = fullPrompt ? `${fullPrompt}\n\n${stdinData}` : stdinData;
  }

  for (const filePath of files) {
    try {
      const content = readFileSync(filePath, "utf8");
      fullPrompt += `\n\n--- File: ${filePath} ---\n${content}`;
    } catch (e) {
      console.error(`Warning: Could not read file ${filePath}: ${e.message}`);
    }
  }

  if (!fullPrompt) {
    console.error("Error: No prompt provided. Pass a prompt string or pipe stdin.");
    process.exit(1);
  }

  try {
    const result = await adapter.generate(fullPrompt, { model });
    process.stdout.write(result.text);
    if (!result.text.endsWith("\n")) {
      process.stdout.write("\n");
    }
  } catch (e) {
    console.error(`Gemini adapter error: ${e.message}`);
    process.exit(1);
  }
}

main();
