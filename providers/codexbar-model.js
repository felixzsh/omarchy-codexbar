// Pure normalization of `codexbar serve` payloads into the flat provider
// records the panel renders. Kept free of QML and module systems so it runs
// both as a QML JS library (`import "codexbar-model.js" as Cbx`) and under
// Node for the fixture tests.

var PROVIDER_NAMES = {
  codex: "Codex",
  openai: "OpenAI",
  azureopenai: "Azure OpenAI",
  claude: "Claude",
  cursor: "Cursor",
  opencode: "OpenCode",
  opencodego: "OpenCode Go",
  alibaba: "Alibaba Coding Plan",
  alibabatokenplan: "Alibaba Token Plan",
  factory: "Droid",
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
  abacus: "Abacus AI",
  mistral: "Mistral",
  deepseek: "DeepSeek",
  codebuff: "Codebuff",
  crof: "Crof",
  venice: "Venice",
  commandcode: "Command Code",
  qoder: "Qoder",
  stepfun: "StepFun",
  bedrock: "AWS Bedrock",
  grok: "Grok",
  groq: "GroqCloud",
  llmproxy: "LLM Proxy",
  litellm: "LiteLLM",
  deepgram: "Deepgram",
  poe: "Poe",
  chutes: "Chutes",
  crossmodel: "CrossModel",
  clawrouter: "ClawRouter",
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

function normalizeWindow(raw, fallbackTitle) {
  if (!raw || typeof raw !== "object") return null
  var percent = toNumber(raw.usedPercent, -1) / 100
  if (!(percent >= 0)) percent = -1
  var windowMinutes = toNumber(raw.windowMinutes, 0)
  return {
    title: windowTitleForMinutes(windowMinutes) || fallbackTitle || "Usage",
    percent: Math.min(1, Math.round(percent * 1000000) / 1000000),
    resetAt: cleanText(raw.resetsAt),
    windowMinutes: windowMinutes
  }
}

function normalizeWindows(usage) {
  var out = []
  if (!usage || typeof usage !== "object") return out
  var order = ["primary", "secondary", "tertiary"]
  for (var i = 0; i < order.length; i++) {
    var w = normalizeWindow(usage[order[i]])
    if (w && w.percent >= 0) out.push(w)
  }
  return out
}

function normalizeCredits(credits) {
  if (!credits || typeof credits !== "object") {
    return { remaining: null, used: null, total: null, plan: "" }
  }
  var remaining = toNumber(credits.remaining, null)
  if (remaining === null) remaining = toNumber(credits.balance, null)
  if (remaining === null) remaining = toNumber(credits.credits, null)
  var used = toNumber(credits.used, null)
  var total = toNumber(credits.total, null)
  if (total === null) total = toNumber(credits.limit, null)
  return {
    remaining: remaining,
    used: used,
    total: total,
    plan: cleanText(credits.plan)
  }
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
  var windows = error ? [] : normalizeWindows(usage)
  var credits = error ? { remaining: null, used: null, total: null, plan: "" } : normalizeCredits(raw && raw.credits)
  var identity = error ? { account: "", plan: "" } : normalizeIdentity(raw || {})
  var status = error ? { indicator: "", text: "" } : normalizeStatus(raw && raw.status)

  var headlinePercent = -1
  for (var i = 0; i < windows.length; i++) {
    if (windows[i].percent > headlinePercent) headlinePercent = windows[i].percent
  }

  var hasData = !error && (windows.length > 0 || credits.remaining !== null)

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
    statusIndicator: status.indicator,
    statusText: status.text,
    error: error ? (error.kind ? error.kind + ": " : "") + error.message : "",
    hasData: hasData
  }
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

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    providerDisplayName: providerDisplayName,
    windowTitleForMinutes: windowTitleForMinutes,
    normalizeProvider: normalizeProvider,
    normalizeProviders: normalizeProviders,
    validProviders: validProviders
  }
}
