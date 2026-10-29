// Generator helper for building Mahjong / 3-Tiles levels matching level0.json structure.
const fs = require('fs');

function createEmptyGrid(size) {
  return new Array(size * size).fill(0);
}

class LevelBuilder {
  constructor(id, name, width = 8) {
    this.id = id;
    this.name = name;
    this.width = width;
    this.dimSize = 8;
    this.layerA = createEmptyGrid(8);
    this.layerB = createEmptyGrid(7);
    this.layerC = createEmptyGrid(6);
    this.layerD = createEmptyGrid(5);
    this.layerE = createEmptyGrid(4);
    this.oneDimSlices = [];
  }

  getGrid(layer) {
    if (layer === 'A') return { grid: this.layerA, size: 8 };
    if (layer === 'B') return { grid: this.layerB, size: 7 };
    if (layer === 'C') return { grid: this.layerC, size: 6 };
    if (layer === 'D') return { grid: this.layerD, size: 5 };
    if (layer === 'E') return { grid: this.layerE, size: 4 };
    throw new Error('Unknown layer: ' + layer);
  }

  // Symmetric plot: plots (x, y) and its horizontal mirror (size - 1 - x, y)
  plot(layer, x, y, val = 1) {
    const { grid, size } = this.getGrid(layer);
    if (x >= 0 && x < size && y >= 0 && y < size) {
      grid[y * size + x] = val;
      grid[y * size + (size - 1 - x)] = val;
    }
    return this;
  }

  plotRaw(layer, x, y, val = 1) {
    const { grid, size } = this.getGrid(layer);
    if (x >= 0 && x < size && y >= 0 && y < size) {
      grid[y * size + x] = val;
    }
    return this;
  }

  box(layer, x, y, w, h, fill = true) {
    for (let r = y; r < y + h; r++) {
      for (let c = x; c < x + w; c++) {
        if (fill || r === y || r === y + h - 1 || c === x || c === x + w - 1) {
          this.plot(layer, c, r);
        }
      }
    }
    return this;
  }

  ring(layer, cx, cy, rInner, rOuter) {
    const { size } = this.getGrid(layer);
    for (let r = 0; r < size; r++) {
      for (let c = 0; c < size; c++) {
        const dx = c - cx;
        const dy = r - cy;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist >= rInner && dist <= rOuter) {
          this.plot(layer, c, r);
        }
      }
    }
    return this;
  }

  diamond(layer, cx, cy, radius, fill = true) {
    const { size } = this.getGrid(layer);
    for (let r = 0; r < size; r++) {
      for (let c = 0; c < size; c++) {
        const d = Math.abs(c - cx) + Math.abs(r - cy);
        if (fill ? d <= radius : Math.round(d) === radius) {
          this.plot(layer, c, r);
        }
      }
    }
    return this;
  }

  line(layer, x1, y1, x2, y2) {
    const dx = Math.abs(x2 - x1);
    const dy = Math.abs(y2 - y1);
    const sx = x1 < x2 ? 1 : -1;
    const sy = y1 < y2 ? 1 : -1;
    let err = dx - dy;
    let x = x1, y = y1;
    while (true) {
      this.plot(layer, x, y);
      if (x === x2 && y === y2) break;
      const e2 = 2 * err;
      if (e2 > -dy) { err -= dy; x += sx; }
      if (e2 < dx) { err += dx; y += sy; }
    }
    return this;
  }

  stack(x, y, height) {
    while (this.oneDimSlices.length < height) {
      this.oneDimSlices.push(createEmptyGrid(8));
    }
    for (let s = 0; s < height; s++) {
      const grid = this.oneDimSlices[s];
      grid[y * 8 + x] = 1;
      grid[y * 8 + (7 - x)] = 1;
    }
    return this;
  }

  totalCount() {
    let count = 0;
    const countArr = arr => arr.reduce((a, b) => a + (b === 1 ? 1 : 0), 0);
    count += countArr(this.layerA);
    count += countArr(this.layerB);
    count += countArr(this.layerC);
    count += countArr(this.layerD);
    count += countArr(this.layerE);
    for (const slice of this.oneDimSlices) {
      count += countArr(slice);
    }
    return count;
  }

  ensureMod3() {
    let rem = this.totalCount() % 3;
    if (rem === 0) return;

    const centerB = [
      { layer: 'B', x: 3, y: 3 },
      { layer: 'B', x: 3, y: 2 },
      { layer: 'B', x: 3, y: 4 },
      { layer: 'B', x: 3, y: 1 },
      { layer: 'B', x: 3, y: 5 },
      { layer: 'D', x: 2, y: 2 },
      { layer: 'D', x: 2, y: 1 },
      { layer: 'D', x: 2, y: 3 },
    ];

    if (rem === 1) {
      let removed = false;
      for (const pt of centerB) {
        const { grid, size } = this.getGrid(pt.layer);
        if (grid[pt.y * size + pt.x] === 1) {
          grid[pt.y * size + pt.x] = 0;
          removed = true;
          break;
        }
      }
      if (!removed) {
        let added = 0;
        for (const pt of centerB) {
          const { grid, size } = this.getGrid(pt.layer);
          if (grid[pt.y * size + pt.x] === 0) {
            grid[pt.y * size + pt.x] = 1;
            added++;
            if (added === 2) break;
          }
        }
      }
    } else if (rem === 2) {
      let added = false;
      for (const pt of centerB) {
        const { grid, size } = this.getGrid(pt.layer);
        if (grid[pt.y * size + pt.x] === 0) {
          grid[pt.y * size + pt.x] = 1;
          added = true;
          break;
        }
      }
      if (!added) {
        let removed = 0;
        for (const pt of centerB) {
          const { grid, size } = this.getGrid(pt.layer);
          if (grid[pt.y * size + pt.x] === 1) {
            grid[pt.y * size + pt.x] = 0;
            removed++;
            if (removed === 2) break;
          }
        }
      }
    }
  }

  toData() {
    this.ensureMod3();
    const oneDimFlat = [];
    for (const slice of this.oneDimSlices) {
      for (const val of slice) oneDimFlat.push(val);
    }
    return {
      Id: this.id,
      Count: this.totalCount(),
      Width: this.width,
      DimSize: this.dimSize,
      LayerA: this.layerA,
      LayerB: this.layerB,
      LayerC: this.layerC,
      LayerD: this.layerD,
      LayerE: this.layerE,
      OneDimLayer: oneDimFlat,
      Name: this.name,
    };
  }
}

module.exports = { LevelBuilder };
