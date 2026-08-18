// Pure normalization of `codexbar serve` payloads into the flat provider
// records the panel renders. Kept free of QML and module systems so it runs
// both as a QML JS library (`import "codexbar.js" as Cbx`) and under
// Node for the fixture tests.

var PROVIDER_NAMES = {
  codex: "Codex",
  openai: "OpenAI",
  "azure-openai": "Azure OpenAI",
  azureopenai: "Azure OpenAI",
  claude: "Claude",
  clinepass: "Clinepass",
  cursor: "Cursor",
  opencode: "OpenCode",
  opencodego: "OpenCode Go",
  "alibaba-coding-plan": "Alibaba Coding Plan",
  alibaba: "Alibaba Coding Plan",
  "alibaba-token-plan": "Alibaba Token Plan",
  alibabatokenplan: "Alibaba Token Plan",
  "qwen-cloud": "Qwen Cloud",
  factory: "Droid",
  fireworks: "Fireworks",
  gemini: "Gemini",
  antigravity: "Antigravity",
  copilot: "GitHub Copilot",
  devin: "Devin",
  zai: "z.ai",
  minimax: "MiniMax",
  manus: "Manus",
  kimi: "Kimi",
  kilo: "Kilo",
  kiro: "Kiro",
  vertexai: "Vertex AI",
  augment: "Augment",
  jetbrains: "JetBrains AI",
  kimik2: "Kimi K2",
  moonshot: "Moonshot",
  amp: "Amp",
  t3chat: "T3 Chat",
  ollama: "Ollama",
  synthetic: "Synthetic",
  warp: "Warp",
  openrouter: "OpenRouter",
  elevenlabs: "ElevenLabs",
  windsurf: "Windsurf",
  zed: "Zed",
  perplexity: "Perplexity",
  mimo: "Xiaomi MiMo",
  doubao: "Doubao",
  sakana: "Sakana AI",
  abacusai: "Abacus AI",
  abacus: "Abacus AI",
  mistral: "Mistral",
  deepseek: "DeepSeek",
  deepinfra: "DeepInfra",
  codebuff: "Codebuff",
  crof: "Crof",
  venice: "Venice",
  commandcode: "Command Code",
  qoder: "Qoder",
  stepfun: "StepFun",
  bedrock: "AWS Bedrock",
  grok: "Grok",
  groqcloud: "GroqCloud",
  groq: "GroqCloud",
  llmproxy: "LLM Proxy",
  litellm: "LiteLLM",
  deepgram: "Deepgram",
  poe: "Poe",
  chutes: "Chutes",
  neuralwatt: "NeuralWatt",
  crossmodel: "CrossModel",
  clawrouter: "ClawRouter",
  longcat: "Longcat",
  sub2api: "Sub2API",
  zenmux: "ZenMux",
  aiand: "AI&",
  zoommate: "ZoomMate",
  xai: "xAI",
  notion: "Notion",
  ibmbob: "IBM Bob",
  wayfinder: "Wayfinder"
}

function toNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function cleanText(value) {
  var text = String(value == null ? "" : value).trim()
  return text === "null" ? "" : text
}

function titleCase(text) {
  var words = String(text || "").split(/[^A-Za-z0-9]+/).filter(function(w) { return w !== "" })
  for (var i = 0; i < words.length; i++) {
    var word = words[i]
    words[i] = word.charAt(0).toUpperCase() + word.slice(1)
  }
  return words.join(" ")
}

function providerDisplayName(id) {
  var name = PROVIDER_NAMES[id]
  if (name) return name
  return titleCase(id)
}

// Brand marks vendored under assets/icons/<id>.svg (dark variant) and
// <id>-light.svg (light variant) from @lobehub/icons-static-svg. Providers
// without a vendored mark fall back to an initials tile in the UI.
var PROVIDER_ICONS = [
  "codex", "openai", "azureopenai", "claude", "cursor", "opencode", "opencodego",
  "alibaba", "alibabatokenplan", "gemini", "antigravity", "copilot", "devin",
  "zai", "minimax", "manus", "kimi", "kilo", "kiro", "vertexai", "kimik2",
  "moonshot", "ollama", "openrouter", "elevenlabs", "windsurf", "perplexity",
  "mimo", "doubao", "mistral", "deepseek", "venice", "qoder", "stepfun",
  "bedrock", "grok", "groq", "poe"
]

