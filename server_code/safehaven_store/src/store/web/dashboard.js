export const renderDashboardHtml = () => `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
<title>SafeHaven Admin</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; }
  body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial; background: #0B1220; color: #EAF1FF; -webkit-font-smoothing: antialiased; }

  .loginWrap { min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 24px; }
  .loginCard { width: 100%; max-width: 380px; background: rgba(255,255,255,.03); border: 1px solid rgba(255,255,255,.08); border-radius: 20px; padding: 36px; }
  .loginTitle { font-size: 20px; font-weight: 850; margin: 0 0 4px; }
  .loginSub { font-size: 13px; color: rgba(234,241,255,.4); margin: 0 0 28px; }
  label { font-size: 11px; color: rgba(234,241,255,.4); letter-spacing: .07em; text-transform: uppercase; display: block; margin-bottom: 5px; }
  input, select { width: 100%; padding: 10px 12px; border-radius: 8px; border: 1px solid rgba(255,255,255,.09); background: rgba(255,255,255,.04); color: #EAF1FF; outline: none; font-size: 13px; font-family: inherit; }
  input:focus, select:focus { border-color: rgba(120,168,255,.4); box-shadow: 0 0 0 3px rgba(120,168,255,.1); }
  .btn { padding: 9px 16px; border-radius: 8px; border: 1px solid rgba(120,168,255,.22); background: rgba(120,168,255,.09); color: #EAF1FF; font-weight: 700; font-size: 13px; cursor: pointer; font-family: inherit; }
  .btn:hover { background: rgba(120,168,255,.17); }
  .btn.full { width: 100%; margin-top: 16px; padding: 11px; }
  .btn.danger { border-color: rgba(248,113,113,.18); background: transparent; color: #f87171; }
  .btn.danger:hover { background: rgba(248,113,113,.07); }
  .st { margin-top: 8px; font-size: 12px; min-height: 16px; }
  .ok { color: #4ade80; }
  .bad { color: #f87171; }

  .app { min-height: 100vh; display: grid; grid-template-columns: 210px 1fr; }
  .side { border-right: 1px solid rgba(255,255,255,.06); padding: 20px 12px; height: 100vh; overflow: auto; position: sticky; top: 0; display: flex; flex-direction: column; }
  .brandTitle { font-size: 13px; font-weight: 800; margin: 0 0 2px 6px; }
  .brandSub { font-size: 11px; color: rgba(234,241,255,.35); margin: 0 0 22px 6px; }
  .nav { display: flex; flex-direction: column; gap: 2px; }
  .navBtn { width: 100%; text-align: left; padding: 9px 10px; border-radius: 7px; border: none; background: transparent; color: rgba(234,241,255,.5); font-weight: 600; font-size: 13px; cursor: pointer; font-family: inherit; }
  .navBtn:hover { color: rgba(234,241,255,.85); background: rgba(255,255,255,.04); }
  .navBtn.active { color: #EAF1FF; background: rgba(255,255,255,.07); }
  .sideFoot { margin-top: auto; padding-top: 16px; }

  .main { padding: 24px 28px; overflow-x: hidden; min-width: 0; }
  .topbar { display: flex; align-items: center; gap: 12px; margin-bottom: 22px; }
  .burger { display: none; border: 1px solid rgba(255,255,255,.1); background: transparent; color: #EAF1FF; border-radius: 7px; padding: 8px 12px; font-weight: 700; font-size: 13px; cursor: pointer; font-family: inherit; }
  .meLabel { font-size: 12px; color: rgba(234,241,255,.3); }

  .section { display: none; }
  .section.show { display: block; }
  .pgTitle { font-size: 15px; font-weight: 800; margin: 0 0 3px; }
  .pgSub { font-size: 13px; color: rgba(234,241,255,.38); margin: 0 0 18px; }

  .surface { background: rgba(255,255,255,.025); border: 1px solid rgba(255,255,255,.065); border-radius: 9px; padding: 16px; margin-bottom: 12px; }
  .surfaceTitle { font-size: 13px; font-weight: 700; margin: 0 0 12px; }
  .row { display: grid; grid-template-columns: 1fr auto; gap: 10px; align-items: end; margin-top: 12px; }

  .mrwrap { border-bottom: 1px solid rgba(255,255,255,.045); }
  .mrwrap:last-child { border-bottom: none; }
  .mr { display: flex; align-items: center; gap: 10px; padding: 11px 0; flex-wrap: wrap; }
  .abtn { padding: 5px 11px; border-radius: 6px; font-size: 12px; font-weight: 700; cursor: pointer; border: 1px solid rgba(255,255,255,.09); background: transparent; color: rgba(234,241,255,.65); font-family: inherit; white-space: nowrap; }
  .abtn:hover { background: rgba(255,255,255,.06); color: #EAF1FF; }
  .abtn.primary { border-color: rgba(120,168,255,.28); background: rgba(120,168,255,.1); color: #EAF1FF; }
  .abtn.primary:hover { background: rgba(120,168,255,.2); }
  .abtn.danger { border-color: rgba(248,113,113,.18); color: #f87171; }
  .abtn.danger:hover { background: rgba(248,113,113,.07); }
  .abtn.ok { border-color: rgba(74,222,128,.2); color: #4ade80; }
  .abtn.ok:hover { background: rgba(74,222,128,.07); }

  .badge { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: .05em; padding: 2px 6px; border-radius: 4px; text-transform: uppercase; }
  .badge-github   { background: rgba(255,255,255,.06); color: rgba(234,241,255,.5); }
  .badge-gitlab   { background: rgba(252,109,38,.12); color: #fc6d26; }
  .badge-codeberg { background: rgba(47,128,237,.12); color: #2f80ed; }
  .badge-fdroid   { background: rgba(74,222,128,.1); color: #4ade80; }
  .badge-unverified { background: rgba(251,191,36,.1); color: #fbbf24; }
  .badge-verified   { background: rgba(120,168,255,.12); color: #78a8ff; }
  .badge-reviewed   { background: rgba(74,222,128,.12); color: #4ade80; }
  .badge-claimed    { background: rgba(255,255,255,.07); color: rgba(234,241,255,.5); }

  .filterBar { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; flex-wrap: wrap; }
  .filterBar select { width: auto; padding: 6px 10px; font-size: 12px; }
  .filterBar input  { width: auto; flex: 1; min-width: 160px; padding: 6px 10px; font-size: 12px; }

  .toolGrid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; }
  .toolCard { background: rgba(255,255,255,.02); border: 1px solid rgba(255,255,255,.06); border-radius: 8px; padding: 14px; }
  .toolCardTitle { font-size: 12px; font-weight: 700; margin: 0 0 4px; }
  .toolCardSub { font-size: 11px; color: rgba(234,241,255,.38); margin: 0 0 10px; line-height: 1.45; }

  .scrim { position: fixed; inset: 0; background: rgba(0,0,0,.5); display: none; z-index: 40; }
  .scrim.open { display: block; }

  @media (max-width: 860px) {
    .app { grid-template-columns: 1fr; }
    .side { position: fixed; inset: 0 auto 0 0; width: 240px; transform: translateX(-110%); transition: transform .18s ease; z-index: 50; background: #0d1628; height: 100vh; }
    .side.open { transform: translateX(0); }
    .burger { display: inline-flex; }
    .main { padding: 16px 14px; }
    .row { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>

<div id="loginScreen" class="loginWrap">
  <div class="loginCard">
    <p class="loginTitle">SafeHaven Admin</p>
    <p class="loginSub">Enter your admin token to continue.</p>
    <div>
      <label>Admin Token</label>
      <input id="tokenInput" type="password" placeholder="admin-token" />
    </div>
    <button class="btn full" id="loginBtn">Sign in</button>
    <div id="loginStatus" class="st"></div>
  </div>
</div>

<div id="adminScreen" style="display:none;">
  <div class="scrim" id="scrim"></div>
  <div class="app">
    <aside class="side" id="side">
      <p class="brandTitle">SafeHaven Admin</p>
      <p class="brandSub">Store Dashboard</p>
      <div class="nav">
        <button class="navBtn active" id="navSubmissions">Submissions</button>
        <button class="navBtn" id="navApps">Apps</button>
        <button class="navBtn" id="navImport">Import</button>
        <button class="navBtn" id="navRatings">Ratings</button>
        <button class="navBtn" id="navTools">Tools</button>
      </div>
      <div class="sideFoot">
        <button class="btn danger" style="width:100%;font-size:12px;padding:7px;" id="logoutBtn">Sign out</button>
      </div>
    </aside>

    <main class="main">
      <div class="topbar">
        <button class="burger" id="burger">Menu</button>
        <span class="meLabel" id="meLabel"></span>
      </div>

      <div class="section show" id="secSubmissions">
        <p class="pgTitle">Submissions</p>
        <p class="pgSub">Review, approve, or reject app submissions.</p>
        <div class="surface">
          <div class="filterBar">
            <select id="submissionStatusFilter">
              <option value="pending_review">Pending review</option>
              <option value="scanning">Scanning</option>
              <option value="pending_scan">Pending scan</option>
              <option value="live">Live</option>
              <option value="rejected">Rejected</option>
            </select>
            <button class="abtn" id="refreshSubmissions">Refresh</button>
          </div>
          <div id="submissionsStatus" class="st"></div>
          <div id="submissionsList"></div>
        </div>
      </div>

      <div class="section" id="secApps">
        <p class="pgTitle">Apps</p>
        <p class="pgSub">Manage category, trust level, and status.</p>
        <div class="surface">
          <div class="filterBar">
            <input id="appsSearch" placeholder="Search by name or package…" />
            <select id="appsUpstreamFilter">
              <option value="">All upstreams</option>
              <option value="github">GitHub</option>
              <option value="gitlab">GitLab</option>
              <option value="codeberg">Codeberg</option>
              <option value="fdroid">F-Droid</option>
            </select>
            <button class="abtn" id="refreshApps">Refresh</button>
          </div>
          <div id="appsStatus" class="st"></div>
          <div id="appsList"></div>
        </div>
      </div>

      <div class="section" id="secImport">
        <p class="pgTitle">Import</p>
        <p class="pgSub">Directly import a GitHub, GitLab, or Codeberg repository with admin privileges.</p>
        <div class="surface">
          <p class="surfaceTitle">Import repository</p>
          <div style="display:grid;gap:10px;max-width:560px;">
            <div>
              <label>Repository URL</label>
              <input id="importRepoUrl" placeholder="https://github.com/user/repo" autocomplete="off" />
            </div>
            <div>
              <label>Asset match (optional)</label>
              <input id="importAssetMatch" placeholder="arm64, universal, …" autocomplete="off" />
            </div>
            <div>
              <button class="abtn primary" id="importRepoBtn">Import</button>
            </div>
          </div>
          <div id="importStatus" class="st"></div>
        </div>
      </div>

      <div class="section" id="secRatings">
        <p class="pgTitle">Ratings</p>
        <p class="pgSub">View and reset app ratings.</p>
        <div class="surface">
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">
            <span style="font-size:13px;font-weight:700;">App ratings</span>
            <button class="abtn" id="refreshRatings">Refresh</button>
          </div>
          <div id="ratingsStatus" class="st"></div>
          <div id="ratingsList"></div>
        </div>
      </div>

      <div class="section" id="secTools">
        <p class="pgTitle">Tools</p>
        <p class="pgSub">Admin operations for store maintenance.</p>
        <div class="toolGrid">
          <div class="toolCard">
            <p class="toolCardTitle">Upstream Poll</p>
            <p class="toolCardSub">Check GitHub, GitLab, and Codeberg apps for new releases.</p>
            <button class="abtn primary" id="toolPollBtn">Run poll</button>
            <div id="toolPollStatus" class="st"></div>
          </div>
          <div class="toolCard">
            <p class="toolCardTitle">F-Droid Sync</p>
            <p class="toolCardSub">Pull latest F-Droid index and import new apps.</p>
            <button class="abtn primary" id="toolFdroidSyncBtn">Run sync</button>
            <div id="toolFdroidSyncStatus" class="st"></div>
          </div>
          <div class="toolCard">
            <p class="toolCardTitle">F-Droid Update Check</p>
            <p class="toolCardSub">Check tracked F-Droid apps for version updates.</p>
            <button class="abtn primary" id="toolFdroidUpdateBtn">Run check</button>
            <div id="toolFdroidUpdateStatus" class="st"></div>
          </div>
          <div class="toolCard">
            <p class="toolCardTitle">Readme Sweep</p>
            <p class="toolCardSub">Refresh descriptions and screenshots from GitHub READMEs.</p>
            <button class="abtn primary" id="toolReadmeBtn">Run sweep</button>
            <div id="toolReadmeStatus" class="st"></div>
          </div>
          <div class="toolCard">
            <p class="toolCardTitle">Clear Index</p>
            <p class="toolCardSub">Wipe the public store index. Use with caution.</p>
            <button class="abtn danger" id="toolClearIndexBtn">Clear index</button>
            <div id="toolClearIndexStatus" class="st"></div>
          </div>
        </div>
      </div>
    </main>
  </div>
</div>

<script>
const apiBase = location.origin;
let TOKEN = "";

const escHtml = (s) => String(s ?? "").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#39;");
const setStatus = (el, msg, ok) => { if (!el) return; el.textContent = msg || ""; el.className = "st " + (ok === true ? "ok" : ok === false ? "bad" : ""); };
const apiFetch = (path, opts = {}) => fetch(apiBase + path, { ...opts, headers: { authorization: "Bearer " + TOKEN, "content-type": "application/json", ...(opts.headers || {}) } });
const byId = (id) => document.getElementById(id);

const loginScreen = byId("loginScreen");
const adminScreen = byId("adminScreen");
const tokenInput  = byId("tokenInput");
const loginBtn    = byId("loginBtn");
const loginStatus = byId("loginStatus");
const side        = byId("side");
const scrim       = byId("scrim");
const burger      = byId("burger");

const showAdmin = (token) => {
  TOKEN = token;
  try { localStorage.setItem("sh_admin_token", token); } catch {}
  loginScreen.style.display = "none";
  adminScreen.style.display = "";
  byId("meLabel").textContent = "admin";
  setTab("submissions");
};

const tryLogin = async () => {
  const t = (tokenInput.value || "").trim();
  if (!t) { setStatus(loginStatus, "Enter your token.", false); return; }
  loginBtn.disabled = true;
  setStatus(loginStatus, "Checking...", null);
  TOKEN = t;
  const res = await apiFetch("/admin/store/submissions?status=pending_review").catch(() => null);
  loginBtn.disabled = false;
  if (!res || res.status === 401 || res.status === 403) {
    TOKEN = "";
    setStatus(loginStatus, "Invalid token.", false);
    return;
  }
  showAdmin(t);
};

loginBtn.onclick = tryLogin;
tokenInput.onkeydown = (e) => { if (e.key === "Enter") tryLogin(); };

byId("logoutBtn").onclick = () => {
  TOKEN = "";
  try { localStorage.removeItem("sh_admin_token"); } catch {}
  adminScreen.style.display = "none";
  loginScreen.style.display = "";
  tokenInput.value = "";
  setStatus(loginStatus, "", null);
};

burger.onclick = () => { side.classList.add("open"); scrim.classList.add("open"); };
scrim.onclick  = () => { side.classList.remove("open"); scrim.classList.remove("open"); };

const TABS = ["submissions", "apps", "import", "ratings", "tools"];

const setTab = (tab) => {
  TABS.forEach((t) => {
    byId("nav" + t.charAt(0).toUpperCase() + t.slice(1)).classList.toggle("active", t === tab);
    byId("sec"  + t.charAt(0).toUpperCase() + t.slice(1)).classList.toggle("show",   t === tab);
  });
  side.classList.remove("open");
  scrim.classList.remove("open");
  if (tab === "submissions") loadSubmissions();
  if (tab === "apps")        loadApps();
  if (tab === "ratings")     loadRatings();
};

TABS.forEach((t) => {
  byId("nav" + t.charAt(0).toUpperCase() + t.slice(1)).onclick = () => setTab(t);
});

const CATEGORIES   = { security:"Security", productivity:"Productivity", utilities:"Utilities", communication:"Communication", entertainment:"Entertainment", finance:"Finance", health:"Health & Fitness", education:"Education", tools:"Tools", other:"Other" };
const TRUST_LEVELS = { unverified:"Unverified", verified_source:"Verified Source", security_reviewed:"Security Reviewed" };
const APP_STATUSES = { active:"Active", suspended:"Suspended", removed:"Removed" };

const upstreamBadge = (u) => {
  if (!u) return "";
  const cls = { github:"badge-github", gitlab:"badge-gitlab", codeberg:"badge-codeberg", fdroid:"badge-fdroid" }[u] || "badge-github";
  return \`<span class="badge \${cls}">\${escHtml(u)}</span>\`;
};

const trustBadge = (t) => {
  if (!t || t === "unverified") return \`<span class="badge badge-unverified">Unverified</span>\`;
  if (t === "verified_source")  return \`<span class="badge badge-verified">Verified</span>\`;
  if (t === "security_reviewed") return \`<span class="badge badge-reviewed">Reviewed</span>\`;
  return \`<span class="badge badge-unverified">\${escHtml(t)}</span>\`;
};

const loadSubmissions = async () => {
  const st     = byId("submissionsStatus");
  const list   = byId("submissionsList");
  const status = byId("submissionStatusFilter").value || "pending_review";
  setStatus(st, "Loading...", null);
  list.innerHTML = "";
  const res  = await apiFetch("/admin/store/submissions?status=" + encodeURIComponent(status));
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { setStatus(st, data.error || "Failed", false); return; }
  const submissions = Array.isArray(data.submissions) ? data.submissions : [];
  if (!submissions.length) { setStatus(st, "No submissions for this status.", null); return; }
  setStatus(st, "", null);
  list.innerHTML = submissions.map((s) => {
    const id          = escHtml(s.id);
    const packageName = escHtml(s.package_name || "");
    const versionName = escHtml(s.version_name || "");
    const versionCode = escHtml(s.version_code || "");
    const sha         = escHtml(s.apk_sha256 || "");
    const size        = Number(s.apk_size || 0);
    const mb          = size > 0 ? (size / 1024 / 1024).toFixed(2) + " MB" : "Unknown size";
    const scanResult  = escHtml(s.scan_result || "");
    const isPending   = s.status === "pending_review";
    return \`<div class="mrwrap"><div class="mr">
      <div style="flex:1;min-width:0;">
        <div style="font-size:13px;font-weight:800;">\${packageName}</div>
        <div style="font-size:12px;opacity:.42;margin-top:3px;">v\${versionName} · code \${versionCode} · \${mb}</div>
        \${sha ? \`<div style="font-size:11px;opacity:.28;margin-top:3px;font-family:monospace;">\${sha.slice(0,32)}…</div>\` : ""}
        \${scanResult ? \`<div style="font-size:11px;opacity:.38;margin-top:3px;">\${scanResult.slice(0,120)}</div>\` : ""}
      </div>
      \${isPending ? \`<div style="display:flex;gap:6px;flex-shrink:0;">
        <button class="abtn primary" onclick="approveSubmission('\${id}')">Approve</button>
        <button class="abtn danger"  onclick="rejectSubmission('\${id}')">Reject</button>
      </div>\` : \`<div style="font-size:12px;opacity:.38;">\${escHtml(s.status || "")}</div>\`}
    </div></div>\`;
  }).join("");
};

const approveSubmission = async (id) => {
  const st = byId("submissionsStatus");
  setStatus(st, "Approving...", null);
  const res  = await apiFetch("/admin/store/submissions/" + encodeURIComponent(id) + "/approve", { method: "POST" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { setStatus(st, data.error || "Failed", false); return; }
  setStatus(st, "Approved and published.", true);
  await loadSubmissions();
};

const rejectSubmission = async (id) => {
  const reason = prompt("Reject reason?", "Rejected during manual review");
  if (reason === null) return;
  const st   = byId("submissionsStatus");
  setStatus(st, "Rejecting...", null);
  const res  = await apiFetch("/admin/store/submissions/" + encodeURIComponent(id) + "/reject", { method: "POST", body: JSON.stringify({ reason }) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { setStatus(st, data.error || "Failed", false); return; }
  setStatus(st, "Rejected.", true);
  await loadSubmissions();
};

byId("refreshSubmissions").onclick = loadSubmissions;
byId("submissionStatusFilter").onchange = loadSubmissions;

let appsData = [];

const loadApps = async () => {
  const st   = byId("appsStatus");
  const list = byId("appsList");
  setStatus(st, "Loading...", null);
  list.innerHTML = "";
  const res  = await apiFetch("/admin/store/apps");
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { setStatus(st, data.error || "Failed", false); return; }
  appsData = Array.isArray(data.apps) ? data.apps : [];
  if (!appsData.length) { setStatus(st, "No apps yet.", null); return; }
  setStatus(st, "", null);
  renderApps();
};

const renderApps = () => {
  const list     = byId("appsList");
  const search   = (byId("appsSearch").value || "").toLowerCase();
  const upstream = byId("appsUpstreamFilter").value || "";

  const filtered = appsData.filter((app) => {
    if (upstream && (app.upstream || "") !== upstream) return false;
    if (search) {
      const hay = ((app.name || "") + " " + (app.package_name || "")).toLowerCase();
      if (!hay.includes(search)) return false;
    }
    return true;
  });

  if (!filtered.length) { list.innerHTML = \`<div style="padding:12px 0;font-size:13px;opacity:.4;">No apps match the current filter.</div>\`; return; }

  list.innerHTML = filtered.map((app) => {
    const id         = escHtml(app.id);
    const pkg        = escHtml(app.package_name || "");
    const name       = escHtml(app.name || "");
    const category   = app.category || "";
    const trustLevel = app.trust_level || "unverified";
    const status     = app.status || "active";
    const catOptions   = Object.entries(CATEGORIES).map(([k,v]) => \`<option value="\${k}" \${category===k?"selected":""}>\${escHtml(v)}</option>\`).join("");
    const trustOptions = Object.entries(TRUST_LEVELS).map(([k,v]) => \`<option value="\${k}" \${trustLevel===k?"selected":""}>\${escHtml(v)}</option>\`).join("");
    const repoUrl    = escHtml(app.repo_url || "");
    const isClaimed  = Number(app.claimed || 0) === 1;
    const isActive   = status === "active";

    return \`<div class="mrwrap"><div class="mr" style="align-items:flex-start;flex-direction:column;gap:8px;padding:14px 0;">
      <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
        <div>
          <div style="font-size:13px;font-weight:800;">\${name}</div>
          <div style="font-size:11px;opacity:.38;margin-top:2px;">\${pkg}</div>
        </div>
        \${upstreamBadge(app.upstream)}
        \${trustBadge(trustLevel)}
        \${isClaimed ? \`<span class="badge badge-claimed">Claimed</span>\` : ""}
        \${!isActive ? \`<span class="badge" style="background:rgba(248,113,113,.1);color:#f87171;">\${escHtml(status)}</span>\` : ""}
      </div>
      \${repoUrl ? \`<div style="font-size:11px;opacity:.32;">\${repoUrl}</div>\` : ""}
      <div style="display:flex;gap:8px;flex-wrap:wrap;width:100%;">
        <div style="flex:1;min-width:130px;">
          <label>Category</label>
          <select id="cat_\${id}" onchange="setCategory('\${id}', this.value)">
            <option value="" \${!category?"selected":""}>— unset —</option>
            \${catOptions}
          </select>
        </div>
        <div style="flex:1;min-width:160px;">
          <label>Trust Level</label>
          <select id="trust_\${id}" onchange="setTrustLevel('\${id}', this.value)">\${trustOptions}</select>
        </div>
        <div style="display:flex;align-items:flex-end;gap:6px;flex-wrap:wrap;">
          \${isActive
            ? \`<button class="abtn danger" onclick="setAppStatus('\${id}', 'suspended')">Suspend</button>
               <button class="abtn danger" onclick="setAppStatus('\${id}', 'removed')">Remove</button>\`
            : \`<button class="abtn ok" onclick="setAppStatus('\${id}', 'active')">Activate</button>\`
          }
        </div>
      </div>
    </div></div>\`;
  }).join("");
};

const setCategory = async (appId, category) => {
  const st  = byId("appsStatus");
  const res = await apiFetch("/admin/store/apps/" + encodeURIComponent(appId) + "/category", { method: "POST", body: JSON.stringify({ category: category || null }) });
  const data = await res.json().catch(() => ({}));
  setStatus(st, res.ok ? "Category updated." : (data.error || "Failed"), res.ok || false);
};

const setTrustLevel = async (appId, trustLevel) => {
  const st  = byId("appsStatus");
  const res = await apiFetch("/admin/store/apps/" + encodeURIComponent(appId) + "/trust-level", { method: "POST", body: JSON.stringify({ trustLevel }) });
  const data = await res.json().catch(() => ({}));
  setStatus(st, res.ok ? "Trust level updated." : (data.error || "Failed"), res.ok || false);
};

const setAppStatus = async (appId, status) => {
  if (status === "removed" && !confirm("Permanently remove this app?")) return;
  const st  = byId("appsStatus");
  setStatus(st, "Updating...", null);
  const res = await apiFetch("/admin/store/apps/" + encodeURIComponent(appId) + "/status", { method: "POST", body: JSON.stringify({ status }) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { setStatus(st, data.error || "Failed", false); return; }
  setStatus(st, "Status updated.", true);
  await loadApps();
};

byId("refreshApps").onclick = loadApps;
byId("appsSearch").oninput  = renderApps;
byId("appsUpstreamFilter").onchange = renderApps;

byId("importRepoBtn").onclick = async () => {
  const st       = byId("importStatus");
  const repoUrl  = (byId("importRepoUrl").value || "").trim();
  const assetMatch = (byId("importAssetMatch").value || "").trim() || undefined;
  if (!repoUrl) { setStatus(st, "Enter a repository URL.", false); return; }
  setStatus(st, "Importing...", null);
  const res  = await apiFetch("/admin/store/import-repo", { method: "POST", body: JSON.stringify({ repoUrl, assetMatch }) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const reason = data?.result?.reason || data.error || "Failed";
    setStatus(st, "Failed: " + reason, false);
    return;
  }
  const r = data.result || {};
  setStatus(st, \`Imported \${escHtml(r.packageName || "")} v\${r.versionCode || "?"}\`, true);
  byId("importRepoUrl").value = "";
  byId("importAssetMatch").value = "";
};

const loadRatings = async () => {
  const st   = byId("ratingsStatus");
  const list = byId("ratingsList");
  setStatus(st, "Loading...", null);
  list.innerHTML = "";
  const res  = await apiFetch("/admin/store/ratings");
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { setStatus(st, data.error || "Failed", false); return; }
  const ratings = Array.isArray(data.ratings) ? data.ratings : [];
  if (!ratings.length) { setStatus(st, "No ratings yet.", null); return; }
  setStatus(st, "", null);
  list.innerHTML = ratings.map((r) => {
    const pkg   = escHtml(r.package_name || "");
    const count = Number(r.rating_count || 0);
    const avg   = count > 0 ? (Number(r.rating_sum) / count).toFixed(1) : "-";
    return \`<div class="mrwrap"><div class="mr">
      <div style="flex:1;min-width:0;">
        <div style="font-size:13px;font-weight:800;">\${pkg}</div>
        <div style="font-size:12px;opacity:.42;margin-top:3px;">\${avg} ★ · \${count} rating\${count !== 1 ? "s" : ""}</div>
      </div>
      <button class="abtn danger" onclick="resetRating('\${pkg}')">Reset</button>
    </div></div>\`;
  }).join("");
};

const resetRating = async (packageName) => {
  if (!confirm("Reset all ratings for " + packageName + "?")) return;
  const st  = byId("ratingsStatus");
  setStatus(st, "Resetting...", null);
  const res  = await apiFetch("/admin/store/ratings/" + encodeURIComponent(packageName), { method: "DELETE" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { setStatus(st, data.error || "Failed", false); return; }
  setStatus(st, "Ratings cleared.", true);
  await loadRatings();
};

byId("refreshRatings").onclick = loadRatings;

const runTool = async (endpoint, btnId, statusId, confirm_msg) => {
  if (confirm_msg && !confirm(confirm_msg)) return;
  const btn = byId(btnId);
  const st  = byId(statusId);
  btn.disabled = true;
  setStatus(st, "Running...", null);
  const res  = await apiFetch(endpoint, { method: "POST" });
  const data = await res.json().catch(() => ({}));
  btn.disabled = false;
  if (!res.ok) { setStatus(st, data.error || "Failed", false); return; }
  const r = data.result || {};
  const summary = [
    r.checked   != null ? \`checked \${r.checked}\`   : null,
    r.submitted != null ? \`submitted \${r.submitted}\` : null,
    r.imported  != null ? \`imported \${r.imported}\`  : null,
    r.updated   != null ? \`updated \${r.updated}\`    : null,
    r.errors?.length    ? \`\${r.errors.length} error(s)\` : null,
  ].filter(Boolean).join(" · ");
  setStatus(st, summary || "Done.", true);
};

byId("toolPollBtn").onclick       = () => runTool("/admin/store/upstream-poll",      "toolPollBtn",       "toolPollStatus");
byId("toolFdroidSyncBtn").onclick  = () => runTool("/admin/store/fdroid-sync",        "toolFdroidSyncBtn", "toolFdroidSyncStatus");
byId("toolFdroidUpdateBtn").onclick = () => runTool("/admin/store/fdroid-update-check","toolFdroidUpdateBtn","toolFdroidUpdateStatus");
byId("toolReadmeBtn").onclick      = () => runTool("/admin/store/readme-sweep",       "toolReadmeBtn",     "toolReadmeStatus");
byId("toolClearIndexBtn").onclick  = () => runTool("/admin/store/clear-index",        "toolClearIndexBtn", "toolClearIndexStatus", "This will wipe the public store index. Are you sure?");

try {
  const saved = localStorage.getItem("sh_admin_token");
  if (saved) showAdmin(saved);
} catch {}
</script>
</body>
</html>`;