// FieldOS owner dashboard: signs in to the FieldOS cloud and reads, through
// the server's row-level security, each site's last 30 days. Read only: it
// never writes anything. No libraries; plain fetch against the REST API.
(function () {
  'use strict';

  var cfg = window.FIELDOS_CLOUD || {};
  var base = (cfg.url || '').replace(/\/+$/, '');
  var key = cfg.anonKey || '';
  var $ = function (id) { return document.getElementById(id); };
  var KEY = 'fieldos-owner-session';

  // ---------- session (this tab only) ----------
  function loadSession() {
    try { return JSON.parse(sessionStorage.getItem(KEY) || 'null'); } catch (e) { return null; }
  }
  function saveSession(s) {
    try {
      if (s) sessionStorage.setItem(KEY, JSON.stringify(s)); else sessionStorage.removeItem(KEY);
    } catch (e) { /* private mode: the session lasts the page */ }
    session = s;
  }
  var session = loadSession();

  function fromTokenResponse(j) {
    return {
      access: j.access_token,
      refresh: j.refresh_token,
      expires: Date.now() + (j.expires_in || 3600) * 1000,
      user: j.user ? { id: j.user.id, email: j.user.email } : (session && session.user) || null,
    };
  }

  function auth(path, body) {
    return fetch(base + '/auth/v1/' + path, {
      method: 'POST',
      headers: { apikey: key, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).then(function (r) {
      return r.json().then(function (j) {
        if (!r.ok) throw new Error(j.error_description || j.msg || j.message || 'Sign-in failed');
        return j;
      });
    });
  }

  function refreshIfNeeded() {
    if (!session) return Promise.reject(new Error('Signed out'));
    if (session.expires - Date.now() > 60000) return Promise.resolve();
    return auth('token?grant_type=refresh_token', { refresh_token: session.refresh })
      .then(function (j) { saveSession(fromTokenResponse(j)); })
      .catch(function (e) { saveSession(null); throw e; });
  }

  function whoAmI() {
    return fetch(base + '/auth/v1/user', { headers: { apikey: key, Authorization: 'Bearer ' + session.access } })
      .then(function (r) { if (!r.ok) throw new Error('Signed out'); return r.json(); })
      .then(function (u) { session.user = { id: u.id, email: u.email }; saveSession(session); });
  }

  // ---------- REST reads ----------
  // GET /rest/v1/<table>?<query>; with count, the number of rows matched.
  function get(table, query, opts) {
    opts = opts || {};
    return refreshIfNeeded().then(function () {
      var headers = { apikey: key, Authorization: 'Bearer ' + session.access, Accept: 'application/json' };
      if (opts.count) headers.Prefer = 'count=exact';
      return fetch(base + '/rest/v1/' + table + '?' + query, { headers: headers });
    }).then(function (r) {
      if (r.status === 401) { saveSession(null); throw new Error('Signed out'); }
      if (!r.ok) {
        return r.text().then(function (t) {
          // A table not on this server yet (migration pending) reads as empty.
          if (r.status === 404 || /does not exist|schema cache/.test(t)) return opts.count ? 0 : [];
          throw new Error('Could not read ' + table);
        });
      }
      if (opts.count) {
        var range = r.headers.get('Content-Range') || '';
        var n = parseInt(range.split('/')[1], 10);
        return isNaN(n) ? 0 : n;
      }
      return r.json();
    });
  }

  function inList(ids) { return 'in.(' + ids.map(encodeURIComponent).join(',') + ')'; }

  // ---------- formatting ----------
  function rupees(n) {
    var v = Math.round(n || 0);
    var s = Math.abs(v).toString();
    var last3 = s.slice(-3), rest = s.slice(0, -3);
    if (rest) last3 = ',' + last3;
    rest = rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',');
    return (v < 0 ? '-' : '') + '₹' + rest + last3;
  }
  function isoDay(d) {
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
  function fmtDay(s) {
    if (!s) return 'never';
    var d = new Date(s.length === 10 ? s + 'T00:00:00' : s);
    return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
  }
  function daysSince(s) {
    if (!s) return Infinity;
    var d = new Date((s.length === 10 ? s : s.slice(0, 10)) + 'T00:00:00');
    var t = new Date(); t.setHours(0, 0, 0, 0);
    return Math.round((t - d) / 86400000);
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;   // never innerHTML: names are user text
    return e;
  }

  // ---------- screens ----------
  function show(which) {
    ['setup', 'signin', 'dash'].forEach(function (id) { $(id).hidden = id !== which; });
    var signedIn = which === 'dash';
    $('sign-out').hidden = !signedIn;
    $('who').hidden = !signedIn;
    if (signedIn && session && session.user) $('who').textContent = session.user.email || '';
  }
  function status(t) { $('status').textContent = t || ''; }

  var companies = [];

  function start() {
    if (!base || !key) { show('setup'); return; }
    // Back from Google: the tokens come in the address's #fragment.
    if (location.hash.indexOf('access_token=') >= 0) {
      var p = new URLSearchParams(location.hash.slice(1));
      saveSession({
        access: p.get('access_token'),
        refresh: p.get('refresh_token'),
        expires: Date.now() + (parseInt(p.get('expires_in'), 10) || 3600) * 1000,
        user: null,
      });
      history.replaceState(null, '', location.pathname + location.search);
    } else if (location.hash.indexOf('error') >= 0) {
      var e = new URLSearchParams(location.hash.slice(1));
      history.replaceState(null, '', location.pathname + location.search);
      show('signin');
      showError(e.get('error_description') || 'Google sign-in failed');
      return;
    }
    if (!session) { show('signin'); return; }
    status('Loading…');
    refreshIfNeeded().then(whoAmI).then(loadCompanies).catch(function () {
      saveSession(null); status(''); show('signin');
    });
  }

  function showError(t) { var e = $('signin-error'); e.textContent = t; e.hidden = !t; }

  $('signin-form').addEventListener('submit', function (ev) {
    ev.preventDefault();
    showError('');
    status('Signing in…');
    auth('token?grant_type=password', { email: $('email').value.trim(), password: $('password').value })
      .then(function (j) { saveSession(fromTokenResponse(j)); $('password').value = ''; return loadCompanies(); })
      .catch(function (e) { status(''); showError(e.message === 'Invalid login credentials' ? 'That email and password don’t match.' : e.message); });
  });

  $('google').addEventListener('click', function () {
    var back = location.origin + location.pathname;
    location.href = base + '/auth/v1/authorize?provider=google&redirect_to=' + encodeURIComponent(back);
  });

  $('sign-out').addEventListener('click', function () {
    var s = session;
    saveSession(null);
    if (s) {
      fetch(base + '/auth/v1/logout', { method: 'POST', headers: { apikey: key, Authorization: 'Bearer ' + s.access } })
        .catch(function () {});
    }
    $('sites').textContent = '';
    $('totals').textContent = '';
    show('signin');
  });

  $('refresh').addEventListener('click', function () { loadSites(); });
  $('company').addEventListener('change', function () { loadSites(); });

  function loadCompanies() {
    return get('company_members', 'select=company_id,role,companies(name)&user_id=eq.' + session.user.id).then(function (rows) {
      companies = rows
        .filter(function (r) { return r.role === 'owner' || r.role === 'project_manager'; })
        .map(function (r) { return { id: r.company_id, name: (r.companies && r.companies.name) || 'Company' }; })
        .sort(function (a, b) { return a.name.localeCompare(b.name); });
      show('dash');
      var sel = $('company');
      sel.textContent = '';
      companies.forEach(function (c) { var o = el('option', null, c.name); o.value = c.id; sel.appendChild(o); });
      sel.hidden = companies.length < 2;
      if (!companies.length) {
        $('company-name').textContent = 'No company to show';
        $('sites').textContent = '';
        $('totals').textContent = '';
        status(rows.length
          ? 'This dashboard is for owners and project managers. Ask your company’s owner if you need it.'
          : 'This account isn’t in a company yet. Sign in to the app and create or join one first.');
        return;
      }
      return loadSites();
    });
  }

  function loadSites() {
    var company = companies.filter(function (c) { return c.id === $('company').value; })[0] || companies[0];
    $('company-name').textContent = company.name;
    status('Loading…');
    var now = new Date();
    var today = isoDay(now);
    var d30 = new Date(now); d30.setDate(d30.getDate() - 29);
    var d14 = new Date(now); d14.setDate(d14.getDate() - 13);
    var d7 = new Date(now); d7.setDate(d7.getDate() - 6); d7.setHours(0, 0, 0, 0);
    var midnight = new Date(now); midnight.setHours(0, 0, 0, 0);

    return get('projects', 'select=id,name,client_name,status&company_id=eq.' + company.id + '&order=name.asc').then(function (projects) {
      var running = projects.filter(function (p) { return p.status === 'active'; });
      if (!running.length) {
        $('sites').textContent = ''; $('totals').textContent = '';
        status('No running sites in ' + company.name + '.');
        return;
      }
      var ids = running.map(function (p) { return p.id; });
      var pin = inList(ids);
      var lim = '&limit=10000';
      return Promise.all([
        get('site_expenses', 'select=project_id,amount&voided=is.false&incurred_on=gte.' + isoDay(d30) + '&project_id=' + pin + lim),
        get('site_payments_received', 'select=project_id,amount&voided=is.false&received_on=gte.' + isoDay(d30) + '&project_id=' + pin + lim),
        get('dpr_entries', 'select=project_id,entry_date&entry_date=gte.' + isoDay(d14) + '&project_id=' + pin + '&order=entry_date.desc' + lim),
        get('site_attendance', 'select=project_id,worker_name&punch_in=gte.' + encodeURIComponent(midnight.toISOString()) + '&project_id=' + pin + lim),
        get('issues', 'select=project_id&status=neq.resolved&project_id=' + pin + lim),
        get('approvals', 'select=project_id&status=eq.pending&project_id=' + pin + lim),
        get('entry_history', 'select=project_id,op&changed_at=gte.' + encodeURIComponent(d7.toISOString()) + '&project_id=' + pin + lim),
        get('site_floor_progress', 'select=project_id,block,floor,pct,as_of,created_at&project_id=' + pin + '&order=as_of.asc,created_at.asc' + lim),
      ]).then(function (r) {
        render(running, {
          spent: sumBy(r[0]), received: sumBy(r[1]), lastReport: lastBy(r[2]), labour: labourBy(r[3]),
          issues: countBy(r[4]), approvals: countBy(r[5]), changes: changesBy(r[6]), progress: progressBy(r[7]),
        }, today);
        $('as-of').textContent = 'As of ' + now.toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
        status('');
      });
    }).catch(function (e) {
      if (!session) { show('signin'); status(''); return; }
      status('Couldn’t load the sites: ' + e.message + '. Try Refresh.');
    });
  }

  function sumBy(rows) {
    var m = {}; rows.forEach(function (r) { m[r.project_id] = (m[r.project_id] || 0) + Number(r.amount || 0); }); return m;
  }
  function countBy(rows) { var m = {}; rows.forEach(function (r) { m[r.project_id] = (m[r.project_id] || 0) + 1; }); return m; }
  function lastBy(rows) {
    var m = {}; rows.forEach(function (r) { var d = String(r.entry_date).slice(0, 10); if (!m[r.project_id] || d > m[r.project_id]) m[r.project_id] = d; }); return m;
  }
  function labourBy(rows) {
    var m = {}; rows.forEach(function (r) { (m[r.project_id] = m[r.project_id] || {})[(r.worker_name || '').toLowerCase()] = 1; });
    var out = {}; Object.keys(m).forEach(function (k) { out[k] = Object.keys(m[k]).length; }); return out;
  }
  function changesBy(rows) {
    var m = {}; rows.forEach(function (r) {
      var c = m[r.project_id] = m[r.project_id] || { changed: 0, deleted: 0 };
      if (r.op === 'delete') c.deleted++; else c.changed++;
    }); return m;
  }
  function progressBy(rows) {
    // Latest per block and floor (rows come oldest first), averaged.
    var latest = {};
    rows.forEach(function (r) { latest[r.project_id + '|' + r.block + '|' + r.floor] = r; });
    var sum = {}, n = {};
    Object.keys(latest).forEach(function (k) { var r = latest[k]; sum[r.project_id] = (sum[r.project_id] || 0) + r.pct; n[r.project_id] = (n[r.project_id] || 0) + 1; });
    var out = {}; Object.keys(sum).forEach(function (p) { out[p] = Math.round(sum[p] / n[p]); }); return out;
  }

  function tile(k, v) { var t = el('div', 'tile'); t.appendChild(el('div', 'k', k)); t.appendChild(el('div', 'v', v)); return t; }

  function render(sites, m, today) {
    var totals = $('totals'); totals.textContent = '';
    var spent = 0, received = 0, labour = 0, waiting = 0, late = 0;
    sites.forEach(function (s) {
      spent += m.spent[s.id] || 0; received += m.received[s.id] || 0; labour += m.labour[s.id] || 0;
      waiting += m.approvals[s.id] || 0;
      if (daysSince(m.lastReport[s.id]) >= 2) late++;
    });
    totals.appendChild(tile('Running sites', String(sites.length)));
    totals.appendChild(tile('Spent, 30 days', rupees(spent)));
    totals.appendChild(tile('Received, 30 days', rupees(received)));
    totals.appendChild(tile('Labour on site today', String(labour)));
    totals.appendChild(tile('Waiting for approval', String(waiting)));
    totals.appendChild(tile('Sites with no report for 2+ days', String(late)));

    var box = $('sites'); box.textContent = '';
    sites.slice().sort(function (a, b) { return score(b) - score(a) || a.name.localeCompare(b.name); }).forEach(function (s) {
      var card = el('article', 'site');
      card.appendChild(el('h2', null, s.name));
      if (s.client_name) card.appendChild(el('div', 'muted small', s.client_name));
      var dl = el('dl');
      function row(k, v) { dl.appendChild(el('dt', null, k)); dl.appendChild(el('dd', null, v)); }
      var last = m.lastReport[s.id];
      row('Spent, 30 days', rupees(m.spent[s.id]));
      row('Received, 30 days', rupees(m.received[s.id]));
      row('Last daily report', last === today ? 'Today' : fmtDay(last));
      row('Labour today', String(m.labour[s.id] || 0));
      row('Open issues', String(m.issues[s.id] || 0));
      row('Waiting for approval', String(m.approvals[s.id] || 0));
      if (m.progress[s.id] != null) row('Construction progress', m.progress[s.id] + '%');
      card.appendChild(dl);

      var flags = el('div', 'flags');
      var since = daysSince(last);
      if (since >= 2) flags.appendChild(el('span', 'flag bad', last ? 'No report for ' + since + ' days' : 'No report in 14 days'));
      var c = m.changes[s.id];
      if (c && c.deleted) flags.appendChild(el('span', 'flag bad', c.deleted + (c.deleted === 1 ? ' entry deleted' : ' entries deleted') + ' this week'));
      if (c && c.changed) flags.appendChild(el('span', 'flag', c.changed + (c.changed === 1 ? ' entry changed' : ' entries changed') + ' this week'));
      if ((m.spent[s.id] || 0) > 0 && !(m.received[s.id] > 0)) flags.appendChild(el('span', 'flag', 'Nothing received in 30 days'));
      if (!flags.childNodes.length) flags.appendChild(el('span', 'flag good', 'Nothing needs you'));
      card.appendChild(flags);
      box.appendChild(card);
    });

    function score(x) {
      var ch = m.changes[x.id] || { deleted: 0 };
      return (daysSince(m.lastReport[x.id]) >= 2 ? 4 : 0) + (ch.deleted ? 2 : 0) + (m.approvals[x.id] ? 1 : 0);
    }
  }

  start();
})();
