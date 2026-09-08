export type NotificationChannel = "whatsapp" | "email";

export interface NotifyResult {
  ok: boolean;
  error?: string;

  /**
   * What the provider said on success. A WhatsApp gateway only ever
   * confirms it *queued* the message, never that it arrived, so this is
   * passed back rather than letting "ok" be read as "delivered".
   */
  detail?: string;
}
