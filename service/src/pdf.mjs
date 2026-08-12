// Extract selectable text from a PDF buffer (best-effort). Returns null on
// failure, "" for image-only / scanned PDFs. unpdf (bundled pdf.js) is
// lazy-loaded so it only costs when a PDF is actually read.
export async function extractPdfText(buf) {
  try {
    const { extractText, getDocumentProxy } = await import("unpdf");
    const doc = await getDocumentProxy(new Uint8Array(buf));
    const { text } = await extractText(doc, { mergePages: true });
    return Array.isArray(text) ? text.join("\n") : String(text ?? "");
  } catch {
    return null;
  }
}

export const isPdf = (name, buf) =>
  /\.pdf$/i.test(String(name ?? "")) || (!!buf && buf.subarray(0, 5).toString("latin1") === "%PDF-");
