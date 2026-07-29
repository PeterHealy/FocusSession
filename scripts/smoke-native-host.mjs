#!/usr/bin/env node

import { spawn } from "node:child_process";
import process from "node:process";

const hostPath = process.argv[2];

if (!hostPath) {
  console.error("Usage: smoke-native-host.mjs <absolute-path-to-FocusSessionNativeHost>");
  process.exit(2);
}

const host = spawn(hostPath, [], {
  stdio: ["pipe", "pipe", "inherit"],
});

const request = Buffer.from(
  JSON.stringify({
    id: "smoke-test",
    type: "getState",
    payload: {},
  }),
  "utf8",
);
const header = Buffer.alloc(4);
header.writeUInt32LE(request.length, 0);
host.stdin.write(Buffer.concat([header, request]));

let received = Buffer.alloc(0);
const timeout = setTimeout(() => {
  host.kill();
  console.error("Native host did not answer within five seconds.");
  process.exit(1);
}, 5_000);

host.stdout.on("data", (chunk) => {
  received = Buffer.concat([received, chunk]);
  if (received.length < 4) {
    return;
  }

  const payloadLength = received.readUInt32LE(0);
  if (received.length < 4 + payloadLength) {
    return;
  }

  clearTimeout(timeout);
  const response = JSON.parse(
    received.subarray(4, 4 + payloadLength).toString("utf8"),
  );
  host.kill();

  if (response.ok !== true || !response.state) {
    console.error("Native host returned an invalid response:", response);
    process.exit(1);
  }

  console.log("Native host smoke test passed.");
});

host.on("error", (error) => {
  clearTimeout(timeout);
  console.error(error.message);
  process.exit(1);
});
