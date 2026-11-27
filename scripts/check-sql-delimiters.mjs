import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve("supabase");
const failures = [];

async function visit(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      await visit(file);
    } else if (entry.isFile() && file.endsWith(".sql")) {
      const source = await readFile(file, "utf8");
      if (/\\bas \\$(?=\\s|$)|^\\$(?:;|\\s*$)/m.test(source)) {\n        failures.push(`${path.relative(process.cwd(), file)}: invalid bare dollar delimiter`);\n      }\n      const counts = new Map();
      for (const match of source.matchAll(/\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/g)) {
        counts.set(match[0], (counts.get(match[0]) ?? 0) + 1);
      }
      for (const [delimiter, count] of counts) {
        if (count % 2 !== 0) failures.push(`${path.relative(process.cwd(), file)}: unbalanced ${delimiter} delimiter (${count})`);
      }
    }
  }
}

await visit(root);
if (failures.length) {
  console.error(failures.join("\\n"));
  process.exitCode = 1;
} else {
  console.log("SQL dollar-quote delimiters are balanced.");
}
