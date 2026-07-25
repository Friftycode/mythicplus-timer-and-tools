// Stamps the version (and interface, if given) into the .toc and package.json.
// An empty interface leaves the Interface line untouched.
//
//   node scripts/apply-release.mjs <version> [interface]

import fs from "node:fs";

const [version, iface] = process.argv.slice(2);
if (!version) {
  console.error("usage: node scripts/apply-release.mjs <version> [interface]");
  process.exit(1);
}

const TOC = "MythicPlusTimerandTools/MythicPlusTimerandTools.toc";
let toc = fs.readFileSync(TOC, "utf8");
if (iface && /^\d{6}$/.test(iface)) {
  toc = toc.replace(/^## Interface:.*$/m, `## Interface: ${iface}`);
}
toc = toc.replace(/^## Version:.*$/m, `## Version: ${version}`);
fs.writeFileSync(TOC, toc);

const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.version = version;
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");

console.log(
  `version=${version}` + (iface ? ` interface=${iface}` : " (interface unchanged)")
);
