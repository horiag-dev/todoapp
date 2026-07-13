const base = `http://127.0.0.1:${process.env.PORT || 5178}`;
const message =
  process.argv[2] ||
  'Add "Prep Q3 board deck" to the Top 5, and mark the urgent item "Daniel S. 1:1 recurring" as Today.';

console.log("USER:", message, "\n");
const r = await fetch(base + "/api/chat", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ message }),
});
const chat = await r.json();
if (!r.ok) { console.error("HTTP", r.status, chat); process.exit(1); }
console.log("REPLY:", chat.reply, "\n");
console.log("NEW OPS:", JSON.stringify(chat.newOps), "\n");
const m = chat.model;
console.log(`dirty=${m.dirty}  top5=${m.top5.length}  urgent=${m.urgent.length}`);
console.log("urgent Today:", m.urgent.filter((i) => i.today).map((i) => i.title));
console.log("top5:", m.top5.map((i) => i.title));

if (process.argv[3] === "apply") {
  const a = await (await fetch(base + "/api/apply", { method: "POST" })).json();
  console.log("\nAPPLIED. dirty now:", a.model.dirty);
}
