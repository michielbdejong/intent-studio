/* Elm owns application state. This bridge only handles browser storage and downloads. */
let saved = null;
try { saved = JSON.parse(localStorage.getItem('intent-studio-v1')); } catch (_) {}
const app = Elm.Main.init({ node: document.getElementById('app'), flags: saved });
app.ports.save.subscribe(data => {
  try { localStorage.setItem('intent-studio-v1', JSON.stringify(data)); }
  catch (_) { alert('Your browser could not save this session. Use Export history to keep a copy.'); }
});
app.ports.download.subscribe(request => {
  let data, name, type;
  if (request.kind === 'svg') {
    const svg = document.querySelector('#drawing').cloneNode(true);
    svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    svg.querySelectorAll('[data-color]').forEach(line => {
      line.setAttribute('stroke', line.dataset.color);
      line.setAttribute('stroke-width', line.dataset.width);
      line.removeAttribute('class');
    });
    data = new XMLSerializer().serializeToString(svg); name = 'paris-postcard.svg'; type = 'image/svg+xml';
  } else { data = JSON.stringify(request.data, null, 2); name = 'paris-intent-history.json'; type = 'application/json'; }
  const url = URL.createObjectURL(new Blob([data], { type }));
  const link = document.createElement('a'); link.href = url; link.download = name; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
