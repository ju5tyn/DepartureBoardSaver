const UPSTREAM = "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Geo-restrict to UK only. request.cf is undefined in local wrangler dev, so
    // we allow requests without CF metadata to keep local development working.
    const country = request.cf?.country;
    if (country && country !== "GB") {
      return json({ error: "This service is only available in the UK." }, 403);
    }

    // Only accept GET /GetDepBoardWithDetails/{CRS}
    const match = url.pathname.match(/^\/GetDepBoardWithDetails\/([A-Za-z]{3})$/);
    if (!match) {
      return json({ error: "Not found" }, 404);
    }

    const crs = match[1].toUpperCase();
    const numRows = clampNumRows(url.searchParams.get("numRows"));
    const upstreamURL = `${UPSTREAM}/GetDepBoardWithDetails/${crs}?numRows=${numRows}`;

    let upstreamResponse;
    try {
      upstreamResponse = await fetch(upstreamURL, {
        headers: { "x-apikey": env.RAILDATA_API_KEY },
        cf: { cacheTtl: 0 },
      });
    } catch {
      return json({ error: "Upstream unreachable" }, 502);
    }

    if (!upstreamResponse.ok) {
      return json({ error: "Upstream error", status: upstreamResponse.status }, upstreamResponse.status);
    }

    const body = await upstreamResponse.text();
    return new Response(body, {
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  },
};

function clampNumRows(raw) {
  const n = parseInt(raw ?? "10", 10);
  if (isNaN(n) || n < 1) return 10;
  if (n > 150) return 150;
  return n;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
