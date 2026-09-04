import { checkRateLimit, incrementMetric } from "../lib/rateLimiter.js";
import { parseReceiptWithGemini, resolveImageMimeType } from "../lib/gemini.js";

// A tighter, separate quota than /api/notify — this shares one Gemini
// free-tier daily allowance across every installation using this relay,
// so a single device scanning receipts in a loop shouldn't be able to
// exhaust it for everyone else.
const MAX_PARSES_PER_HOUR = 10;

/**
 * Reads a receipt photo via Gemini and returns structured items/total.
 * Like /api/notify, this is stateless with respect to content — the image
 * is held in memory only for this one request and is never written to a
 * database, file, or log.
 */
export async function POST(req: Request): Promise<Response> {
  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return jsonResponse(400, { error: "Expected multipart/form-data." });
  }

  const installationToken = str(form.get("installationToken"));
  if (!installationToken) {
    return jsonResponse(400, { error: "Missing installationToken." });
  }

  const withinLimit = await checkRateLimit(installationToken, "parse-receipt", MAX_PARSES_PER_HOUR);
  if (!withinLimit) {
    return jsonResponse(429, { error: "Rate limit exceeded for this installation." });
  }

  const imageEntry = form.get("image");
  if (!(imageEntry instanceof File)) {
    return jsonResponse(400, { error: "Missing image file." });
  }

  const imageBytes = await imageEntry.arrayBuffer();

  // Decided from the bytes, not from what the client claimed: an upload
  // with no declared type arrives as application/octet-stream, and passing
  // that on makes Gemini reject the photo as raw binary.
  const mimeType = resolveImageMimeType(imageBytes, imageEntry.type);
  if (!mimeType) {
    return jsonResponse(400, {
      error: "That file isn't a photo we can read. Take the receipt photo again and retry.",
    });
  }

  const result = await parseReceiptWithGemini(imageBytes, mimeType);

  await incrementMetric(result.ok ? "receipts_parsed_total" : "receipts_parse_failed_total");

  if (!result.ok) {
    return jsonResponse(502, { error: result.error });
  }
  return jsonResponse(200, result.data);
}

function str(value: FormDataEntryValue | null): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
