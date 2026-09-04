import type { NotifyResult } from "./types.js";

/**
 * Sends the fallback email via Resend (PRD §13). Like the WhatsApp path,
 * the attachment is forwarded inline (base64) rather than uploaded and
 * linked — this relay has nowhere it's allowed to keep the file even
 * long enough to hand back a URL (PRD §12).
 */
export async function sendEmail(params: {
  to: string;
  subject: string;
  text: string;
  attachment?: { bytes: ArrayBuffer; filename: string };
}): Promise<NotifyResult> {
  const apiKey = process.env.RESEND_API_KEY;
  const fromAddress = process.env.RESEND_FROM_ADDRESS;
  if (!apiKey || !fromAddress) {
    return { ok: false, error: "Email sending is not configured on the relay." };
  }

  const body: Record<string, unknown> = {
    from: fromAddress,
    to: [params.to],
    subject: params.subject,
    text: params.text,
  };

  if (params.attachment) {
    body.attachments = [
      {
        filename: params.attachment.filename,
        content: Buffer.from(params.attachment.bytes).toString("base64"),
      },
    ];
  }

  let response: Response;
  try {
    response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
  } catch {
    return { ok: false, error: "Could not reach the email provider." };
  }

  if (!response.ok) {
    return { ok: false, error: `Email provider returned HTTP ${response.status}.` };
  }
  return { ok: true };
}
