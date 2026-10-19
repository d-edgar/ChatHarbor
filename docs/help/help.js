'use strict';
const search = document.querySelector('#guide-search');
const guides = [...document.querySelectorAll('[data-guide]')];
const links = [...document.querySelectorAll('nav[aria-label="Guide index"] a')];
function filterGuides() {
  const words = search.value.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
  let count = 0;
  guides.forEach((guide, index) => {
    const matches = words.every(word => guide.textContent.toLocaleLowerCase().includes(word));
    guide.hidden = !matches;
    links[index].hidden = !matches;
    if (matches) count++;
  });
  document.querySelector('#search-status').textContent = `${count} of ${guides.length} guides shown.`;
  document.querySelector('#no-results').hidden = count !== 0;
}
search.addEventListener('input', filterGuides);
// A deep link must remain usable even when a previous search hid its guide.
window.addEventListener('hashchange', () => {
  search.value = '';
  filterGuides();
  const target = document.getElementById(location.hash.slice(1));
  if (target) target.scrollIntoView();
});
