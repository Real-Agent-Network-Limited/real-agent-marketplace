// Real Agent's own details, which setup needs and no client gives: each member of Real Agent's staff who works in a
// firm's project, by name and work email address; the email address the owner invites into their Supabase
// organisation as a Developer, so Real Agent can apply upgrades; and the address an owner writes to when setup fails
// before they have signed in. Real Agent's staff keep this list. okb-setup makes an
// Auth user for each, and first-administrator.sql makes each one an actor named "<name> (Real Agent)" with the
// real_agent access template. An empty list makes no Real Agent actor; Real Agent adds its staff later.
export const STAFF: { name: string; email: string }[] = [{ name: "Support", email: "support@realagent.network" }];

/** The address the owner invites as a Developer, or null until Real Agent gives one. */
export const DEVELOPER_EMAIL: string | null = "support@realagent.network";

/** The address an owner writes to when setup fails before they can raise a support request, or null. */
export const SUPPORT_EMAIL: string | null = "support@realagent.network";
