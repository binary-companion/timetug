const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const config = JSON.parse(fs.readFileSync('site/firebase.json', 'utf8'));
const entries = config.hosting;
const NEW = 'https://timetug.binarycompanion.com';
const content = entries.find(entry => entry.site === 'timetug-site');
const legacy = entries.find(entry => entry.site === 'timetug');

// Firebase redirect source matching, reduced to what this site uses: `/`, `/:name` segments, and `/**`.
function matches(source, requestPath) {
  if (source === '/**') return true;
  const want = source.split('/').filter(Boolean);
  const have = requestPath.split('/').filter(Boolean);
  if (want.length !== have.length) return false;
  return want.every((part, index) => part.startsWith(':') || part === have[index]);
}

// First matching rule wins, as in Firebase; returns the redirect a request would get.
function redirectFor(requestPath) {
  const rule = legacy.redirects.find(candidate => matches(candidate.source, requestPath));
  if (!rule) return null;
  const names = rule.source.split('/').filter(Boolean);
  const values = requestPath.split('/').filter(Boolean);
  let destination = rule.destination;
  names.forEach((name, index) => {
    if (name.startsWith(':')) destination = destination.replace(name, values[index]);
  });
  return { type: rule.type, location: destination };
}

function page(name) {
  return fs.readFileSync(path.join('site/public', `${name}.html`), 'utf8');
}

test('content is served by timetug-site and redirects by timetug', () => {
  assert.ok(content, 'missing timetug-site entry');
  assert.ok(legacy, 'missing timetug entry');
  assert.equal(content.public, 'public');
  assert.equal(legacy.public, 'legacy');
  assert.equal((content.redirects || []).some(rule => rule.source !== '/appcast.xml'), false,
    'the content site may only redirect /appcast.xml');
  assert.equal(legacy.redirects.every(rule => rule.type === 301), true);
});

test('every old URL answers 301 with the matching new URL', () => {
  const paths = ['/', '/privacy', '/terms', '/style.css', '/download.js', '/favicon.ico',
    '/img/social-preview.jpg', '/img/app-icon-256.png', '/appcast.xml',
    '/.well-known/microsoft-identity-association.json'];
  for (const requestPath of paths) {
    const result = redirectFor(requestPath);
    assert.ok(result, `no rule for ${requestPath}`);
    assert.equal(result.type, 301, requestPath);
    assert.equal(result.location, NEW + requestPath, requestPath);
  }
  assert.equal(redirectFor('/a/b/c/d/e').location, NEW + '/');
});

test('the content site answers /appcast.xml with a 301 to the current feed', () => {
  const rule = content.redirects.find(candidate => candidate.source === '/appcast.xml');
  assert.ok(rule, 'missing /appcast.xml rule');
  assert.equal(rule.type, 301);
  assert.equal(rule.destination, 'https://darkarena1.github.io/timetug/appcast.xml');
});

test('pages name the new domain and no longer name the old one', () => {
  const canonical = { index: `${NEW}/`, privacy: `${NEW}/privacy`, terms: `${NEW}/terms` };
  for (const [name, url] of Object.entries(canonical)) {
    const html = page(name);
    assert.equal(/obryan\.cloud/.test(html), false, `${name}.html still names obryan.cloud`);
    assert.ok(html.includes(`<link rel="canonical" href="${url}">`), `${name}.html canonical`);
    assert.ok(html.includes(`<meta property="og:url" content="${url}">`), `${name}.html og:url`);
  }
  assert.ok(page('index').includes(`content="${NEW}/img/social-preview.jpg"`));
});

test('homepage and privacy policy link to each other', () => {
  assert.match(page('index'), /href="\/privacy"/);
  assert.match(page('privacy'), /href="\/"/);
});

test('contacts use the Binary Companion address', () => {
  for (const name of ['index', 'privacy', 'terms']) {
    const html = page(name);
    assert.equal(/darkarena@gmail\.com/.test(html), false, `${name}.html`);
    assert.ok(html.includes('mailto:sobryan@binarycompanion.com'), `${name}.html`);
  }
});

test('privacy policy and terms name Binary Companion, LLC as the operator', () => {
  assert.match(page('privacy'), /made and operated by Binary Companion, LLC/);
  assert.match(page('terms'), /made and operated by Binary Companion, LLC/);
  assert.equal(/individual developer/.test(page('terms')), false);
});
