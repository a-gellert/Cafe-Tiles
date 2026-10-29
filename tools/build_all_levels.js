const fs = require('fs');
const path = require('path');
const { newLevels } = require('./gen_100_levels');

const unityLevelsPath = 'd:/UnityProjects/WEB/Brain Storm_WEB/Assets/Levels/level0.json';
const unityData = JSON.parse(fs.readFileSync(unityLevelsPath, 'utf8'));
const unityLevels = unityData.level;

console.log('Original levels from level0.json:', unityLevels.length);
console.log('New generated levels:', newLevels.length);

const all151Levels = [];

unityLevels.forEach((lvl, i) => {
  all151Levels.push({
    Id: lvl.Id,
    Count: lvl.Count,
    Width: lvl.Width || 8,
    DimSize: lvl.DimSize || 8,
    LayerA: lvl.LayerA || [],
    LayerB: lvl.LayerB || [],
    LayerC: lvl.LayerC || [],
    LayerD: lvl.LayerD || [],
    LayerE: lvl.LayerE || [],
    OneDimLayer: lvl.OneDimLayer || [],
    Name: 'Unity_Level_' + i,
  });
});

newLevels.forEach((lvl) => {
  all151Levels.push(lvl);
});

console.log('Total combined levels:', all151Levels.length);

function convertToPositions(lvl) {
  const tiles = [];
  const addLayer = (arr, size, layerIdx) => {
    if (!arr || arr.length === 0) return;
    for (let i = 0; i < size; i++) {
      for (let j = 0; j < size; j++) {
        if (arr[j + size * i] === 1) {
          tiles.push({
            x: layerIdx + 2 * j,
            y: layerIdx + 2 * (size - 1 - i),
            z: layerIdx,
          });
        }
      }
    }
  };

  addLayer(lvl.LayerA, 8, 0);
  addLayer(lvl.LayerB, 7, 1);
  addLayer(lvl.LayerC, 6, 2);
  addLayer(lvl.LayerD, 5, 3);
  addLayer(lvl.LayerE, 4, 4);

  if (lvl.OneDimLayer && lvl.OneDimLayer.length > 0) {
    const slices = lvl.OneDimLayer.length / 64;
    for (let s = 0; s < slices; s++) {
      for (let i = 0; i < 8; i++) {
        for (let j = 0; j < 8; j++) {
          if (lvl.OneDimLayer[s * 64 + i * 8 + j] === 1) {
            const tx = 2 * j;
            const ty = 2 * (7 - i);
            let maxUnder = -1;
            for (const t of tiles) {
              if (Math.abs(t.x - tx) < 2 && Math.abs(t.y - ty) < 2) {
                if (t.z > maxUnder) maxUnder = t.z;
              }
            }
            tiles.push({
              x: tx,
              y: ty,
              z: Math.max(5 + s, maxUnder + 1),
            });
          }
        }
      }
    }
  }

  let minx = 1000, maxx = -1000, miny = 1000, maxy = -1000, maxz = 0;
  for (const t of tiles) {
    if (t.x < minx) minx = t.x;
    if (t.x > maxx) maxx = t.x;
    if (t.y < miny) miny = t.y;
    if (t.y > maxy) maxy = t.y;
    if (t.z > maxz) maxz = t.z;
  }
  const cols = Math.floor((maxx - minx) / 2) + 1;
  const rows = Math.floor((maxy - miny) / 2) + 1;

  let freeCount = 0;
  for (let a = 0; a < tiles.length; a++) {
    let blocked = false;
    for (let c = 0; c < tiles.length; c++) {
      if (tiles[c].z > tiles[a].z && Math.abs(tiles[c].x - tiles[a].x) < 2 && Math.abs(tiles[c].y - tiles[a].y) < 2) {
        blocked = true;
        break;
      }
    }
    if (!blocked) freeCount++;
  }

  return {
    tiles,
    cols,
    rows,
    layers: maxz + 1,
    freeCount,
  };
}

let minFree = 1000;
let maxFree = 0;
let invalidCounts = 0;

const processedLevels = [];

all151Levels.forEach((lvl, idx) => {
  const converted = convertToPositions(lvl);
  if (converted.tiles.length !== lvl.Count || lvl.Count % 3 !== 0) {
    console.error(`Level ${idx + 1} (Id ${lvl.Id}) invalid count! Expected ${lvl.Count}, got ${converted.tiles.length}`);
    invalidCounts++;
  }
  if (converted.freeCount < minFree) minFree = converted.freeCount;
  if (converted.freeCount > maxFree) maxFree = converted.freeCount;
  processedLevels.push({
    id: lvl.Id,
    levelNum: idx + 1,
    count: lvl.Count,
    triples: lvl.Count / 3,
    cols: converted.cols,
    rows: converted.rows,
    layers: converted.layers,
    freeCount: converted.freeCount,
    positions: converted.tiles,
  });
});

console.log(`Validation finished. Invalid counts: ${invalidCounts}`);
console.log(`Free tiles range at start: ${minFree} to ${maxFree}`);

fs.writeFileSync('tools/levels_151.json', JSON.stringify({ level: all151Levels }, null, 2));
fs.writeFileSync('main/assets/levels_151.json', JSON.stringify({ level: all151Levels }, null, 2));
console.log('Saved tools/levels_151.json and main/assets/levels_151.json');

let luaContent = `-- Precomputed handcrafted and generated 151 levels.
-- Levels 1..51 are from Brain Storm level0.json (Ids 0..50).
-- Levels 52..151 are +100 similar handcrafted/procedural thematic levels (Ids 51..150).
local M = {}

M.COUNT = ${processedLevels.length}

M.LEVELS = {
`;

processedLevels.forEach((l) => {
  luaContent += `\t[${l.levelNum}] = {\n`;
  luaContent += `\t\tid = ${l.id},\n`;
  luaContent += `\t\ttriples = ${l.triples},\n`;
  luaContent += `\t\tcols = ${l.cols},\n`;
  luaContent += `\t\trows = ${l.rows},\n`;
  luaContent += `\t\tlayers = ${l.layers},\n`;
  luaContent += `\t\tpositions = {\n`;
  for (let i = 0; i < l.positions.length; i++) {
    const p = l.positions[i];
    luaContent += `\t\t\t{ x = ${p.x}, y = ${p.y}, z = ${p.z} },\n`;
  }
  luaContent += `\t\t},\n`;
  luaContent += `\t},\n`;
});

luaContent += `}\n\nreturn M\n`;

fs.writeFileSync('main/modules/level_data.lua', luaContent);
console.log('Saved main/modules/level_data.lua successfully!');
