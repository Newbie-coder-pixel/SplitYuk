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

// Overridable via the GEMINI_MODEL env var without a redeploy, in case the
// hardcoded default here goes stale (Google's model lineup moves quickly).
const DEFAULT_MODEL = "gemini-3.8-flash";
const GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/interactions";

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
  "set isReceipt to true and extract every purchased line item with its " +
  "exact name and its final line price as a plain integer number of " +
  "Rupiah — no currency symbol, no thousands separators, no decimals. " +
  "Never include barcodes, product/goods codes, loyalty or member numbers, " +
  "cashier/POS/serial metadata, payment method lines (e.g. a bank name), " +
  "or change/kembali lines as items. If a printed grand total is visible, " +
  "extract it as detectedTotal as a plain integer. Respond with only the " +
  "structured JSON, nothing else.";

/**
 * Sends the receipt photo itself (not pre-extracted OCR text) to Gemini so
 * it reads the image directly — this intentionally replaces on-device OCR
 * for accuracy, per an explicit product decision: the receipt photo now
 * leaves the device at scan time, not just at notification-send time.
 * Nothing here is logged or stored — same stateless-relay contract as
 * /api/notify.
 */
export async function parseReceiptWithGemini(
  imageBytes: ArrayBuffer,
  mimeType: string,
): Promise<GeminiOutcome> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return { ok: false, error: "GEMINI_API_KEY is not configured on the relay." };
  }

  const model = process.env.GEMINI_MODEL?.trim() || DEFAULT_MODEL;
  const base64 = Buffer.from(imageBytes).toString("base64");

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
    });
  } catch {
    return { ok: false, error: "Could not reach Gemini." };
  }

  if (!response.ok) {
    const bodyText = await response.text().catch(() => "");
    return { ok: false, error: `Gemini returned HTTP ${response.status}. ${bodyText}`.trim() };
  }

  const raw = (await response.json().catch(() => null)) as Record<string, unknown> | null;
  const outputText = extractOutputText(raw);
  if (typeof outputText !== "string") {
    return { ok: false, error: "Unexpected response shape from Gemini." };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(outputText);
  } catch {
    return { ok: false, error: "Gemini did not return valid JSON." };
  }

  if (!isValidParseResult(parsed)) {
    return { ok: false, error: "Gemini response did not match the expected schema." };
  }

  return { ok: true, data: parsed };
}

/**
 * Defensive on purpose: the exact response field name is taken on faith
 * from documentation that could not be verified against a live call before
 * this shipped. Tries every plausible shape rather than assuming one.
 */
function extractOutputText(raw: Record<string, unknown> | null): string | undefined {
  if (!raw) return undefined;
  if (typeof raw.output_text === "string") return raw.output_text;
  if (typeof raw.outputText === "string") return raw.outputText;

  // Fallback: the older, long-stable generateContent response shape, in
  // case this relay ends up talking to that API surface after all.
  const candidates = raw.candidates as Array<Record<string, unknown>> | undefined;
  const firstPart = (candidates?.[0]?.content as Record<string, unknown> | undefined)?.parts as
    | Array<Record<string, unknown>>
    | undefined;
  const text = firstPart?.[0]?.text;
  if (typeof text === "string") return text;

  return undefined;
}

function isValidParseResult(value: unknown): value is GeminiParseResult {
  if (typeof value !== "object" || value === null) return false;
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
