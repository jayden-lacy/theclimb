import assert from "node:assert/strict";
import worker from "../worker.js";

async function request(path, options = {}, env = {}) {
  return worker.fetch(new Request(`https://theclimbapp.org${path}`, options), env);
}

const download = await request("/download");
assert.equal(download.status, 200);
assert.match(download.headers.get("content-type") ?? "", /^text\/html/);
assert.match(await download.text(), /The release link is being connected/);

const invalidDownload = await request("/download", {}, { APP_STORE_URL: "https://example.com/not-allowed" });
assert.equal(invalidDownload.status, 200);

const redirect = await request(
  "/download",
  {},
  { APP_STORE_URL: "https://apps.apple.com/us/app/the-climb/id1234567890" }
);
assert.equal(redirect.status, 302);
assert.equal(redirect.headers.get("location"), "https://apps.apple.com/us/app/the-climb/id1234567890");

const association = await request("/.well-known/apple-app-site-association");
assert.equal(association.status, 200);
assert.match(association.headers.get("content-type") ?? "", /^application\/json/);
const associationBody = await association.json();
assert.equal(
  associationBody.applinks.details[0].appID,
  "BLH227B4U7.com.jaydenlacy.theclimb"
);

const privacy = await request("/privacy");
assert.equal(privacy.status, 200);
assert.match(await privacy.text(), /July 23, 2026/);

const head = await request("/terms", { method: "HEAD" });
assert.equal(head.status, 200);
assert.equal(await head.text(), "");

const rejectedWrite = await request("/privacy", { method: "POST" });
assert.equal(rejectedWrite.status, 405);
assert.equal(rejectedWrite.headers.get("allow"), "GET, HEAD");

console.log("Website worker validation passed.");
