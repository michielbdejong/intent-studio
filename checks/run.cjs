const { Elm } = require('./checks.js');
const app = Elm.Checks.init({ flags: null });
app.ports.report.subscribe(results => {
  results.forEach(r => console.log(`${r.passed ? 'PASS' : 'FAIL'} ${r.name}`));
  process.exit(results.every(r => r.passed) ? 0 : 1);
});
