import { checkRateLimit, incrementMetric } from "../lib/rateLimiter.js";
import { sendWhatsApp } from "../lib/fonnte.js";
import { sendEmail } from "../lib/email.js";
import type { NotificationChannel, NotifyResult } from "../lib/types.js";

/**
 * The one endpoint this whole backend has: relay a single notification.
 *
 * Deliberately stateless with respect to content (PRD §12) — nothing here
 * is written to a database, file, or log. The request body (phone/email,
 * amount, message, attachment) is held only in memory for the duration of
 * this one call, then discarded. The only things that outlive a single
 * request are the anonymized rate-limit counter and metrics in
 * lib/rateLimiter.ts, keyed by installation token — never by anything in
 * this payload.
 */
// Vercel's Node.js runtime routes requests to the named export matching the
// HTTP method (not a generic default export) — GET/PUT/etc. get a 405 from
// the platform itself before this file is even reached.
export async function POST(req: Request): Promise<Response> {
  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return jsonResponse(400, { error: "Expected multipart/form-data." });
  }

  const installationToken = str(form.get("installationToken"));
  const channelRaw = form.get("channel");
  const billTitle = str(form.get("billTitle")) ?? "SplitYuk bill";
  const amountDueRaw = str(form.get("amountDue"));
  const recipientName = str(form.get("recipientName")) ?? "there";
  const phone = str(form.get("phone"));
  const email = str(form.get("email"));
  const attachmentEntry = form.get("attachment");

  if (!installationToken) {
    return jsonResponse(400, { error: "Missing installationToken." });
  }
  if (channelRaw !== "whatsapp" && channelRaw !== "email") {
    return jsonResponse(400, { error: "channel must be 'whatsapp' or 'email'." });
  }
  const channel: NotificationChannel = channelRaw;

  const amountDue = Number.parseInt(amountDueRaw ?? "", 10);
  if (!Number.isFinite(amountDue) || amountDue < 0) {
    return jsonResponse(400, { error: "amountDue must be a non-negative integer." });
  }

  const withinLimit = await checkRateLimit(installationToken);
  if (!withinLimit) {
    return jsonResponse(429, { error: "Rate limit exceeded for this installation." });
  }

  let attachment: { bytes: ArrayBuffer; filename: string; contentType: string } | undefined;
  if (attachmentEntry instanceof File) {
    attachment = {
      bytes: await attachmentEntry.arrayBuffer(),
      filename: attachmentEntry.name || "receipt.png",
      contentType: attachmentEntry.type || "image/png",
    };
  }

  const message =
    `${billTitle}\n\nHi ${recipientName}, your share comes to Rp ${amountDue.toLocaleString("id-ID")}.` +
    (attachment ? "\n(Full breakdown attached.)" : "");

  const result = await deliver(channel, { phone, email, billTitle, message, attachment });

  await incrementMetric(result.ok ? "notifications_sent_total" : "notifications_failed_total");

  return jsonResponse(result.ok ? 200 : 502, result.ok ? { ok: true } : { error: result.error });
}

async function deliver(
  channel: NotificationChannel,
  params: {
    phone: string | undefined;
    email: string | undefined;
    billTitle: string;
    message: string;
    attachment?: { bytes: ArrayBuffer; filename: string; contentType: string };
  },
): Promise<NotifyResult> {
  if (channel === "whatsapp") {
    if (!params.phone) return { ok: false, error: "No phone number provided." };

    // NFR reliability requirement: retry once, then fall back to email if
    // one was provided.
    let result = await sendWhatsApp({
      phone: params.phone,
      message: params.message,
      attachment: params.attachment,
    });
    if (!result.ok) {
      result = await sendWhatsApp({
        phone: params.phone,
        message: params.message,
        attachment: params.attachment,
      });
    }
    if (!result.ok && params.email) {
      return sendEmail({
        to: params.email,
        subject: params.billTitle,
        text: params.message,
        attachment: params.attachment,
      });
    }
    return result;
  }

  if (!params.email) return { ok: false, error: "No email address provided." };
  return sendEmail({
    to: params.email,
    subject: params.billTitle,
    text: params.message,
    attachment: params.attachment,
  });
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
