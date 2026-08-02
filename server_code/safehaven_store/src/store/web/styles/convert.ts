/* dont look at me like that choom, im lazy. 
   run with node if you decide to make any changes */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

const FILES: string[] = ["theme.css", "components.css"];

for (const name of FILES) {
  const srcPath = join(__dirname, name);
  const outPath = join(__dirname, `${name}.ts`);

  const css: string = readFileSync(srcPath, "utf8");
  const js: string = `export default ${JSON.stringify(css)};\n`;

  writeFileSync(outPath, js);
  console.log(`${name} -> ${name}.ts (${css.length} chars)`);
}