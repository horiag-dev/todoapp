const port = process.env.PORT || 5178;
const m = await (await fetch(`http://127.0.0.1:${port}/api/model`)).json();
console.log(
  `urgent=${m.urgent.length} (${m.urgent.filter((i) => i.starred).length} star)  normal=${m.normal.length}  top5=${m.top5.length}  completed=${m.completed}  deleted=${m.deleted}  goalsLines=${m.goals.length}  toRead=${m.toread.length}`,
);
console.log("stars:", m.urgent.filter((i) => i.starred).map((i) => i.title).join(" | "));
console.log("first urgent item:", JSON.stringify(m.urgent[0]));
