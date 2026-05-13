'use strict';
/**
 * prefs.cjs — autopilot per-user preferences
 *
 * Stores user preferences to ~/.autopilot/prefs.json
 * Format: { "auto_close_after_decision": true, ... }
 *
 * API: { load, save, getPref, setPref, PREFS_FILE }
 *
 * Contract (C-prefs):
 *   - getPref(key, defaultValue) never throws; returns defaultValue on missing/corrupt file
 *   - setPref(key, value) creates PREFS_DIR if missing, then writeFileSync
 *   - After setPref(key, v), getPref(key, _) === v (strict equality)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const PREFS_DIR = path.join(os.homedir(), '.autopilot');
const PREFS_FILE = path.join(PREFS_DIR, 'prefs.json');

/** In-memory cache. Lazily loaded. null means not yet loaded. */
let _cache = null;

/**
 * Load prefs from disk. On any error (missing file, corrupt JSON),
 * silently falls back to an empty object.
 * @returns {Object} parsed prefs object
 */
function load() {
  try {
    const raw = fs.readFileSync(PREFS_FILE, 'utf-8');
    _cache = JSON.parse(raw);
    if (typeof _cache !== 'object' || _cache === null || Array.isArray(_cache)) {
      _cache = {};
    }
  } catch (e) {
    // Missing file or corrupt JSON — silent fallback
    _cache = {};
  }
  return _cache;
}

/**
 * Save current in-memory prefs to disk.
 * Creates PREFS_DIR if it doesn't exist.
 * On write failure, logs to stderr but does NOT throw.
 */
function save() {
  try {
    if (!fs.existsSync(PREFS_DIR)) {
      fs.mkdirSync(PREFS_DIR, { recursive: true });
    }
    fs.writeFileSync(PREFS_FILE, JSON.stringify(_cache || {}, null, 2), 'utf-8');
  } catch (e) {
    console.error('[prefs.cjs] Failed to write prefs:', e.message);
  }
}

/**
 * Get a preference value by key.
 * Falls back to defaultValue if: file missing, corrupt JSON, or key absent.
 * NEVER throws.
 *
 * @param {string} key
 * @param {*} defaultValue
 * @returns {*}
 */
function getPref(key, defaultValue) {
  // Force fresh load each time getPref is called with a null cache.
  // This ensures T1.5-S2 (corrupt JSON) works even when module is require()'d fresh.
  if (_cache === null) {
    load();
  }
  if (Object.prototype.hasOwnProperty.call(_cache, key)) {
    return _cache[key];
  }
  return defaultValue;
}

/**
 * Set a preference value and persist to disk immediately.
 * Creates ~/.autopilot/ directory if missing.
 *
 * @param {string} key
 * @param {*} value
 */
function setPref(key, value) {
  if (_cache === null) {
    load();
  }
  _cache[key] = value;
  save();
}

module.exports = { load, save, getPref, setPref, PREFS_FILE };
