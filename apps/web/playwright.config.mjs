import { createRequire } from "node:module";

if (!process.env.PLAYWRIGHT_CLI_PATH) {
  throw new Error("PLAYWRIGHT_CLI_PATH must point to the temporary Playwright CLI installed by CI.");
}

const require = createRequire(process.env.PLAYWRIGHT_CLI_PATH);
const { defineConfig } = require("@playwright/test");

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  reporter: "list",
  timeout: 90_000,
  expect: { timeout: 15_000 },
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://127.0.0.1:3000",
    browserName: "chromium",
    headless: true,
    trace: "retain-on-failure",
  },
});
