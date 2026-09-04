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

  const form = new FormData();
  form.set("target", params.phone);
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

  const data = (await response.json().catch(() => null)) as { status?: boolean } | null;
  if (data?.status === false) {
    return { ok: false, error: "Fonnte reported the message was not sent." };
  }
  return { ok: true };
}