function providerIconBase(id) {
  for (var i = 0; i < PROVIDER_ICONS.length; i++) {
    if (PROVIDER_ICONS[i] === id) return id
  }
  return ICON_ALIASES[id] || ""
}

// Provider ids that renamed in the CLI map to the still-vendored icon asset
// (the SVG filename predates the rename).
var ICON_ALIASES = {
  "azure-openai": "azureopenai",
  "alibaba-coding-plan": "alibaba",
  "alibaba-token-plan": "alibabatokenplan",
  groqcloud: "groq",
  abacusai: "abacus"
}

// windowMinutes -> short human title. CodexBar's three canonical windows are
// 300 (5h), 10080 (7d), and 43200 (30d); anything else gets a compact label.
function windowTitleForMinutes(minutes) {
  var mins = toNumber(minutes, 0)
  if (mins <= 0) return "Usage"
  if (mins === 300) return "5-Hour"
  if (mins === 10080) return "Weekly"
  if (mins === 43200) return "Monthly"
  if (mins % 1440 === 0) return (mins / 1440) + "d"
  if (mins % 60 === 0) return (mins / 60) + "h"
  return mins + "m"
}

function normalizeWindow(raw, fallbackTitle, paceRaw) {
  if (!raw || typeof raw !== "object") return null
  var percent = toNumber(raw.usedPercent, -1) / 100
  if (!(percent >= 0)) percent = -1
  var windowMinutes = toNumber(raw.windowMinutes, 0)
  var pace = null
  if (paceRaw && typeof paceRaw === "object" && percent >= 0) {
    var expected = toNumber(paceRaw.expectedUsedPercent, -1) / 100
    pace = {
      expectedPercent: Math.min(1, Math.round(expected * 1000000) / 1000000),
      deltaPercent: toNumber(paceRaw.deltaPercent, null),
      willLastToReset: paceRaw.willLastToReset === true,
      stage: cleanText(paceRaw.stage),
      summary: cleanText(paceRaw.summary)
    }
  }
  return {
    title: windowTitleForMinutes(windowMinutes) || fallbackTitle || "Usage",
    percent: Math.min(1, Math.round(percent * 1000000) / 1000000),
    resetAt: cleanText(raw.resetsAt),
    windowMinutes: windowMinutes,
    pace: pace
  }
}

function normalizeWindows(usage, paces) {
  var out = []
  if (!usage || typeof usage !== "object") return out
  var order = ["primary", "secondary", "tertiary"]
  paces = paces || {}
  for (var i = 0; i < order.length; i++) {
    var w = normalizeWindow(usage[order[i]], null, paces[order[i]])
    if (!w || w.percent < 0) continue
    // The primary window is a session limit whose length varies by provider,
    // so it keeps one stable label instead of a duration that only fits some.
    if (order[i] === "primary") w.title = "Session"
    out.push(w)
  }
  return out
}

// Credits/balance. The CLI used to report a top-level `credits` object; 0.53
// moved spend into `usage.providerCost` (currencyCode, period, used, limit,
// updatedAt). Both shapes are honored. providerCost only counts as a balance
// when it carries a positive limit — a zero limit (e.g. OpenCode Go's "Zen
// balance") is a spend figure, not a credit pool, so it stays null.
function normalizeCredits(credits, usage) {
  var remaining = null
  var used = null
  var total = null
  var plan = ""
  if (credits && typeof credits === "object") {
    remaining = toNumber(credits.remaining, null)
    if (remaining === null) remaining = toNumber(credits.balance, null)
    if (remaining === null) remaining = toNumber(credits.credits, null)
    used = toNumber(credits.used, null)
    total = toNumber(credits.total, null)
    if (total === null) total = toNumber(credits.limit, null)
    plan = cleanText(credits.plan)
  }
  var pc = usage && usage.providerCost && typeof usage.providerCost === "object" ? usage.providerCost : null
  if (pc) {
    var limit = toNumber(pc.limit, 0)
    var spent = toNumber(pc.used, null)
    if (limit > 0) {
      total = limit
      if (spent !== null) {
        used = spent
        remaining = Math.max(0, limit - spent)
      }
    }
    if (plan === "" && cleanText(pc.period) !== "") plan = cleanText(pc.period)
  }
  return { remaining: remaining, used: used, total: total, plan: plan }
}

