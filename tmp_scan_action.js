const fs = require('fs');
const s = fs.readFileSync(process.env.TEMP + '/fb-action.js', 'utf8');
const start = s.indexOf('iu.prototype.start=function');
const window = s.slice(start - 3000, start);
const re = /function xc\(|xc=function\(|var xc=/g;
let m;
while ((m = re.exec(window))) {
  console.log('local', m.index, window.slice(m.index, m.index + 180));
}
console.log('--- tail ---');
console.log(window.slice(-1500));
