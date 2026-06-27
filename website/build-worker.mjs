import { readFileSync, writeFileSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = dirname(here);
const siteUrl = "https://theclimbapp.org";

const read = (path) => readFileSync(join(here, path), "utf8");

const html = read("index.html");
const privacy = read("privacy.html");
const terms = read("terms.html");
const css = read("styles.css");
const js = read("script.js");

const notFound = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <base href="/" />
    <title>Page Not Found | The Climb</title>
    <meta name="robots" content="noindex" />
    <meta name="theme-color" content="#f6f6f2" media="(prefers-color-scheme: light)" />
    <meta name="theme-color" content="#10110f" media="(prefers-color-scheme: dark)" />
    <link rel="icon" href="/assets/icons/app-icon.png" />
    <link rel="apple-touch-icon" href="/assets/icons/app-icon.png" />
    <script nonce="__CSP_NONCE__">
      (() => {
        try {
          const theme = localStorage.getItem("the-climb-theme") || "system";
          if (theme === "light" || theme === "dark") {
            document.documentElement.dataset.theme = theme;
          }
        } catch {
          /* Keep system theme if storage is unavailable. */
        }
      })();
    </script>
    <link rel="stylesheet" href="/styles.css" />
  </head>
  <body>
    <main class="legal-page">
      <article class="legal-card">
        <p class="eyebrow">404</p>
        <h1>Page not found.</h1>
        <p>The page you opened does not exist.</p>
        <p><a class="button button-secondary" href="/">Back to The Climb</a></p>
      </article>
    </main>
    <script src="/script.js"></script>
  </body>
</html>`;

const downloadNotConfigured = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <base href="/" />
    <title>Download Not Configured | The Climb</title>
    <meta name="robots" content="noindex" />
    <meta name="theme-color" content="#f6f6f2" media="(prefers-color-scheme: light)" />
    <meta name="theme-color" content="#10110f" media="(prefers-color-scheme: dark)" />
    <link rel="icon" href="/assets/icons/app-icon.png" />
    <link rel="apple-touch-icon" href="/assets/icons/app-icon.png" />
    <script nonce="__CSP_NONCE__">
      (() => {
        try {
          const theme = localStorage.getItem("the-climb-theme") || "system";
          if (theme === "light" || theme === "dark") {
            document.documentElement.dataset.theme = theme;
          }
        } catch {
          /* Keep system theme if storage is unavailable. */
        }
      })();
    </script>
    <link rel="stylesheet" href="/styles.css" />
  </head>
  <body>
    <main class="legal-page">
      <article class="legal-card">
        <p class="eyebrow">Download</p>
        <h1>App Store link missing.</h1>
        <p>
          The Climb download route is not public yet because the App Store URL is not configured.
          Set the Cloudflare Worker environment variable APP_STORE_URL to the live
          App Store listing before public traffic uses this link.
        </p>
        <p><a class="button button-secondary" href="/">Back to The Climb</a></p>
      </article>
    </main>
    <script src="/script.js"></script>
  </body>
</html>`;

const robots = `User-agent: *
Allow: /
Sitemap: ${siteUrl}/sitemap.xml
`;

const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${siteUrl}/</loc>
    <lastmod>2026-06-14</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>${siteUrl}/privacy</loc>
    <lastmod>2026-06-14</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.4</priority>
  </url>
  <url>
    <loc>${siteUrl}/terms</loc>
    <lastmod>2026-06-14</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.4</priority>
  </url>
</urlset>
`;

const ogImage = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630" role="img" aria-labelledby="title desc">
  <title id="title">The Climb</title>
  <desc id="desc">The Climb is preparing for iPhone launch. Stop drifting. Start climbing.</desc>
  <defs>
    <radialGradient id="g" cx="72%" cy="18%" r="70%">
      <stop offset="0" stop-color="#d1c08c" stop-opacity="0.7"/>
      <stop offset="0.48" stop-color="#3b5848" stop-opacity="0.25"/>
      <stop offset="1" stop-color="#0b0b0f" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1200" height="630" fill="#0b0b0f"/>
  <rect width="1200" height="630" fill="url(#g)"/>
  <circle cx="866" cy="286" r="148" fill="#f4eadc" opacity="0.06"/>
  <circle cx="866" cy="286" r="92" fill="none" stroke="#f4eadc" stroke-opacity="0.16" stroke-width="2"/>
  <path d="M160 430 306 188l98 160 76-112 154 194H160Z" fill="#f4eadc"/>
  <path d="M306 188 404 348 356 322 324 368 292 314 238 430H160l146-242Z" fill="#d1c08c" opacity="0.78"/>
  <text x="160" y="126" fill="#d1c08c" font-family="Arial, sans-serif" font-size="24" font-weight="700" letter-spacing="5">THE CLIMB</text>
  <text x="160" y="178" fill="#f4eadc" font-family="Arial, sans-serif" font-size="30" font-weight="700">IPHONE LAUNCH PENDING</text>
  <text x="160" y="520" fill="#f4eadc" font-family="Arial, sans-serif" font-size="72" font-weight="800">Stop drifting.</text>
  <text x="160" y="584" fill="#f4eadc" font-family="Arial, sans-serif" font-size="72" font-weight="800">Start climbing.</text>
</svg>
`;

const mimeTypes = new Map([
  [".avif", "image/avif"],
  [".gif", "image/gif"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".png", "image/png"],
  [".svg", "image/svg+xml; charset=utf-8"],
  [".ttf", "font/ttf"],
  [".webp", "image/webp"],
  [".woff", "font/woff"],
  [".woff2", "font/woff2"],
]);

const assetPaths = [
  "assets/fonts/DMSans.ttf",
  "assets/icons/app-icon.png",
];

const assets = Object.fromEntries(
  assetPaths.map((assetPath) => {
    const fullPath = join(here, assetPath);
    const ext = extname(assetPath).toLowerCase();

    return [
      "/" + assetPath,
      {
        contentType: mimeTypes.get(ext) || "application/octet-stream",
        body: readFileSync(fullPath).toString("base64"),
      },
    ];
  })
);

const worker = `export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const nonce = createNonce();

    if (request.method !== "GET" && request.method !== "HEAD") {
      return methodNotAllowed(["GET", "HEAD"]);
    }

    if (url.pathname === "/download") {
      return downloadResponse(env, request.method, nonce);
    }

    if (url.pathname === "/robots.txt") {
      return textResponse(ROBOTS, "text/plain; charset=utf-8", request.method, nonce, 200, "public, max-age=3600");
    }

    if (url.pathname === "/sitemap.xml") {
      return textResponse(SITEMAP, "application/xml; charset=utf-8", request.method, nonce, 200, "public, max-age=3600");
    }

    if (url.pathname === "/og-image.svg") {
      return textResponse(OG_IMAGE, "image/svg+xml; charset=utf-8", request.method, nonce, 200, "public, max-age=86400");
    }

    if (url.pathname === "/styles.css") {
      return textResponse(CSS, "text/css; charset=utf-8", request.method, nonce, 200, "public, max-age=3600");
    }

    if (url.pathname === "/script.js") {
      return textResponse(JS, "text/javascript; charset=utf-8", request.method, nonce, 200, "public, max-age=3600");
    }

    const asset = ASSETS[url.pathname];
    if (asset) {
      return assetResponse(asset, request.method, nonce);
    }

    if (url.pathname === "/" || url.pathname === "/index.html") {
      return textResponse(HTML, "text/html; charset=utf-8", request.method, nonce);
    }

    if (url.pathname === "/privacy" || url.pathname === "/privacy.html") {
      return textResponse(PRIVACY, "text/html; charset=utf-8", request.method, nonce);
    }

    if (url.pathname === "/terms" || url.pathname === "/terms.html") {
      return textResponse(TERMS, "text/html; charset=utf-8", request.method, nonce);
    }

    return textResponse(NOT_FOUND, "text/html; charset=utf-8", request.method, nonce, 404, "public, max-age=60");
  },
};

function downloadResponse(env = {}, method, nonce) {
  const appStoreUrl = typeof env.APP_STORE_URL === "string" ? env.APP_STORE_URL.trim() : "";

  if (isAllowedAppStoreUrl(appStoreUrl)) {
    return new Response(null, {
      status: 302,
      headers: redirectHeaders(appStoreUrl),
    });
  }

  return textResponse(DOWNLOAD_NOT_CONFIGURED, "text/html; charset=utf-8", method, nonce, 503, "no-store");
}

function isAllowedAppStoreUrl(value) {
  try {
    const target = new URL(value);
    return target.protocol === "https:" && (target.hostname === "apps.apple.com" || target.hostname === "itunes.apple.com");
  } catch {
    return false;
  }
}

function redirectHeaders(location) {
  return {
    location,
    "cache-control": "no-store",
    "referrer-policy": "strict-origin-when-cross-origin",
    "strict-transport-security": "max-age=31536000; includeSubDomains",
    "x-content-type-options": "nosniff",
  };
}

function textResponse(body, contentType, method, nonce, status = 200, cacheControl = "public, max-age=300") {
  const responseBody = contentType.startsWith("text/html")
    ? body.replaceAll("__CSP_NONCE__", nonce)
    : body;

  return new Response(method === "HEAD" ? null : responseBody, {
    status,
    headers: securityHeaders(contentType, nonce, cacheControl),
  });
}

function assetResponse(asset, method, nonce) {
  return new Response(method === "HEAD" ? null : decodeBase64(asset.body), {
    headers: securityHeaders(asset.contentType, nonce, "public, max-age=31536000, immutable"),
  });
}

function methodNotAllowed(allowed) {
  return new Response("Method Not Allowed", {
    status: 405,
    headers: {
      Allow: allowed.join(", "),
      "cache-control": "no-store",
      "strict-transport-security": "max-age=31536000; includeSubDomains",
      "x-content-type-options": "nosniff",
    },
  });
}

function securityHeaders(contentType, nonce, cacheControl) {
  return {
    "content-type": contentType,
    "cache-control": cacheControl,
    "content-security-policy": [
      "default-src 'self'",
      "script-src 'self' 'nonce-" + nonce + "'",
      "style-src 'self'",
      "img-src 'self' data:",
      "font-src 'self'",
      "connect-src 'self'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "object-src 'none'",
      "upgrade-insecure-requests",
    ].join("; "),
    "cross-origin-opener-policy": "same-origin",
    "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=()",
    "referrer-policy": "strict-origin-when-cross-origin",
    "strict-transport-security": "max-age=31536000; includeSubDomains",
    "x-content-type-options": "nosniff",
    "x-frame-options": "DENY",
  };
}

function createNonce() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function decodeBase64(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

const HTML = ${JSON.stringify(html)};
const PRIVACY = ${JSON.stringify(privacy)};
const TERMS = ${JSON.stringify(terms)};
const NOT_FOUND = ${JSON.stringify(notFound)};
const DOWNLOAD_NOT_CONFIGURED = ${JSON.stringify(downloadNotConfigured)};
const CSS = ${JSON.stringify(css)};
const JS = ${JSON.stringify(js)};
const ROBOTS = ${JSON.stringify(robots)};
const SITEMAP = ${JSON.stringify(sitemap)};
const OG_IMAGE = ${JSON.stringify(ogImage)};
const ASSETS = ${JSON.stringify(assets)};
`;

writeFileSync(join(root, "worker.js"), worker);
