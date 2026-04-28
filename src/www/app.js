'use strict';

const API = '/cgi-bin/norypt.cgi';
let csrfToken = '';

function initCsrf() {
  const meta = document.querySelector('meta[name="norypt-token"]');
  csrfToken = meta ? meta.getAttribute('content') : '';
}

async function api(action, body) {
  const opts = {
    method: 'POST',
    headers: { 'X-Norypt-Token': csrfToken },
  };
  if (body) {
    opts.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    opts.body = body;
  }
  const res = await fetch(`${API}?action=${encodeURIComponent(action)}`, opts);
  if (res.status === 403) throw new Error('CSRF token invalid — reload the page');
  return res.text();
}

function parseKV(text) {
  const out = {};
  for (const line of text.split('\n')) {
    const eq = line.indexOf('=');
    if (eq > 0) out[line.slice(0, eq)] = line.slice(eq + 1);
  }
  return out;
}

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = String(value);
}

function makeDot(connected) {
  const span = document.createElement('span');
  span.className = connected ? 'dot dot-g' : 'dot dot-r';
  return span;
}

async function loadStatus() {
  try {
    const d = parseKV(await api('status'));
    setText('val-imei', d.imei || '—');
    setText('val-bssid-2g', d.bssid_2g || '—');
    setText('val-bssid-5g', d.bssid_5g || '—');
    setText('val-wan-mac', d.wan_mac || '—');

    const cel = document.getElementById('cellular-status');
    if (cel) {
      cel.textContent = '';
      const connected = d.cellular === 'connected';
      cel.appendChild(makeDot(connected));
      cel.appendChild(document.createTextNode(
        (connected ? 'Connected' : 'Disconnected') + ' (fw: ' + (d.fw || '?') + ')'
      ));
    }
  } catch (e) {
    setText('val-imei', 'Error: ' + e.message);
  }
}

async function loadConfig() {
  try {
    const cfg = parseKV(await api('get_config'));
    document.querySelectorAll('[data-cfg]').forEach(toggle => {
      const v = cfg[toggle.dataset.cfg];
      if (v === '1' || v === '0') toggle.checked = v === '1';
    });
  } catch (e) { /* keep default-checked state on failure */ }
}

async function loadHistory() {
  const container = document.getElementById('history-list');
  if (!container) return;
  try {
    const raw = await api('get_history');
    const lines = raw.split('\n').filter(l => l.trim() && !l.includes('no_history'));
    container.textContent = '';
    if (!lines.length) {
      const p = document.createElement('p');
      p.className = 'muted';
      p.textContent = 'No history yet';
      container.appendChild(p);
      return;
    }
    for (const line of lines.reverse()) {
      const parts = line.split(' ');
      const row = document.createElement('div');
      row.className = 'h-row';
      const time = document.createElement('span');
      time.className = 'h-time';
      time.textContent = parts.slice(0, 2).join(' ');
      const rest = document.createTextNode(parts.slice(2).join(' '));
      row.appendChild(time);
      row.appendChild(rest);
      container.appendChild(row);
    }
  } catch (e) {
    container.textContent = 'Error: ' + e.message;
  }
}

async function triggerAction(action, btn) {
  const orig = btn.textContent;
  btn.disabled = true;
  btn.textContent = '...';
  try {
    await api(action);
    await loadStatus();
    await loadHistory();
  } catch (e) {
    alert(e.message);
  } finally {
    btn.disabled = false;
    btn.textContent = orig;
  }
}

async function setConfig(key, val) {
  try {
    await api('set_config', key + '=' + (val ? '1' : '0'));
  } catch (e) {
    alert(e.message);
  }
}

function bindControls() {
  document.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', () => triggerAction(btn.dataset.action, btn));
  });
  document.querySelectorAll('[data-cfg]').forEach(toggle => {
    toggle.addEventListener('change', () => setConfig(toggle.dataset.cfg, toggle.checked));
  });
}

document.addEventListener('DOMContentLoaded', () => {
  initCsrf();
  bindControls();
  loadStatus();
  loadConfig();
  loadHistory();
  setInterval(loadStatus, 30000);
});
