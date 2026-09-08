import type { NotifyResult } from "./types.js";

/**
 * Sends a WhatsApp message through Fonnte (PRD §13/§15 — an unofficial
 * gateway; see the PRD for the unresolved single-shared-number risk).
 *
 * The attachment is forwarded as a raw file upload (Fonnte's `file` field)
 * rather than a hosted `url` — this relay never stores the image anywhere,
 * even temporarily, so it has no URL to give Fonnte; forwarding the bytes
 * directly is what keeps this step actually stateless (PRD §12).
 */
export async function sendWhatsApp(params: {
  phone: string;
  message: string;
  attachment?: { bytes: ArrayBuffer; filename: string; contentType: string };
}): Promise<NotifyResult> {
  const apiKey = process.env.FONNTE_API_KEY;
  if (!apiKey) {
    return { ok: false, error: "FONNTE_API_KEY is not configured on the relay." };
  }

  const target = normalizePhone(params.phone);
  if (!target) {
    return { ok: false, error: `"${params.phone}" is not a usable WhatsApp number.` };
  }

  // A WhatsApp gateway cannot message the very device it sends from:
  // Fonnte accepts the request, queues it, reports success, and nothing
  // ever arrives. That is indistinguishable from a broken integration
  // from the outside, so say it plainly instead. Set
  // FONNTE_DEVICE_NUMBER to the number linked to FONNTE_API_KEY to get
  // this check; without it the send proceeds as before.
  const ownNumber = normalizePhone(process.env.FONNTE_DEVICE_NUMBER ?? "");
  if (ownNumber && ownNumber === target) {
    return {
      ok: false,
      error:
        "That is the number SplitYuk sends from, and WhatsApp will not deliver a " +
        "message to its own sender. Use a different number for this member.",
    };
  }

  const form = new FormData();
  form.set("target", target);
  form.set("message", params.message);
  if (params.attachment) {
    form.set(
      "file",
      new Blob([params.attachment.bytes], { type: params.attachment.contentType }),
      params.attachment.filename,
    );
  }

  let response: Response;
  try {
    response = await fetch("https://api.fonnte.com/send", {
      method: "POST",
      headers: { Authorization: apiKey },
      body: form,
    });
  } catch {
    return { ok: false, error: "Could not reach Fonnte." };
  }

  if (!response.ok) {
    return { ok: false, error: `Fonnte returned HTTP ${response.status}.` };
  }

  const data = (await response.json().catch(() => null)) as Record<string, unknown> | null;
  return interpretFonnteResponse(data);
}

/**
 * Turns Fonnte's reply into a verdict.
 *
 * Fonnte answers HTTP 200 with `status: true` for a number that has no
 * WhatsApp account at all — verified against the live API — so "the call
 * succeeded" is not the same as "the message was accepted for this
 * number", and treating them as equal told users a bill had been sent
 * when nothing was ever delivered.
 *
 * Fonnte reports rejected numbers in a separate list whose name has
 * varied across its API versions, so this looks for any list of targets
 * that came back rejected rather than trusting one field name — the same
 * lesson as the Gemini extractor.
 */
export function interpretFonnteResponse(data: Record<string, unknown> | null): NotifyResult {
  if (!data) return { ok: false, error: "Fonnte returned a response we could not read." };

  const detail = typeof data.detail === "string" ? data.detail : undefined;
  const reason = typeof data.reason === "string" ? data.reason : undefined;
  const explanation = [reason, detail].filter(Boolean).join(" ").trim();

  if (data.status === false) {
    // Fonnte's own words ("device not connected", "quota exceeded") are
    // the only way to tell these apart from outside, and they describe the
    // sending device, never the recipient.
    return {
      ok: false,
      error: `Fonnte did not send the message.${explanation ? ` ${explanation}` : ""}`,
    };
  }

  for (const key of ["invalid", "not_registered", "notRegistered", "failed", "reject"]) {
    const rejected = data[key];
    if (Array.isArray(rejected) && rejected.length > 0) {
      return {
        ok: false,
        error: "That number was rejected by WhatsApp — check it has an active WhatsApp account.",
      };
    }
  }

  return { ok: true, detail: detail ?? "Queued by Fonnte." };
}

/**
 * A phone number in the form Fonnte's `target` expects: digits only, with
 * an international dialling code and no leading `+`.
 *
 * Numbers reach this relay exactly as they were typed or as the phone's
 * address book formatted them — "+62 819-3303-2412", "0819 3303 2412",
 * "(0819) 3303-2412". Fonnte silently refuses those, which surfaces to the
 * user as an unexplained delivery failure, so the cleaning happens here
 * rather than trusting every app build to have done it.
 *
 * A local Indonesian leading zero becomes 62, matching the product's
 * market (PRD §1). Any other number that already carries a country code is
 * passed through — this must not mangle a foreign number into an
 * Indonesian one.
 *
 * Returns undefined when there is no plausible number to send to.
 */
export function normalizePhone(raw: string): string | undefined {
  const trimmed = raw.trim();
  const hadPlus = trimmed.startsWith("+");
  const digits = trimmed.replace(/\D/g, "");
  if (!digits) return undefined;

  // "0819…" is the Indonesian domestic form of "62819…". Only a leading
  // zero means this; an explicit "+" already carries a country code.
  const withCountryCode = !hadPlus && digits.startsWith("0") ? `62${digits.slice(1)}` : digits;

  // Short enough to be an extension or a typo, or long enough to be two
  // numbers run together — either way, not something to send a bill to.
  if (withCountryCode.length < 8 || withCountryCode.length > 15) return undefined;

  return withCountryCode;
}