function normalizeIdentity(provider) {
  var account = ""
  var plan = ""
  var usage = provider.usage
  if (usage && usage.identity && typeof usage.identity === "object") {
    account = cleanText(usage.identity.accountEmail) || account
    plan = cleanText(usage.identity.loginMethod) || plan
    if (plan === "" && usage.identity.accountOrganization) plan = cleanText(usage.identity.accountOrganization)
  }
  if (account === "") account = cleanText(provider.accountEmail)
  if (account === "") account = cleanText(provider.account)
  return { account: account, plan: plan }
}

function normalizeStatus(status) {
  if (!status || typeof status !== "object") {
    return { indicator: "", text: "" }
  }
  var indicator = cleanText(status.indicator)
  return {
    indicator: indicator === "none" ? "" : indicator,
    text: cleanText(status.description)
  }
}

// One `codexbar serve` usage entry (with or without an error) -> flat record.
function normalizeProvider(raw) {
  var providerId = cleanText(raw && raw.provider)
  var error = null
  if (raw && raw.error && typeof raw.error === "object") {
    error = {
      message: cleanText(raw.error.message),
      kind: cleanText(raw.error.kind)
    }
  }

  var usage = (raw && raw.usage) || {}
  var windows = error ? [] : normalizeWindows(usage, raw && raw.pace)
  var credits = error ? { remaining: null, used: null, total: null, plan: "" } : normalizeCredits(raw && raw.credits, usage)
  var identity = error ? { account: "", plan: "" } : normalizeIdentity(raw || {})
  var status = error ? { indicator: "", text: "" } : normalizeStatus(raw && raw.status)

  var headlinePercent = -1
  for (var i = 0; i < windows.length; i++) {
    if (windows[i].percent > headlinePercent) headlinePercent = windows[i].percent
  }

  return {
    providerId: providerId,
    providerName: providerDisplayName(providerId),
    source: cleanText(raw && raw.source),
    updatedAt: cleanText(usage.updatedAt || (raw && raw.updatedAt)),
    updatedAtMs: usage.updatedAt ? Date.parse(String(usage.updatedAt)) : 0,
    windows: windows,
    headlinePercent: headlinePercent,
    creditsRemaining: credits.remaining,
    creditsUsed: credits.used,
    creditsTotal: credits.total,
    plan: identity.plan || credits.plan,
    account: identity.account,
    iconBase: providerIconBase(providerId),
    statusIndicator: status.indicator,
    statusText: status.text,
    error: error ? (error.kind ? error.kind + ": " : "") + error.message : "",
    // Populated by the /cost merge (codexbar.js normalizeCost), never by
    // guessing: empty until a provider actually reports token history.
    recentDays: [],
    dailyUpdatedAt: "",
    hasData: providerHasData(error, windows.length, credits.remaining, [])
  }
}

// A provider earns a seat when it reports limits, credits, or a daily token
// history. recentDays is checked live so a post-merge record can flip valid.
function providerHasData(error, windowCount, creditsRemaining, recentDays) {
  if (error) return false
  return windowCount > 0 || creditsRemaining !== null || (recentDays && recentDays.length > 0)
}

// `codexbar cost` daily buckets -> the native widget's recentDays rows so the
// panel can reuse the same day-chart rendering. totalTokens is what CodexBar
// reports per day; there is no per-model token split, only per-model cost.
function normalizeCost(raw) {
  if (!raw || typeof raw !== "object") return { recentDays: [], updatedAt: "" }
  var days = Array.isArray(raw.daily) ? raw.daily : []
  var out = []
  for (var i = 0; i < days.length; i++) {
    var d = days[i] || {}
    var date = cleanText(d.date)
    if (date === "") continue
    var tokens = Math.round(toNumber(d.totalTokens, 0))
    if (tokens < 0) tokens = 0
    out.push({ date: date, messageCount: tokens })
  }
  out.sort(function(a, b) { return a.date < b.date ? -1 : (a.date > b.date ? 1 : 0) })
  return {
    recentDays: out,
    updatedAt: cleanText(raw.updatedAt)
  }
}

