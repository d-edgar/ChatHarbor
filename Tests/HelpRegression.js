// Run with node Tests/HelpRegression.js; no packages or network required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../docs');
const html = fs.readFileSync(path.join(root, 'help/index.html'), 'utf8');
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]);
assert.equal(new Set(ids).size, ids.length, 'IDs must be unique');
for (const file of ['help/index.html', 'index.html']) {
  const text = fs.readFileSync(path.join(root, file), 'utf8');
  for (const [, href] of text.matchAll(/(?:href|src)="([^"]+)"/g)) {
    if (/^https?:/.test(href)) continue;
    const [pathname, fragment] = href.split('#');
    let target = path.resolve(path.dirname(path.join(root, file)), pathname || path.basename(file));
    if (fs.statSync(target).isDirectory()) target = path.join(target, 'index.html');
    assert(fs.existsSync(target), `Missing ${href}`);
    if (fragment) assert(fs.readFileSync(target, 'utf8').includes(`id="${fragment}"`), `Missing anchor ${href}`);
  }
}
for (const file of ['Views/SettingsView.swift', 'Views/GettingStartedGuide.swift', 'Views/KeyboardShortcuts.swift']) {
  const swift = fs.readFileSync(path.resolve(__dirname, '../ChatHarbor', file), 'utf8');
  for (const [, id] of swift.matchAll(/https:\/\/chatharbor.app\/help\/#([a-z]+)"/g)) assert(ids.includes(id), `Missing app guide ${id}`);
}
for (const id of ['overview','connect','chat','ships','harbors','data','apple','ollama','lmstudio','servers','cloud']) assert(ids.includes(id));
const settings = fs.readFileSync(path.resolve(__dirname, '../ChatHarbor/Views/SettingsView.swift'), 'utf8');
for (const id of ['apple','ollama','lmstudio','custom','openai','anthropic','google']) {
  assert(settings.includes(`"${id}": ("Get`), `Missing Get link for ${id}`);
}
const guides = [...html.matchAll(/<article id="([^"]+)" data-guide>([\s\S]*?)<\/article>/g)].map(m => ({id:m[1], textContent:m[2].replace(/<[^>]+>/g, ' '), hidden:false, scrollIntoView() { this.scrolled = true; }}));
const links = guides.map(() => ({hidden:false}));
const events = {};
const search = {value:'', addEventListener(type, fn) {events[type] = fn;}};
const status = {}, empty = {};
const location = {hash:''};
vm.runInNewContext(fs.readFileSync(path.join(root, 'help/help.js'), 'utf8'), {
  document: {querySelector: s => ({'#guide-search':search,'#search-status':status,'#no-results':empty}[s]), querySelectorAll:s => s === '[data-guide]' ? guides : links, getElementById:id => guides.find(g => g.id === id)},
  window: {addEventListener(type, fn) {events[type] = fn;}}, location
});
search.value='  LM STUDIO  '; events.input();
assert(!guides.find(g=>g.id==='lmstudio').hidden);
search.value='no-such-topic-9f2'; events.input(); assert.equal(empty.hidden,false); assert(guides.every(g=>g.hidden));
location.hash='#data'; events.hashchange(); assert.equal(search.value,''); assert(guides.every(g=>!g.hidden)); assert(guides.find(g=>g.id==='data').scrolled);
search.value=''; events.input(); assert.equal(empty.hidden,true);
assert(links.every(l=>!l.hidden));
console.log('PASS: knowledge-base files, deep links, search, no results, and hash navigation');
