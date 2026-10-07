import { build } from "esbuild";
import { readFile, writeFile } from "node:fs/promises";

const output = "../../Gallae/Resources/VisualDiff/viewer.js";
await build({
  entryPoints: ["viewer.js"], outfile: output, bundle: true, minify: true,
  format: "iife", platform: "browser", target: "safari18", legalComments: "eof",
  // Only renderAll/manifest hashing uses crypto. Our render-only entry is tree-shaken.
  external: ["node:crypto"],
});
const bundled = await readFile(output, "utf8");
if (bundled.includes("node:crypto") || bundled.includes("require(")) {
  throw new Error("Visual Diff must run without Node or external modules.");
}
const packages = ["@coldtea/pr-lens-renderer", "@coldtea/pr-lens-schema", "zod"];
const licenses = await Promise.all(packages.map(async name => {
  const metadata = JSON.parse(await readFile(`node_modules/${name}/package.json`, "utf8"));
  return `${name} ${metadata.version}\n${await readFile(`node_modules/${name}/LICENSE`, "utf8")}`;
}));
await writeFile("../../Gallae/Resources/VisualDiff/LICENSES.txt", licenses.join("\n\n"));
