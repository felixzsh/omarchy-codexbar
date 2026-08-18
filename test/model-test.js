#!/usr/bin/env node
"use strict"

const assert = require("assert")
const path = require("path")
const model = require(path.join(__dirname, "..", "codexbar.js"))

// Fixture 1: the real opencodego payload captured from `codexbar serve`.
const opencodego = [
  {
    provider: "opencodego",
    source: "local",
    usage: {
      updatedAt: "2026-08-03T13:56:50Z",
      primary: { resetsAt: "2026-08-03T18:08:59Z", usedPercent: 5.8, windowMinutes: 300 },
      secondary: { resetsAt: "2026-08-09T23:59:59Z", usedPercent: 3.8, windowMinutes: 10080 },
      tertiary: { resetsAt: "2026-08-29T20:39:29Z", usedPercent: 5.9, windowMinutes: 43200 }
    }
  }
]

{
  const list = model.normalizeProviders(opencodego)
  assert.strictEqual(list.length, 1, "one provider")
  const p = list[0]
  assert.strictEqual(p.providerId, "opencodego")
  assert.strictEqual(p.providerName, "OpenCode Go")
  assert.strictEqual(p.source, "local")
  assert.strictEqual(p.windows.length, 3)
  assert.strictEqual(p.windows[0].title, "Session")
  assert.strictEqual(p.windows[1].title, "Weekly")
  assert.strictEqual(p.windows[2].title, "Monthly")
  assert.strictEqual(p.windows[0].percent, 0.058)
  assert.strictEqual(p.windows[1].percent, 0.038)
  assert.strictEqual(p.windows[2].percent, 0.059)
  assert.strictEqual(p.headlinePercent, 0.059)
  assert.strictEqual(p.windows[0].resetAt, "2026-08-03T18:08:59Z")
  assert.strictEqual(p.hasData, true)
  assert.strictEqual(p.error, "")
}
console.log("PASS: normalizes the real opencodego payload")

// Fixture 2: error entries are kept but flagged, and dropped from valid list.
const withErrors = [
  { provider: "codex", source: "auto", error: { kind: "provider", code: 1, message: "auth required" } },
  opencodego[0]
]
{
  const all = model.normalizeProviders(withErrors)
  assert.strictEqual(all.length, 2)
  // Providers with data lead the list; errored providers trail behind.
  assert.strictEqual(all[0].providerId, "opencodego")
  const codex = all[1]
  assert.strictEqual(codex.providerId, "codex")
  assert.strictEqual(codex.error, "provider: auth required")
  assert.strictEqual(codex.hasData, false)
  assert.strictEqual(codex.windows.length, 0)
  const valid = model.validProviders(withErrors)
  assert.strictEqual(valid.length, 1)
  assert.strictEqual(valid[0].providerId, "opencodego")
}
console.log("PASS: errors are isolated and valid providers are filtered")

// Fixture 3: credits + identity + status surface on the record.
const rich = [
  {
    provider: "claude",
    source: "web",
    usage: {
      updatedAt: "2026-08-03T14:00:00Z",
      primary: { usedPercent: 12, resetsAt: "2026-08-03T15:00:00Z", windowMinutes: 300 },
      identity: { providerID: "claude", accountEmail: "user@example.com", loginMethod: "pro" }
    },
    credits: { remaining: 40, total: 50, plan: "Pro" },
    status: { indicator: "none", description: "Operational" }
  }
]
{
  const p = model.normalizeProviders(rich)[0]
  assert.strictEqual(p.providerName, "Claude")
  assert.strictEqual(p.account, "user@example.com")
  assert.strictEqual(p.plan, "pro")
  assert.strictEqual(p.creditsRemaining, 40)
  assert.strictEqual(p.creditsTotal, 50)
  assert.strictEqual(p.statusIndicator, "")
  assert.strictEqual(p.headlinePercent, 0.12)
  assert.strictEqual(p.hasData, true)
}
console.log("PASS: credits, identity, and status are normalized")

