import { writeFileSync, renameSync } from "node:fs";

// Write to a temp sibling then rename over the target — atomic on the same
// filesystem, so a crash mid-write never leaves a half-written vault file.
export function writeFileAtomic(path, content) {
  const tmp = `${path}.tmp-${process.pid}`;
  writeFileSync(tmp, content, "utf8");
  renameSync(tmp, path);
}