// Filter already-normalized records (after a cost merge) down to the ones the
// panel shows, recomputing validity so daily-only providers count.
function filterValid(records) {
  var out = []
  if (!Array.isArray(records)) return out
  for (var i = 0; i < records.length; i++) {
    var p = records[i]
    if (!p) continue
    p.hasData = providerHasData(p.error, p.windows.length, p.creditsRemaining, p.recentDays)
    if (p.hasData) out.push(p)
  }
  return out
}

// Sort so the providers running hottest lead the list; keep the order stable
// otherwise by remembering the original index.
function normalizeProviders(rawList) {
  var out = []
  if (!Array.isArray(rawList)) return out
  for (var i = 0; i < rawList.length; i++) {
    var p = normalizeProvider(rawList[i])
    if (p.providerId !== "") out.push(p)
  }
  out.sort(function(a, b) {
    var ah = a.hasData ? Math.max(0, a.headlinePercent) : -1
    var bh = b.hasData ? Math.max(0, b.headlinePercent) : -1
    return bh - ah
  })
  return out
}

function validProviders(rawList) {
  var all = normalizeProviders(rawList)
  var out = []
  for (var i = 0; i < all.length; i++) {
    if (all[i].hasData) out.push(all[i])
  }
  return out
}

// Dev-only: one curated provider that exercises every field the panel can
// render, so a maintainer who does not have real access to a provider can
// still see the full UI. It is never injected unless Main.qml is told to via
// the `devMock` setting (default off) — end users never see it.
function mockProviderList() {
  var now = new Date()
  function iso(daysFromNow) {
    var d = new Date(now.getTime() + daysFromNow * 86400000)
    return d.toISOString()
  }
  function day(offset, tokens) {
    var d = new Date(now.getTime() + offset * 86400000)
    return d.getFullYear()
      + "-" + String(d.getMonth() + 1).padStart(2, "0")
      + "-" + String(d.getDate()).padStart(2, "0")
  }
  var raw = {
    provider: "mock",
    source: "web",
    account: "dev@example.com",
    usage: {
      updatedAt: iso(0),
      primary: { usedPercent: 82, resetsAt: iso(1), windowMinutes: 300 },
      secondary: { usedPercent: 44, resetsAt: iso(2), windowMinutes: 10080 },
      tertiary: { usedPercent: 71, resetsAt: iso(5), windowMinutes: 43200 },
      providerCost: { currencyCode: "USD", period: "Pro", used: 18.5, limit: 50, updatedAt: iso(0) }
    },
    pace: {
      primary: { expectedUsedPercent: 100, deltaPercent: -92, stage: "farBehind", willLastToReset: true, summary: "92% in reserve | Expected 100% used | Lasts until reset" },
      secondary: { expectedUsedPercent: 30, deltaPercent: 4, stage: "aheadOfPace", willLastToReset: true, summary: "4% ahead of pace | Expected 30% used | Lasts until reset" },
      tertiary: { expectedUsedPercent: 90, deltaPercent: -55, stage: "farBehind", willLastToReset: false, summary: "55% in reserve | Expected 90% used | Runs out before reset" }
    }
  }
  var rec = normalizeProvider(raw)
  rec.recentDays = [
    { date: day(-6, 120000), messageCount: 120000 },
    { date: day(-5, 180000), messageCount: 180000 },
    { date: day(-4, 90000), messageCount: 90000 },
    { date: day(-3, 260000), messageCount: 260000 },
    { date: day(-2, 140000), messageCount: 140000 },
    { date: day(-1, 210000), messageCount: 210000 },
    { date: day(0, 75000), messageCount: 75000 }
  ]
  rec.dailyUpdatedAt = iso(0)
  rec.hasData = providerHasData(rec.error, rec.windows.length, rec.creditsRemaining, rec.recentDays)
  return [rec]
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    providerDisplayName: providerDisplayName,
    providerIconBase: providerIconBase,
    windowTitleForMinutes: windowTitleForMinutes,
    normalizeProvider: normalizeProvider,
    normalizeProviders: normalizeProviders,
    normalizeCost: normalizeCost,
    validProviders: validProviders,
    filterValid: filterValid,
    mockProviderList: mockProviderList
  }
}
