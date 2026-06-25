import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set([
  "https://young222-debug.github.io",
  "http://localhost:8787",
  "http://127.0.0.1:8787"
]);

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://young222-debug.github.io",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json"
  };
}

function json(req: Request, body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(req)
  });
}

function normalizeEmail(value: unknown) {
  return String(value || "").trim().toLowerCase();
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) });
  }

  if (req.method !== "POST") {
    return json(req, { error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return json(req, { error: "Invite service is not configured" }, 500);
  }

  const authHeader = req.headers.get("Authorization") || "";
  const accessToken = authHeader.replace(/^Bearer\s+/i, "");
  if (!accessToken) {
    return json(req, { error: "Missing user session" }, 401);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  });

  const { data: userData, error: userError } = await adminClient.auth.getUser(accessToken);
  if (userError || !userData.user) {
    return json(req, { error: "Invalid user session" }, 401);
  }

  const { data: adminRow, error: adminError } = await adminClient
    .from("app_admins")
    .select("user_id")
    .eq("user_id", userData.user.id)
    .maybeSingle();

  if (adminError) {
    return json(req, { error: "Cannot verify admin permission" }, 500);
  }

  if (!adminRow) {
    return json(req, { error: "Only admins can invite users" }, 403);
  }

  const body = await req.json().catch(() => ({}));
  const email = normalizeEmail(body.email);
  const name = String(body.name || "").trim().slice(0, 80);
  const note = String(body.note || "").trim().slice(0, 240);
  const redirectTo = String(body.redirectTo || "").trim();

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json(req, { error: "Please provide a valid email" }, 400);
  }

  const inviteOptions: { data: Record<string, string>; redirectTo?: string } = {
    data: { display_name: name || email }
  };
  if (redirectTo.startsWith("https://young222-debug.github.io/time-corridor-diary/")) {
    inviteOptions.redirectTo = redirectTo;
  }

  const { data: invited, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email, inviteOptions);
  if (inviteError) {
    return json(req, { error: inviteError.message || "Invite failed" }, 400);
  }

  const now = new Date().toISOString();
  const { data: invitation, error: invitationError } = await adminClient
    .from("invitations")
    .upsert({
      inviter_id: userData.user.id,
      email,
      name,
      note,
      status: "已发送",
      auth_user_id: invited.user?.id || null,
      invited_at: now,
      updated_at: now
    }, { onConflict: "inviter_id,email" })
    .select("id,email,name,note,status,auth_user_id,invited_at,created_at,updated_at")
    .single();

  if (invitationError) {
    return json(req, { error: "Invite sent, but invitation record was not saved" }, 500);
  }

  return json(req, {
    ok: true,
    invitation
  });
});
