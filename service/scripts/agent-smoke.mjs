import { query } from "@anthropic-ai/claude-agent-sdk";

const q = query({
  prompt: "Reply with exactly the single word: pong",
  options: { settingSources: [] },
});

for await (const msg of q) {
  if (msg.type === "assistant") {
    const text = (msg.message?.content ?? [])
      .filter((b) => b.type === "text")
      .map((b) => b.text)
      .join("");
    if (text) console.log("assistant:", JSON.stringify(text));
  } else if (msg.type === "result") {
    console.log("result.subtype:", msg.subtype, "| is_error:", msg.is_error);
    if (msg.result) console.log("result.text:", JSON.stringify(msg.result));
  } else {
    console.log("msg:", msg.type);
  }
}
