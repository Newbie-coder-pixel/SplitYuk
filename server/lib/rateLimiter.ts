import { Redis } from "@upstash/redis";

/**
 * The only server-side state this relay keeps across requests (PRD §12):
 * a per-installation rate-limit counter and fully anonymized aggregate
 * delivery metrics. Both are keyed by a random installation token that
 * carries no link to a person, bill, or phone number — never a user id,
 * never a phone number, never anything from the message content itself.
 *
 * Both fail OPEN (never block or crash a send) if Upstash isn't configured
 * or unreachable — this is an abuse-prevention/metrics layer, not core
 * functionality, and Fonnte/email sending should keep working independently
 * of whether Redis has been wired up yet.
 */

const WINDOW_SECONDS = 60 * 60; // 1 hour
const MAX_REQUESTS_PER_WINDOW = 20; // generous for real use, tight for abuse

let redis: Redis | undefined | null;

function getRedis(): Redis | null {
  if (redis === undefined) {
    try {
      redis = Redis.fromEnv();
    } catch {
      console.warn("Upstash Redis is not configured — rate-limiting/metrics are disabled.");
      redis = null;
    }
  }
  return redis;
}

/** Returns true if this installation is still within its rate limit. */
export async function checkRateLimit(installationToken: string): Promise<boolean> {
  const client = getRedis();
  if (!client) return true;
  try {
    const key = `ratelimit:${installationToken}`;
    const count = await client.incr(key);
    if (count === 1) {
      await client.expire(key, WINDOW_SECONDS);
    }
    return count <= MAX_REQUESTS_PER_WINDOW;
  } catch (err) {
    console.warn("Rate-limit check failed, allowing the request through:", err);
    return true;
  }
}

export type MetricName = "notifications_sent_total" | "notifications_failed_total";

/** Increments a simple, anonymous aggregate counter — never tied to a bill or person. */
export async function incrementMetric(name: MetricName): Promise<void> {
  const client = getRedis();
  if (!client) return;
  try {
    await client.incr(`metric:${name}`);
  } catch (err) {
    console.warn("Failed to increment metric:", err);
  }
}
