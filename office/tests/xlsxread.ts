import { crc32 as zlibCrc } from 'node:zlib';

// Reads back the stored zip the office writes, checking every CRC with
// Node's own zlib so a wrong checksum in our writer can't pass unnoticed.
export function unzip(buf: Uint8Array): Map<string, string> {
  const v = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const out = new Map<string, string>();
  let at = 0;
  const dec = new TextDecoder();
  while (v.getUint32(at, true) === 0x04034b50) {
    if (v.getUint16(at + 8, true) !== 0) throw new Error('not stored');
    const crc = v.getUint32(at + 14, true);
    const size = v.getUint32(at + 18, true);
    const nameLen = v.getUint16(at + 26, true);
    const extra = v.getUint16(at + 28, true);
    const name = dec.decode(buf.subarray(at + 30, at + 30 + nameLen));
    const data = buf.subarray(at + 30 + nameLen + extra, at + 30 + nameLen + extra + size);
    if (zlibCrc(data) !== crc) throw new Error(`bad CRC for ${name}`);
    out.set(name, dec.decode(data));
    at += 30 + nameLen + extra + size;
  }
  if (v.getUint32(at, true) !== 0x02014b50) throw new Error('no central directory');
  return out;
}

/** Sheet name -> rows of cell texts/numbers, from a workbook's parts. */
export function sheets(parts: Map<string, string>): Map<string, (string | number)[][]> {
  const wb = parts.get('xl/workbook.xml') ?? '';
  const names = [...wb.matchAll(/<sheet name="([^"]*)" sheetId="(\d+)"/g)].map((m) => [unescape(m[1]), m[2]] as const);
  const out = new Map<string, (string | number)[][]>();
  for (const [name, id] of names) {
    const xml = parts.get(`xl/worksheets/sheet${id}.xml`) ?? '';
    const rows = [...xml.matchAll(/<row r="\d+">(.*?)<\/row>/g)].map((r) => {
      const cells: (string | number)[] = [];
      for (const c of r[1].matchAll(/<c r="([A-Z]+)\d+"[^>]*?(?: t="inlineStr")?[^>]*>(.*?)<\/c>/g)) {
        const col = c[1].split('').reduce((n, ch) => n * 26 + ch.charCodeAt(0) - 64, 0) - 1;
        const text = /<t[^>]*>(.*?)<\/t>/.exec(c[2]);
        cells[col] = text ? unescape(text[1]) : Number(/<v>(.*?)<\/v>/.exec(c[2])![1]);
      }
      return Array.from(cells, (x) => x ?? '');
    });
    out.set(name, rows);
  }
  return out;
}

const unescape = (s: string) =>
  s.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
