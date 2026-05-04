// Structured JSON logging. Every log line includes request_id so we can join them across an
// end-to-end turn (dm-turn ↔ resolve-roll ↔ summarize-campaign).
//
// Edge Functions in Supabase forward stdout to the dashboard's log explorer, so plain
// console.log with a JSON payload is the right choice — no need for a logging library.

export type LogLevel = "debug" | "info" | "warn" | "error";

export class Logger {
  constructor(public readonly requestId: string, public readonly fn: string) {}

  log(level: LogLevel, msg: string, extra: Record<string, unknown> = {}) {
    const line = JSON.stringify({
      ts: new Date().toISOString(),
      level,
      fn: this.fn,
      request_id: this.requestId,
      msg,
      ...extra,
    });
    if (level === "error") console.error(line);
    else if (level === "warn") console.warn(line);
    else console.log(line);
  }

  info(msg: string, extra?: Record<string, unknown>) { this.log("info", msg, extra); }
  warn(msg: string, extra?: Record<string, unknown>) { this.log("warn", msg, extra); }
  error(msg: string, extra?: Record<string, unknown>) { this.log("error", msg, extra); }
  debug(msg: string, extra?: Record<string, unknown>) { this.log("debug", msg, extra); }
}

export function newLogger(fn: string): Logger {
  return new Logger(crypto.randomUUID(), fn);
}
