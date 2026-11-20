// The review queue's groups of proposals (20261123000000_review_groups.sql sorts them), in
// the order they are listed, with what each is and what we'd do with it.

export type GroupKind = "duplicates" | "changes";
export type Advice = "accept" | "look" | "decline";

export type GroupInfo = { key: string; kind: GroupKind; title: string; advice: Advice; why: string };

export const GROUPS: GroupInfo[] = [
  {
    key: "dup_feed_same",
    kind: "duplicates",
    title: "Same store listed twice by one feed",
    advice: "accept",
    why: "Both places come from the same All the Places feed, with the same name and address. Qdoba's feed lists every store once per page of its website (tacos, salads, catering, delivery), so most stores came in several times.",
  },
  {
    key: "dup_feed_variant",
    kind: "duplicates",
    title: "One feed, name or address differs",
    advice: "look",
    why: "Both places come from the same feed and sit close together, but the name or the address isn't quite the same. Usually still one store; sometimes two branches.",
  },
  {
    key: "dup_name_near",
    kind: "duplicates",
    title: "Same name, two sources, within 25 m",
    advice: "accept",
    why: "Two sources describe a place with the same name at nearly the same spot. A different phone is often a chain's central number.",
  },
  {
    key: "dup_name_far",
    kind: "duplicates",
    title: "Same name, two sources, 25 to 75 m apart",
    advice: "look",
    why: "Usually one place with a rough pin, but two branches of a chain can sit this close (a mall and its food court, two corners of one junction).",
  },
  {
    key: "dup_variant",
    kind: "duplicates",
    title: "Names differ",
    advice: "look",
    why: "The brand is written differently (“Dunkin’” and “Dunkin Donuts”), or one name adds a branch or a place (“Starbucks - Birmingham”).",
  },
  {
    key: "chg_website",
    kind: "changes",
    title: "Websites",
    advice: "accept",
    why: "All the Places gives the chain’s own page for this store. What we have now is often a home page or a wrong link (a YouTube channel, a careers site, another shop).",
  },
  {
    key: "chg_address_same",
    kind: "changes",
    title: "Addresses with the same house number",
    advice: "accept",
    why: "Spelling, abbreviations or a suite number differ; the street address is the same.",
  },
  {
    key: "chg_address_other",
    kind: "changes",
    title: "Addresses that differ",
    advice: "look",
    why: "Another house number, or one side has none. The store finder is usually right, but check a few.",
  },
  {
    key: "chg_state_theirs",
    kind: "changes",
    title: "States: the town is in the proposed state",
    advice: "accept",
    why: "The town is a Census place in the proposed state and not in the one we have (Houston filed under Wyoming).",
  },
  {
    key: "chg_state_ours",
    kind: "changes",
    title: "States: the town is in our state",
    advice: "decline",
    why: "The town is a Census place in the state we have and not in the proposed one (Arlington, VA proposed as DC). The feed guessed wrong near a state line.",
  },
  {
    key: "chg_state_unclear",
    kind: "changes",
    title: "States: the town list can’t tell",
    advice: "look",
    why: "Towns with the same name on both sides of a state line (Kansas City, Bristol), or towns not in the Census list.",
  },
  {
    key: "chg_name",
    kind: "changes",
    title: "Names",
    advice: "look",
    why: "Store finders sometimes add a store number or a town to the name.",
  },
  {
    key: "chg_other",
    kind: "changes",
    title: "Phones, ZIP codes, towns and pins",
    advice: "look",
    why: "Few of these; check them one by one.",
  },
  {
    key: "chg_status",
    kind: "changes",
    title: "Closures and places missing from loads",
    advice: "look",
    why: "A source says a place closed or reopened, or a place was missing from two loads.",
  },
];

export const GROUP = Object.fromEntries(GROUPS.map((g) => [g.key, g])) as Record<string, GroupInfo>;

export const ADVICE_LABEL: Record<Advice, string> = { accept: "I’d accept", look: "Look first", decline: "I’d decline" };

// The words on the buttons, by kind.
export const VERBS: Record<GroupKind, { accept: string; decline: string; accepted: string; declined: string }> = {
  duplicates: { accept: "Merge", decline: "Keep separate", accepted: "Merged", declined: "Kept separate" },
  changes: { accept: "Apply", decline: "Reject", accepted: "Applied", declined: "Rejected" },
};

export type GroupRow = { review_group: string; kind: GroupKind; items: number; examples: string[] };
