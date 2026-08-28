// Formatting and derivation for BTC Watcher. Pure functions on plain data, so
// the bar and the panel phrase the same numbers the same way and neither
// needs to know where they came from.

.pragma library

var WINDOW_LABELS = {
  "10m": "10 min",
  "15m": "15 min",
  "30m": "30 min",
  "1h": "1 hour",
  "6h": "6 hours",
  "12h": "12 hours",
  "24h": "24 hours"
};

// Symbols for the currencies people actually pick; everything else falls back
// to its code, which is honest and fits the bar.
var SYMBOLS = {
  USD: "$", EUR: "€", GBP: "£", JPY: "¥", CNY: "¥", CHF: "CHF",
  AUD: "A$", CAD: "C$", NZD: "NZ$", SEK: "kr", NOK: "kr", DKK: "kr",
  PLN: "zł", CZK: "Kč", HUF: "Ft", RUB: "₽", TRY: "₺", INR: "₹",
  KRW: "₩", BRL: "R$", MXN: "MX$", ZAR: "R", ILS: "₪", THB: "฿"
};

function currencySymbol(code) {
  var key = String(code || "").toUpperCase();
  return SYMBOLS[key] || key;
}

function windowLabel(key) {
  return WINDOW_LABELS[key] || String(key || "");
}

/**
 * Read a boolean setting.
 *
 * `omarchy bar set` writes into shell.json as text, so a switch that was
 * turned off arrives as the string "false" — which is truthy, and compares
 * unequal to the boolean. Anything reading these has to accept both spellings
 * or the switch silently does nothing.
 */
function flag(value, fallback) {
  if (value === undefined || value === null) return fallback;
  if (typeof value === "boolean") return value;
  var text = String(value).toLowerCase();
  if (text === "false" || text === "0" || text === "no" || text === "off") return false;
  if (text === "true" || text === "1" || text === "yes" || text === "on") return true;
  return fallback;
}

// Grouped with a plain space rather than a locale separator: a period between
// thousands reads as a decimal point at small sizes. A thin space (U+2009) is
// the typographically correct separator and was the first attempt, but at bar
// size it renders as no gap at all — "67479" — so the honest choice is the
// space that actually shows.
function groupDigits(value) {
  var s = String(Math.round(value));
  var out = "";
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 === 0) out += " ";
    out += s.charAt(i);
  }
  return out;
}

function formatPrice(value, currency) {
  if (value === null || value === undefined || isNaN(value)) return "";
  var symbol = currencySymbol(currency);
  // Below a thousand the decimals matter; above, they are noise on a value
  // that moves by more than a cent between two blinks.
  var body = value >= 1000 ? groupDigits(value) : value.toFixed(2);
  return symbol.length === 1 ? symbol + body : body + " " + symbol;
}

function formatChange(pct, opts) {
  if (pct === null || pct === undefined || isNaN(pct)) return "–";
  var digits = (opts && opts.digits !== undefined) ? opts.digits : 1;
  var arrow = pct > 0 ? "▲" : (pct < 0 ? "▼" : "–");
  var body = Math.abs(pct).toFixed(digits) + " %";
  return (opts && opts.bare) ? body : arrow + " " + body;
}

function changeSign(pct) {
  if (pct === null || pct === undefined || isNaN(pct)) return 0;
  return pct > 0 ? 1 : (pct < 0 ? -1 : 0);
}

function formatHeight(height) {
  if (height === null || height === undefined) return "";
  return "▦ " + groupDigits(height);
}

function formatAge(seconds) {
  if (seconds === null || seconds === undefined) return "";
  var minutes = Math.floor(seconds / 60);
  if (minutes < 60) return minutes + "m";
  var hours = Math.floor(minutes / 60);
  return hours + "h" + (minutes % 60) + "m";
}

function formatHashrate(hps) {
  if (!hps || isNaN(hps)) return "–";
  var units = ["H/s", "kH/s", "MH/s", "GH/s", "TH/s", "PH/s", "EH/s", "ZH/s"];
  var i = 0;
  var v = hps;
  while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
  return v.toFixed(v < 10 ? 2 : 0) + " " + units[i];
}

function formatCount(n) {
  if (n === null || n === undefined || isNaN(n)) return "–";
  return groupDigits(n);
}

// "in 12 days" / "in 5 hours" — a retarget or halving is never worth a clock.
function formatEta(timestampSeconds, nowSeconds) {
  if (!timestampSeconds) return "–";
  var delta = timestampSeconds - (nowSeconds || Math.floor(Date.now() / 1000));
  if (delta <= 0) return "due";
  var hours = Math.round(delta / 3600);
  if (hours < 48) return "in " + hours + " h";
  return "in " + Math.round(hours / 24) + " days";
}

function formatFee(satsPerVb) {
  if (satsPerVb === null || satsPerVb === undefined) return "–";
  return satsPerVb + " sat/vB";
}

// A modern single-input, two-output transaction is about 140 vB. Nobody thinks
// in sat/vB when deciding whether to send now — they think in money, so the
// fee rate is turned into what it actually costs.
var TYPICAL_TX_VBYTES = 140;

function formatFeeCost(satsPerVb, price, currency) {
  if (satsPerVb === null || satsPerVb === undefined) return "–";
  var line = satsPerVb + " sat/vB";
  if (!price || price <= 0) return line;
  var cost = satsPerVb * TYPICAL_TX_VBYTES / 100000000 * price;
  var symbol = currencySymbol(currency);
  var money = cost < 10 ? cost.toFixed(2) : String(Math.round(cost));
  return line + "  ·  " + (symbol.length === 1 ? symbol + money : money + " " + symbol);
}

