// Prints the TOC interface number for the live retail client, from Blizzard's
// product-versions service. Queries product `wow` (live), never `wowt`/beta, so
// a PTR patch can't leak in. Prints nothing on any failure rather than guess.
// Interface = major*10000 + minor*100 + patch (12.0.7 -> 120007).

const URL = "https://us.version.battle.net/v2/products/wow/versions";

try {
  const res = await fetch(URL, { headers: { "User-Agent": "toc-interface-check" } });
  if (!res.ok) process.exit(0);
  const lines = (await res.text()).split(/\r?\n/).filter(Boolean);

  // The header row names each pipe-separated column ("Region!STRING:0|...|
  // VersionsName!String:0|..."); find which column holds the version name.
  const header = lines.find((l) => l.includes("VersionsName"));
  if (!header) process.exit(0);
  const cols = header.split("|").map((c) => c.split("!")[0].trim());
  const vi = cols.indexOf("VersionsName");
  const ri = cols.indexOf("Region");
  if (vi < 0) process.exit(0);

  const row = lines.find((l) => {
    const f = l.split("|");
    return f.length > vi && (ri < 0 || f[ri] === "us") && /^\d+\.\d+\.\d+/.test(f[vi]);
  });
  if (!row) process.exit(0);

  const [maj, min, pat] = row.split("|")[vi].split(".").map(Number);
  if (![maj, min, pat].every(Number.isFinite)) process.exit(0);
  const iface = maj * 10000 + min * 100 + pat;
  // Retail interface numbers are six digits; anything else means we misread the
  // feed, so say nothing rather than write it.
  if (iface < 100000 || iface > 999999) process.exit(0);
  process.stdout.write(String(iface));
} catch {
  process.exit(0);
}
