// Best-effort To Read unfurl: turn a bare URL into a `[Page Title](url)` markdown
// link so the list is skimmable and de-stalable. Always falls back to the raw URL
// on any failure — never blocks a capture.

// Pure, testable: pull and decode the <title> from an HTML string.
export function extractTitle(html) {
  const m = String(html || "").match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (!m) return null;
  let title = m[1]
    .replace(/\s+/g, " ")
    .trim()
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#0?39;|&#x27;|&apos;/gi, "'").replace(/&nbsp;/gi, " ");
  return title ? title.slice(0, 140) : null;
}

export const isBareUrl = (text) => /^https?:\/\/\S+$/.test(String(text ?? "").trim());

export async function unfurlUrl(text, fetchImpl = globalThis.fetch) {
  const t = String(text ?? "").trim();
  if (!isBareUrl(t) || typeof fetchImpl !== "function") return t;
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 5000);
    const res = await fetchImpl(t, { signal: ctrl.signal, redirect: "follow", headers: { "user-agent": "Mozilla/5.0 (BigRocksFirst)" } });
    clearTimeout(timer);
    if (!res.ok) return t;
    const ct = res.headers?.get?.("content-type") || "";
    if (ct && !ct.includes("text/html")) return t;
    const title = extractTitle((await res.text()).slice(0, 200000));
    return title ? `[${title}](${t})` : t;
  } catch {
    return t;
  }
}