// A block holds roughly 1 vMB, so the backlog in vMB is close enough to "how
// many blocks before mine gets in" to be the honest way to say it.
function formatMempool(vsize) {
  if (!vsize || isNaN(vsize)) return "–";
  var blocks = Math.round(vsize / 1000000);
  var mood = blocks <= 2 ? "empty" : (blocks <= 12 ? "normal" : (blocks <= 60 ? "busy" : "congested"));
  return mood + "  ·  " + blocks + (blocks === 1 ? " block deep" : " blocks deep");
}

// Sats per unit of currency — the figure that answers "what do I get for one
// euro", which is the direction people actually think in when stacking.
function satsPerUnit(price) {
  if (!price || price <= 0) return null;
  return 100000000 / price;
}

function formatSatsPerUnit(price, currency) {
  var sats = satsPerUnit(price);
  if (!sats) return "–";
  return groupDigits(sats) + " sat / " + currencySymbol(currency);
}

// U+20BF BITCOIN SIGN. A plain character rather than a Nerd Font glyph, so it
// survives a theme whose font has no icon range.
var ICON = "\u20BF";

// What the pill can carry. Order here is the order they appear, so the
// switches and the bar always agree without a second list to keep in sync.
var DISPLAY_PARTS = ["price", "change", "block"];

function displayLabel(part) {
  switch (part) {
    case "change": return "Change";
    case "block": return "Block";
    default: return "Price";
  }
}

/**
 * The selected parts, in canonical order.
 *
 * Stored as a comma-separated list. The two single-value spellings from the
 * first version are still understood, so an existing shell.json keeps working
 * instead of silently falling back to the default.
 */
function displayList(settings) {
  var raw = String((settings && settings.display) || "price,change");
  var wanted = raw.split(",");
  var chosen = [];

  for (var i = 0; i < wanted.length; i++) {
    var part = wanted[i].replace(/^\s+|\s+$/g, "");
    if (part === "height") part = "block";
    if (part === "price+change") { chosen.push("price"); chosen.push("change"); continue; }
    if (DISPLAY_PARTS.indexOf(part) >= 0) chosen.push(part);
  }

  var ordered = [];
  for (var j = 0; j < DISPLAY_PARTS.length; j++) {
    if (chosen.indexOf(DISPLAY_PARTS[j]) >= 0) ordered.push(DISPLAY_PARTS[j]);
  }
  // Matches the manifest default, so a fresh install looks like the README.
  return ordered.length > 0 ? ordered : ["price", "change"];
}

/**
 * What the bar pill says. Returns "" when there is nothing to show, which
 * hides the widget rather than parking an empty box in the bar.
 */
function barText(data, settings) {
  if (!data) return "";

  var currency = (settings && settings.currency) || "EUR";
  var win = (settings && settings.changeWindow) || "24h";
  var showIcon = flag(settings && settings.showIcon, true);

  var price = data.price ? data.price.value : null;
  var change = (data.price && data.price.change) ? data.price.change[win] : null;
  var chain = data.chain || null;

  var parts = displayList(settings);
  var out = [];

  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "price" && price !== null) out.push(formatPrice(price, currency));
    else if (parts[i] === "change" && price !== null) out.push(formatChange(change));
    else if (parts[i] === "block" && chain) out.push(formatHeight(chain.height) + " · " + formatAge(chain.tip_age_s));
  }

  if (out.length === 0) return "";
  var body = out.join("  ");
  return showIcon ? ICON + " " + body : body;
}

function tooltipText(data, settings) {
  if (!data) return "BTC Watcher";
  var currency = (settings && settings.currency) || "EUR";
  var win = (settings && settings.changeWindow) || "24h";
  var parts = [];
  if (data.price) {
    parts.push(formatPrice(data.price.value, currency));
    var c = data.price.change ? data.price.change[win] : null;
    if (c !== null && c !== undefined)
      parts.push(formatChange(c) + " (" + windowLabel(win) + ")");
  }
  if (data.chain) parts.push(formatHeight(data.chain.height));
  return parts.length ? parts.join(" · ") : "BTC Watcher";
}

/**
 * Decide whether a move deserves a notification.
 *
 * Returns null, or { direction: "up"|"down", percent, window }.
 * Thresholds of 0 mean "off". The caller owns the quiet period; this only
 * answers whether the threshold is crossed right now.
 */
function pendingAlert(data, settings) {
  if (!data || !data.price || !data.price.change) return null;
  var win = (settings && settings.notifyWindow) || "1h";
  var change = data.price.change[win];
  if (change === null || change === undefined || isNaN(change)) return null;

  // Same reasoning as the widget: a hand-edited shell.json must not turn a
  // threshold into NaN, which compares false against everything and would
  // silently disable the alert the user thought they had set.
  var up = Number((settings && settings.notifyUpPercent) || 0);
  var down = Number((settings && settings.notifyDownPercent) || 0);
  if (!isFinite(up)) up = 0;
  if (!isFinite(down)) down = 0;

  if (up > 0 && change >= up) return { direction: "up", percent: change, window: win };
  if (down > 0 && change <= -down) return { direction: "down", percent: change, window: win };
  return null;
}
