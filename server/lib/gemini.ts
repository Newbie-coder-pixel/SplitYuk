export interface ParsedReceiptItem {
  name: string;
  price: number;
}

export interface GeminiParseResult {
  isReceipt: boolean;
  reason?: string;
  items: ParsedReceiptItem[];
  detectedTotal?: number;
}

interface GeminiOutcome {
  ok: boolean;
  data?: GeminiParseResult;
  error?: string;
}

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta";
const GEMINI_ENDPOINT = `${GEMINI_BASE}/interactions`;
const MODELS_ENDPOINT = `${GEMINI_BASE}/models`;

/**
 * Last-resort model id, used only when the API's own model listing can't
 * be reached and GEMINI_MODEL isn't set. Everything else about model
 * choice is resolved at runtime — see resolveModels().
 */
const FALLBACK_MODEL = "gemini-3.8-flash";

/** Per-attempt ceiling. Without one, a stalled call hangs the function. */
const REQUEST_TIMEOUT_MS = 25_000;

/** Attempts per model before moving on to the next candidate. */
const ATTEMPTS_PER_MODEL = 2;

const RETRYABLE_STATUSES = new Set([408, 429, 500, 502, 503, 504]);

const RECEIPT_SCHEMA = {
  type: "object",
  properties: {
    isReceipt: { type: "boolean" },
    reason: { type: "string" },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          price: { type: "integer" },
        },
        required: ["name", "price"],
      },
    },
    detectedTotal: { type: "integer" },
  },
  required: ["isReceipt", "items"],
};

const PROMPT =
  "You are reading a photo that may or may not be a physical retail or " +
  "restaurant receipt (most likely Indonesian, prices in Rupiah which has " +
  "no decimal subunits). First decide whether this photo genuinely shows a " +
  "receipt/bill/invoice at all. If it does NOT (e.g. a random photo, a " +
  "person, a landscape, an unrelated screenshot), set isReceipt to false " +
  "and give a short, human-readable reason why. If it DOES show a receipt, " +
  "set isReceipt to true and extract EVERY purchased line item — do not " +
  "stop early, do not summarise, do not merge two products into one line, " +
  "and do not skip a line just because its description is truncated or " +
  "hard to read. For each item give its exact printed name and its final " +
  "line price as a plain integer number of Rupiah — no currency symbol, no " +
  "thousands separators, no decimals. When a line shows a quantity and a " +
  "unit price, the price you return is the line total (quantity times unit " +
  "price), not the unit price. Never include barcodes, product/goods " +
  "codes, loyalty or member numbers, cashier/POS/serial metadata, " +
  "subtotal/tax/service/discount lines, payment method lines (e.g. a bank " +
  "name), or change/kembali lines as items. If a printed grand total is " +
  "visible, extract it as detectedTotal as a plain integer. Respond with " +
  "only the structured JSON, nothing else.";

/**
 * Sends the receipt photo itself (not pre-extracted OCR text) to Gemini so
 * it reads the image directly — this intentionally replaces on-device OCR
 * for accuracy, per an explicit product decision: the receipt photo now
 * leaves the device at scan time, not just at notification-send time.
 * Nothing here is logged or stored — same stateless-relay contract as
 * /api/notify.
 *
 * Verified against the live API on 2026-09-04. Three real failure modes
 * showed up in the first three calls and are all handled here: the model
 * answering HTTP 500 "experiencing high demand" (retried), the request
 * stalling with no response at all (timed out and retried), and a
 * perfectly successful 200 whose payload shape the old single-field
 * extractor didn't recognise (see extractResult).
 */
