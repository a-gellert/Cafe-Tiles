// Writes main/assets/fonts/main.font with every glyph the UI strings need.
// usage (from the project root): node tools/gen_font.js
// Covered: ASCII, Latin-1 (es/pt/de/fr), Turkish letters, Cyrillic (ru).
const fs = require('fs');

let chars = '';
for (let c = 32; c < 127; c++) chars += String.fromCharCode(c);
for (let c = 0xa1; c <= 0xff; c++) chars += String.fromCharCode(c);
chars += 'ĞğİıŞşŒœ';
for (let c = 0x410; c <= 0x44f; c++) chars += String.fromCharCode(c);
chars += 'Ёё—–…№×';

// protobuf text format: octal escapes for non-ASCII bytes, like the Defold editor writes
const esc = [...Buffer.from(chars, 'utf8')].map(b => {
  if (b === 0x22) return '\\"';
  if (b === 0x5c) return '\\\\';
  if (b < 32 || b > 126) return '\\' + b.toString(8).padStart(3, '0');
  return String.fromCharCode(b);
}).join('');

const font = [
  'font: "/main/assets/fonts/Roboto-Bold.ttf"',
  'material: "/builtins/fonts/font-df.material"',
  'size: 44',
  'outline_alpha: 1.0',
  'outline_width: 4.0',
  'shadow_blur: 0',
  'output_format: TYPE_DISTANCE_FIELD',
  'render_mode: MODE_MULTI_LAYER',
  `characters: "${esc}"`,
  '',
].join('\n');
fs.writeFileSync('main/assets/fonts/main.font', font);
console.log(`${[...chars].length} glyphs`);
