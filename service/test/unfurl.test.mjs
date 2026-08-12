import { test } from "node:test";
import assert from "node:assert/strict";
import { extractTitle, isBareUrl, unfurlUrl } from "../src/unfurl.mjs";

test("extractTitle pulls and decodes the <title>", () => {
  assert.equal(extractTitle("<html><head><title>  Hello &amp; Goodbye </title></head>"), "Hello & Goodbye");
  assert.equal(extractTitle("<TITLE>Multi\n line\ttitle</TITLE>"), "Multi line title");
  assert.equal(extractTitle('<title>It&#39;s &quot;quoted&quot;</title>'), `It's "quoted"`);
  assert.equal(extractTitle("<html>no title element</html>"), null);
});

test("isBareUrl only matches a lone URL", () => {
  assert.ok(isBareUrl("https://example.com/x"));
  assert.ok(isBareUrl("  http://example.com  "));
  assert.ok(!isBareUrl("[Title](https://example.com)"));
  assert.ok(!isBareUrl("read this https://example.com later"));
  assert.ok(!isBareUrl("just a note"));
});

test("unfurlUrl wraps a fetched title and falls back safely", async () => {
  const okFetch = async () => ({ ok: true, headers: { get: () => "text/html" }, text: async () => "<title>Cool Article</title>" });
  assert.equal(await unfurlUrl("https://ex.com/a", okFetch), "[Cool Article](https://ex.com/a)");

  // non-URL input is returned untouched (and never fetched)
  assert.equal(await unfurlUrl("just a reference", okFetch), "just a reference");

  // network error → raw URL
  const boom = async () => { throw new Error("network"); };
  assert.equal(await unfurlUrl("https://ex.com/a", boom), "https://ex.com/a");

  // non-HTML content-type → raw URL
  const pdf = async () => ({ ok: true, headers: { get: () => "application/pdf" }, text: async () => "%PDF" });
  assert.equal(await unfurlUrl("https://ex.com/a.pdf", pdf), "https://ex.com/a.pdf");

  // no <title> → raw URL
  const noTitle = async () => ({ ok: true, headers: { get: () => "text/html" }, text: async () => "<html>hi</html>" });
  assert.equal(await unfurlUrl("https://ex.com/a", noTitle), "https://ex.com/a");
});