export async function parseReceiptWithGemini(
  imageBytes: ArrayBuffer,
  mimeType: string,
): Promise<GeminiOutcome> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return { ok: false, error: "GEMINI_API_KEY is not configured on the relay." };
  }

  const base64 = Buffer.from(imageBytes).toString("base64");
  const models = await resolveModels(apiKey);

  let lastError = "Gemini could not be reached.";

  for (const model of models) {
    for (let attempt = 0; attempt < ATTEMPTS_PER_MODEL; attempt++) {
      const outcome = await callOnce(apiKey, model, base64, mimeType);
      if (outcome.ok) return outcome;

      lastError = outcome.error ?? lastError;
      if (!outcome.retryable) break; // e.g. an unknown model — try the next one
      if (attempt + 1 < ATTEMPTS_PER_MODEL) {
        await sleep(600 * (attempt + 1));
      }
    }
  }

  return { ok: false, error: lastError };
}

interface AttemptOutcome extends GeminiOutcome {
  retryable?: boolean;
}

async function callOnce(
  apiKey: string,
  model: string,
  base64: string,
  mimeType: string,
): Promise<AttemptOutcome> {
  const requestBody = {
    model,
    input: [
      { type: "text", text: PROMPT },
      { type: "image", data: base64, mime_type: mimeType },
    ],
    response_format: {
      type: "text",
      mime_type: "application/json",
      schema: RECEIPT_SCHEMA,
    },
  };

  let response: Response;
  try {
    response = await fetch(GEMINI_ENDPOINT, {
      method: "POST",
      headers: {
        "x-goog-api-key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch {
    // Includes the abort: a stalled call is worth retrying, and must never
    // be allowed to hang the whole serverless invocation.
    return { ok: false, error: "Gemini did not respond in time.", retryable: true };
  }

  if (!response.ok) {
    const bodyText = await response.text().catch(() => "");
    return {
      ok: false,
      error: `Gemini returned HTTP ${response.status}. ${bodyText}`.trim(),
      retryable: RETRYABLE_STATUSES.has(response.status),
    };
  }

  const raw = await response.json().catch(() => null);
  const result = extractResult(raw);
  if (!result) {
    // Log the *shape* only — key names and value types, never any value.
    // Receipt content must not reach the platform logs (PRD §12), but
    // without this a shape change is undiagnosable from the outside.
    console.warn("Unrecognised Gemini response shape:", describeShape(raw));
    return { ok: false, error: "Unexpected response shape from Gemini.", retryable: true };
  }

  return { ok: true, data: result };
}

/**
 * The model ids to try, most preferred first.
 *
 * Nothing here is pinned to a model that happened to exist when this was
 * written: GEMINI_MODEL (a single id, or a comma-separated preference
 * list) wins if set, otherwise the API's own model listing is asked what
 * exists right now and the newest vision-capable "flash" models are
 * chosen. FALLBACK_MODEL is used only if that listing can't be reached.
 * Resolved once per warm instance.
 */
let cachedModels: string[] | undefined;

async function resolveModels(apiKey: string): Promise<string[]> {
  const configured = process.env.GEMINI_MODEL?.trim();
  if (configured) {
    return configured.split(",").map((m) => m.trim()).filter(Boolean);
  }

  if (cachedModels) return cachedModels;

  const discovered = await listModels(apiKey);
  cachedModels = discovered.length > 0 ? discovered : [FALLBACK_MODEL];
  return cachedModels;
}

async function listModels(apiKey: string): Promise<string[]> {
  let response: Response;
  try {
    response = await fetch(MODELS_ENDPOINT, {
      headers: { "x-goog-api-key": apiKey },
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    return [];
  }
  if (!response.ok) return [];

  const raw = (await response.json().catch(() => null)) as Record<string, unknown> | null;
  const entries = (raw?.models ?? raw?.data) as Array<Record<string, unknown>> | undefined;
  if (!Array.isArray(entries)) return [];

  const ids = entries
    .map((entry) => {
      const id = entry.name ?? entry.id ?? entry.model;
      return typeof id === "string" ? id.replace(/^models\//, "") : undefined;
    })
    .filter((id): id is string => typeof id === "string" && /^gemini-/.test(id))
    // Preview/experimental/thinking variants are less predictable for a
    // structured-output call, and TTS/embedding/image models can't read a
    // receipt at all.
    .filter((id) => !/(embedding|aqa|tts|image|audio|native|live|exp|preview)/.test(id));

  const flash = ids.filter((id) => id.includes("flash")).sort(byVersionDesc);
  const rest = ids.filter((id) => !id.includes("flash")).sort(byVersionDesc);

  return [...flash, ...rest].slice(0, 3);
}

/** Newest version number first ("gemini-3.8-flash" before "gemini-2.5-flash"). */
function byVersionDesc(a: string, b: string): number {
  return versionOf(b) - versionOf(a);
}

function versionOf(id: string): number {
  const match = /gemini-(\d+)(?:\.(\d+))?/.exec(id);
  if (!match) return 0;
  return Number(match[1]) * 100 + Number(match[2] ?? 0);
}

/**
 * Finds the parsed receipt anywhere in the response.
 *
 * Deliberately structure-agnostic rather than reading one documented
 * field: a live call returned HTTP 200 with a payload the previous
 * field-by-field extractor rejected outright, throwing away a perfectly
 * good answer. A structured-output response may carry the result as an
 * already-decoded object, or as a JSON string nested at any depth
 * (`output_text`, `candidates[0].content.parts[0].text`, …), and those
 * shapes move between API versions. So this walks the whole response and
 * accepts the first thing that actually *is* a receipt result — which is
 * the property that matters, and the one that can't silently change.
 */
function extractResult(raw: unknown): GeminiParseResult | undefined {
  const seen = new Set<unknown>();
  const queue: unknown[] = [raw];

  while (queue.length > 0) {
    const node = queue.shift();
    if (node === null || node === undefined) continue;

    if (typeof node === "string") {
      const decoded = tryParseJson(node);
      if (decoded !== undefined) queue.push(decoded);
      continue;
    }

    if (typeof node !== "object") continue;
    if (seen.has(node)) continue;
    seen.add(node);

    if (isValidParseResult(node)) return node;

    if (Array.isArray(node)) {
      queue.push(...node);
    } else {
      queue.push(...Object.values(node as Record<string, unknown>));
    }
  }

  return undefined;
}

function tryParseJson(value: string): unknown {
  const trimmed = value.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
    // Models sometimes wrap JSON in a ```json fence despite being asked
    // not to; unwrap before giving up on it.
    const fenced = /```(?:json)?\s*([\s\S]*?)```/.exec(trimmed);
    const inner = fenced?.[1];
    if (inner === undefined) return undefined;
    return tryParseJson(inner);
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return undefined;
  }
}

/**
 * A privacy-safe sketch of a payload: key names and value *types* only, so
 * an unexpected shape can be diagnosed from the Vercel logs without any
 * receipt content ever being written there.
 */
function describeShape(value: unknown, depth = 0): string {
  if (depth > 4) return "…";
  if (value === null) return "null";
  if (Array.isArray(value)) {
    return value.length === 0 ? "[]" : `[${describeShape(value[0], depth + 1)} x${value.length}]`;
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .slice(0, 12)
      .map(([key, child]) => `${key}: ${describeShape(child, depth + 1)}`);
    return `{${entries.join(", ")}}`;
  }
  return typeof value;
}

function isValidParseResult(value: unknown): value is GeminiParseResult {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const v = value as Record<string, unknown>;
  if (typeof v.isReceipt !== "boolean") return false;
  if (!Array.isArray(v.items)) return false;
  for (const item of v.items) {
    if (typeof item !== "object" || item === null) return false;
    const it = item as Record<string, unknown>;
    if (typeof it.name !== "string" || typeof it.price !== "number") return false;
  }
  if (v.detectedTotal !== undefined && typeof v.detectedTotal !== "number") return false;
  if (v.reason !== undefined && typeof v.reason !== "string") return false;
  return true;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