// Fixture 4: providers with no windows and no credits are not "valid".
const empty = [{ provider: "wayfinder", source: "auto", error: { message: "gateway down" } }]
{
  assert.strictEqual(model.validProviders(empty).length, 0)
  const p = model.normalizeProvider(empty[0])
  assert.strictEqual(p.error, "gateway down")
  assert.strictEqual(p.hasData, false)
}
console.log("PASS: providers without usable data stay out of the panel")

// Fixture 5: unknown providers get a readable fallback name.
{
  assert.strictEqual(model.providerDisplayName("codex"), "Codex")
  assert.strictEqual(model.providerDisplayName("opencodego"), "OpenCode Go")
  assert.strictEqual(model.providerDisplayName("brand-new-provider"), "Brand New Provider")
  assert.strictEqual(model.windowTitleForMinutes(300), "5-Hour")
  assert.strictEqual(model.windowTitleForMinutes(10080), "Weekly")
  assert.strictEqual(model.windowTitleForMinutes(43200), "Monthly")
  assert.strictEqual(model.windowTitleForMinutes(1440), "1d")
  assert.strictEqual(model.windowTitleForMinutes(60), "1h")
  assert.strictEqual(model.windowTitleForMinutes(30), "30m")
}
console.log("PASS: provider names and window titles are human-readable")

// Fixture 6: cost daily buckets map to the day chart, and a merge can make a
// tokens-only provider valid.
{
  const cost = model.normalizeCost({
    provider: "codex", source: "local", historyDays: 30, updatedAt: "2026-08-03T14:40:38Z",
    daily: [
      { date: "2026-08-02", totalTokens: 125000, inputTokens: 50000, outputTokens: 75000 },
      { date: "2026-08-01", totalTokens: 64000 }
    ]
  })
  assert.strictEqual(cost.recentDays.length, 2)
  assert.strictEqual(cost.recentDays[0].date, "2026-08-01")
  assert.strictEqual(cost.recentDays[0].messageCount, 64000)
  assert.strictEqual(cost.recentDays[1].date, "2026-08-02")
  assert.strictEqual(cost.recentDays[1].messageCount, 125000)
  assert.strictEqual(cost.updatedAt, "2026-08-03T14:40:38Z")

  const tokenOnly = model.normalizeProvider({ provider: "brand-x", source: "local" })
  assert.strictEqual(tokenOnly.hasData, false)
  tokenOnly.recentDays = [{ date: "2026-08-03", messageCount: 100 }]
  assert.strictEqual(model.filterValid([tokenOnly]).length, 1)
  assert.strictEqual(model.filterValid([tokenOnly])[0].hasData, true)
}
console.log("PASS: daily token history merges and can earn a provider a seat")

// Fixture 7: vendored brand marks resolve, unknown providers fall back.
{
  assert.strictEqual(model.providerIconBase("opencodego"), "opencodego")
  assert.strictEqual(model.providerIconBase("codex"), "codex")
  assert.strictEqual(model.providerIconBase("brand-new-provider"), "")
  assert.strictEqual(model.normalizeProvider({ provider: "opencodego" }).iconBase, "opencodego")
}
console.log("PASS: provider icon bases map to vendored assets")

