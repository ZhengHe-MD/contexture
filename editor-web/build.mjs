import * as esbuild from "esbuild";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outdir = path.resolve(__dirname, "../Sources/ContextureApp/Resources/editor");

fs.mkdirSync(outdir, { recursive: true });
fs.copyFileSync(path.join(__dirname, "src/index.html"), path.join(outdir, "index.html"));
fs.copyFileSync(path.join(__dirname, "src/editor.css"), path.join(outdir, "editor.css"));

const watch = process.argv.includes("--watch");

const buildOptions = {
  entryPoints: [path.join(__dirname, "src/main.js")],
  bundle: true,
  outfile: path.join(outdir, "bundle.js"),
  format: "iife",
  target: "safari17",
  sourcemap: false,
  logLevel: "info",
};

if (watch) {
  const ctx = await esbuild.context(buildOptions);
  await ctx.watch();
  console.log("watching for changes...");
} else {
  await esbuild.build(buildOptions);
  console.log(`built editor bundle -> ${outdir}`);
}
