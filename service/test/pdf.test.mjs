import { test } from "node:test";
import assert from "node:assert/strict";
import { extractPdfText, isPdf } from "../src/pdf.mjs";

const MINIMAL_PDF = Buffer.from(`%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 200]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
4 0 obj<</Length 46>>stream
BT /F1 18 Tf 20 120 Td (Hello PDF 42) Tj ET
endstream endobj
5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
trailer<</Root 1 0 R>>
%%EOF`, "latin1");

test("isPdf detects by extension and by magic bytes", () => {
  assert.ok(isPdf("report.pdf", Buffer.from("")));
  assert.ok(isPdf("no-extension", Buffer.from("%PDF-1.7 ...")));
  assert.ok(!isPdf("notes.txt", Buffer.from("hello there")));
  assert.ok(!isPdf("thing", Buffer.from("plain text")));
});

test("extractPdfText pulls selectable text from a PDF", async () => {
  const text = await extractPdfText(MINIMAL_PDF);
  assert.match(text, /Hello PDF 42/);
});

test("extractPdfText returns null on non-PDF input", async () => {
  assert.equal(await extractPdfText(Buffer.from("this is not a pdf at all")), null);
});
