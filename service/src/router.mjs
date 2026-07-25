// Auto model routing. Given a chat message plus a few *structural* signals (which
// button was pressed, whether a single todo is pinned via the 💬 bar, the shape of
// the message, the tier of the ongoing conversation), pick a tier — model + effort
// + turn budget. Pure and deterministic: no pre-flight LLM call, so the everyday
// fast path never pays a classification round-trip.
//
// The chat handler calls this only when the picker is on "Auto"; an explicit model
// choice always wins upstream and skips the router entirely.

// Effort is never set on Haiku (the raw API rejects effort on Haiku 4.5), so the
// fast tier leaves it undefined. Default-when-uncertain is Sonnet, not Haiku:
// misrouting *up* costs ~2s and pennies; misrouting a real task *down* to Haiku
// costs quality.
export const TIERS = {
  fast: { tier: "fast", model: "haiku", effort: undefined, maxTurns: 8 },
  standard: { tier: "standard", model: "sonnet", effort: undefined, maxTurns: 24 },
  deep: { tier: "deep", model: "opus", effort: "high", maxTurns: 24 },
};

// Short imperative that maps to one deterministic mutation.
const TRIVIAL_VERB = /^(add|capture|delete|remove|drop|rename|complete|finish|mark|move|park|unpark|star|unstar|today|demote|promote|tag|untag|clear|restore)\b/i;
// Chaining turns a "trivial" edit into a multi-step task.
const CHAINED = /\b(and|then|also|plus)\b|[;,]|\n/i;
// Heavy reasoning / reorganization keywords.
const HEAVY = /\b(review|reorganiz|reorganise|clean\s?up|declutter|tidy|triage|re?prioriti[sz]e|top\s?5|weekly|audit|overhaul|restructur|consolidat)|\bplan (my|the) (day|week)\b/i;

const withReason = (tier, reason) => ({ ...TIERS[tier], reason });

// → { tier, model, effort, maxTurns, reason }
export function routeTier({ message = "", context = null, intent = null, prevTier = null } = {}) {
  const text = String(message || "").trim();

  // 1. Explicit heavy intent from a button (weekly review / plan my day / tidy).
  if (["review", "plan", "tidy"].includes(intent)) return withReason("deep", `${intent} intent`);

  // 2. A single todo is pinned via the 💬 bar — the item is already resolved, so the
  //    model only has to interpret the verb. Fast, unless the instruction itself is
  //    heavy or long (then let Sonnet handle it).
  if (context && context.id) {
    if (HEAVY.test(text) || text.length > 300) return withReason("standard", "pinned, non-trivial");
    return withReason("fast", "pinned single-item");
  }

  // 3. Trivial single-item edit — short, imperative, no chaining. Checked before the
  //    heavy shape so an incidental keyword ("delete the review notes") stays fast.
  if (text.length <= 120 && TRIVIAL_VERB.test(text) && !CHAINED.test(text)) return withReason("fast", "trivial edit");

  // 4. Heavy shape — reasoning keywords, or a lot of pasted text.
  if (HEAVY.test(text) || text.length > 400) return withReason("deep", "heavy request");

  // 5. Deep-session continuation — a short follow-up ("ok do it", "the second one")
  //    that matched nothing above inherits the ongoing conversation's tier, so the
  //    judgment stays with the model that started the thread. Only inherits *up*
  //    (deep/standard): a short follow-up after a fast edit shouldn't keep Haiku for
  //    what might be a fresh, non-trivial question — fall through to the default.
  if ((prevTier === "deep" || prevTier === "standard") && text.length < 40) return withReason(prevTier, `continues ${prevTier}`);

  // 6. Default when uncertain: Sonnet.
  return withReason("standard", "default");
}