// Fixture 8: the 0.53 schema — `pace` forecasts and `usage.providerCost`
// replace the old top-level `credits`.
const newSchema = [
  {
    provider: "opencodego",
    source: "web",
    usage: {
      updatedAt: "2026-08-18T23:26:41Z",
      primary: { usedPercent: 8, resetsAt: "2026-08-18T23:30:56Z", windowMinutes: 300 },
      secondary: { usedPercent: 25, resetsAt: "2026-08-23T23:59:59Z", windowMinutes: 10080 },
      tertiary: { usedPercent: 54, resetsAt: "2026-08-27T01:24:05Z", windowMinutes: 43200 },
      providerCost: { currencyCode: "USD", period: "Zen balance", used: 8.5, limit: 0, updatedAt: "2026-08-18T23:26:41Z" }
    },
    pace: {
      primary: { expectedUsedPercent: 99, deltaPercent: -91, stage: "farBehind", willLastToReset: true, summary: "91% in reserve | Expected 99% used | Lasts until reset" },
      secondary: { expectedUsedPercent: 28, deltaPercent: -3, stage: "slightlyBehind", willLastToReset: true, summary: "3% in reserve | Expected 28% used | Lasts until reset" },
      tertiary: { expectedUsedPercent: 74, deltaPercent: -20, stage: "farBehind", willLastToReset: true, summary: "20% in reserve | Expected 74% used | Lasts until reset" }
    }
  }
]
{
  const p = model.normalizeProviders(newSchema)[0]
  assert.strictEqual(p.windows.length, 3)
  assert.strictEqual(p.windows[0].pace.stage, "farBehind")
  assert.strictEqual(p.windows[0].pace.expectedPercent, 0.99)
  assert.strictEqual(p.windows[0].pace.willLastToReset, true)
  assert.strictEqual(p.windows[2].pace.stage, "farBehind")
  assert.strictEqual(p.windows[2].pace.willLastToReset, true)
  // A zero providerCost limit is spend, not a credit pool -> no balance shown.
  assert.strictEqual(p.creditsRemaining, null)
  assert.strictEqual(p.creditsTotal, null)
}
console.log("PASS: 0.53 pace forecasts normalize per window")

// Fixture 9: providerCost with a positive limit becomes a credit balance.
{
  const p = model.normalizeProvider({
    provider: "claude", source: "web",
    usage: { providerCost: { currencyCode: "USD", period: "Pro", used: 18.5, limit: 50, updatedAt: "2026-08-18T23:00:00Z" } }
  })
  assert.strictEqual(p.creditsRemaining, 31.5)
  assert.strictEqual(p.creditsUsed, 18.5)
  assert.strictEqual(p.creditsTotal, 50)
  assert.strictEqual(p.plan, "Pro")
}
console.log("PASS: providerCost with a positive limit maps to credits")

// Fixture 10: renamed provider ids keep pretty names and vendored icons.
{
  assert.strictEqual(model.providerDisplayName("groqcloud"), "GroqCloud")
  assert.strictEqual(model.providerIconBase("groqcloud"), "groq")
  assert.strictEqual(model.providerDisplayName("azure-openai"), "Azure OpenAI")
  assert.strictEqual(model.providerIconBase("azure-openai"), "azureopenai")
  assert.strictEqual(model.providerDisplayName("alibaba-coding-plan"), "Alibaba Coding Plan")
  assert.strictEqual(model.providerIconBase("alibaba-coding-plan"), "alibaba")
  assert.strictEqual(model.providerDisplayName("qwen-cloud"), "Qwen Cloud")
  assert.strictEqual(model.providerIconBase("qwen-cloud"), "")
}
console.log("PASS: renamed and new provider ids are human-readable")

// Fixture 11: the dev mock covers every renderable field and stays valid.
{
  const mock = model.mockProviderList()
  assert.strictEqual(mock.length, 1)
  const p = mock[0]
  assert.strictEqual(p.providerId, "mock")
  assert.strictEqual(p.hasData, true)
  assert.strictEqual(p.windows.length, 3)
  assert.ok(p.windows.every(function(w) { return w.pace }), "every mock window carries pace")
  assert.strictEqual(p.creditsRemaining, 31.5)
  assert.ok(p.recentDays.length > 0, "mock carries daily token history")
  assert.strictEqual(p.account, "dev@example.com")
  assert.ok(p.windows.some(function(w) { return !w.pace.willLastToReset }), "mock shows a run-out forecast too")
}
console.log("PASS: dev mock exercises the full provider surface")

console.log("ALL MODEL TESTS PASS")
