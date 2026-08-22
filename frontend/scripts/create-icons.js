const fs = require('fs');
const sharp = require('sharp');
const path = require('path');

const sizes = [72, 96, 128, 144, 152, 192, 384, 512];

const svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'>
  <rect fill='#1e293b' width='100' height='100' rx='15'/>
  <text x='50' y='65' font-size='50' text-anchor='middle' fill='white' font-weight='bold' font-family='Arial'>F</text>
</svg>`;

const svgBuffer = Buffer.from(svg);

async function generateIcons() {
  for (const size of sizes) {
    const outputPath = path.join(__dirname, '../public/icons', `icon-${size}x${size}.png`);
    await sharp(svgBuffer)
      .resize(size, size)
      .png()
      .toFile(outputPath);
    console.log(`Generated ${size}x${size}`);
  }
  console.log('All icons generated!');
}

generateIcons().catch(console.error);